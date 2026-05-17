import "dart:async";
import "dart:math" as math;
import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "home_page.dart";
import "user_profile_page.dart";

class ChatBox extends StatefulWidget {
  final ChatContact contact;
  final bool isGroup;
  final String? groupId;

  const ChatBox({
    super.key,
    required this.contact,
    this.isGroup = false,
    this.groupId,
  });

  @override
  State<ChatBox> createState() => _ChatBoxState();
}

class _ChatBoxState extends State<ChatBox> with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  bool _showScrollToBottom = false;
  bool _sending = false;
  bool _isEditing = false;
  String? _editingMessageId;
  Map<String, dynamic>? _replyingTo;

  late AnimationController _entranceCtrl;
  late Animation<double> _entranceFade;

  static const List<String> _reactionEmojis = [
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
    '👍'
  ];

  static const Color _bgChat = Color(0xFFFAF6F0);
  static const Color _theirBubble = Color(0xFFFFFFFF);
  static const Color _myText = Color(0xFFFFFFFF);
  static const Color _theirText = Color(0xFF1A1A1A);
  static const Color _timeColor = Color(0xFF999999);
  static const Color _accent = Color(0xFFF5A623);
  static const Color _accentDark = Color(0xFFBF5B0A);
  static const LinearGradient _grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)],
  );

  String get _myUid => _auth.currentUser!.uid;

  String get _chatId {
    if (widget.isGroup && widget.groupId != null) return widget.groupId!;
    final ids = [_myUid, widget.contact.id]..sort();
    return ids.join('_');
  }

  CollectionReference get _msgs =>
      _db.collection('chats').doc(_chatId).collection('messages');
  DocumentReference get _chat => _db.collection('chats').doc(_chatId);

  // ── Lifecycle ──────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
    _entranceFade =
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeIn);

    _scrollController.addListener(() {
      final atBottom = _scrollController.offset >=
          _scrollController.position.maxScrollExtent - 80;
      if (atBottom != !_showScrollToBottom)
        setState(() => _showScrollToBottom = !atBottom);
    });

    final init = widget.isGroup
        ? {'lastUpdated': FieldValue.serverTimestamp()}
        : {
            'participants': [_myUid, widget.contact.id],
            'lastUpdated': FieldValue.serverTimestamp()
          };
    _chat.set(init, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ── Scroll ─────────────────────────────────────────────────────────
  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;
    final t = _scrollController.position.maxScrollExtent + 100;
    if (animated) {
      _scrollController.animateTo(t,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(t);
    }
  }

  // ── Send / Edit ────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    // Guard: check block status before sending (both directions)
    if (!widget.isGroup) {
      final myDoc = await _db.collection('users').doc(_myUid).get();
      final theirDoc =
          await _db.collection('users').doc(widget.contact.id).get();
      final myBlocked = List<String>.from(
          (myDoc.data() as Map<String, dynamic>?)?['blockedUsers'] as List? ??
              []);
      final theirBlocked = List<String>.from((theirDoc.data()
              as Map<String, dynamic>?)?['blockedUsers'] as List? ??
          []);
      if (myBlocked.contains(widget.contact.id) ||
          theirBlocked.contains(_myUid)) {
        _showSnack('You can\'t send messages to this person.');
        return;
      }
    }

    if (_isEditing && _editingMessageId != null) {
      await _saveEdit(text);
      return;
    }

    setState(() => _sending = true);
    _inputController.clear();
    try {
      final now = FieldValue.serverTimestamp();
      final msg = <String, dynamic>{
        'text': text,
        'senderId': _myUid,
        'timestamp': now,
        'readBy': [_myUid],
        'deletedFor': <String>[],
        'deletedForEveryone': false,
        'edited': false,
      };
      if (_replyingTo != null) msg['replyTo'] = _replyingTo;
      await _msgs.add(msg);

      final update = <String, dynamic>{
        'lastMessage': text,
        'lastSenderId': _myUid,
        'lastUpdated': now
      };
      if (!widget.isGroup) update['participants'] = [_myUid, widget.contact.id];
      await _chat.set(update, SetOptions(merge: true));

      setState(() => _replyingTo = null);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToBottom(animated: true));
    } catch (_) {
      if (mounted) {
        _inputController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Failed to send.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _saveEdit(String newText) async {
    setState(() => _sending = true);
    try {
      await _msgs.doc(_editingMessageId).update({
        'text': newText,
        'edited': true,
        'editedAt': FieldValue.serverTimestamp()
      });
      setState(() {
        _isEditing = false;
        _editingMessageId = null;
        _inputController.clear();
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _cancelEdit() => setState(() {
        _isEditing = false;
        _editingMessageId = null;
        _inputController.clear();
      });

  // ── Message actions ────────────────────────────────────────────────
  Future<void> _deleteForMe(String id) => _msgs.doc(id).update({
        'deletedFor': FieldValue.arrayUnion([_myUid])
      });
  Future<void> _burnForEveryone(String id) => _msgs
      .doc(id)
      .update({'deletedForEveryone': true, 'text': 'This letter was burned.'});
  Future<void> _addReaction(String id, String e) =>
      _msgs.doc(id).update({'reactions.$_myUid': e});
  Future<void> _removeReaction(String id) =>
      _msgs.doc(id).update({'reactions.$_myUid': FieldValue.delete()});
  Future<void> _markRead(String id) => _msgs.doc(id).update({
        'readBy': FieldValue.arrayUnion([_myUid])
      });

  // ── System message helper ──────────────────────────────────────────
  Future<void> _postSystem(String text) => _msgs.add({
        'text': text,
        'senderId': 'system',
        'timestamp': FieldValue.serverTimestamp(),
        'readBy': <String>[],
        'deletedFor': <String>[],
        'deletedForEveryone': false,
        'edited': false,
        'isSystem': true,
      });

  // ── Group admin actions ────────────────────────────────────────────
  Future<void> _makeAdmin(String uid, String username) async {
    await _chat.update({'adminUid': uid});
    await _postSystem('📜 $username is now the guild master.');
  }

  Future<void> _removeMember(String uid, String username) async {
    await _chat.update({
      'participants': FieldValue.arrayRemove([uid])
    });
    await _postSystem('📜 $username has been removed from the guild.');
  }

  Future<void> _leaveGuild() async {
    final snap = await _chat.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final adminUid = data['adminUid'] as String? ?? '';
    final parts = List<String>.from(data['participants'] as List? ?? []);
    final others = parts.where((id) => id != _myUid).toList();
    if (adminUid == _myUid && others.isNotEmpty) {
      _showSnack('Appoint a new guild master before leaving.');
      return;
    }
    final name = await _fetchName(_myUid);
    await _chat.update({
      'participants': FieldValue.arrayRemove([_myUid])
    });
    await _postSystem('📜 $name has left the guild.');
    if (others.isEmpty) {
      final msgs = await _msgs.get();
      for (final d in msgs.docs) await d.reference.delete();
      await _chat.delete();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteGuild() async {
    final snap = await _msgs.get();
    for (final d in snap.docs) await d.reference.delete();
    await _chat.delete();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _renameGuild(String newName) async {
    await _chat.update({'groupName': newName});
    await _postSystem('📜 Guild renamed to "$newName".');
  }

  Future<void> _addMembersToGuild(List<String> newUids) async {
    await _chat.update({'participants': FieldValue.arrayUnion(newUids)});
    for (final uid in newUids) {
      final name = await _fetchName(uid);
      await _postSystem('📜 $name has joined the guild.');
    }
  }

  Future<void> _blockUser() async {
    await _db.collection('users').doc(_myUid).update({
      'blockedUsers': FieldValue.arrayUnion([widget.contact.id]),
    });
    _showSnack('${widget.contact.username} blocked.');
    if (mounted) Navigator.of(context).pop();
  }

  void _showMuteOptions() {
    final options = [
      ('1 hour', DateTime.now().add(const Duration(hours: 1))),
      ('4 hours', DateTime.now().add(const Duration(hours: 4))),
      ('8 hours', DateTime.now().add(const Duration(hours: 8))),
      ('Always', DateTime(2099)),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text('Mute notifications',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          const Divider(height: 1),
          ...options.map((o) => InkWell(
                onTap: () async {
                  Navigator.pop(context);
                  await _db.collection('users').doc(_myUid).update({
                    'mutedChats.$_chatId': o.$2.millisecondsSinceEpoch,
                  });
                  _showSnack('Muted for ${o.$1}.');
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(children: [
                    const Icon(Icons.notifications_off_outlined,
                        color: Color(0xFFBF5B0A), size: 20),
                    const SizedBox(width: 14),
                    Text(o.$1, style: const TextStyle(fontSize: 14)),
                  ]),
                ),
              )),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ]),
      ),
    );
  }

  // ── Real-time stream watching BOTH users' block lists ──────────────
  // Uses Rx-style combineLatest via a StreamController so both sides
  // update in real time — exactly like Messenger.
  Stream<List<DocumentSnapshot>> _blockStream() {
    final myStream = _db.collection('users').doc(_myUid).snapshots();
    final theirStream =
        _db.collection('users').doc(widget.contact.id).snapshots();

    // Combine both snapshots so either side's change triggers a rebuild
    late StreamController<List<DocumentSnapshot>> controller;
    DocumentSnapshot? myDoc;
    DocumentSnapshot? theirDoc;

    void emit() {
      if (myDoc != null && theirDoc != null) {
        controller.add([myDoc!, theirDoc!]);
      }
    }

    controller = StreamController<List<DocumentSnapshot>>(
      onListen: () {
        myStream.listen((doc) {
          myDoc = doc;
          emit();
        });
        theirStream.listen((doc) {
          theirDoc = doc;
          emit();
        });
      },
    );
    return controller.stream;
  }

  // ── Blocked state banner (exactly like Messenger) ──────────────────
  Widget _blockedBanner({required bool iBlockedThem}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, color: Colors.grey.shade400, size: 24),
        const SizedBox(height: 8),
        Text(
          iBlockedThem
              ? 'You blocked ${widget.contact.username}'
              : "You can't reply to this conversation",
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          iBlockedThem
              ? 'Unblock to send a message'
              : '${widget.contact.username} is unavailable',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
              fontStyle: FontStyle.italic),
        ),
        if (iBlockedThem) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () async {
              await _db.collection('users').doc(_myUid).update({
                'blockedUsers': FieldValue.arrayRemove([widget.contact.id]),
              });
              _showSnack('${widget.contact.username} unblocked.');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
              decoration: BoxDecoration(
                gradient: _grad,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Unblock',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: const Color(0xFF6B3A10),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 3),
    ));
  }

  void _showRenameGuild() {
    final ctrl = TextEditingController(text: widget.contact.username);
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: const Text('Rename Guild',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              content: TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                      hintText: 'New guild name…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                              color: Color(0xFFF5A623), width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(color: Colors.grey.shade500))),
                TextButton(
                    onPressed: () async {
                      final name = ctrl.text.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(context);
                      await _renameGuild(name);
                    },
                    child: const Text('Rename',
                        style: TextStyle(
                            color: Color(0xFFBF5B0A),
                            fontWeight: FontWeight.w700))),
              ],
            ));
  }

  void _showAddMembers() async {
    final snap = await _chat.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final existing = List<String>.from(data['participants'] as List? ?? []);
    final selected = <String>{};
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (_) => StatefulBuilder(
              builder: (ctx, setSt) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                title: const Text('Add Members',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                content: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 300, minWidth: 240),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _db.collection('users').snapshots(),
                    builder: (_, uSnap) {
                      if (!uSnap.hasData)
                        return const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFF5A623)));
                      final users = uSnap.data!.docs
                          .where((d) => !existing.contains(d['uid']))
                          .toList();
                      if (users.isEmpty)
                        return Text('No new users to add.',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 13));
                      return ListView.builder(
                          shrinkWrap: true,
                          itemCount: users.length,
                          itemBuilder: (_, i) {
                            final u = users[i].data() as Map<String, dynamic>;
                            final uid = u['uid'] as String;
                            final nm = u['username'] as String? ?? '?';
                            return CheckboxListTile(
                              value: selected.contains(uid),
                              onChanged: (v) => setSt(() => v == true
                                  ? selected.add(uid)
                                  : selected.remove(uid)),
                              title: Text(nm,
                                  style: const TextStyle(fontSize: 13)),
                              activeColor: const Color(0xFFF5A623),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            );
                          });
                    },
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel',
                          style: TextStyle(color: Colors.grey.shade500))),
                  TextButton(
                      onPressed: () async {
                        if (selected.isEmpty) return;
                        Navigator.pop(ctx);
                        await _addMembersToGuild(selected.toList());
                      },
                      child: const Text('Add',
                          style: TextStyle(
                              color: Color(0xFFBF5B0A),
                              fontWeight: FontWeight.w700))),
                ],
              ),
            ));
  }

  // ── Guild panel ────────────────────────────────────────────────────
  void _showGuildPanel() async {
    final snap = await _chat.get();
    final data = snap.data() as Map<String, dynamic>? ?? {};
    final adminUid = data['adminUid'] as String? ?? '';
    final participants = List<String>.from(data['participants'] as List? ?? []);
    final amAdmin = adminUid == _myUid;
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GuildPanel(
        myUid: _myUid,
        adminUid: adminUid,
        amAdmin: amAdmin,
        participants: participants,
        db: _db,
        groupName: widget.contact.username,
        onMakeAdmin: (uid, name) {
          Navigator.pop(context);
          _confirm(
              'Transfer Leadership',
              'Make $name the guild master? You become a regular member.',
              'Transfer',
              () => _makeAdmin(uid, name));
        },
        onRemoveMember: (uid, name) {
          Navigator.pop(context);
          _confirm('Remove Member', 'Remove $name from the guild?', 'Remove',
              () => _removeMember(uid, name));
        },
        onLeave: () {
          Navigator.pop(context);
          _confirm('Leave Guild', 'Leave "${widget.contact.username}"?',
              'Leave', _leaveGuild);
        },
        onMute: () {
          Navigator.pop(context);
          _showMuteOptions();
        },
        onRename: amAdmin
            ? () {
                Navigator.pop(context);
                _showRenameGuild();
              }
            : null,
        onAddMembers: amAdmin
            ? () {
                Navigator.pop(context);
                _showAddMembers();
              }
            : null,
        onDelete: amAdmin
            ? () {
                Navigator.pop(context);
                _confirm(
                    'Disband Guild',
                    'Permanently disband "${widget.contact.username}"? All letters will be erased.',
                    'Disband',
                    _deleteGuild);
              }
            : null,
      ),
    );
  }

  // ── Long-press menu ────────────────────────────────────────────────
  void _showOptions(Map<String, dynamic> data, String msgId) {
    final isMe = data['senderId'] == _myUid;
    final isDeleted = data['deletedForEveryone'] == true;
    final text = data['text'] as String? ?? '';
    final myReaction = (data['reactions'] as Map?)?[_myUid] as String?;
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _OptionsSheet(
        isMe: isMe,
        isDeleted: isDeleted,
        text: text,
        myReaction: myReaction,
        onReact: (e) {
          Navigator.pop(context);
          myReaction == e ? _removeReaction(msgId) : _addReaction(msgId, e);
        },
        onReply: () {
          Navigator.pop(context);
          _fetchName(data['senderId'] as String).then((name) {
            setState(() =>
                _replyingTo = {'id': msgId, 'text': text, 'senderName': name});
          });
          _focusNode.requestFocus();
        },
        onCopy: () {
          Navigator.pop(context);
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating));
        },
        onEdit: isMe && !isDeleted
            ? () {
                Navigator.pop(context);
                setState(() {
                  _isEditing = true;
                  _editingMessageId = msgId;
                  _inputController.text = text;
                });
                _focusNode.requestFocus();
              }
            : null,
        onDeleteForMe: () {
          Navigator.pop(context);
          _confirm(
              'Remove for Me',
              'This letter will vanish from your view only.',
              'Remove',
              () => _deleteForMe(msgId));
        },
        onBurnForEveryone: isMe && !isDeleted
            ? () {
                Navigator.pop(context);
                _confirm(
                    'Burn for Everyone',
                    'This letter will be burned for all recipients.',
                    'Burn',
                    () => _burnForEveryone(msgId));
              }
            : null,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  Future<String> _fetchName(String uid) async {
    if (uid == 'system') return 'System';
    try {
      final d = await _db.collection('users').doc(uid).get();
      return (d.data() as Map<String, dynamic>?)?['username'] as String? ??
          'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  void _confirm(String title, String body, String label, VoidCallback fn) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(body, style: const TextStyle(fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.grey.shade500))),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                fn();
              },
              child: Text(label,
                  style: const TextStyle(
                      color: _accentDark, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  String _fmtTime(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = (ts as dynamic).toDate().toLocal() as DateTime;
      final h = dt.hour == 0
          ? 12
          : dt.hour > 12
              ? dt.hour - 12
              : dt.hour;
      return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
    } catch (_) {
      return '';
    }
  }

  bool _diffDay(dynamic a, dynamic b) {
    if (a == null || b == null) return false;
    try {
      final da = (a as dynamic).toDate().toLocal() as DateTime;
      final db = (b as dynamic).toDate().toLocal() as DateTime;
      return da.year != db.year || da.month != db.month || da.day != db.day;
    } catch (_) {
      return false;
    }
  }

  Widget _dateDivider(dynamic ts) {
    if (ts == null) return const SizedBox.shrink();
    try {
      final dt = (ts as dynamic).toDate().toLocal() as DateTime;
      final now = DateTime.now();
      String label;
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day)
        label = '— Today —';
      else if (dt.year == now.year &&
          dt.month == now.month &&
          now.day - dt.day == 1)
        label = '— Yesterday —';
      else
        label =
            '— ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} —';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFD4A853).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFD4A853).withOpacity(0.3), width: 0.8),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: Color(0xFF9E7E5A),
                    fontSize: 10,
                    fontStyle: FontStyle.italic)),
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgChat,
      body: FadeTransition(
        opacity: _entranceFade,
        child: Column(children: [
          _appBar(),
          Expanded(
              child: Stack(children: [
            CustomPaint(
              painter: _RuledPainter(),
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    _msgs.orderBy('timestamp', descending: false).snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: _accent));
                  }
                  final all = snap.data?.docs ?? [];
                  final docs = all.where((d) {
                    final data = d.data() as Map<String, dynamic>;
                    if (data['isSystem'] == true) return true;
                    return !List<String>.from(data['deletedFor'] as List? ?? [])
                        .contains(_myUid);
                  }).toList();

                  for (final d in all) {
                    final data = d.data() as Map<String, dynamic>;
                    final readBy =
                        List<String>.from(data['readBy'] as List? ?? []);
                    if (data['senderId'] != _myUid && !readBy.contains(_myUid))
                      _markRead(d.id);
                  }

                  if (docs.isEmpty)
                    return Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.mail_outline,
                                color: Colors.grey.shade300, size: 56),
                            const SizedBox(height: 12),
                            Text('No letters yet.\nWrite the first one!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    height: 1.6)),
                          ]),
                    );

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final doc = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      final isSystem = data['isSystem'] == true;
                      final isMe = data['senderId'] == _myUid;
                      final showDate = i == 0 ||
                          _diffDay((docs[i - 1].data() as Map)['timestamp'],
                              data['timestamp']);
                      return Column(children: [
                        if (showDate) _dateDivider(data['timestamp']),
                        if (isSystem)
                          _systemMsg(data['text'] as String? ?? '')
                        else
                          _bubble(
                              data: data,
                              msgId: doc.id,
                              isMe: isMe,
                              time: _fmtTime(data['timestamp'])),
                      ]);
                    },
                  );
                },
              ),
            ),
            if (_showScrollToBottom)
              Positioned(
                bottom: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => _scrollToBottom(animated: true),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 8)
                        ]),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: _accent, size: 22),
                  ),
                ),
              ),
          ])),
          if (_replyingTo != null) _replyBar(),
          if (_isEditing) _editBar(),
          // ── Block check: replace input with banner if blocked ────
          if (!widget.isGroup)
            StreamBuilder<List<DocumentSnapshot>>(
              stream: _blockStream(),
              builder: (ctx, snap) {
                final docs = snap.data ?? [];
                bool iBlockedThem = false;
                bool theyBlockedMe = false;

                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final blocked =
                      List<String>.from(data['blockedUsers'] as List? ?? []);
                  if (doc.id == _myUid && blocked.contains(widget.contact.id)) {
                    iBlockedThem = true;
                  }
                  if (doc.id == widget.contact.id && blocked.contains(_myUid)) {
                    theyBlockedMe = true;
                  }
                }

                if (iBlockedThem) return _blockedBanner(iBlockedThem: true);
                if (theyBlockedMe) return _blockedBanner(iBlockedThem: false);
                return _inputBar();
              },
            )
          else
            _inputBar(),
        ]),
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────
  Widget _appBar() {
    return Container(
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 12,
          bottom: 12),
      decoration: BoxDecoration(
        gradient: _grad,
        boxShadow: [
          BoxShadow(
              color: _accentDark.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(children: [
        IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
        // ── Avatar: taps open the contact's profile ─────────────────
        GestureDetector(
          onTap: widget.isGroup
              ? null
              : () async {
                  // Fetch their latest avatar before opening profile
                  final doc = await _db
                      .collection('users')
                      .doc(widget.contact.id)
                      .get();
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final avatar = data['avatarBase64'] as String?;
                  if (!mounted) return;
                  Navigator.of(context).push(PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 350),
                    pageBuilder: (_, __, ___) => UserProfilePage(
                      uid: widget.contact.id,
                      username: widget.contact.username,
                      avatarBase64: avatar,
                    ),
                    transitionsBuilder: (_, anim, __, child) => SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0, 1), end: Offset.zero)
                          .animate(CurvedAnimation(
                              parent: anim, curve: Curves.easeOut)),
                      child: child,
                    ),
                  ));
                },
          child: _ContactAvatar(
            uid: widget.isGroup ? null : widget.contact.id,
            isGroup: widget.isGroup,
            db: _db,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.contact.username,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
            Row(children: [
              Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: Color(0xFF6BCB6B), shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(
                  widget.isGroup
                      ? 'Postal guild'
                      : 'available to receive letters',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 10,
                      fontStyle: FontStyle.italic)),
            ]),
          ]),
        ),
        if (widget.isGroup)
          IconButton(
              onPressed: _showGuildPanel,
              icon: const Icon(Icons.shield_outlined,
                  color: Colors.white, size: 22))
        else
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 22),
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'clear')
                _confirm('Clear Conversation',
                    'Remove all letters for you only?', 'Clear', () async {
                  final s = await _msgs.get();
                  for (final m in s.docs)
                    await m.reference.update({
                      'deletedFor': FieldValue.arrayUnion([_myUid])
                    });
                });
              if (v == 'mute') _showMuteOptions();
              if (v == 'block')
                _confirm(
                    'Block User',
                    'Block ${widget.contact.username}? They cannot send you messages.',
                    'Block',
                    _blockUser);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'mute',
                  child: Row(children: [
                    Icon(Icons.notifications_off_outlined,
                        size: 18, color: Color(0xFFBF5B0A)),
                    SizedBox(width: 10),
                    Text('Mute notifications', style: TextStyle(fontSize: 13))
                  ])),
              const PopupMenuItem(
                  value: 'clear',
                  child: Row(children: [
                    Icon(Icons.delete_sweep_outlined,
                        size: 18, color: Color(0xFFBF5B0A)),
                    SizedBox(width: 10),
                    Text('Clear conversation', style: TextStyle(fontSize: 13))
                  ])),
              const PopupMenuItem(
                  value: 'block',
                  child: Row(children: [
                    Icon(Icons.block_rounded,
                        size: 18, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Block user',
                        style: TextStyle(fontSize: 13, color: Colors.redAccent))
                  ])),
            ],
          ),
      ]),
    );
  }

  Widget _systemMsg(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFD4A853).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFD4A853).withOpacity(0.25), width: 0.8),
            ),
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF9E7E5A),
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ),
        ),
      );

  Widget _replyBar() => Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF8EE),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _accent.withOpacity(0.4), width: 1)),
        child: Row(children: [
          Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                  color: _accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_replyingTo!['senderName'] as String? ?? '',
                    style: const TextStyle(
                        color: _accentDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_replyingTo!['text'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF9E7E5A),
                        fontSize: 12,
                        fontStyle: FontStyle.italic)),
              ])),
          GestureDetector(
              onTap: () => setState(() => _replyingTo = null),
              child: Icon(Icons.close, size: 18, color: Colors.grey.shade400)),
        ]),
      );

  Widget _editBar() => Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _accentDark.withOpacity(0.4), width: 1)),
        child: Row(children: [
          const Icon(Icons.edit, color: _accentDark, size: 16),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('Editing letter',
                  style: TextStyle(
                      color: _accentDark,
                      fontSize: 12,
                      fontStyle: FontStyle.italic))),
          GestureDetector(
              onTap: _cancelEdit,
              child: Icon(Icons.close, size: 18, color: Colors.grey.shade400)),
        ]),
      );

  Widget _bubble(
      {required Map<String, dynamic> data,
      required String msgId,
      required bool isMe,
      required String time}) {
    final isDeleted = data['deletedForEveryone'] == true;
    final isEdited = data['edited'] == true && !isDeleted;
    final text = data['text'] as String? ?? '';
    final readBy = List<dynamic>.from(data['readBy'] as List? ?? []);
    final reactions =
        Map<String, dynamic>.from(data['reactions'] as Map? ?? {});
    final replyTo = data['replyTo'] as Map<String, dynamic>?;
    final myReaction = reactions[_myUid] as String?;
    final reactionCounts = <String, int>{};
    for (final e in reactions.values)
      reactionCounts[e as String] = (reactionCounts[e] ?? 0) + 1;
    final readByOthers = readBy.where((id) => id != _myUid).isNotEmpty;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      builder: (_, v, child) => Opacity(opacity: v, child: child),
      child: GestureDetector(
        onLongPress: isDeleted ? null : () => _showOptions(data, msgId),
        child: Padding(
          padding: EdgeInsets.only(
              left: isMe ? 48 : 0, right: isMe ? 0 : 48, bottom: 6),
          child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (widget.isGroup && !isMe)
                  FutureBuilder<String>(
                    future: _fetchName(data['senderId'] as String? ?? ''),
                    builder: (_, s) => Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 2),
                        child: Text(s.data ?? '…',
                            style: const TextStyle(
                                color: _accentDark,
                                fontSize: 10,
                                fontWeight: FontWeight.w700))),
                  ),
                if (replyTo != null) _replyPreview(replyTo, isMe),
                Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.72),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isMe && !isDeleted ? _grad : null,
                    color: isDeleted
                        ? Colors.grey.shade200
                        : isMe
                            ? null
                            : _theirBubble,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 4,
                          offset: const Offset(0, 1))
                    ],
                    border: (!isMe && !isDeleted)
                        ? Border.all(color: const Color(0xFFEEEEEE), width: 1)
                        : null,
                  ),
                  child: Text(isDeleted ? '🔥 This letter was burned.' : text,
                      style: TextStyle(
                        color: isDeleted
                            ? Colors.grey.shade500
                            : isMe
                                ? _myText
                                : _theirText,
                        fontSize: isDeleted ? 12 : 14,
                        height: 1.45,
                        fontStyle: FontStyle.italic,
                      )),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding:
                      EdgeInsets.only(left: isMe ? 0 : 6, right: isMe ? 4 : 0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isEdited)
                      Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text('edited',
                              style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 9,
                                  fontStyle: FontStyle.italic))),
                    Text(time,
                        style:
                            const TextStyle(color: _timeColor, fontSize: 10)),
                    if (isMe && !isDeleted) ...[
                      const SizedBox(width: 3),
                      Icon(readByOthers ? Icons.done_all : Icons.done,
                          color: readByOthers ? _accent : Colors.grey.shade400,
                          size: 13),
                    ],
                  ]),
                ),
                if (reactionCounts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                        spacing: 4,
                        children: reactionCounts.entries.map((e) {
                          final mine = myReaction == e.key;
                          return GestureDetector(
                            onTap: () => mine
                                ? _removeReaction(msgId)
                                : _addReaction(msgId, e.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: mine
                                    ? _accent.withOpacity(0.15)
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: mine
                                        ? _accent.withOpacity(0.5)
                                        : Colors.grey.shade300,
                                    width: 0.8),
                              ),
                              child: Text('${e.key} ${e.value}',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          );
                        }).toList()),
                  ),
                const SizedBox(height: 4),
              ]),
        ),
      ),
    );
  }

  Widget _replyPreview(Map<String, dynamic> r, bool isMe) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color:
              isMe ? Colors.white.withOpacity(0.18) : const Color(0xFFFFF0DC),
          borderRadius: BorderRadius.circular(8),
          border: Border(
              left:
                  BorderSide(color: isMe ? Colors.white70 : _accent, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['senderName'] as String? ?? '',
              style: TextStyle(
                  color: isMe ? Colors.white : _accentDark,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(r['text'] as String? ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: isMe
                      ? Colors.white.withOpacity(0.8)
                      : const Color(0xFF9E7E5A),
                  fontSize: 11,
                  fontStyle: FontStyle.italic)),
        ]),
      );

  Widget _inputBar() => Container(
        padding: EdgeInsets.only(
            left: 10,
            right: 10,
            top: 8,
            bottom: MediaQuery.of(context).padding.bottom + 8),
        decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(
                top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, -2))
            ]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 130),
              decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFDDDDDD), width: 1)),
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    height: 1.5),
                decoration: InputDecoration(
                  hintText:
                      _isEditing ? 'Edit your letter…' : 'Write your letter…',
                  hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                      fontStyle: FontStyle.italic),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.edit_note_rounded,
                      color: Colors.grey.shade400, size: 20),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _sending
                        ? [
                            const Color(0xFFF5A623).withOpacity(0.5),
                            const Color(0xFFBF5B0A).withOpacity(0.5)
                          ]
                        : [const Color(0xFFF5A623), const Color(0xFFBF5B0A)]),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFBF5B0A).withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: _sending
                  ? const Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2)))
                  : Icon(_isEditing ? Icons.check : Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ]),
      );
}

