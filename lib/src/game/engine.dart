import 'dart:math' as math;

/// Phases of a single build round.
enum Phase {
  /// No bet placed yet. The crane swings, BUILD starts the round.
  betting,

  /// Bet is live, a block hangs on the crane waiting to be dropped.
  aiming,

  /// The released block is in the air.
  falling,

  /// The block landed, impact FX and camera travel are playing.
  landing,

  /// The block missed, the tower is coming down.
  collapsing,

  /// Round closed by the player, win banner is showing.
  cashout,
}

/// All screen dependent sizes derived from the play area.
///
/// Everything is expressed as a fraction of the play area so the scene keeps
/// the same proportions on any phone.
class Metrics {
  const Metrics(this.w, this.h);

  final double w;
  final double h;

  /// Screen y of the pavement the base shop stands on (camera at rest).
  double get groundY => h * 0.88;

  /// Screen y the top of the tower is parked at once the camera starts
  /// following it.
  double get anchorY => h * 0.58;

  /// Screen y of the crane hook tip, i.e. the pendulum pivot.
  double get pivotY => h * 0.095;

  /// Rope length between the hook tip and the top edge of the block.
  double get cable => h * 0.075;

  double get blockW => w * 0.33;
  double get baseW => w * 0.385;
  double get axisX => w * 0.5;

  double get gravity => h * 5.4;
  double get swingAmp => w * 0.17;

  /// Distance the camera lets the tower grow before it starts to scroll.
  double get camSlack => groundY - anchorY;
}

/// A block that is part of the standing tower.
class PlacedBlock {
  PlacedBlock({
    required this.sprite,
    required this.bottomY,
    required this.width,
    required this.height,
    required this.dx,
    required this.angle,
  });

  final int sprite;
  double bottomY;
  double width;
  double height;

  /// Horizontal offset from the tower axis kept after the snap.
  double dx;

  /// Residual tilt kept after the snap.
  double angle;

  /// Squash animation played right after the impact, 0 when finished.
  double squash = 0;
}

/// A block travelling through the air: the dropped one or collapse debris.
class Flying {
  Flying({
    required this.sprite,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.angle,
    required this.spin,
    required this.width,
    required this.height,
    this.delay = 0,
  });

  final int sprite;

  /// World x of the centre (world x == screen x, the camera never pans).
  double x;

  /// World y of the centre, positive upwards from the pavement.
  double y;

  double vx;
  double vy;
  double angle;
  double spin;
  final double width;
  final double height;
  double delay;

  /// Set once the block has come to rest on the pavement.
  bool grounded = false;
}

/// One cartoon smoke puff.
class Puff {
  Puff({
    required this.sprite,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.growth,
    required this.maxLife,
    required this.angle,
    required this.spin,
  }) : life = maxLife;

  final int sprite;
  double x;
  double y;
  double vx;
  double vy;
  double size;
  final double growth;
  final double maxLife;
  double life;
  double angle;
  final double spin;
}

/// The big multiplier text that pops over the tower.
class Popup {
  Popup(this.text, this.kind, this.x, this.y);

  final String text;
  final PopupKind kind;

  /// Screen position captured when the popup was created.
  final double x;
  final double y;
  double age = 0;
  double get life => kind == PopupKind.zero ? 1.6 : 1.25;
  bool get done => age >= life;
}

enum PopupKind { win, zero }

/// A drifting background cloud.
class Cloud {
  Cloud(this.sprite, this.x, this.y, this.scale, this.speed, this.alpha);

  final int sprite;
  double x;
  final double y;
  final double scale;
  final double speed;
  final double alpha;
}

/// Simulation of the whole Skyspire scene: crane, physics, camera and FX.
class SkyEngine {
  SkyEngine({
    required this.blockAspects,
    required this.blockFloorFractions,
    required this.blockTopFractions,
    required this.baseAspect,
    math.Random? rng,
  }) : _rng = rng ?? math.Random();

  /// width / height of every block sprite (opaque bounds).
  final List<double> blockAspects;

  /// Fraction of the block height that lives above its stacking floor. The
  /// remaining `1 - floorFraction` is decoration hanging below the floor.
  final List<double> blockFloorFractions;

  /// Fraction of the block height that lives below the usable ceiling
  /// (surface the next block stacks on). Below `1.0` for shapes with a
  /// pointy peak like the hexagon.
  final List<double> blockTopFractions;
  final double baseAspect;
  final math.Random _rng;

