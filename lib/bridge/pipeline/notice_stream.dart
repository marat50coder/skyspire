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
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../shell/spire_shell.dart' show rootNavigatorKey;
import '../charts/bridge_manifest.dart';
import '../scenes/aperture_pane.dart';
import 'signal_vault.dart';

/// Observed state so callers (SpireShell) can rebuild once the push token
/// arrives — nothing in the pipeline blocks on it though.
///
/// This also powers the "push-token-after-offline-boot" recovery: if the
/// first verdict call shipped with push_token=null (because FCM needed the
/// network and the user installed via OneLink on a dead connection), the
/// BridgeConductor listens here for a later token arrival and fires a
/// background refresh POST so the partner can finally arm notifications.
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

  /// Cached applicationId so `_routeTo(url)` can construct an AperturePane
  /// without a BuildContext. Populated by `prime()` / `primeToken()`.
  /// If a notification tap fires before either prime(), we simply fall back
  /// to the stash path (SignalVault) and let BridgeConductor pick it up on
  /// the next cold-start.
  String? _applicationId;

  /// Full prime — raises the Android 13+ permission dialog and wires every
  /// callback. Called by OptInCurtain after the user taps Accept.
  Future<void> prime({String? applicationId}) async {
    if (applicationId != null) _applicationId = applicationId;
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
  Future<void> primeToken({String? applicationId}) async {
    if (applicationId != null) _applicationId = applicationId;
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
    // Pass coldStart=true so we DO NOT try to pushReplacement — the root
    // navigator is not mounted yet; LaunchStage will consume the stashed URL
    // through TapResolver and route to AperturePane itself.
    try {
      final initial = await messaging.getInitialMessage();
      if (initial != null) await _bridgePendingUrl(initial, coldStart: true);
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

  // Warm tap: FCM delivered a notification, user tapped it, app came back
  // from background. The navigator is mounted — route them straight into
  // AperturePane with the payload URL. The old implementation only stashed
  // the URL in SignalVault, which was never read until the next cold start
  // (BridgeConductor.decide() does not re-run while the app is alive), so
  // the user would see the current screen stay put after tapping the push.
  Future<void> _onOpened(RemoteMessage msg) =>
      _bridgePendingUrl(msg, coldStart: false);

  Future<void> _bridgePendingUrl(
    RemoteMessage msg, {
    required bool coldStart,
  }) async {
    final url = msg.data['url']?.toString();
    if (url == null || url.isEmpty) return;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !(parsed.isScheme('http') || parsed.isScheme('https'))) {
      return;
    }
    // Always stash as a safety net — if _routeTo fails (navigator not ready,
    // disposed, etc.) the next cold boot will still pick it up.
    await SignalVault.stashPendingSecureUrl(url);
    if (!coldStart) _routeTo(url);
  }

  // Local notification shown while the app was in the foreground. By the
  // time the user taps it the app is already running, so we take the warm
  // path (navigate directly). Still stash as a fallback.
  Future<void> _onLocalTap(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final parsed = Uri.tryParse(payload);
    if (parsed == null || !(parsed.isScheme('http') || parsed.isScheme('https'))) {
      return;
    }
    await SignalVault.stashPendingSecureUrl(payload);
    _routeTo(payload);
  }

  /// Push the user into an AperturePane pointing at [url] using the root
  /// navigator key. Silent no-op if either the navigator is not yet mounted
  /// (very early boot) or we never learnt the applicationId — in those cases
  /// the URL already lives in SignalVault, so a subsequent cold boot will
  /// surface it via TapResolver.
  void _routeTo(String url) {
    final navigator = rootNavigatorKey.currentState;
    final appId = _applicationId;
    if (navigator == null || appId == null) {
      if (kDebugMode) {
        debugPrint('[NoticeStream] warm route skipped '
            '(nav=${navigator != null}, appId=${appId != null})');
      }
      return;
    }
    // pushReplacement rather than push so the user cannot swipe back into
    // whatever ephemeral screen (LaunchStage, HomeBerth, OptInCurtain) they
    // were on when the notification fired.
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AperturePane(
          destination: url,
          applicationId: appId,
        ),
      ),
    );
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