// ── Contact avatar for chat header (shows real PP if available) ───────
class _ContactAvatar extends StatelessWidget {
  final String? uid;
  final bool isGroup;
  final FirebaseFirestore db;

  const _ContactAvatar(
      {required this.uid, required this.isGroup, required this.db});

  @override
  Widget build(BuildContext context) {
    if (isGroup || uid == null) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.25),
            border:
                Border.all(color: Colors.white.withOpacity(0.5), width: 1.5)),
        child: const Icon(Icons.people, color: Colors.white, size: 20),
      );
    }
    return FutureBuilder<DocumentSnapshot>(
      future: db.collection('users').doc(uid).get(),
      builder: (_, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final avatar = data['avatarBase64'] as String?;
        final username = data['username'] as String? ?? '?';
        return Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.25),
              border:
                  Border.all(color: Colors.white.withOpacity(0.5), width: 1.5)),
          child: ClipOval(
            child: avatar != null
                ? Image.memory(base64Decode(avatar),
                    width: 38, height: 38, fit: BoxFit.cover)
                : Center(
                    child: Text(
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

// ── Guild panel sheet ─────────────────────────────────────────────────
class _GuildPanel extends StatelessWidget {
  final String myUid, adminUid, groupName;
  final bool amAdmin;
  final List<String> participants;
  final FirebaseFirestore db;
  final void Function(String, String) onMakeAdmin;
  final void Function(String, String) onRemoveMember;
  final VoidCallback onLeave;
  final VoidCallback? onRename;
  final VoidCallback? onAddMembers;
  final VoidCallback onMute;
  final VoidCallback? onDelete;

  const _GuildPanel({
    required this.myUid,
    required this.adminUid,
    required this.amAdmin,
    required this.participants,
    required this.db,
    required this.groupName,
    required this.onMakeAdmin,
    required this.onRemoveMember,
    required this.onLeave,
    required this.onMute,
    this.onRename,
    this.onAddMembers,
    this.onDelete,
  });

  static const Color _accent = Color(0xFFF5A623);
  static const Color _accentDark = Color(0xFFBF5B0A);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        colors: [Color(0xFF4A2E14), Color(0xFF6B3F1A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)),
                child: const Icon(Icons.people, color: Colors.white, size: 22)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(groupName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('${participants.length} members',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic)),
                ])),
            if (amAdmin)
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: _accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('Guild Master',
                      style: TextStyle(
                          color: _accentDark,
                          fontSize: 10,
                          fontWeight: FontWeight.w700))),
          ]),
        ),
        const Divider(height: 1),
        // Member list
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.35),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: participants.length,
            itemBuilder: (_, i) {
              final uid = participants[i];
              final isAdmin = uid == adminUid;
              final isMe = uid == myUid;
              return FutureBuilder<DocumentSnapshot>(
                future: db.collection('users').doc(uid).get(),
                builder: (_, snap) {
                  final uData = snap.hasData && snap.data!.exists
                      ? snap.data!.data() as Map<String, dynamic>
                      : <String, dynamic>{};
                  final username = uData['username'] as String? ?? '…';
                  final avatar = uData['avatarBase64'] as String?;
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: avatar == null
                                ? const LinearGradient(
                                    colors: [
                                        Color(0xFFF5A623),
                                        Color(0xFFBF5B0A)
                                      ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight)
                                : null),
                        child: avatar != null
                            ? ClipOval(
                                child: Image.memory(base64Decode(avatar),
                                    fit: BoxFit.cover))
                            : Center(
                                child: Text(
                                    username.isNotEmpty
                                        ? username[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700)))),
                    title: Row(children: [
                      Text(isMe ? '$username (you)' : username,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isMe ? FontWeight.w600 : FontWeight.w400)),
                      if (isAdmin) ...[
                        const SizedBox(width: 6),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: _accent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text('admin',
                                style: TextStyle(
                                    color: _accentDark,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700))),
                      ],
                    ]),
                    trailing: (!isMe && amAdmin)
                        ? PopupMenuButton<String>(
                            icon: Icon(Icons.more_horiz,
                                color: Colors.grey.shade400, size: 20),
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            onSelected: (v) {
                              if (v == 'admin') onMakeAdmin(uid, username);
                              if (v == 'remove') onRemoveMember(uid, username);
                            },
                            itemBuilder: (_) => [
                              if (!isAdmin)
                                const PopupMenuItem(
                                    value: 'admin',
                                    child: Row(children: [
                                      Icon(Icons.shield_outlined,
                                          size: 16, color: Color(0xFFBF5B0A)),
                                      SizedBox(width: 10),
                                      Text('Make guild master',
                                          style: TextStyle(fontSize: 12))
                                    ])),
                              const PopupMenuItem(
                                  value: 'remove',
                                  child: Row(children: [
                                    Icon(Icons.person_remove_outlined,
                                        size: 16, color: Colors.redAccent),
                                    SizedBox(width: 10),
                                    Text('Remove from guild',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.redAccent))
                                  ])),
                            ],
                          )
                        : null,
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        // Admin actions
        if (onAddMembers != null)
          _action(Icons.person_add_outlined, 'Add members', _accentDark,
              onAddMembers!),
        if (onRename != null)
          _action(Icons.drive_file_rename_outline, 'Rename guild', _accentDark,
              onRename!),
        _action(Icons.notifications_off_outlined, 'Mute notifications',
            Colors.grey.shade600, onMute),
        _action(Icons.exit_to_app_rounded, 'Leave guild',
            Colors.orange.shade700, onLeave),
        if (onDelete != null)
          _action(Icons.delete_forever_rounded, 'Disband guild',
              Colors.red.shade600, onDelete!),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ]),
    );
  }

  Widget _action(
          IconData icon, String label, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.w500))
          ]),
        ),
      );
}