  // ---- tuning -------------------------------------------------------------

  /// Time of one full left-right-left crane travel, as in the original.
  static const double swingPeriod = 2.7;

  /// The crane reaches a little further out the higher the tower gets.
  static const double swingGrowth = 0.005;
  static const int swingGrowthCap = 8;

  /// How much of a block width may hang over the edge and still hold.
  static const double tolerance = 0.42;

  /// Air drag applied to the horizontal speed of a falling block.
  static const double fallDrag = 1.1;

  static const double _cloudBand = 0.62;
  static const double _cloudParallax = 0.62;

  // ---- state --------------------------------------------------------------

  Metrics m = const Metrics(1, 1);
  Phase phase = Phase.betting;

  double _swingT = 0;
  double trolleyX = 0;
  double _trolleyVx = 0;
  double _trolleyAx = 0;

  /// Pendulum angle of the hanging block and its rate of change.
  double theta = 0;
  double thetaDot = 0;

  /// 0 -> the fresh block is still above the screen, 1 -> fully lowered.
  double spawnT = 1;

  int currentSprite = 0;
  bool hasHangingBlock = true;

  final List<PlacedBlock> tower = <PlacedBlock>[];
  double camScroll = 0;

  Flying? flying;
  final List<Flying> debris = <Flying>[];
  final List<Puff> puffs = <Puff>[];
  final List<Cloud> clouds = <Cloud>[];
  Popup? popup;

  /// Multipliers collected during the running round, newest first.
  final List<double> results = <double>[];
  double totalMult = 1;
  int bet = 100;

  double _phaseTimer = 0;
  int _lastSprite = -1;
  bool _cloudsSeeded = false;

  /// Fired when a block settles on the tower.
  void Function()? onImpact;

  /// Fired when the round is lost.
  void Function()? onCrash;

  /// Fired when the round is closed with a win. Argument is the payout.
  void Function(double payout)? onCashout;

  /// Player wants smaller visual effects: halved dust bursts on crashes.
  bool reducedFx = false;

  // ---- derived ------------------------------------------------------------

  double get baseHeight => m.baseW / baseAspect;

  double blockHeight(int sprite) => m.blockW / blockAspects[sprite];

  double blockFloorFraction(int sprite) => blockFloorFractions[sprite];

  double blockTopFraction(int sprite) => blockTopFractions[sprite];

  /// Depth of decoration that hangs under a block's stacking floor.
  double _blockBelowFloor(int sprite) =>
      blockHeight(sprite) * (1 - blockFloorFractions[sprite]);

  /// World y of the usable ceiling of a placed block (surface the next
  /// block stacks on). Accounts for decoration above the ceiling like a
  /// pointy peak.
  double _blockCeilingY(PlacedBlock b) =>
      b.bottomY + b.height * blockTopFractions[b.sprite];

  /// World y of the surface the next block has to land on. For most blocks
  /// this is the visible top; for shapes with a pointy peak the usable
  /// ceiling sits a bit lower so the next block rests on the wider body.
  double get towerTopY =>
      tower.isEmpty ? baseHeight : _blockCeilingY(tower.last);

  double get camTarget => math.max(0, towerTopY - m.camSlack);

  double get swingAmplitude =>
      m.swingAmp +
      m.w * swingGrowth * math.min(swingGrowthCap, tower.length);

  /// Pendulum length: pivot to the centre of the hanging block.
  double get ropeLength => m.cable + blockHeight(currentSprite) / 2;

  /// Extra downward shift while the fresh block is being lowered in.
  double get spawnOffsetY => -(1 - _easeOutCubic(spawnT)) * m.h * 0.62;

  double get hangCenterX => trolleyX + ropeLength * math.sin(theta);

  double get hangCenterY =>
      m.pivotY + spawnOffsetY + ropeLength * math.cos(theta);

  double get pivotScreenY => m.pivotY + spawnOffsetY;

  bool get canDrop =>
      (phase == Phase.betting || phase == Phase.aiming) && spawnT >= 1;

  bool get canCashout => phase == Phase.aiming && results.isNotEmpty;

  double get payout => bet * totalMult;

  double screenY(double worldY) => m.groundY - worldY + camScroll;

  double worldY(double screen) => m.groundY + camScroll - screen;

  // ---- lifecycle ----------------------------------------------------------

