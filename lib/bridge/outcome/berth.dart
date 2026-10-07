// Berth — sealed outcome of the BridgeConductor's `decide()` call.
//
// Three concrete subclasses map 1:1 to the three screens the LaunchStage can
// swap to: the native game shell (HomeBerth), the external WebView portal
// (PortalBerth) and the offline fallback (UnreachableBerth).
//
// Also lives here: `TrailMemory`, the enum we persist in the SignalVault so
// repeat-boots can skip the verdict call. Wire names for the enum are rolled
// vs. the sibling template (fresh/opened/stayPut) so a bundle-dump that
// greps for `"portal"` or `"native"` finds nothing.
sealed class Berth {
  const Berth();
}

class HomeBerth extends Berth {
  const HomeBerth();
}

class PortalBerth extends Berth {
  const PortalBerth(this.destination);
  final String destination;
}

class UnreachableBerth extends Berth {
  const UnreachableBerth();
}

/// Persisted route decision. `fresh` = never seen a verdict,
/// `opened` = portal has been shown at least once (keep showing it),
/// `stayPut` = user belongs on the native HomeBerth forever.
enum TrailMemory {
  fresh('fr'),
  opened('op'),
  stayPut('sp');

  const TrailMemory(this.wire);

  /// Short wire token stored in the SignalVault. Picked to be two chars so
  /// a hex-dump of the preferences file is boring to read.
  final String wire;

  static TrailMemory parse(String? raw) {
    if (raw == null || raw.isEmpty) return TrailMemory.fresh;
    for (final value in TrailMemory.values) {
      if (value.wire == raw) return value;
    }
    // Legacy / sibling-template tokens — map them so a user migrating from
    // another portfolio build does not land on an UnreachableBerth loop.
    switch (raw) {
      case 'portal':
      case 'web':
        return TrailMemory.opened;
      case 'native':
      case 'game':
        return TrailMemory.stayPut;
      case 'undecided':
        return TrailMemory.fresh;
    }
    return TrailMemory.fresh;
  }
}
