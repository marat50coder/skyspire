// BridgeCourier — an `http.BaseClient` that attaches the forged UA to every
// request. We cannot rely on `WebView.userAgent` alone because:
//   • Verdict calls go through the dart `http` package.
//   • AppsFlyer GCD rescue also uses dart `http`.
//   • Partners that validate `User-Agent` server-side need the same string
//     the WebView will later advertise.
//
// This client ships one `User-Agent` header per request; everything else is
// delegated to the inner `http.Client` so proxy/certificate behaviour matches
// Flutter's default.
import 'package:http/http.dart' as http;

import 'gadget_fingerprint.dart';

class BridgeCourier extends http.BaseClient {
  BridgeCourier(this._applicationId) : _inner = http.Client();

  final String _applicationId;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Overwrite rather than appendIfAbsent — some callers set a dart-default
    // UA that would otherwise unmask the Flutter version.
    request.headers['User-Agent'] =
        GadgetFingerprint.currentUa(_applicationId);
    request.headers.putIfAbsent('Accept', () => '*/*');
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