  void resize(Metrics value) {
    final bool first = m.w <= 1;
    final double kx = first ? 1 : value.w / m.w;
    final double ky = first ? 1 : value.h / m.h;
    m = value;
    if (first) {
      trolleyX = m.axisX;
      _resetScene();
      return;
    }
    // Keep the scene proportional when the play area changes size.
    trolleyX *= kx;
    camScroll *= ky;
    for (final PlacedBlock b in tower) {
      b.bottomY *= ky;
      b.width *= kx;
      b.height *= ky;
      b.dx *= kx;
    }
  }

  void _resetScene() {
    tower.clear();
    debris.clear();
    puffs.clear();
    results.clear();
    flying = null;
    popup = null;
    totalMult = 1;
    camScroll = 0;
    _swingT = _rng.nextDouble() * swingPeriod;
    theta = 0;
    thetaDot = 0;
    _spawnBlock(instant: false);
    _seedClouds();
  }

  void _seedClouds() {
    if (_cloudsSeeded) return;
    _cloudsSeeded = true;
    for (int i = 0; i <= _highestBand; i++) {
      _addCloudBand(i);
    }
  }

  void _addCloudBand(int band) {
    final math.Random r = math.Random(band * 7919 + 13);
    final int count = 1 + r.nextInt(2);
    for (int i = 0; i < count; i++) {
      clouds.add(
        Cloud(
          r.nextInt(2),
          (r.nextDouble() * 1.6 - 0.3) * m.w,
          (band + r.nextDouble()) * m.h * _cloudBand,
          0.45 + r.nextDouble() * 0.7,
          (r.nextBool() ? 1 : -1) * (0.004 + r.nextDouble() * 0.012),
          0.35 + r.nextDouble() * 0.45,
        ),
      );
    }
  }

  void _spawnBlock({bool instant = false}) {
    int s = _rng.nextInt(blockAspects.length);
    if (s == _lastSprite) s = (s + 1 + _rng.nextInt(blockAspects.length - 1)) % blockAspects.length;
    _lastSprite = s;
    currentSprite = s;
    hasHangingBlock = true;
    spawnT = instant ? 1 : 0;
  }

  // ---- input --------------------------------------------------------------

  /// Places the bet (if needed) and releases the hanging block.
  void drop() {
    if (!canDrop) return;
    if (phase == Phase.betting) {
      phase = Phase.aiming;
    }

    final double l = ropeLength;
    final double cs = math.cos(theta);
    final double sn = math.sin(theta);

    // Velocity of the block centre at the moment the hook lets go.
    final double vx = _trolleyVx + l * cs * thetaDot;
    final double vyUp = l * sn * thetaDot;

    flying = Flying(
      sprite: currentSprite,
      x: hangCenterX,
      y: worldY(hangCenterY),
      vx: vx,
      vy: vyUp,
      angle: theta,
      spin: thetaDot * 0.9 + vx / m.w * 1.4,
      width: m.blockW,
      height: blockHeight(currentSprite),
    );
    hasHangingBlock = false;
    phase = Phase.falling;
  }

  /// Closes the round and banks the payout.
  void cashout() {
    if (!canCashout) return;
    final double amount = payout;
    phase = Phase.cashout;
    _phaseTimer = 0;
    hasHangingBlock = false;
    popup = null;
    onCashout?.call(amount);
  }

  // ---- simulation ---------------------------------------------------------

  void tick(double dt) {
    dt = math.min(dt, 1 / 30);
    _updateCrane(dt);
    _updateCamera(dt);
    _updateFlying(dt);
    _updateDebris(dt);
    _updatePuffs(dt);
    _updateClouds(dt);
    _updateTower(dt);

    final Popup? p = popup;
    if (p != null) {
      p.age += dt;
      if (p.done) popup = null;
    }

    switch (phase) {
      case Phase.landing:
        _phaseTimer += dt;
        if (_phaseTimer > 0.55 && !hasHangingBlock) {
          _spawnBlock();
          phase = Phase.aiming;
        }
      case Phase.collapsing:
        _phaseTimer += dt;
        if (_phaseTimer > 2.5) {
          phase = Phase.betting;
          _resetRound();
        }
      case Phase.cashout:
        _phaseTimer += dt;
        if (_phaseTimer > 2.2) {
          phase = Phase.betting;
          _resetRound();
        }
      case Phase.betting:
      case Phase.aiming:
      case Phase.falling:
        break;
    }
  }

  void _resetRound() {
    tower.clear();
    debris.clear();
    results.clear();
    totalMult = 1;
    camScroll = 0;
    flying = null;
    _spawnBlock();
  }

