// Public-facing URLs that are OK to ship as plaintext — these are already
// published on Google Play's store listing, so hiding them in encoded bytes
// would gain nothing while adding runtime cost.
//
// All three URLs point at a different host (`skyiyspire.com`) than the
// verdict endpoint (`skyspirre.com`) on purpose: the policy site and the
// config endpoint are allowed to be rotated independently.
class PublicLinks {
  const PublicLinks._();

  /// Opened from the LaunchStage legal footer (only shown on cold-start).
  static const String homeLink = 'https://skyspirre.com';

  /// Linked from the OptInCurtain and the "What is this?" footer.
  static const String privacyLink = 'https://skyiyspire.com/privacy-policy';

  /// Linked from the UnreachableWall and the LaunchStage long-press area.
  static const String supportLink = 'https://skyiyspire.com/support';
}
