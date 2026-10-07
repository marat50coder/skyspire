// SpireMedia — asset path constants for the bridge-flow screens.
//
// Only the LaunchStage splash actually paints from an image now — both the
// OptInCurtain and the UnreachableWall render a flat gradient (user request)
// so the notice/offline art is gone. File names here are deliberately not
// `Vertical_Loading_Screen` / `Horizontal_Loading_Screen` — those names
// cluster across 14+ sibling portfolio builds and would surface in a Play
// Store asset-listing diff. Short neutral tokens below do not.
class SpireMedia {
  const SpireMedia._();

  static const String _root = 'assets/boot_art/';

  static const String portraitLoading = '${_root}view_portrait_boot.webp';
  static const String landscapeLoading = '${_root}view_landscape_boot.webp';
}