  void _updateCrane(double dt) {
    if (spawnT < 1) {
      spawnT = math.min(1, spawnT + dt / 0.62);
    }

    _swingT += dt;
    final double omega = 2 * math.pi / swingPeriod;
    final double a = swingAmplitude;
    trolleyX = m.axisX + a * math.sin(omega * _swingT);
    _trolleyVx = a * omega * math.cos(omega * _swingT);
    _trolleyAx = -a * omega * omega * math.sin(omega * _swingT);

    // Driven damped pendulum: the block lags behind the trolley and tilts.
    final double l = ropeLength;
    final double acc =
        -(m.gravity / l) * math.sin(theta) -
        (_trolleyAx / l) * math.cos(theta) -
        1.9 * thetaDot;
    thetaDot += acc * dt;
    theta += thetaDot * dt;
    theta = theta.clamp(-0.55, 0.55);
  }

  void _updateCamera(double dt) {
    final double target = camTarget;
    final double k = 1 - math.exp(-dt * 7.5);
    camScroll += (target - camScroll) * k;
    if ((target - camScroll).abs() < 0.3) camScroll = target;
  }

  void _updateFlying(double dt) {
    final Flying? f = flying;
    if (f == null) return;
    if (f.grounded) return;

    // Collisions use the block's stacking floor, not the outermost pixel,
    // so decorative grass or stones under the floor never trigger a landing.
    final double belowFloor = _blockBelowFloor(f.sprite);
    final double prevFloor = f.y - f.height / 2 + belowFloor;

    f.vy -= m.gravity * dt;
    f.vx *= math.exp(-fallDrag * dt);
    f.x += f.vx * dt;
    f.y += f.vy * dt;
    f.angle += f.spin * dt;

    if (phase == Phase.falling) {
      final double top = towerTopY;
      final double floor = f.y - f.height / 2 + belowFloor;
      if (prevFloor > top && floor <= top) {
        final double offset = f.x - (m.axisX + _towerTopDx());
        if (offset.abs() <= tolerance * m.blockW) {
          _land(f, offset, top);
        } else {
          _miss(f, offset);
        }
        return;
      }
    }

    if (_settleOnPavement(f)) return;
    if (screenY(f.y) > m.h + f.height * 1.5) flying = null;
  }

  /// Stops a tumbling block on the street the way the original does when the
  /// very first block of a round misses the shop.
  bool _settleOnPavement(Flying f) {
    if (f.grounded) return true;
    if (f.y - f.height / 2 > 0) return false;
    if (screenY(0) > m.h + f.height) return false;
    f.grounded = true;
    f.vx = 0;
    f.vy = 0;
    f.spin = 0;
    f.y = f.height / 2;
    f.angle = f.angle.clamp(-0.35, 0.35);
    _spawnDust(f.x, 0, f.width);
    return true;
  }

  double _towerTopDx() => tower.isEmpty ? 0 : tower.last.dx;

  void _land(Flying f, double offset, double top) {
    final double ratio = (offset.abs() / (tolerance * m.blockW)).clamp(0.0, 1.0);
    final double accuracy = 1 - ratio;
    // Two-branch multiplier so the round always mixes positive and
    // negative outcomes:
    //   * well-centered drop (accuracy >= 0.5) → 1.00 .. 2.00
    //   * edge landing       (accuracy <  0.5) → 0.50 .. 0.95
    double mult;
    if (accuracy >= 0.5) {
      final double t = (accuracy - 0.5) * 2;
      mult = 1.0 + math.pow(t, 1.2).toDouble();
    } else {
      // accuracy = 0 -> 0.50, accuracy = 0.5 -> 0.95
      mult = 0.5 + accuracy * 0.9;
    }
    mult = (mult * 100).round() / 100;

    // The block's floor snaps onto `top`; its decoration (if any) hangs
    // below that surface, so the visible bottom sits a bit lower.
    final double belowFloor = _blockBelowFloor(f.sprite);
    final PlacedBlock block = PlacedBlock(
      sprite: f.sprite,
      bottomY: top - belowFloor,
      width: f.width,
      height: f.height,
      // Blocks always land level, only a small horizontal offset is inherited
      // from the parent so a tall tower can drift but never lean.
      dx: _towerTopDx() * 0.55 + offset * 0.22,
      angle: 0,
    );
    block.squash = 1;
    tower.add(block);

    results.insert(0, mult);
    totalMult *= mult;
    totalMult = (totalMult * 10000).round() / 10000;

    flying = null;
    phase = Phase.landing;
    _phaseTimer = 0;
    popup = Popup(
      _formatMult(mult),
      PopupKind.win,
      m.axisX,
      math.max(m.h * 0.2, screenY(top + block.height) - m.h * 0.1),
    );

    _spawnImpactSmoke(block);
    onImpact?.call();
  }

