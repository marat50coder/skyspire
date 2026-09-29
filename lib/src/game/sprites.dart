import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// One block bitmap plus geometry describing where its "floor" is.
///
/// * [trim] is the opaque bounding box of the sprite inside its source image.
///   Rendering uses this rectangle so a block never sits on empty air just
///   because the source PNG has transparent padding.
/// * [floorFraction] is the fraction of the trimmed height that lives above
///   the block's usable floor line. Decoration under that line (grass tufts,
///   step stones, plinths) hangs below the surface the block stacks on.
class BlockSprite {
  BlockSprite(this.image, this.trim, this.floorFraction, this.topFraction);

  final ui.Image image;

  /// Opaque bounds inside `image`, in pixel coordinates.
  final Rect trim;

  /// Height fraction above the floor. `1.0` means no decoration under it.
  final double floorFraction;

  /// Height fraction below the block's usable ceiling. `1.0` means the
  /// stacking surface is the very top of the trim. On shapes like the
  /// hexagon it drops below `1.0` because the pointy peak is decoration.
  final double topFraction;

  double get aspect => trim.width / trim.height;
}

/// Every bitmap the scene needs, decoded once at start up.
class Sprites {
  Sprites({
    required this.sky,
    required this.city,
    required this.hook,
    required this.base,
    required this.blocks,
    required this.clouds,
  });

  final ui.Image sky;
  final ui.Image city;
  final ui.Image hook;
  final BlockSprite base;
  final List<BlockSprite> blocks;
  final List<ui.Image> clouds;

  List<double> get blockAspects =>
      blocks.map((BlockSprite b) => b.aspect).toList();

  List<double> get blockFloorFractions =>
      blocks.map((BlockSprite b) => b.floorFraction).toList();

  List<double> get blockTopFractions =>
      blocks.map((BlockSprite b) => b.topFraction).toList();

  double get baseAspect => base.aspect;

  static const String _gameplay = 'assets/Skyspire_gameplay_assets';

  static Future<Sprites> load() async {
    final List<ui.Image> images = await Future.wait(<Future<ui.Image>>[
      _decode('$_gameplay/bg_sky_asset_1.webp'),
      _decode('$_gameplay/city_background.webp'),
      _decode('$_gameplay/hook_asset.webp'),
      _decode('$_gameplay/start_block_asset_5.webp'),
      _decode('$_gameplay/block_asset_1.webp'),
      _decode('$_gameplay/block_asset_2.webp'),
      _decode('$_gameplay/block_asset_3.webp'),
      _decode('$_gameplay/block_asset_4.webp'),
      _decode('$_gameplay/cloud_asset_1.webp'),
      _decode('$_gameplay/cloud_asset_2.webp'),
    ]);

    final List<BlockSprite> blocks = <BlockSprite>[];
    for (int i = 4; i <= 7; i++) {
      blocks.add(await _makeBlock(images[i]));
    }
    // The base carries no decoration below its stacking floor.
    final BlockSprite base = await _makeBlock(images[3], forceFullFloor: true);

    return Sprites(
      sky: images[0],
      city: images[1],
      hook: images[2],
      base: base,
      blocks: blocks,
      clouds: images.sublist(8, 10),
    );
  }

  static Future<ui.Image> _decode(String path) async {
    final ByteData data = await rootBundle.load(path);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<BlockSprite> _makeBlock(
    ui.Image img, {
    bool forceFullFloor = false,
  }) async {
    final (Rect trim, double floor, double top) = await _analyze(img);
    return BlockSprite(
      img,
      trim,
      forceFullFloor ? 1.0 : floor,
      forceFullFloor ? 1.0 : top,
    );
  }

  /// Finds the opaque bounding box of `img` plus the block's floor line.
  ///
  /// The trim rectangle covers the entire visible sprite (body **and**
  /// any decoration hanging under it, e.g. the door step and grass on the
  /// hexagon), so nothing is cut from the rendered artwork. `floorFraction`
  /// tells the engine where the block's stacking floor is inside that
  /// rectangle: the falling block lands with its floor line on top of the
  /// previous block, and any decoration below the floor drapes over the
  /// edge instead of counting as part of the collision surface.
  ///
  /// Detection uses the length of the longest contiguous opaque strip in
  /// each row. Body rows are one big continuous silhouette; decorative
  /// rows (grass tufts, small stones) are fragmented and rate much lower
  /// even when their total pixel count is high.
  static Future<(Rect, double, double)> _analyze(
    ui.Image img, {
    int alpha = 24,
    double bodyRatio = 0.65,
  }) async {
    final ByteData? data = await img.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final int w = img.width;
    final int h = img.height;
    final Rect fullRect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    if (data == null) return (fullRect, 1.0, 1.0);

    final Uint8List bytes = data.buffer.asUint8List();
    final List<int> rowRun = List<int>.filled(h, 0);
    int minX = w;
    int maxX = -1;
    int minY = h;
    int maxY = -1;
    for (int y = 0; y < h; y++) {
      final int row = y * w * 4;
      int longest = 0;
      int current = 0;
      for (int x = 0; x < w; x++) {
        if (bytes[row + x * 4 + 3] > alpha) {
          current++;
          if (current > longest) longest = current;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        } else {
          current = 0;
        }
      }
      rowRun[y] = longest;
      if (longest > 0) {
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (maxY < 0) return (fullRect, 1.0, 1.0);

    int peakRun = 0;
    for (int y = minY; y <= maxY; y++) {
      if (rowRun[y] > peakRun) peakRun = rowRun[y];
    }
    final double floorT = peakRun * bodyRatio;

    // Floor: bottom-most row whose longest opaque strip is still close to
    // the block's peak strip width. Everything below is decoration
    // (grass, stone step, `лестница`) and is kept in the sprite but does
    // not participate in stacking collisions.
    int floorRow = maxY;
    for (int y = maxY; y >= minY; y--) {
      if (rowRun[y] >= floorT) {
        floorRow = y;
        break;
      }
    }

    // Trim rectangle covers the whole opaque silhouette so nothing gets
    // cut from what the player sees.
    final Rect trim = Rect.fromLTRB(
      (minX - 1).clamp(0, w - 1).toDouble(),
      (minY - 1).clamp(0, h - 1).toDouble(),
      (maxX + 2).clamp(1, w).toDouble(),
      (maxY + 2).clamp(1, h).toDouble(),
    );
    final double trimH = trim.height;
    final double floorFromTop = (floorRow + 1) - trim.top;
    // How much of the sprite lives above the stacking floor. `1.0` means
    // there is no decoration below the floor; smaller values mean the
    // remaining fraction hangs under the floor and gets drawn dangling
    // over the previous block.
    final double floorFraction = (floorFromTop / trimH).clamp(0.55, 1.0);
    return (trim, floorFraction, 1.0);
  }
}
