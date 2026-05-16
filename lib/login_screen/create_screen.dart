import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "../home/home_page.dart";

class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  bool _isLoading = false;

  static const Color _surface = Color(0xFF3D2408);
  static const Color _gold = Color(0xFFD4A853);
  static const Color _parchment = Color(0xFFF5DEB3);
  static const Color _inkRed = Color(0xFF8B1A1A);
  static const Color _dimText = Color(0xFF9E7E5A);

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
            CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  bool _validateUsername(String v) => RegExp(r'^[a-z0-9]+$').hasMatch(v);
  bool _validatePassword(String v) => !v.contains(' ') && v.length >= 6;

  // We store accounts with username@hulak.app as the email
  String _toEmail(String username) => '$username@hulak.app';

  Future<void> _createAccount() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (username.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = "All fields are required.");
      return;
    }
    if (!_validateUsername(username)) {
      setState(
          () => _errorMessage = "Username: only lowercase letters & numbers.");
      return;
    }
    if (username.length < 3) {
      setState(() => _errorMessage = "Username must be at least 3 characters.");
      return;
    }
    if (!_validatePassword(password)) {
      setState(() => _errorMessage = "Min 6 chars · no spaces.");
      return;
    }
    if (password != confirm) {
      setState(() => _errorMessage = "Passwords do not match.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Create Firebase Auth account
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _toEmail(username),
        password: password,
      );

      // 2. Update display name
      await credential.user!.updateDisplayName(username);

      // 3. Store user profile in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'uid': credential.user!.uid,
        'username': username,
        'createdAt': FieldValue.serverTimestamp(),
        'photoUrl': null,
      });

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 700),
          pageBuilder: (_, __, ___) => const HomePage(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
        switch (e.code) {
          case 'email-already-in-use':
            _errorMessage = "Username '$username' is already taken.";
            break;
          case 'weak-password':
            _errorMessage = "Password is too weak. Use at least 6 characters.";
            break;
          case 'invalid-email':
            _errorMessage = "Invalid username format.";
            break;
          default:
            _errorMessage = "Registration failed. Try again.";
        }
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Something went wrong. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2C1A0E), Color(0xFF4A2E14), Color(0xFF3D2008)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStampHeader(),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: _surface.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: _gold.withOpacity(0.35), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 24,
                                offset: const Offset(0, 8))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text("NEW POSTBOX",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: _gold,
                                    letterSpacing: 5)),
                            const SizedBox(height: 6),
                            Divider(
                                color: _gold.withOpacity(0.3), thickness: 1),
                            const SizedBox(height: 22),
                            _buildLabel("USERNAME"),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: _usernameController,
                              hint: "e.g. example123",
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[a-z0-9]'))
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text("Lowercase letters and numbers only",
                                style: TextStyle(
                                    color: _dimText.withOpacity(0.7),
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic)),
                            const SizedBox(height: 18),
                            _buildLabel("PASSWORD"),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: _passwordController,
                              hint: "••••••••",
                              obscure: _obscurePassword,
                              isPassword: true,
                              onToggleObscure: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                            const SizedBox(height: 4),
                            Text("Min 6 chars · no spaces",
                                style: TextStyle(
                                    color: _dimText.withOpacity(0.7),
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic)),
                            const SizedBox(height: 18),
                            _buildLabel("CONFIRM PASSWORD"),
                            const SizedBox(height: 6),
                            _buildTextField(
                              controller: _confirmPasswordController,
                              hint: "••••••••",
                              obscure: _obscureConfirm,
                              isPassword: true,
                              onToggleObscure: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                            const SizedBox(height: 12),
                            if (_errorMessage != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(_errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: _inkRed,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        height: 1.5)),
                              ),
                            const SizedBox(height: 6),
                            _buildPrimaryButton(
                                label: "REGISTER MY POSTBOX",
                                onTap: _isLoading ? null : _createAccount),
                            const SizedBox(height: 14),
                            _buildSecondaryButton(
                                label: "BACK TO LOGIN",
                                onTap: () => Navigator.of(context).pop()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text("Hulak Ko Chitthi",
                          style: TextStyle(
                              color: _dimText.withOpacity(0.5),
                              fontSize: 11,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStampHeader() {
    return Column(children: [
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _gold.withOpacity(0.5), width: 2),
          color: _surface.withOpacity(0.6),
        ),
        child: Center(
            child: Image.asset("assets/images/Pigeon.png",
                width: 52, height: 52, fit: BoxFit.contain)),
      ),
      const SizedBox(height: 14),
      Text("HULAK KO CHITTHI",
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _parchment,
              letterSpacing: 4)),
      const SizedBox(height: 4),
      Text("Register your postal address",
          style: TextStyle(
              fontSize: 11,
              color: _dimText,
              letterSpacing: 1.2,
              fontStyle: FontStyle.italic)),
    ]);
  }

  Widget _buildLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _gold,
          letterSpacing: 3));

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    bool isPassword = false,
    VoidCallback? onToggleObscure,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: _parchment, fontSize: 14),
      cursorColor: _gold,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _dimText.withOpacity(0.6), fontSize: 13),
        filled: true,
        fillColor: Colors.black.withOpacity(0.25),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: _gold.withOpacity(0.25))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: _gold.withOpacity(0.25))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: _gold, width: 1.5)),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                    color: _dimText, size: 18),
                onPressed: onToggleObscure)
            : null,
      ),
    );
  }

  Widget _buildPrimaryButton(
      {required String label, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: onTap == null ? _gold.withOpacity(0.5) : _gold,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
                color: _gold.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: _isLoading
            ? const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)))
            : Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFF2C1A0E),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5)),
      ),
    );
  }

  Widget _buildSecondaryButton(
      {required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: _gold.withOpacity(0.45), width: 1.5),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: _gold.withOpacity(0.85),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.5)),
      ),
    );
  }
}
