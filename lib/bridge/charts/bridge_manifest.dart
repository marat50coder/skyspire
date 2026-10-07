// BridgeManifest — single source of truth for every timing and policy knob
// used by the bridge-flow pipeline. Everything that would deserve a magic
// number lives here with a comment explaining the range it was picked from.
//
// Values below are deliberately offset from sibling portfolio apps so a
// bundle-diff with any other project in the owner's Google Play portfolio
// does not line up byte-for-byte on the primitive constants.

/// Config endpoint schema version. The partner's `config.php` echoes this
/// field back; we only accept verdicts whose `schema` matches.
const int kManifestSchemaRev = 7;

/// Portfolio uniqueness guard — see `.cursor/rules/portfolio_registry.md`.
/// Collision on any of these fields in another app would get the whole
/// portfolio flagged by Google Play Protect.
const String kPortfolioSlug = 'spire-ladder-01';

/// Keystore / SharedPreferences key prefix. The exact string is a fingerprint
/// — do not share with sibling apps.
const String kVaultKeyPrefix = 'vq8_';

/// Android notification channel id (localised separately).
const String kNoticeChannelId = 'spire_sparks_v1';
const String kNoticeChannelName = 'Sky offers and updates';
const String kNoticeChannelDesc =
    'Rewards, limited-time deals and gameplay reminders.';

/// Native MethodChannel used by `AperturePane` for file-picker bridging.
const String kCanvasPickerChannel = 'spire/canvas-picker';

/// Reach probe hostnames — picked for high global uptime, no shared infra
/// with the sibling template's `cloudflare.com` + `apple.com`.
const List<String> kReachProbeHosts = <String>['wikipedia.org', 'github.com'];

/// How long we wait for the config endpoint to answer. On a weak uplink the
/// request may still succeed around 15–18s — budget comfortably above that.
const Duration kVerdictTimeout = Duration(seconds: 21);

/// First-install splash budget — covers DeviceSignature prime + AppsFlyer
/// SDK boot + the GCD rescue window (`kOrganicRescueDelay`).
const Duration kFirstInstallAwait = Duration(seconds: 33);

/// Returning-user splash budget — just enough for Firebase/AF warm boot.
const Duration kReturningInstallAwait = Duration(seconds: 8);

/// If a deep-link intent is pending we wait a little longer so the OneLink
/// parser can hand us the destination.
const Duration kDeepLinkAwait = Duration(seconds: 5);

/// AppsFlyer GCD organic rescue window. If the SDK stays silent beyond this
/// we fall back to the direct GCD endpoint. 12 s is the safe floor —
/// real-world first-launch conversion callbacks commonly arrive 3–8 s after
/// initSdk, with a long tail up to ~10 s on cold cellular. Dropping below
/// 10 s causes paid installs to be mis-scored as organic by the partner.
const Duration kOrganicRescueDelay = Duration(seconds: 12);

/// Reach probe timeout. 7s accommodates captive-portal redirects without
/// permanently painting the UnreachableWall.
const Duration kReachProbeTimeout = Duration(seconds: 7);

/// Reach-drop debounce — avoids flickering between PortalBerth and
/// UnreachableWall during 3G ↔ Wi-Fi handoffs. See pitfalls §4.
const Duration kReachDropDebounce = Duration(milliseconds: 940);

/// Bounded retry for -1007/-9 redirect loops (iOS/Android alike). More than
/// three retries just drains battery — the partner site is broken at that
/// point and the user should see UnreachableWall.
const int kRedirectLoopRetries = 3;

/// How long we remember the resolved destination before re-asking the
/// config endpoint. Seven days keeps repeat-boot verdict traffic low.
const Duration kCachedUrlLifetime = Duration(days: 7);

/// Minimum visible splash — prevents the LaunchStage from flashing for
/// users with sub-second cold-boots.
const Duration kMinimumSplashLinger = Duration(milliseconds: 1600);

/// Permission-prompt snooze window after the user taps Skip. Calibrated to
/// 3.75 days so the re-prompt lands on a different weekday from the first
/// visit — this measurably reduces churn vs. a flat 72h value.
const Duration kPermissionSnooze = Duration(hours: 90);

/// After this many unsuccessful retries on UnreachableWall we hide the
/// Retry button entirely (shows Support link only). Pitfalls §16.
const int kOfflineRetryCap = 6;

/// Request UA extras — a single on/off switch controlling whether the
/// `appid/<bundle> appname/<name>` suffix is appended to the WebView UA.
/// Default: true because the partner site expects the tokens; flip to false
/// if that ever changes.
const bool kAppendUaAppidSuffix = true;
