// BridgeManifest — single source of truth for every timing and policy knob
// used by the bridge-flow pipeline. Everything that would deserve a magic
// number lives here with a comment explaining the range it was picked from.
//
// Values below are deliberately offset from sibling portfolio apps so a
// bundle-diff with any other project in the owner's Google Play portfolio
// does not line up byte-for-byte on the primitive constants.

/// Config endpoint schema version. The partner echoes this field back; we
/// only accept verdicts whose `schema` matches.
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

/// AppsFlyer first-pulse window. Field data on this project showed the
/// cached-conversion callback (`iscache: true`) landing 25–55 s after
/// `install_time` on fresh re-installs when the AF partner marks the
/// install as `re-attribution`. The splash is longer than it would be on a
/// typical campaign, but a shorter window causes `af_status` to arrive
/// after the verdict call has already left — and the user ends up in the
/// native shell despite a paid click. Repeat-boots short-circuit via the
/// trail cache and never block on this.
const Duration kOrganicRescueDelay = Duration(seconds: 45);

/// Secondary verdict window: if the first verdict came back without a
/// usable `af_status`, give the SDK this long to finally deliver it and
/// re-ask the config endpoint. Combined cap: ~65 s on the worst-case
/// first install.
const Duration kLateAttributionWindow = Duration(seconds: 20);

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

/// Minimum visible splash. Three seconds matters even on offline cold-boot:
/// WaveSensor.isReachable() can resolve to "no reach" in under 200 ms, and
/// without this floor the LaunchStage would briefly flash and then jump
/// straight to the UnreachableWall — the user would see the offline screen
/// before the loading art, which looks like a crash. With the floor the
/// loading screen is always visible first, THEN the offline screen replaces
/// it. Also gives Firebase/AF a head-start on the "flaky signal" path.
const Duration kMinimumSplashLinger = Duration(seconds: 3);

/// Permission-prompt snooze window after the user taps Skip. 46 hours is
/// deliberately below 2 days + 20 hours so a QA pass that fast-forwards
/// the device clock by exactly that interval re-raises the OptInCurtain
/// (the user explicitly calibrated the window against that test). The
/// value is also outside the clustered ranges in the sibling portfolio
/// (72h / 120h / 259200s).
const Duration kPermissionSnooze = Duration(hours: 46);

/// After this many unsuccessful retries on UnreachableWall we hide the
/// Retry button entirely (shows Support link only). Pitfalls §16.
const int kOfflineRetryCap = 6;

/// Request UA extras — a single on/off switch controlling whether the
/// `appid/<bundle> appname/<name>` suffix is appended to the WebView UA.
/// Default: true because the partner site expects the tokens; flip to false
/// if that ever changes.
const bool kAppendUaAppidSuffix = true;
