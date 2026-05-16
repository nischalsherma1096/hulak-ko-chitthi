import "dart:convert";
import "dart:typed_data";
import "dart:ui" as ui;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:image_picker/image_picker.dart";
import "../login_screen/login_screen.dart";
import "package:hulak_ko_chitthi/home/avatar_crop_screen.dart";

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  static const LinearGradient _headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)],
  );
  static const Color _gradBottom = Color(0xFFBF5B0A);
  static const Color _darkText = Color(0xFF1A1A1A);
  static const Color _bodyText = Color(0xFF555555);
  static const Color _divider = Color(0xFFEEEEEE);
  static const Color _danger = Color(0xFFD32F2F);

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  String _username = "";
  String? _avatarBase64;

  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _deletePasswordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();

  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showDeletePassword = false;
  bool _savingPassword = false;
  bool _uploadingAvatar = false;
  bool _deletingAccount = false;
  bool _savingUsername = false;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  User? get _user => _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF5A623),
      statusBarIconBrightness: Brightness.light,
    ));
    _loadProfile();
  }

  @override
  void dispose() {
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _deletePasswordCtrl.dispose();
    _usernameCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (_user == null) return;
    final doc = await _db.collection('users').doc(_user!.uid).get();
    if (doc.exists && mounted) {
      setState(() {
        _username = doc['username'] ?? _user!.displayName ?? '';
        _avatarBase64 = doc.data()?['avatarBase64'] as String?;
        _usernameCtrl.text = _username;
      });
    }
  }

  // ── Pick photo → full screen crop editor → save ───────────────────
  Future<void> _pickAndSaveAvatar() async {
    try {
      final xFile = await _picker.pickImage(source: ImageSource.gallery);
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      if (bytes.isEmpty) {
        _showSnack('Could not read the image. Try another photo.');
        return;
      }
      if (!mounted) return;
      final cropped = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => AvatarCropScreen(imageBytes: bytes)),
      );
      if (cropped == null || !mounted) return;

      setState(() => _uploadingAvatar = true);

      // Resize to 300×300 max to keep base64 under Firestore 1MB limit
      final codec = await ui.instantiateImageCodec(cropped,
          targetWidth: 300, targetHeight: 300);
      final frame = await codec.getNextFrame();
      final resized =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      final finalBytes = resized?.buffer.asUint8List() ?? cropped;

      final base64Str = base64Encode(finalBytes);
      if (base64Str.length > 900000) {
        setState(() => _uploadingAvatar = false);
        _showSnack('Image too large. Try a smaller photo.');
        return;
      }

      await _db
          .collection('users')
          .doc(_user!.uid)
          .update({'avatarBase64': base64Str});

      if (mounted) {
        setState(() {
          _avatarBase64 = base64Str;
          _uploadingAvatar = false;
        });
        _showSnack('Profile photo updated!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
        _showSnack('Could not open photo. Try again.');
      }
    }
  }

  // ── Avatar: remove ─────────────────────────────────────────────────
  Future<void> _removeAvatar() async {
    await _db
        .collection('users')
        .doc(_user!.uid)
        .update({'avatarBase64': FieldValue.delete()});
    if (mounted) {
      setState(() => _avatarBase64 = null);
      _showSnack("Photo removed.");
    }
  }

  // ── Full-screen photo viewer ───────────────────────────────────────
  void _openFullPhoto() {
    if (_avatarBase64 == null) return;
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _FullPhotoViewer(
        avatarBase64: _avatarBase64!,
        username: _username,
        onRemove: () async {
          Navigator.of(context).pop();
          await _removeAvatar();
        },
        onChange: () async {
          Navigator.of(context).pop();
          await _pickAndSaveAvatar();
        },
      ),
    ));
  }

  // ── Change username ────────────────────────────────────────────────
  void _showChangeUsername() {
    _usernameCtrl.text = _username;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Change Username',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: _usernameCtrl,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]'))
          ],
          decoration: InputDecoration(
            hintText: 'new_username',
            hintStyle: TextStyle(
                color: Colors.grey.shade400, fontStyle: FontStyle.italic),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFF5A623), width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.grey.shade500))),
          TextButton(
            onPressed: () async {
              final newName = _usernameCtrl.text.trim();
              if (newName.isEmpty || newName == _username) {
                Navigator.pop(context);
                return;
              }
              if (newName.length < 3) {
                _showSnack("Username must be at least 3 characters.");
                return;
              }
              Navigator.pop(context);
              setState(() => _savingUsername = true);
              try {
                // Check if taken
                final existing = await _db
                    .collection('users')
                    .where('username', isEqualTo: newName)
                    .get();
                if (existing.docs.isNotEmpty) {
                  _showSnack("Username already taken. Try another.");
                  return;
                }
                await _db
                    .collection('users')
                    .doc(_user!.uid)
                    .update({'username': newName});
                setState(() => _username = newName);
                _showSnack("Username updated!");
              } catch (_) {
                _showSnack("Failed to update username.");
              } finally {
                if (mounted) setState(() => _savingUsername = false);
              }
            },
            child: const Text('Save',
                style: TextStyle(
                    color: Color(0xFFBF5B0A), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Change password ────────────────────────────────────────────────
  Future<void> _savePassword() async {
    final currentPw = _currentPasswordCtrl.text;
    final newPw = _newPasswordCtrl.text.trim();
    if (currentPw.isEmpty) {
      _showSnack("Please enter your current password.");
      return;
    }
    if (newPw.length < 6) {
      _showSnack("New password must be at least 6 characters.");
      return;
    }
    if (currentPw == newPw) {
      _showSnack("New password must be different from current.");
      return;
    }
    setState(() => _savingPassword = true);
    try {
      final credential = EmailAuthProvider.credential(
          email: _user!.email!, password: currentPw);
      await _user!.reauthenticateWithCredential(credential);
      await _user!.updatePassword(newPw);
      _currentPasswordCtrl.clear();
      _newPasswordCtrl.clear();
      _showSnack("Password updated successfully!");
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          _showSnack("Current password is incorrect.");
          break;
        case 'weak-password':
          _showSnack("New password is too weak.");
          break;
        default:
          _showSnack("Failed to update password. Try again.");
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  // ── Delete account ─────────────────────────────────────────────────
  void _confirmDeleteAccount() {
    _deletePasswordCtrl.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _danger.withOpacity(0.1),
                      border: Border.all(color: _danger.withOpacity(0.3))),
                  child: const Icon(Icons.delete_forever,
                      color: _danger, size: 30)),
              const SizedBox(height: 16),
              const Text("DELETE ACCOUNT",
                  style: TextStyle(
                      color: _danger,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
              const SizedBox(height: 10),
              const Text(
                  "This will permanently delete your account, profile, and all your data.\n\nThis cannot be undone.",
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: _bodyText, fontSize: 13, height: 1.6)),
              const SizedBox(height: 20),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Confirm your password:",
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                          fontWeight: FontWeight.w600))),
              const SizedBox(height: 8),
              TextField(
                controller: _deletePasswordCtrl,
                obscureText: !_showDeletePassword,
                style: const TextStyle(color: _darkText, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Enter your password",
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF9F9F9),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _danger.withOpacity(0.3))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _danger.withOpacity(0.3))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _danger, width: 1.5)),
                  suffixIcon: GestureDetector(
                      onTap: () => setDialogState(
                          () => _showDeletePassword = !_showDeletePassword),
                      child: Icon(
                          _showDeletePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.grey.shade400,
                          size: 18)),
                ),
              ),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(
                    child: GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _deletePasswordCtrl.clear();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.grey.shade300, width: 1.5)),
                    child: Text("CANCEL",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5)),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: GestureDetector(
                  onTap: () async {
                    final pw = _deletePasswordCtrl.text;
                    Navigator.of(ctx).pop();
                    await _deleteAccount(pw);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                        color: _danger,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                              color: _danger.withOpacity(0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ]),
                    child: const Text("DELETE",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  ),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount(String password) async {
    if (password.isEmpty) {
      _showSnack("Password is required to delete your account.");
      return;
    }
    setState(() => _deletingAccount = true);
    try {
      final credential = EmailAuthProvider.credential(
          email: _user!.email!, password: password);
      await _user!.reauthenticateWithCredential(credential);
      final uid = _user!.uid;
      await _db.collection('users').doc(uid).delete();
      final chatsSnap = await _db
          .collection('chats')
          .where('participants', arrayContains: uid)
          .get();
      for (final chatDoc in chatsSnap.docs) {
        final msgs = await chatDoc.reference.collection('messages').get();
        for (final msg in msgs.docs) await msg.reference.delete();
        await chatDoc.reference.delete();
      }
      await _user!.delete();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, __, ___) => const LoginScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child)),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _deletingAccount = false);
        switch (e.code) {
          case 'wrong-password':
          case 'invalid-credential':
            _showSnack("Incorrect password. Account not deleted.");
            break;
          case 'requires-recent-login':
            _showSnack("Please log out and log back in, then try again.");
            break;
          default:
            _showSnack("Failed to delete account. Try again.");
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _deletingAccount = false);
        _showSnack("Something went wrong. Try again.");
      }
    }
  }

  // ── Unblock user ───────────────────────────────────────────────────
  Future<void> _unblock(String blockedUid, String blockedUsername) async {
    await _db.collection('users').doc(_user!.uid).update({
      'blockedUsers': FieldValue.arrayRemove([blockedUid]),
    });
    _showSnack("$blockedUsername unblocked.");
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: const Color(0xFF6B3A10),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      duration: const Duration(seconds: 3),
    ));
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text("Log Out",
            style: TextStyle(
                color: _darkText, fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text("Are you sure you want to log out?",
            style: TextStyle(color: _bodyText, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text("Cancel",
                  style: TextStyle(color: Colors.grey.shade500))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _auth.signOut();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 600),
                    pageBuilder: (_, __, ___) => const LoginScreen(),
                    transitionsBuilder: (_, animation, __, child) =>
                        FadeTransition(opacity: animation, child: child)),
                (route) => false,
              );
            },
            child: const Text("Log Out",
                style: TextStyle(color: _danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: _deletingAccount
            ? const Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                    CircularProgressIndicator(color: _danger),
                    SizedBox(height: 20),
                    Text("Deleting your account…",
                        style: TextStyle(
                            color: _bodyText,
                            fontSize: 14,
                            fontStyle: FontStyle.italic)),
                  ]))
            : Column(children: [
                _buildAppBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Column(children: [
                      _buildAvatarSection(),
                      const SizedBox(height: 24),
                      _buildSection(title: "Account", children: [
                        // Username row with edit button
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                          child: Row(children: [
                            _fieldIcon(Icons.person_outline),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text("Username",
                                      style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 10,
                                          letterSpacing: 0.5)),
                                  const SizedBox(height: 4),
                                  _savingUsername
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFF5A623)))
                                      : Text(_username,
                                          style: const TextStyle(
                                              color: _darkText,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500)),
                                ])),
                            GestureDetector(
                              onTap: _showChangeUsername,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    gradient: _headerGradient,
                                    borderRadius: BorderRadius.circular(16)),
                                child: const Text("Edit",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ]),
                        ),
                        Divider(height: 1, color: _divider, indent: 60),
                        _buildPasswordField(
                          icon: Icons.lock_outline,
                          label: "Current Password",
                          controller: _currentPasswordCtrl,
                          hint: "Enter current password",
                          showPassword: _showCurrentPassword,
                          onToggle: () => setState(() =>
                              _showCurrentPassword = !_showCurrentPassword),
                        ),
                        Divider(height: 1, color: _divider, indent: 60),
                        _buildPasswordField(
                          icon: Icons.lock_reset_outlined,
                          label: "New Password",
                          controller: _newPasswordCtrl,
                          hint: "Enter new password (min 6 chars)",
                          showPassword: _showNewPassword,
                          onToggle: () => setState(
                              () => _showNewPassword = !_showNewPassword),
                          showSaveButton: true,
                        ),
                      ]),
                      const SizedBox(height: 16),
                      // ── Blocked users section ────────────────────
                      _buildBlockedSection(),
                      const SizedBox(height: 16),
                      _buildLogoutButton(),
                      const SizedBox(height: 12),
                      _buildDeleteAccountButton(),
                    ]),
                  ),
                ),
              ]),
      ),
    );
  }

  // ── Blocked users list ─────────────────────────────────────────────
  Widget _buildBlockedSection() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('users').doc(_user!.uid).snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final blockedUids =
            List<String>.from(data['blockedUsers'] as List? ?? []);
        if (blockedUids.isEmpty) return const SizedBox.shrink();
        return _buildSection(title: "Blocked Accounts", children: [
          ...blockedUids
              .map((uid) => FutureBuilder<DocumentSnapshot>(
                    future: _db.collection('users').doc(uid).get(),
                    builder: (_, uSnap) {
                      final uData =
                          uSnap.data?.data() as Map<String, dynamic>? ?? {};
                      final username = uData['username'] as String? ?? uid;
                      return Column(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                          child: Row(children: [
                            _fieldIcon(Icons.block_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(username,
                                    style: const TextStyle(
                                        color: _darkText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500))),
                            GestureDetector(
                              onTap: () => _unblock(uid, username),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFD32F2F)
                                        .withOpacity(0.1),
                                    border: Border.all(
                                        color: const Color(0xFFD32F2F)
                                            .withOpacity(0.4)),
                                    borderRadius: BorderRadius.circular(16)),
                                child: const Text("Unblock",
                                    style: TextStyle(
                                        color: _danger,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ]),
                        ),
                        if (uid != blockedUids.last)
                          Divider(height: 1, color: _divider, indent: 60),
                      ]);
                    },
                  ))
              .toList(),
        ]);
      },
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
        gradient: _headerGradient,
        boxShadow: [
          BoxShadow(
              color: _gradBottom.withOpacity(0.4),
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
                child: Text("PROFILE",
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 2.5)))),
        const SizedBox(width: 22),
      ]),
    );
  }

  Widget _buildAvatarSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        gradient: _headerGradient,
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
              color: _gradBottom.withOpacity(0.25),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(children: [
        Stack(children: [
          // Avatar circle
          GestureDetector(
            onTap: _avatarBase64 != null ? _openFullPhoto : null,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.25),
                border: Border.all(
                    color: Colors.white.withOpacity(0.6), width: 2.5),
              ),
              child: ClipOval(
                child: _uploadingAvatar
                    ? Container(
                        color: Colors.black26,
                        child: const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2)))
                    : _avatarBase64 != null
                        ? Image.memory(base64Decode(_avatarBase64!),
                            width: 110, height: 110, fit: BoxFit.cover)
                        : Center(
                            child: Text(
                              _username.isNotEmpty
                                  ? _username[0].toUpperCase()
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
          // Camera button
          Positioned(
            bottom: 2,
            right: 2,
            child: GestureDetector(
              onTap: _uploadingAvatar ? null : _pickAndSaveAvatar,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _gradBottom.withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.15), blurRadius: 4)
                  ],
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: Color(0xFFBF5B0A), size: 17),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Text(_username,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(
          _avatarBase64 != null
              ? 'Tap photo to view  •  Camera to change'
              : 'Tap camera to add a photo',
          style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 11,
              fontStyle: FontStyle.italic),
        ),
      ]),
    );
  }

  Widget _buildSection(
      {required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  color: _gradBottom,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2)),
        ),
        Container(
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
          child: Column(children: children),
        ),
      ]),
    );
  }

  Widget _buildPasswordField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hint,
    required bool showPassword,
    required VoidCallback onToggle,
    bool showSaveButton = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(children: [
        _fieldIcon(icon),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            obscureText: !showPassword,
            style: const TextStyle(
                color: _darkText, fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              suffixIcon: GestureDetector(
                  onTap: onToggle,
                  child: Icon(
                      showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.grey.shade400,
                      size: 18)),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ),
        ])),
        if (showSaveButton) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _savingPassword ? null : _savePassword,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  gradient: _headerGradient,
                  borderRadius: BorderRadius.circular(20)),
              child: _savingPassword
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text("Save",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _fieldIcon(IconData icon) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            gradient: _headerGradient, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 16),
      );

  Widget _buildLogoutButton() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: _confirmLogout,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _danger.withOpacity(0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ]),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: _danger, size: 18),
                  SizedBox(width: 10),
                  Text("Log Out",
                      style: TextStyle(
                          color: _danger,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ]),
          ),
        ),
      );

  Widget _buildDeleteAccountButton() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: _confirmDeleteAccount,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
                color: _danger,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: _danger.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ]),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_forever_rounded,
                      color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Text("Delete My Account",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ]),
          ),
        ),
      );
}

// ── Full-screen photo viewer ──────────────────────────────────────────
class _FullPhotoViewer extends StatelessWidget {
  final String avatarBase64;
  final String username;
  final VoidCallback onRemove;
  final VoidCallback onChange;

  const _FullPhotoViewer({
    required this.avatarBase64,
    required this.username,
    required this.onRemove,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Photo
        Center(
          child: Hero(
            tag: 'avatar',
            child: InteractiveViewer(
              child:
                  Image.memory(base64Decode(avatarBase64), fit: BoxFit.contain),
            ),
          ),
        ),
        // Top bar
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
        // Bottom actions
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                top: 16,
                left: 24,
                right: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.85), Colors.transparent],
              ),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionBtn(Icons.delete_outline_rounded, "Remove",
                      Colors.red.shade400, onRemove),
                  _actionBtn(Icons.camera_alt_rounded, "Change",
                      const Color(0xFFF5A623), onChange),
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
              border: Border.all(color: color.withOpacity(0.6), width: 1.5)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
