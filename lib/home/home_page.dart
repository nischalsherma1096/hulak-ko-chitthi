import "dart:convert";
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "chat_box.dart";
import "profile.dart";
import "contacts.dart";
import "user_profile_page.dart";

class ChatContact {
  final String id;
  final String username;
  String lastMessage;
  String time;
  int unread;
  final List<ChatMessage> messages;

  ChatContact({
    required this.id,
    required this.username,
    required this.lastMessage,
    required this.time,
    required this.unread,
    required this.messages,
  });
}

class ChatMessage {
  final String text;
  final bool isMe;
  final String time;
  final MessageStatus status;
  ChatMessage(
      {required this.text,
      required this.isMe,
      required this.time,
      this.status = MessageStatus.delivered});
}

enum MessageStatus { sent, delivered }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _tab = 0;

  static const Color _darkText = Color(0xFF1A1A1A);
  static const Color _bodyText = Color(0xFF555555);
  static const Color _timeText = Color(0xFF999999);
  static const Color _divider = Color(0xFFEEEEEE);
  static const Color _unreadBg = Color(0xFFFFF5E6);
  static const Color _accent = Color(0xFFF5A623);
  static const Color _accentDk = Color(0xFFBF5B0A);
  static const LinearGradient _grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)],
  );

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String get _myUid => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    try {
      dt = (ts as dynamic).toDate().toLocal() as DateTime;
    } catch (_) {
      return '';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) {
      final h = dt.hour == 0
          ? 12
          : dt.hour > 12
              ? dt.hour - 12
              : dt.hour;
      final min = dt.minute.toString().padLeft(2, '0');
      return '$h:$min ${dt.hour < 12 ? 'AM' : 'PM'}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7)
      return const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun'
      ][dt.weekday - 1];
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // ── Sanitise last-message preview (real-time stream) ──────────────
  // Returns a stream so the home tile always shows the latest real message
  // even after a burn/recall, matching Messenger behaviour.
  Stream<String> _previewStream(String chatId) {
    const burned = ['This letter was burned.', 'This letter was recalled.'];
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) {
      for (final doc in snap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        if (d['deletedForEveryone'] == true) continue;
        if (d['isSystem'] == true) continue;
        final t = (d['text'] as String? ?? '').trim();
        if (burned.contains(t)) continue;
        // Skip messages deleted for me
        final deletedFor = List<String>.from(d['deletedFor'] as List? ?? []);
        if (deletedFor.contains(_myUid)) continue;
        return t;
      }
      return '';
    });
  }

  // ── Mute helpers ───────────────────────────────────────────────────
  // Returns null if not muted, or the mute-until DateTime if muted.
  DateTime? _muteUntil(Map<String, dynamic> myUserData, String chatId) {
    final mutedChats =
        (myUserData['mutedChats'] as Map<String, dynamic>?) ?? {};
    final raw = mutedChats[chatId];
    if (raw == null) return null;
    int ms;
    if (raw is Map) {
      ms = (raw['until'] as int?) ?? 0;
    } else {
      ms = raw as int; // legacy int format
    }
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    if (until.isBefore(DateTime.now())) return null; // expired
    return until;
  }

  String _muteLabel(Map<String, dynamic> myUserData, String chatId) {
    final mutedChats =
        (myUserData['mutedChats'] as Map<String, dynamic>?) ?? {};
    final raw = mutedChats[chatId];
    if (raw == null) return '';
    if (raw is Map) return (raw['label'] as String?) ?? 'Muted';
    // legacy: compute label from remaining time
    final diff = DateTime.fromMillisecondsSinceEpoch(raw as int)
        .difference(DateTime.now());
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    return '${diff.inMinutes}m';
  }

  // Formats mute label shown on home tile
  // Always = "Always", 1h mute = "1h", 8h mute = "8h", etc.
  // No countdown — shows the original mute duration label, not time remaining.

  Future<void> _deleteChat(String chatId) async {
    final snap =
        await _db.collection('chats').doc(chatId).collection('messages').get();
    for (final d in snap.docs) await d.reference.delete();
    await _db.collection('chats').doc(chatId).delete();
  }

  // ── Group long-press options (Messenger-style) ─────────────────────
  void _showGroupOptions(
    BuildContext context, {
    required String chatId,
    required String name,
    required bool isAdmin,
    required bool isMuted,
    required Map<String, dynamic> myData,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroupOptionsSheet(
        name: name,
        isMuted: isMuted,
        onMute: () {
          Navigator.pop(context);
          _showMuteOptions(chatId);
        },
        onUnmute: () {
          Navigator.pop(context);
          _unmuteGroupChat(chatId);
        },
        onMarkRead: () {
          Navigator.pop(context);
          _markAllRead(chatId);
        },
      ),
    );
  }

  void _showMuteOptions(String chatId) {
    final options = [
      ('15 minutes', '15m', const Duration(minutes: 15)),
      ('1 hour', '1h', const Duration(hours: 1)),
      ('8 hours', '8h', const Duration(hours: 8)),
      ('24 hours', '24h', const Duration(hours: 24)),
      ('Always', 'Always', const Duration(days: 365 * 10)),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const Text('Mute notifications for',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 16),
          ...options.map((o) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: ShaderMask(
                  shaderCallback: (b) => _grad.createShader(b),
                  child: const Icon(Icons.notifications_off_outlined,
                      color: Colors.white, size: 20),
                ),
                title: Text(o.$1,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF1A1A1A))),
                onTap: () {
                  Navigator.pop(context);
                  _muteGroupChat(chatId, o.$3, o.$2);
                },
              )),
        ]),
      ),
    );
  }

  Future<void> _muteGroupChat(
      String chatId, Duration duration, String label) async {
    final until = DateTime.now().add(duration);
    await _db.collection('users').doc(_myUid).update({
      'mutedChats.$chatId': {
        'until': until.millisecondsSinceEpoch,
        'label': label,
      },
    });
    _showSnack('Muted');
  }

  Future<void> _unmuteGroupChat(String chatId) async {
    await _db.collection('users').doc(_myUid).update({
      'mutedChats.$chatId': FieldValue.delete(),
    });
    _showSnack('Unmuted');
  }

  Future<void> _markAllRead(String chatId) async {
    final msgs = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: _myUid)
        .get();
    final batch = _db.batch();
    for (final doc in msgs.docs) {
      final readBy = List<String>.from(
          (doc.data() as Map<String, dynamic>)['readBy'] as List? ?? []);
      if (!readBy.contains(_myUid)) {
        batch.update(doc.reference, {
          'readBy': FieldValue.arrayUnion([_myUid])
        });
      }
    }
    await batch.commit();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF6B3A10),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── New guild dialog ───────────────────────────────────────────────
  void _showNewGuild() {
    final nameCtrl = TextEditingController();
    final selected = <String>{};

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Row(children: [
                  CustomPaint(
                      size: const Size(26, 26),
                      painter: _WaxSealPainter(color: _accentDk)),
                  const SizedBox(width: 10),
                  const Text('New Postal Guild',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
                content: SizedBox(
                    width: double.maxFinite,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          hintText: 'Guild name…',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontStyle: FontStyle.italic),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: _accent, width: 1.5)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Add members:',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600))),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _db.collection('users').snapshots(),
                          builder: (_, snap) {
                            if (!snap.hasData)
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: _accent));
                            final users = snap.data!.docs
                                .where((d) => d['uid'] != _myUid)
                                .toList();
                            if (users.isEmpty)
                              return Text('No other users yet.',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 12));
                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: users.length,
                              itemBuilder: (_, i) {
                                final u =
                                    users[i].data() as Map<String, dynamic>;
                                final uid = u['uid'] as String;
                                final name = u['username'] as String? ?? '?';
                                return CheckboxListTile(
                                  value: selected.contains(uid),
                                  onChanged: (v) => setSt(() => v == true
                                      ? selected.add(uid)
                                      : selected.remove(uid)),
                                  title: Text(name,
                                      style: const TextStyle(fontSize: 13)),
                                  activeColor: _accent,
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel',
                          style: TextStyle(color: Colors.grey.shade500))),
                  TextButton(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return; // members not required
                      Navigator.pop(ctx);
                      await _createGuild(name, selected.toList());
                    },
                    child: const Text('Create Guild',
                        style: TextStyle(
                            color: _accentDk, fontWeight: FontWeight.w700)),
                  ),
                ],
              )),
    );
  }

  Future<void> _createGuild(String name, List<String> members) async {
    final all = [_myUid, ...members];
    final ref = _db.collection('chats').doc();
    await ref.set({
      'isGroup': true,
      'groupName': name,
      'participants': all,
      'adminUid': _myUid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '📜 Guild established.',
      'lastSenderId': _myUid,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
    await ref.collection('messages').add({
      'text': '📜 The postal guild "$name" has been established.',
      'senderId': 'system',
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': <String>[],
      'deletedFor': <String>[],
      'deletedForEveryone': false,
      'edited': false,
      'isSystem': true,
    });
    if (!mounted) return;
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => ChatBox(
        contact: ChatContact(
            id: ref.id,
            username: name,
            lastMessage: '',
            time: '',
            unread: 0,
            messages: []),
        isGroup: true,
        groupId: ref.id,
      ),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _appBar(),
          Expanded(child: _tab == 0 ? _chatList() : const ContactsPage()),
          _bottomNav(),
        ]),
      ),
    );
  }

  Widget _appBar() {
    return Container(
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          bottom: 14),
      decoration: BoxDecoration(
        gradient: _grad,
        boxShadow: [
          BoxShadow(
              color: _accentDk.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 400),
            pageBuilder: (_, __, ___) => const ProfilePage(),
            transitionsBuilder: (_, anim, __, child) => SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
                      .animate(
                          CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
          )),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
                border: Border.all(
                    color: Colors.white.withOpacity(0.5), width: 1.5)),
            child:
                const Icon(Icons.person_outline, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('HULAK KO CHITTHI',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
          SizedBox(height: 1),
          Text('Your postal messenger',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.5)),
        ])),

        // ── Wax Seal button with label ───────────────────────────────
        GestureDetector(
          onTap: _showNewGuild,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Layered gradients simulate the raised wax look
                gradient: RadialGradient(
                  center: const Alignment(-0.35, -0.35),
                  radius: 1.0,
                  colors: [
                    Colors.white.withOpacity(0.38),
                    Colors.white.withOpacity(0.08),
                  ],
                ),
                border: Border.all(
                    color: Colors.white.withOpacity(0.60), width: 1.5),
                boxShadow: [
                  // outer drop shadow
                  BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 3)),
                  // inner glow (simulated with a lighter outer shadow)
                  BoxShadow(
                      color: Colors.white.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(-1, -1)),
                ],
              ),
              child: Center(
                child: CustomPaint(
                    size: const Size(28, 28), painter: _WaxSealPainter()),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Create Guild',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                shadows: [
                  Shadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: Offset(0, 1))
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _chatList() {
    // Outer stream: my own user doc (live mute data)
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc(_myUid).snapshots(),
      builder: (ctx, mySnap) {
        final myData = mySnap.data?.data() as Map<String, dynamic>? ?? {};
        return StreamBuilder<QuerySnapshot>(
          stream: _db
              .collection('chats')
              .where('participants', arrayContains: _myUid)
              .snapshots(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: _accent));
            }
            final docs = (snap.data?.docs ?? [])
              ..sort((a, b) {
                final at = (a.data() as Map)['lastUpdated'];
                final bt = (b.data() as Map)['lastUpdated'];
                if (at == null && bt == null) return 0;
                if (at == null) return 1;
                if (bt == null) return -1;
                return (bt as dynamic).compareTo(at as dynamic);
              });

            if (docs.isEmpty)
              return Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ShaderMask(
                          shaderCallback: (b) => _grad.createShader(b),
                          child: const Icon(Icons.mail_outline,
                              color: Colors.white, size: 64)),
                      const SizedBox(height: 14),
                      Text('No letters yet.\nHead to Contacts to write one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              height: 1.6)),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: _showNewGuild,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                              gradient: _grad,
                              borderRadius: BorderRadius.circular(20)),
                          child: const Text('Start a Postal Guild',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
              );

            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => Divider(
                  color: _divider, height: 1, indent: 80, endIndent: 16),
              itemBuilder: (_, i) {
                final data = docs[i].data() as Map<String, dynamic>;
                final chatId = docs[i].id;
                return data['isGroup'] == true
                    ? _groupTile(data, chatId, myData)
                    : _dmTile(data, chatId, myData);
              },
            );
          },
        );
      },
    );
  }

  Widget _groupTile(
      Map<String, dynamic> data, String chatId, Map<String, dynamic> myData) {
    final name = data['groupName'] as String? ?? 'Unnamed Guild';
    final lastBy = data['lastSenderId'] as String? ?? '';
    final timeStr = _fmtTs(data['lastUpdated']);
    final adminUid = data['adminUid'] as String? ?? '';
    final isMyMsg = lastBy == _myUid;
    final muteUntil = _muteUntil(myData, chatId);

    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('senderId', isNotEqualTo: _myUid)
          .snapshots(),
      builder: (_, msgSnap) {
        final unread = msgSnap.hasData
            ? msgSnap.data!.docs.where((d) {
                final readBy =
                    (d.data() as Map<String, dynamic>)['readBy'] as List?;
                return readBy == null || !readBy.contains(_myUid);
              }).length
            : 0;
        final hasUnread = unread > 0;

        return Dismissible(
          key: Key(chatId),
          direction: adminUid == _myUid
              ? DismissDirection.endToStart
              : DismissDirection.none,
          background: _swipeBg('Disband'),
          confirmDismiss: (_) => _confirmDismiss('Disband guild "$name"?'),
          onDismissed: (_) => _deleteChat(chatId),
          child: InkWell(
            onLongPress: () => _showGroupOptions(
              context,
              chatId: chatId,
              name: name,
              isAdmin: adminUid == _myUid,
              isMuted: muteUntil != null,
              myData: myData,
            ),
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => ChatBox(
                contact: ChatContact(
                    id: chatId,
                    username: name,
                    lastMessage: '',
                    time: timeStr,
                    unread: 0,
                    messages: []),
                isGroup: true,
                groupId: chatId,
              ),
              transitionsBuilder: (_, anim, __, child) => SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(1, 0), end: Offset.zero)
                    .animate(
                        CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                child: child,
              ),
            )),
            splashColor: _accent.withOpacity(0.08),
            child: Container(
              color: hasUnread ? _unreadBg : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Stack(children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: hasUnread
                            ? [const Color(0xFF4A2E14), const Color(0xFF6B3F1A)]
                            : [
                                const Color(0xFF4A2E14).withOpacity(0.6),
                                const Color(0xFF6B3F1A).withOpacity(0.6)
                              ],
                      ),
                    ),
                    child: const Icon(Icons.people_rounded,
                        color: Colors.white, size: 26),
                  ),
                  if (hasUnread)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                            color: Color(0xFFBF3A0A), shape: BoxShape.circle),
                        child: Center(
                            child: Text('$unread',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800))),
                      ),
                    ),
                ]),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Text(name,
                                  style: TextStyle(
                                      color: _darkText,
                                      fontSize: 14.5,
                                      fontWeight: hasUnread
                                          ? FontWeight.w700
                                          : FontWeight.w500)),
                              if (adminUid == _myUid) ...[
                                const SizedBox(width: 6),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: _accent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: const Text('admin',
                                        style: TextStyle(
                                            color: _accentDk,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5))),
                              ],
                            ]),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(timeStr,
                                    style: TextStyle(
                                        color:
                                            hasUnread ? _accentDk : _timeText,
                                        fontSize: 11,
                                        fontWeight: hasUnread
                                            ? FontWeight.w600
                                            : FontWeight.normal)),
                                if (muteUntil != null) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.notifications_off_outlined,
                                            color: Colors.grey.shade400,
                                            size: 11),
                                        const SizedBox(width: 2),
                                        Text(_muteLabel(myData, chatId),
                                            style: TextStyle(
                                                color: Colors.grey.shade400,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500)),
                                      ]),
                                ],
                              ],
                            ),
                          ]),
                      const SizedBox(height: 4),
                      Row(children: [
                        if (isMyMsg)
                          Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.done_all,
                                  color: _accent.withOpacity(0.8), size: 13)),
                        Expanded(
                            child: StreamBuilder<String>(
                          stream: _previewStream(chatId),
                          builder: (_, s) => Text(s.data ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: hasUnread ? _darkText : _bodyText,
                                  fontSize: 13,
                                  fontWeight: hasUnread
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                  fontStyle: FontStyle.italic)),
                        )),
                      ]),
                    ])),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _dmTile(
      Map<String, dynamic> data, String chatId, Map<String, dynamic> myData) {
    final parts = List<String>.from(data['participants'] ?? []);
    final otherUid = parts.firstWhere((id) => id != _myUid, orElse: () => '');
    if (otherUid.isEmpty) return const SizedBox.shrink();

    final lastBy = data['lastSenderId'] as String? ?? '';
    final timeStr = _fmtTs(data['lastUpdated']);
    final isMyMsg = lastBy == _myUid;
    final muteUntil = _muteUntil(myData, chatId);

    return FutureBuilder<DocumentSnapshot>(
      future: _db.collection('users').doc(otherUid).get(),
      builder: (_, userSnap) {
        if (!userSnap.hasData || !userSnap.data!.exists)
          return const SizedBox(height: 72);
        final uData = userSnap.data!.data() as Map<String, dynamic>;
        final username = uData['username'] as String? ?? '?';
        final avatar = uData['avatarBase64'] as String?;

        return StreamBuilder<QuerySnapshot>(
          stream: _db
              .collection('chats')
              .doc(chatId)
              .collection('messages')
              .where('senderId', isNotEqualTo: _myUid)
              .snapshots(),
          builder: (_, msgSnap) {
            final unread = msgSnap.hasData
                ? msgSnap.data!.docs.where((d) {
                    final readBy =
                        (d.data() as Map<String, dynamic>)['readBy'] as List?;
                    return readBy == null || !readBy.contains(_myUid);
                  }).length
                : 0;
            final hasUnread = unread > 0;

            return Dismissible(
              key: Key(chatId),
              direction: DismissDirection.endToStart,
              background: _swipeBg('Delete'),
              confirmDismiss: (_) =>
                  _confirmDismiss('Delete conversation with $username?'),
              onDismissed: (_) => _deleteChat(chatId),
              child: InkWell(
                onTap: () async {
                  if (msgSnap.hasData) {
                    for (final d in msgSnap.data!.docs) {
                      final readBy = List<String>.from(
                          (d.data() as Map)['readBy'] as List? ?? []);
                      if (!readBy.contains(_myUid)) {
                        readBy.add(_myUid);
                        await d.reference.update({'readBy': readBy});
                      }
                    }
                  }
                  if (!mounted) return;
                  await Navigator.of(context).push(PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 350),
                    pageBuilder: (_, __, ___) => ChatBox(
                        contact: ChatContact(
                            id: otherUid,
                            username: username,
                            lastMessage: '',
                            time: timeStr,
                            unread: 0,
                            messages: [])),
                    transitionsBuilder: (_, anim, __, child) => SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(1, 0), end: Offset.zero)
                          .animate(CurvedAnimation(
                              parent: anim, curve: Curves.easeOut)),
                      child: child,
                    ),
                  ));
                },
                splashColor: _accent.withOpacity(0.08),
                child: Container(
                  color: hasUnread ? _unreadBg : Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(PageRouteBuilder(
                          transitionDuration: const Duration(milliseconds: 350),
                          pageBuilder: (_, __, ___) => UserProfilePage(
                            uid: otherUid,
                            username: username,
                            avatarBase64: avatar,
                          ),
                          transitionsBuilder: (_, anim, __, child) =>
                              SlideTransition(
                            position: Tween<Offset>(
                                    begin: const Offset(0, 1), end: Offset.zero)
                                .animate(CurvedAnimation(
                                    parent: anim, curve: Curves.easeOut)),
                            child: child,
                          ),
                        ));
                      },
                      child: Stack(children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: avatar == null
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: hasUnread
                                        ? [_accent, _accentDk]
                                        : [
                                            _accent.withOpacity(0.6),
                                            _accentDk.withOpacity(0.6)
                                          ],
                                  )
                                : null,
                          ),
                          child: avatar != null
                              ? ClipOval(
                                  child: Image.memory(base64Decode(avatar),
                                      width: 50, height: 50, fit: BoxFit.cover))
                              : Center(
                                  child: Text(username[0].toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700))),
                        ),
                        if (hasUnread)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFBF3A0A),
                                  shape: BoxShape.circle),
                              child: Center(
                                  child: Text('$unread',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800))),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(username,
                                    style: TextStyle(
                                        color: _darkText,
                                        fontSize: 14.5,
                                        fontWeight: hasUnread
                                            ? FontWeight.w700
                                            : FontWeight.w500)),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(timeStr,
                                        style: TextStyle(
                                            color: hasUnread
                                                ? _accentDk
                                                : _timeText,
                                            fontSize: 11,
                                            fontWeight: hasUnread
                                                ? FontWeight.w600
                                                : FontWeight.normal)),
                                    if (muteUntil != null) ...[
                                      const SizedBox(height: 3),
                                      Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                Icons
                                                    .notifications_off_outlined,
                                                color: Colors.grey.shade400,
                                                size: 11),
                                            const SizedBox(width: 2),
                                            Text(_muteLabel(myData, chatId),
                                                style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w500)),
                                          ]),
                                    ],
                                  ],
                                ),
                              ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            if (isMyMsg)
                              Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(Icons.done_all,
                                      color: _accent.withOpacity(0.8),
                                      size: 13)),
                            Expanded(
                                child: StreamBuilder<String>(
                              stream: _previewStream(chatId),
                              builder: (_, s) => Text(s.data ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: hasUnread ? _darkText : _bodyText,
                                      fontSize: 13,
                                      fontWeight: hasUnread
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                      fontStyle: FontStyle.italic)),
                            )),
                          ]),
                        ])),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _swipeBg(String label) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFFBF5B0A).withOpacity(0.12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.delete_outline_rounded,
              color: Color(0xFFBF5B0A), size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFFBF5B0A),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  Future<bool?> _confirmDismiss(String msg) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Text(msg, style: const TextStyle(fontSize: 13, height: 1.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: TextStyle(color: Colors.grey.shade500))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete',
                    style: TextStyle(
                        color: Color(0xFFBF5B0A),
                        fontWeight: FontWeight.w700))),
          ],
        ),
      );

  Widget _bottomNav() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          border:
              const Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, -2))
          ]),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 4, top: 8),
      child: Row(children: [
        _navItem(0, Icons.mail_outline, Icons.mail, 'LETTERS'),
        _navItem(1, Icons.people_outline, Icons.people, 'CONTACTS'),
      ]),
    );
  }

  Widget _navItem(int idx, IconData icon, IconData active, String label) {
    final sel = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (b) => (sel
                    ? _grad
                    : const LinearGradient(
                        colors: [Color(0xFFBBBBBB), Color(0xFFBBBBBB)]))
                .createShader(b),
            child: Icon(sel ? active : icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color: sel ? _accentDk : Colors.grey.shade400,
                  fontSize: 9,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: sel ? 24 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                  gradient: sel ? _grad : null,
                  borderRadius: BorderRadius.circular(2))),
        ]),
      ),
    );
  }
}

