// SpireMedia — asset path constants for every bridge-flow screen.
//
// The user ships three pairs of orientation-specific backgrounds:
//   • Loading (both orientations)
//   • Notifications (both orientations)
// No dedicated "No Wi-Fi" asset was supplied, so the UnreachableWall paints
// the loading background with a tinted overlay instead. This is a deliberate
// trade-off — a solid-colour fallback would look out of place with the rest
// of the UI.
class SpireMedia {
  const SpireMedia._();

  static const String _root = 'assets/Skyspire_additional_assets/';

  static const String portraitLoading = '${_root}Vertical_Loading_Screen.webp';
  static const String landscapeLoading = '${_root}Horizontal_Loading_Screen.webp';
  static const String portraitNotice = '${_root}Vertical_Notifications_Screen.webp';
  static const String landscapeNotice = '${_root}Horizontal_Notifications_Screen.webp';

  // We reuse the loading art as the offline backdrop (no dedicated asset).
  static const String portraitOffline = portraitLoading;
  static const String landscapeOffline = landscapeLoading;
}
