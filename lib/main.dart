import "package:flutter/material.dart";
import "package:firebase_core/firebase_core.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:hulak_ko_chitthi/login_screen/login_screen.dart";
import "package:hulak_ko_chitthi/home/home_page.dart";
import "firebase_options.dart";
import "startup_page.dart";
import "notification_service.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialise push notifications
  await NotificationService.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ── App display name ───────────────────────────────────────────
      title: "Hulak ko Chitthi",
      debugShowCheckedModeBanner: false,
      home: StartupPage(nextPage: const _AuthGate()),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF2C1A0E),
            body: Center(
                child: CircularProgressIndicator(color: Color(0xFFD4A853))),
          );
        }
        if (snapshot.hasData) {
          // Save FCM token whenever a user is logged in
          NotificationService.instance.saveToken();
          return const HomePage();
        }
        return const LoginScreen();
      },
    );
  }
}
