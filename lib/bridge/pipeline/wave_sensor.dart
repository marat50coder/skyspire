// WaveSensor — reach probe used by BridgeConductor and UnreachableWall.
//
// Guard against VPN false-negatives (pitfalls §3): `connectivity_plus`
// reports `ConnectivityResult.vpn` as a separate adapter, so we treat it as
// "live" and let the DNS probe decide whether the far side answers.
import 'dart:io' show InternetAddress;

import 'package:connectivity_plus/connectivity_plus.dart';

import '../charts/bridge_manifest.dart';

class WaveSensor {
  const WaveSensor._();

  static final Connectivity _channel = Connectivity();

  // Adapters we accept as "potentially online". VPN is included so the
  // probe does not instantly fail users routing through a corporate VPN.
  static const Set<ConnectivityResult> _liveAdapters = <ConnectivityResult>{
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.other,
  };

  /// `true` if we have any live adapter AND at least one probe host resolves.
  static Future<bool> isReachable() async {
    List<ConnectivityResult> adapters;
    try {
      adapters = await _channel.checkConnectivity();
    } catch (_) {
      // If the plugin itself throws, assume online — we don't want a dead
      // probe to lock the user on the UnreachableWall.
      return true;
    }
    if (!adapters.any(_liveAdapters.contains)) return false;
    return _resolveAnyProbe();
  }

  static Future<bool> _resolveAnyProbe() async {
    for (final host in kReachProbeHosts) {
      try {
        final list = await InternetAddress.lookup(host)
            .timeout(kReachProbeTimeout);
        if (list.isNotEmpty && list.first.rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // move on to the next host
      }
    }
    return false;
  }

  /// Reactive stream — emits whenever the connectivity adapter changes.
  /// AperturePane subscribes to this to toggle a transient banner.
  static Stream<bool> watchReachability() {
    return _channel.onConnectivityChanged.asyncMap((event) async {
      if (!event.any(_liveAdapters.contains)) return false;
      return _resolveAnyProbe();
    });
  }
}