// ── Message options sheet ─────────────────────────────────────────────
class _OptionsSheet extends StatelessWidget {
  final bool isMe, isDeleted;
  final String text;
  final String? myReaction;
  final ValueChanged<String> onReact;
  final VoidCallback onReply, onCopy, onDeleteForMe;
  final VoidCallback? onEdit, onBurnForEveryone;

  const _OptionsSheet({
    required this.isMe,
    required this.isDeleted,
    required this.text,
    required this.myReaction,
    required this.onReact,
    required this.onReply,
    required this.onCopy,
    required this.onDeleteForMe,
    this.onEdit,
    this.onBurnForEveryone,
  });

  static const List<String> _emojis = ['❤️', '😂', '😮', '😢', '🙏', '👍'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        if (!isDeleted)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF8EE),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: const Color(0xFFF5A623).withOpacity(0.3),
                      width: 1)),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: _emojis.map((e) {
                    final sel = myReaction == e;
                    return GestureDetector(
                        onTap: () => onReact(e),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: sel
                                    ? const Color(0xFFF5A623).withOpacity(0.2)
                                    : Colors.transparent,
                                shape: BoxShape.circle),
                            child: Text(e,
                                style: TextStyle(fontSize: sel ? 26 : 22))));
                  }).toList()),
            ),
          ),
        const Divider(height: 1),
        _opt(Icons.reply_rounded, 'Reply', onReply),
        if (!isDeleted) _opt(Icons.copy_rounded, 'Copy text', onCopy),
        if (onEdit != null) _opt(Icons.edit_rounded, 'Edit letter', onEdit!),
        _opt(Icons.delete_outline_rounded, 'Delete for me', onDeleteForMe,
            color: Colors.red.shade400),
        if (onBurnForEveryone != null)
          _opt(Icons.local_fire_department_rounded, 'Burn for everyone',
              onBurnForEveryone!,
              color: Colors.red.shade700),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ]),
    );
  }

  Widget _opt(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final c = color ?? const Color(0xFF1A1A1A);
    return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 16),
            Text(label,
                style: TextStyle(
                    color: c, fontSize: 14, fontWeight: FontWeight.w500))
          ]),
        ));
  }
}

// ── Ruled lines painter ───────────────────────────────────────────────
class _RuledPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFF5A623).withOpacity(0.06)
      ..strokeWidth = 0.7;
    for (double y = 30; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