  void _miss(Flying f, double offset) {
    final double dir = offset.isNegative ? -1 : 1;
    // Only a block that actually clipped the edge gets deflected; one that
    // sails past untouched keeps its trajectory.
    final bool clipped = offset.abs() < m.blockW * 1.05;
    final double top = towerTopY;

    if (clipped) {
      // Kick the block off the tower with a proper bounce: strong upward
      // pop, sideways shove and a fast tumble, matching how it reads in a
      // classic drop-and-stack slot.
      f.spin += dir * (2.4 + _rng.nextDouble() * 1.5);
      f.vx = dir * m.w * (0.32 + _rng.nextDouble() * 0.12);
      f.vy = m.h * (0.42 + _rng.nextDouble() * 0.16);
      // Push the block back above the tower top so its next fall re-plays
      // the trajectory instead of clipping through the standing stack.
      f.y = top + f.height / 2 + m.blockW * 0.05;

      // Two puff bursts: a big central impact plus a stream trailing on
      // the side the block glanced off of.
      _spawnBurstSmoke(f.x, top);
      _spawnEdgeBurst(m.axisX + _towerTopDx() + dir * m.blockW * 0.5, top);

      // Squash the top block of the tower to sell the collision.
      if (tower.isNotEmpty) tower.last.squash = 1;
    } else {
      // A clean miss whooshes past untouched.
      f.spin += dir * (0.9 + _rng.nextDouble() * 0.8);
    }

    phase = Phase.collapsing;
    _phaseTimer = 0;
    popup = Popup(
      'x0',
      PopupKind.zero,
      m.axisX,
      math.max(m.h * 0.2, screenY(towerTopY) - m.h * 0.16),
    );
    results.clear();
    totalMult = 0;

    // The standing tower stays where it is; only the block that missed the
    // stack keeps tumbling and eventually settles on the pavement.
    onCrash?.call();
  }

  void _updateDebris(double dt) {
    for (int i = debris.length - 1; i >= 0; i--) {
      final Flying d = debris[i];
      if (d.grounded) continue;
      if (d.delay > 0) {
        d.delay -= dt;
        continue;
      }
      d.vy -= m.gravity * dt;
      d.vx *= math.exp(-fallDrag * 0.4 * dt);
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.angle += d.spin * dt;

      if (d.y - d.height / 2 <= 0 && screenY(0) < m.h + d.height) {
        d.grounded = true;
        d.vx = 0;
        d.vy = 0;
        d.spin = 0;
        d.y = d.height / 2;
        d.angle = d.angle.clamp(-0.5, 0.5);
        _spawnDust(d.x, 0, d.width);
        continue;
      }
      if (screenY(d.y) > m.h + d.height * 1.5) debris.removeAt(i);
    }
  }

  void _spawnDust(double x, double y, double width) {
    for (int i = 0; i < 5; i++) {
      final double side = _rng.nextBool() ? 1 : -1;
      puffs.add(
        Puff(
          sprite: _rng.nextInt(2),
          x: x + side * width * _rng.nextDouble() * 0.5,
          y: y + _rng.nextDouble() * width * 0.08,
          vx: side * m.w * (0.05 + _rng.nextDouble() * 0.12),
          vy: m.h * (0.02 + _rng.nextDouble() * 0.05),
          size: m.blockW * (0.18 + _rng.nextDouble() * 0.18),
          growth: 1.4 + _rng.nextDouble(),
          maxLife: 0.5 + _rng.nextDouble() * 0.4,
          angle: _rng.nextDouble() * math.pi,
          spin: (_rng.nextDouble() - 0.5) * 1.5,
        ),
      );
    }
  }

