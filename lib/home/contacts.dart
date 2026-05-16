import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chat_box.dart';
import 'home_page.dart';
import 'user_profile_page.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});
  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage>
    with SingleTickerProviderStateMixin {
  static const LinearGradient _grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)],
  );
  static const Color _accent = Color(0xFFF5A623);
  static const Color _accentDark = Color(0xFFBF5B0A);
  static const Color _darkText = Color(0xFF1A1A1A);
  static const Color _bodyText = Color(0xFF555555);
  static const Color _dimText = Color(0xFF999999);
  static const Color _divider = Color(0xFFEEEEEE);

  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  final _myUid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450))
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openProfile(Map<String, dynamic> userData) {
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => UserProfilePage(
        uid: userData['uid'] as String,
        username: userData['username'] as String? ?? '?',
        avatarBase64: userData['avatarBase64'] as String?,
      ),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    ));
  }

  void _openChat(Map<String, dynamic> userData) {
    final contact = ChatContact(
      id: userData['uid'],
      username: userData['username'],
      lastMessage: '',
      time: '',
      unread: 0,
      messages: [],
    );
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => ChatBox(contact: contact),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(children: [
        _buildSearchBar(),
        Expanded(
          // ✅ FIX: No orderBy — fetches ALL users reliably
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (ctx, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF5A623)));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmpty("No users on the server yet.");
              }

              final docs = snapshot.data!.docs
                  .where((d) => d['uid'] != _myUid)
                  .where((d) =>
                      _searchQuery.isEmpty ||
                      (d['username'] as String)
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()))
                  .toList();

              if (docs.isEmpty) {
                return _buildEmpty(_searchQuery.isNotEmpty
                    ? 'No contacts match "$_searchQuery"'
                    : "No other users yet.");
              }

              return Column(children: [
                _buildHeader(docs.length),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => Divider(
                        color: _divider, height: 1, indent: 76, endIndent: 16),
                    itemBuilder: (ctx, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      return _buildTile(data, i);
                    },
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: _darkText, fontSize: 14),
        cursorColor: _accent,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search contacts…',
          hintStyle: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
              fontStyle: FontStyle.italic),
          prefixIcon: ShaderMask(
            shaderCallback: (b) => _grad.createShader(b),
            child: const Icon(Icons.search, color: Colors.white, size: 20),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon:
                      Icon(Icons.close, color: Colors.grey.shade400, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  })
              : null,
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accent, width: 1.5)),
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        ShaderMask(
            shaderCallback: (b) => _grad.createShader(b),
            child: const Icon(Icons.people_alt_rounded,
                color: Colors.white, size: 15)),
        const SizedBox(width: 6),
        Text('$count ${count == 1 ? 'person' : 'people'} on the server',
            style: const TextStyle(
                color: _bodyText, fontSize: 12, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _buildTile(Map<String, dynamic> data, int index) {
    final username = data['username'] as String? ?? '?';
    final avatarBase64 = data['avatarBase64'] as String?; // ✅ local avatar
    final initial = username[0].toUpperCase();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 280 + index * 45),
      curve: Curves.easeOut,
      builder: (ctx, val, child) => Opacity(
          opacity: val,
          child: Transform.translate(
              offset: Offset(0, 16 * (1 - val)), child: child)),
      child: InkWell(
        onTap: () => _openChat(data),
        onLongPress: () => _openProfile(data),
        splashColor: _accent.withOpacity(0.08),
        highlightColor: _accent.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            // Avatar — tappable to view profile
            GestureDetector(
              onTap: () => _openProfile(data),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: avatarBase64 == null
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFF5A623), Color(0xFFBF5B0A)])
                      : null,
                  boxShadow: [
                    BoxShadow(
                        color: _accent.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: avatarBase64 != null
                    ? ClipOval(
                        child: Image.memory(
                          base64Decode(avatarBase64),
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Text(initial,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700))),
              ),
            ), // closes GestureDetector avatar
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(username,
                      style: const TextStyle(
                          color: _darkText,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  const Text(
                      "Tap to chat  •  Hold or tap photo to view profile",
                      style: TextStyle(
                          color: _dimText,
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic)),
                ])),
            Icon(Icons.chevron_right_rounded,
                color: _accentDark.withOpacity(0.4), size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildEmpty(String msg) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      ShaderMask(
          shaderCallback: (b) => _grad.createShader(b),
          child: const Icon(Icons.person_search_rounded,
              color: Colors.white, size: 58)),
      const SizedBox(height: 14),
      Text(msg,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
              fontStyle: FontStyle.italic,
              height: 1.6)),
    ]));
  }
}