// ── Wax Seal Painter — realistic embossed stamp ────────────────────────
// 16-point scalloped border · inner ring · H monogram with serifs
// highlight arc for 3-D emboss effect
class _WaxSealPainter extends CustomPainter {
  final Color color;
  const _WaxSealPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // 1 ── Soft drop shadow ────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy + r * 0.10),
      r * 0.86,
      Paint()
        ..color = Colors.black.withOpacity(0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // 2 ── 16-point scalloped body ─────────────────────────────────
    const pts = 16;
    final outerR = r * 0.94;
    final innerR = r * 0.80;
    final body = Path();
    for (int i = 0; i < pts * 2; i++) {
      final angle = (i * math.pi / pts) - math.pi / 2;
      final radius = i.isEven ? outerR : innerR;
      final x = cx + radius * math.cos(angle);
      final y = cy + radius * math.sin(angle);
      i == 0 ? body.moveTo(x, y) : body.lineTo(x, y);
    }
    body.close();

    // Wax fill
    canvas.drawPath(
        body,
        Paint()
          ..color = color.withOpacity(0.20)
          ..style = PaintingStyle.fill);

    // Rim
    canvas.drawPath(
        body,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.058
          ..strokeJoin = StrokeJoin.round);

    // 3 ── Emboss highlight (top-left crescent) ────────────────────
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(cx - r * 0.14, cy - r * 0.14), radius: r * 0.50),
      -math.pi * 0.85,
      math.pi * 0.60,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.072
        ..strokeCap = StrokeCap.round,
    );

    // 4 ── Inner ring ──────────────────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.62,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.046,
    );

    // 5 ── H monogram ──────────────────────────────────────────────
    final hW = r * 0.26;
    final hH = r * 0.34;
    final mono = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.082;

    // verticals
    canvas.drawLine(Offset(cx - hW, cy - hH), Offset(cx - hW, cy + hH), mono);
    canvas.drawLine(Offset(cx + hW, cy - hH), Offset(cx + hW, cy + hH), mono);
    // crossbar
    canvas.drawLine(Offset(cx - hW, cy), Offset(cx + hW, cy), mono);

    // serif ticks (top & bottom of each vertical leg)
    final serif = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.046;
    final sw = r * 0.11;
    for (final x in [cx - hW, cx + hW]) {
      canvas.drawLine(Offset(x - sw, cy - hH), Offset(x + sw, cy - hH), serif);
      canvas.drawLine(Offset(x - sw, cy + hH), Offset(x + sw, cy + hH), serif);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Group long-press options bottom sheet (Messenger-style) ───────────
class _GroupOptionsSheet extends StatelessWidget {
  final String name;
  final bool isMuted;
  final VoidCallback onMute;
  final VoidCallback onUnmute;
  final VoidCallback onMarkRead;

  static const LinearGradient _grad = LinearGradient(
    colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)],
  );

  const _GroupOptionsSheet({
    required this.name,
    required this.isMuted,
    required this.onMute,
    required this.onUnmute,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),

        // Group name header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF4A2E14), Color(0xFF6B3F1A)],
                ),
              ),
              child: const Icon(Icons.people_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A))),
            ),
          ]),
        ),

        const Divider(height: 1),

        // Mute / Unmute
        _option(
          icon: isMuted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: isMuted ? 'Unmute notifications' : 'Mute notifications',
          onTap: isMuted ? onUnmute : onMute,
        ),

        // Mark as read
        _option(
          icon: Icons.done_all_rounded,
          label: 'Mark as read',
          onTap: onMarkRead,
        ),
      ]),
    );
  }

  Widget _option({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFD32F2F) : const Color(0xFF1A1A1A);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          ShaderMask(
            shaderCallback: (b) => danger
                ? const LinearGradient(
                        colors: [Color(0xFFD32F2F), Color(0xFFD32F2F)])
                    .createShader(b)
                : _grad.createShader(b),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          Text(label,
              style: TextStyle(
                  fontSize: 14, color: color, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
