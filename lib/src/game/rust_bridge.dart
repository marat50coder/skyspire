import 'dart:async';

import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';

/// Thin wrapper over the native (Rust) round-scoring engine.
///
/// The physics loop stays in Dart, but the authoritative multiplier and the
/// banked payout are owned by Rust: Dart reports each landed block and asks
/// for the payout at cash-out.
class RustScoring {
  /// Begins a fresh scoring round for [bet].
  void resetRound(int bet) => RoundReset(bet: bet).sendSignalToRust();

  /// Reports a settled block. [accuracy] is 0..1 (1 = dead-centre).
  void blockLanded(double accuracy) {
    final int bp = (accuracy.clamp(0.0, 1.0) * 1000).round();
    BlockLanded(accuracyBp: bp).sendSignalToRust();
  }

  /// Requests the authoritative payout from Rust. Returns `null` if the native
  /// report does not arrive promptly, so the UI can fall back to its estimate.
  Future<RoundReport?> cashOut(int bet) {
    final Completer<RoundReport?> completer = Completer<RoundReport?>();
    late final StreamSubscription<RustSignalPack<RoundReport>> sub;
    sub = RoundReport.rustSignalStream.listen((RustSignalPack<RoundReport> pack) {
      if (!completer.isCompleted) completer.complete(pack.message);
      sub.cancel();
    });
    CashOut(bet: bet).sendSignalToRust();
    return completer.future.timeout(
      const Duration(milliseconds: 400),
      onTimeout: () {
        sub.cancel();
        return null;
      },
    );
  }
}
