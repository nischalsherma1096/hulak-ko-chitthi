import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────
// UserProfilePage — view another user's avatar, username, block/unblock
// ─────────────────────────────────────────────────────────────────────
class UserProfilePage extends StatefulWidget {
  final String uid;
  final String username;
  final String? avatarBase64;

  const UserProfilePage({
    super.key,
    required this.uid,
    required this.username,
    this.avatarBase64,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with SingleTickerProviderStateMixin {
  static const LinearGradient _grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)],
  );
  static const Color _accent = Color(0xFFF5A623);
  static const Color _accentDark = Color(0xFFBF5B0A);
  static const Color _danger = Color(0xFFD32F2F);

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  String? _avatarBase64;
  bool _isBlocked = false;
  bool _loading = true;
  bool _toggling = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  String get _myUid => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _avatarBase64 = widget.avatarBase64;
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Fetch fresh avatar + check block status in parallel
    final myDoc = _db.collection('users').doc(_myUid).get();
    final theirDoc = _db.collection('users').doc(widget.uid).get();

    final results = await Future.wait([myDoc, theirDoc]);
    final myData = results[0].data() as Map<String, dynamic>? ?? {};
    final theirData = results[1].data() as Map<String, dynamic>? ?? {};

    if (mounted) {
      setState(() {
        _isBlocked = (List<String>.from(myData['blockedUsers'] as List? ?? []))
            .contains(widget.uid);
        _avatarBase64 =
            theirData['avatarBase64'] as String? ?? widget.avatarBase64;
        _loading = false;
      });
    }
  }

  Future<void> _toggleBlock() async {
    setState(() => _toggling = true);
    try {
      if (_isBlocked) {
        await _db.collection('users').doc(_myUid).update({
          'blockedUsers': FieldValue.arrayRemove([widget.uid]),
        });
        setState(() => _isBlocked = false);
        _showSnack('${widget.username} unblocked.');
      } else {
        final confirm = await _confirmBlock();
        if (confirm != true) {
          setState(() => _toggling = false);
          return;
        }
        await _db.collection('users').doc(_myUid).update({
          'blockedUsers': FieldValue.arrayUnion([widget.uid]),
        });
        setState(() => _isBlocked = true);
        _showSnack('${widget.username} blocked.');
      }
    } catch (_) {
      _showSnack('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<bool?> _confirmBlock() => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Block User',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Text(
              'Block ${widget.username}? They will no longer be able to send you messages.',
              style: const TextStyle(fontSize: 13, height: 1.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: TextStyle(color: Colors.grey.shade500))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Block',
                    style: TextStyle(
                        color: _danger, fontWeight: FontWeight.w700))),
          ],
        ),
      );

  void _openFullPhoto() {
    if (_avatarBase64 == null) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _FullAvatarViewer(
        avatarBase64: _avatarBase64!,
        username: widget.username,
      ),
    ));
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF6B3A10),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Column(children: [
          _buildAppBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF5A623)))
                : SingleChildScrollView(
                    child: Column(children: [
                      _buildAvatarSection(),
                      const SizedBox(height: 24),
                      _buildInfoCard(),
                      const SizedBox(height: 20),
                      _buildBlockButton(),
                      const SizedBox(height: 32),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 10,
          left: 4,
          right: 16,
          bottom: 14),
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
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 18)),
        ),
        const Expanded(
            child: Center(
                child: Text('PROFILE',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 2.5)))),
        const SizedBox(width: 40),
      ]),
    );
  }

  Widget _buildAvatarSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        gradient: _grad,
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
              color: _accentDark.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(children: [
        GestureDetector(
          onTap: _avatarBase64 != null ? _openFullPhoto : null,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.25),
              border:
                  Border.all(color: Colors.white.withOpacity(0.6), width: 2.5),
            ),
            child: ClipOval(
              child: _avatarBase64 != null
                  ? Image.memory(base64Decode(_avatarBase64!),
                      width: 100, height: 100, fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        widget.username.isNotEmpty
                            ? widget.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(widget.username,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        if (_avatarBase64 != null) ...[
          const SizedBox(height: 4),
          Text('Tap photo to view full screen',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                  fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }

  Widget _buildInfoCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  gradient: _grad, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.person_outline,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Username',
                  style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 10,
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(widget.username,
                  style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildBlockButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: _toggling ? null : _toggleBlock,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: _isBlocked ? Colors.white : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _isBlocked
                    ? _accent.withOpacity(0.4)
                    : _danger.withOpacity(0.35),
                width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: _toggling
              ? Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _isBlocked ? _accentDark : _danger)))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_isBlocked ? Icons.block_flipped : Icons.block_rounded,
                      color: _isBlocked ? _accentDark : _danger, size: 18),
                  const SizedBox(width: 10),
                  Text(
                      _isBlocked
                          ? 'Unblock ${widget.username}'
                          : 'Block ${widget.username}',
                      style: TextStyle(
                          color: _isBlocked ? _accentDark : _danger,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3)),
                ]),
        ),
      ),
    );
  }
}

// ── Full-screen avatar viewer (read-only, for other users) ─────────────
class _FullAvatarViewer extends StatelessWidget {
  final String avatarBase64;
  final String username;

  const _FullAvatarViewer({required this.avatarBase64, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: InteractiveViewer(
            child:
                Image.memory(base64Decode(avatarBase64), fit: BoxFit.contain),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                  child: Text(username,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
        ),
      ]),
    );
  }
}
