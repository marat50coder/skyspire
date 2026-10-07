// NoticeStream — Firebase Cloud Messaging + flutter_local_notifications.
//
// Boots lazily: `OptInCurtain` only calls `prime()` after the user agrees to
// notifications, and `TapResolver` consumes the deep-link URL (if any) when
// the user taps a notification that opens the app from cold.
//
// All failure paths are swallowed. Push is a nice-to-have; the gray-flow
// pipeline MUST still work for users who deny the OS prompt.
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../charts/bridge_manifest.dart';
import 'signal_vault.dart';

/// Observed state so callers (SpireShell) can rebuild once the push token
/// arrives — nothing in the pipeline blocks on it though.
class NoticePresence extends ChangeNotifier {
  String? _token;
  String? get token => _token;

  void _ingest(String? value) {
    if (value == _token) return;
    _token = value;
    notifyListeners();
  }
}

class NoticeStream {
  NoticeStream._();

  static final NoticeStream instance = NoticeStream._();
  final NoticePresence presence = NoticePresence();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _primed = false;
  bool _tokenPrimed = false;

  /// Full prime — raises the Android 13+ permission dialog and wires every
  /// callback. Called by OptInCurtain after the user taps Accept.
  Future<void> prime() async {
    if (_primed) return;
    _primed = true;
    try {
      await _wireLocal();
      await _wireRemote(requestPermission: true);
    } catch (_) {}
  }

  /// Lightweight prime — resolves the FCM token WITHOUT raising the system
  /// permission dialog. Safe to call from main() so the token is already
  /// cached in NoticePresence by the time BridgeConductor.compose() assembles
  /// the verdict body. Without this the first verdict always went out with
  /// `push_token: null` because `prime()` only ran after the user tapped
  /// Accept — much later than the config POST.
  Future<void> primeToken() async {
    if (_tokenPrimed) return;
    _tokenPrimed = true;
    try {
      await _wireRemote(requestPermission: false);
    } catch (_) {}
  }

  Future<void> _wireLocal() async {
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const settings = InitializationSettings(android: androidInit);
    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: _onLocalTap,
    );
    final androidPlugin =
        _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        kNoticeChannelId,
        kNoticeChannelName,
        description: kNoticeChannelDesc,
        importance: Importance.high,
      );
      try {
        await androidPlugin.createNotificationChannel(channel);
        await androidPlugin.requestNotificationsPermission();
      } catch (_) {}
    }
  }

  Future<void> _wireRemote({required bool requestPermission}) async {
    final messaging = FirebaseMessaging.instance;
    if (requestPermission) {
      try {
        await messaging.requestPermission(
            alert: true, badge: true, sound: true);
      } catch (_) {}
    }
    try {
      final token = await messaging.getToken();
      presence._ingest(token);
    } catch (_) {}
    messaging.onTokenRefresh.listen(presence._ingest);

    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);

    // Cold-start: if the app was launched from a notification, stash the
    // destination so TapResolver can pick it up when BridgeConductor runs.
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) await _bridgePendingUrl(initial);
    } catch (_) {}
  }

  Future<void> _onForeground(RemoteMessage msg) async {
    try {
      final title = msg.notification?.title ?? msg.data['title']?.toString();
      final body = msg.notification?.body ?? msg.data['body']?.toString();
      if (title == null && body == null) return;
      await _local.show(
        msg.hashCode & 0x7fffffff,
        title ?? kNoticeChannelName,
        body ?? '',
        _localDetails(),
        payload: msg.data['url']?.toString(),
      );
    } catch (_) {}
  }

  Future<void> _onOpened(RemoteMessage msg) => _bridgePendingUrl(msg);

  Future<void> _bridgePendingUrl(RemoteMessage msg) async {
    final url = msg.data['url']?.toString();
    if (url == null || url.isEmpty) return;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !(parsed.isScheme('http') || parsed.isScheme('https'))) {
      return;
    }
    await SignalVault.stashPendingSecureUrl(url);
  }

  Future<void> _onLocalTap(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    await SignalVault.stashPendingSecureUrl(payload);
  }

  NotificationDetails _localDetails() {
    const android = AndroidNotificationDetails(
      kNoticeChannelId,
      kNoticeChannelName,
      channelDescription: kNoticeChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );
    return const NotificationDetails(android: android);
  }
}
