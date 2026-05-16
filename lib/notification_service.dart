import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

// ── Background message handler (top-level, not inside a class) ────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs
  await NotificationService.instance.showLocalNotification(message);
}

// ─────────────────────────────────────────────────────────────────────
// NotificationService
// Usage: call NotificationService.instance.init() in main() after
//        Firebase.initializeApp(). Then call saveToken() after login.
// ─────────────────────────────────────────────────────────────────────
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  // Android notification channel
  static const _channelId = 'hulak_messages';
  static const _channelName = 'Letters & Messages';
  static const _channelDesc =
      'Notifications for new letters and guild messages';

  Future<void> init() async {
    // 1. Request permission (iOS + Android 13+)
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // 2. Setup local notifications plugin
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 3. Create Android channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
      playSound: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 4. Set FCM foreground presentation options (iOS)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 5. Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 6. Foreground messages → show local notification
    FirebaseMessaging.onMessage.listen((message) async {
      await showLocalNotification(message);
    });

    // 7. Handle notification tap when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpen);

    // 8. Handle notification tap when app was terminated
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleMessageOpen(initial);
  }

  // ── Save FCM token to Firestore for the logged-in user ─────────────
  Future<void> saveToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _fcm.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'fcmToken': token});

    // Listen for token refresh
    _fcm.onTokenRefresh.listen((newToken) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': newToken});
    });
  }

  // ── Remove token on logout ──────────────────────────────────────────
  Future<void> removeToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'fcmToken': FieldValue.delete()});
    await _fcm.deleteToken();
  }

  // ── Show a local notification from a RemoteMessage ──────────────────
  Future<void> showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;
    if (notification == null) return;

    final title = notification.title ?? 'New Letter';
    final body = notification.body ?? '';

    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId, _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          // Use the app icon (Pigeon) as the notification icon.
          // This references @mipmap/ic_launcher which you set to Pigeon.png.
          icon: '@mipmap/ic_launcher',
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Navigation is handled by the app's router / AuthGate on resume.
    // You can parse response.payload here to deep-link into a specific chat.
  }

  void _handleMessageOpen(RemoteMessage message) {
    // Same as above — extend this to navigate to a chat screen if needed.
  }
}