  void _spawnImpactSmoke(PlacedBlock block) {
    final double cx = m.axisX + block.dx;
    final double y = block.bottomY;
    for (final double side in <double>[-1, 1]) {
      for (int i = 0; i < 4; i++) {
        puffs.add(
          Puff(
            sprite: _rng.nextInt(2),
            x: cx + side * block.width * (0.38 + _rng.nextDouble() * 0.2),
            y: y + _rng.nextDouble() * block.height * 0.1,
            vx: side * m.w * (0.06 + _rng.nextDouble() * 0.12),
            vy: m.h * (0.03 + _rng.nextDouble() * 0.07),
            size: m.blockW * (0.22 + _rng.nextDouble() * 0.2),
            growth: 1.5 + _rng.nextDouble(),
            maxLife: 0.55 + _rng.nextDouble() * 0.45,
            angle: _rng.nextDouble() * math.pi,
            spin: (_rng.nextDouble() - 0.5) * 1.6,
          ),
        );
      }
    }
  }

  void _spawnBurstSmoke(double x, double y) {
    final int count = reducedFx ? 7 : 14;
    for (int i = 0; i < count; i++) {
      final double a = _rng.nextDouble() * math.pi * 2;
      final double sp = m.w * (0.10 + _rng.nextDouble() * 0.28);
      puffs.add(
        Puff(
          sprite: _rng.nextInt(2),
          x: x + math.cos(a) * m.blockW * 0.18,
          y: y + math.sin(a) * m.blockW * 0.18,
          vx: math.cos(a) * sp,
          vy: math.sin(a) * sp * 0.55 + m.h * 0.05,
          size: m.blockW * (0.30 + _rng.nextDouble() * 0.35),
          growth: 1.9 + _rng.nextDouble() * 1.1,
          maxLife: 0.7 + _rng.nextDouble() * 0.6,
          angle: _rng.nextDouble() * math.pi,
          spin: (_rng.nextDouble() - 0.5) * 2.4,
        ),
      );
    }
  }

  /// Trail of puffs streaming off the edge the block glanced against, giving
  /// the miss a directional "swept off" feel.
  void _spawnEdgeBurst(double x, double y) {
    final int count = reducedFx ? 3 : 6;
    for (int i = 0; i < count; i++) {
      final double a = (_rng.nextDouble() - 0.5) * 0.9;
      final double sp = m.w * (0.14 + _rng.nextDouble() * 0.18);
      final double dir = x > m.axisX ? 1 : -1;
      puffs.add(
        Puff(
          sprite: _rng.nextInt(2),
          x: x,
          y: y - _rng.nextDouble() * m.blockW * 0.15,
          vx: dir * sp * math.cos(a),
          vy: -sp * math.sin(a).abs() * 0.6 + m.h * 0.03,
          size: m.blockW * (0.24 + _rng.nextDouble() * 0.22),
          growth: 2.0 + _rng.nextDouble(),
          maxLife: 0.55 + _rng.nextDouble() * 0.4,
          angle: _rng.nextDouble() * math.pi,
          spin: (_rng.nextDouble() - 0.5) * 2.0,
        ),
      );
    }
  }

  void _updatePuffs(double dt) {
    for (int i = puffs.length - 1; i >= 0; i--) {
      final Puff p = puffs[i];
      p.life -= dt;
      if (p.life <= 0) {
        puffs.removeAt(i);
        continue;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= math.exp(-2.2 * dt);
      p.vy *= math.exp(-2.0 * dt);
      p.size += p.growth * p.size * dt;
      p.angle += p.spin * dt;
    }
  }

  void _updateClouds(double dt) {
    for (final Cloud c in clouds) {
      c.x += c.speed * m.w * dt * 6;
      if (c.x > m.w * 1.45) c.x = -m.w * 0.45;
      if (c.x < -m.w * 0.45) c.x = m.w * 1.45;
    }
    // Keep the sky populated as the camera climbs.
    final int wanted = (worldY(0) / (m.h * _cloudBand)).ceil() + 3;
    while (_highestBand < wanted) {
      _highestBand++;
      _addCloudBand(_highestBand);
    }
  }

  int _highestBand = 11;

  void _updateTower(double dt) {
    for (final PlacedBlock b in tower) {
      if (b.squash > 0) b.squash = math.max(0, b.squash - dt * 4.5);
    }
  }

  double cloudScreenY(Cloud c) => m.groundY - c.y + camScroll * _cloudParallax;

  static String _formatMult(double v) {
    final String s = v.toStringAsFixed(2);
    if (s.endsWith('0')) {
      final String t = s.substring(0, s.length - 1);
      return 'x${t.endsWith('.0') ? t.substring(0, t.length - 2) : t}';
    }
    return 'x$s';
  }

  static double _easeOutCubic(double t) {
    final double u = 1 - t;
    return 1 - u * u * u;
  }
}
