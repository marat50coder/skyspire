// AperturePane — WebView host for the external PortalBerth destination.
//
// Responsibilities:
//   • Immersive-sticky system UI, orientation unlocked.
//   • Bounded redirect-loop retry (pitfalls §4, kRedirectLoopRetries).
//   • Debounced reach drops (kReachDropDebounce) → UnreachableWall swap.
//   • External scheme hand-off (tel:, mailto:, intent://, etc.) via url_launcher.
//   • File-picker bridging through the native `spire/canvas-picker` method
//     channel — we deliberately avoid the file_picker package (pitfalls §2).
//   • Lens enhancer bundle injection on every page finish.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../shell/spire_theme.dart';
import '../charts/bridge_manifest.dart';
import '../pipeline/gadget_fingerprint.dart';
import '../pipeline/lens_enhancers.dart';
import '../pipeline/wave_sensor.dart';
import 'unreachable_wall.dart';

class AperturePane extends StatefulWidget {
  const AperturePane({
    super.key,
    required this.destination,
    required this.applicationId,
  });

  final String destination;
  final String applicationId;

  @override
  State<AperturePane> createState() => _AperturePaneState();
}

class _AperturePaneState extends State<AperturePane> {
  static const MethodChannel _canvasPicker =
      MethodChannel(kCanvasPickerChannel);

  late final WebViewController _controller;
  StreamSubscription<bool>? _reachSub;
  Timer? _reachDebounce;
  int _redirectRetries = 0;
  String? _lastFailedUrl;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: const <SystemUiOverlay>[],
    );
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller = _spinUp();
    _watchReach();
  }

  WebViewController _spinUp() {
    final params = Platform.isAndroid
        ? AndroidWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();
    final ctl = WebViewController.fromPlatformCreationParams(params);
    ctl
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(SpirePalette.abyssDeep)
      ..setUserAgent(GadgetFingerprint.currentUa(widget.applicationId))
      ..enableZoom(false)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: _afterLoad,
        onWebResourceError: _onWebError,
        onNavigationRequest: _gateNavigation,
      ));

    final platform = ctl.platform;
    if (platform is AndroidWebViewController) {
      platform
        ..setMediaPlaybackRequiresUserGesture(false)
        ..setOnShowFileSelector(_showFileSelector);
    }

    ctl.loadRequest(Uri.parse(widget.destination));
    return ctl;
  }

  void _watchReach() {
    _reachSub = WaveSensor.watchReachability().listen((live) {
      _reachDebounce?.cancel();
      if (live) {
        // Transient drops recover on their own — nothing to do.
        return;
      }
      _reachDebounce = Timer(kReachDropDebounce, () async {
        if (!mounted) return;
        final stillDown = !(await WaveSensor.isReachable());
        if (!mounted || !stillDown) return;
        _toUnreachable();
      });
    });
  }

  Future<void> _afterLoad(String url) async {
    _redirectRetries = 0;
    try {
      await _controller.runJavaScript(LensEnhancers.assembleBundle());
    } catch (_) {}
  }

  void _onWebError(WebResourceError e) {
    // Codes -1007 (ERR_NAME_NOT_RESOLVED on iOS) and -9 (iOS: cancelled by
    // redirect) spike during legitimate hopping between CDN edges — only
    // treat them as fatal once we exceed the retry budget. All other codes
    // short-circuit straight to UnreachableWall.
    final code = e.errorCode;
    final isMainFrame = e.isForMainFrame ?? true;
    if (!isMainFrame) return;
    if (code == -1007 || code == -9 || code == -2 /* no connection */) {
      _redirectRetries++;
      if (_redirectRetries <= kRedirectLoopRetries) {
        _controller.reload();
        return;
      }
    }
    _lastFailedUrl = e.url;
    _toUnreachable();
  }

  Future<NavigationDecision> _gateNavigation(NavigationRequest req) async {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;
    final allowed = <String>{'http', 'https', 'about', 'data', 'blob'};
    if (allowed.contains(uri.scheme)) {
      return NavigationDecision.navigate;
    }
    // Hand off tel:, mailto:, intent:// etc. to the OS. Swallow failure so a
    // broken scheme does not strand the user on a blank page.
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    return NavigationDecision.prevent;
  }

  Future<List<String>> _showFileSelector(
      FileSelectorParams params) async {
    try {
      final result = await _canvasPicker.invokeMethod<List<Object?>>(
        'pick',
        <String, dynamic>{
          'allowMultiple': params.mode == FileSelectorMode.openMultiple,
          'types': params.acceptTypes,
        },
      );
      if (result == null) return const <String>[];
      return result.whereType<String>().toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  void _toUnreachable() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => UnreachableWall(
          onRetryBuild: (_) => AperturePane(
            destination: _lastFailedUrl ?? widget.destination,
            applicationId: widget.applicationId,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _reachSub?.cancel();
    _reachDebounce?.cancel();
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    // Keep immersive sticky — user explicitly asked to never show the
    // Android system navigation bar inside the shell.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }
        // Nothing to pop back to inside the webview — hand control to the
        // native navigator (which usually means closing the Berth).
        if (!context.mounted) return;
        Navigator.of(context).maybePop();
      },
      child: Scaffold(
        backgroundColor: SpirePalette.abyssDeep,
        body: SafeArea(
          minimum: EdgeInsets.zero,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}
