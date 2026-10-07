// TapResolver — a tiny helper that returns the pending notification URL (if
// any) so BridgeConductor can hand it straight to the AperturePane without
// a second verdict call.
//
// Separate file so unit tests can stub it independently of NoticeStream.
import 'signal_vault.dart';

class TapResolver {
  const TapResolver._();

  static Future<String?> consume() => SignalVault.consumePendingSecureUrl();
}
