import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ui/palette.dart';

/// Privacy Policy / Support pages shown inside the app.
class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (WebResourceError error) {
            if (!error.isForMainFrame!) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _failed = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _retry() {
    setState(() {
      _failed = false;
      _loading = true;
    });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Palette.barDark,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: <Widget>[
          if (!_failed) WebViewWidget(controller: _controller),
          if (_loading && !_failed)
            const Center(
              child: CircularProgressIndicator(color: Palette.blue),
            ),
          if (_failed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.wifi_off, size: 46, color: Colors.black38),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not load the page.\nCheck your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 15),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
