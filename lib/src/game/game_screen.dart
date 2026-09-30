import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/settings.dart';
import '../data/wallet.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'engine.dart';
import 'rust_bridge.dart';
import 'scene_painter.dart';
import 'sprites.dart';
import '../bindings/bindings.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.sprites,
    required this.wallet,
    required this.settings,
  });

  final Sprites sprites;
  final Wallet wallet;
  final Settings settings;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final SkyEngine _engine = SkyEngine(
    blockAspects: widget.sprites.blockAspects,
    blockFloorFractions: widget.sprites.blockFloorFractions,
    blockTopFractions: widget.sprites.blockTopFractions,
    baseAspect: widget.sprites.baseAspect,
  );
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final RustScoring _rust = RustScoring();

  Duration _last = Duration.zero;
  String _uiKey = '';
  _Banner? _banner;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockPortraitAndHideSystemBars();
    _engine.reducedFx = widget.settings.reducedFx;
    widget.settings.addListener(_syncFromSettings);
    _engine.onImpact = widget.settings.hapticLight;
    _engine.onBlockLanded = (double accuracy) => _rust.blockLanded(accuracy);
    _engine.onCrash = () {
      widget.settings.hapticHeavy();
      _showBanner(const _Banner('OOPS!', null, false));
    };
    _engine.onCashout = (double payout) {
      // Banking is handled in [_handleCashout] using the authoritative
      // payout returned by the native scorer; here we only add feedback.
      widget.settings.hapticMedium();
    };
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _lockPortraitAndHideSystemBars() async {
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_syncFromSettings);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _syncFromSettings() {
    _engine.reducedFx = widget.settings.reducedFx;
  }

  void _onTick(Duration elapsed) {
    final double dt = _last == Duration.zero
        ? 1 / 60
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_paused) {
      _frame.value++;
      return;
    }
    _engine.tick(dt);
    _frame.value++;

    final String key =
        '${_engine.phase}|${_engine.results.length}|'
        '${_engine.totalMult}|${_engine.canDrop}|${_engine.canCashout}';
    if (key != _uiKey) {
      _uiKey = key;
      if (mounted) setState(() {});
    }
  }

  void _showBanner(_Banner banner) {
    setState(() => _banner = banner);
    Future<void>.delayed(const Duration(milliseconds: 2300), () {
      if (mounted && _banner == banner) setState(() => _banner = null);
    });
  }

  void _openPause() {
    if (_paused) return;
    setState(() => _paused = true);
  }

  void _closePause() {
    if (!_paused) return;
    setState(() => _paused = false);
  }

  void _onBuild() {
    if (!_engine.canDrop) return;
    if (_engine.phase == Phase.betting) {
      final Wallet w = widget.wallet;
      if (!w.canBet) {
        _showNoFunds();
        return;
      }
      w.take(w.bet);
      _engine.bet = w.bet;
      _banner = null;
      _rust.resetRound(w.bet);
    }
    _engine.drop();
    setState(() {});
  }

  Future<void> _handleCashout() async {
    if (!_engine.canCashout) return;
    final int bet = _engine.bet;
    final double localEstimate = _engine.payout;
    _engine.cashout();
    setState(() {});
    final RoundReport? report = await _rust.cashOut(bet);
    if (!mounted) return;
    final double amount = report?.payout ?? localEstimate;
    widget.wallet.give(amount);
    _showBanner(_Banner('YOU WIN', '${formatCoins(amount)} COINS', true));
  }

  void _showNoFunds() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.barDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Out of coins',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Grab a free stack and keep building.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 18),
              BlueButton(
                height: 50,
                onTap: () {
                  widget.wallet.refill();
                  Navigator.of(context).pop();
                  setState(() {});
                },
                child: const Text(
                  '+500 COINS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15171A),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: <Widget>[
            _TopBar(wallet: widget.wallet, onPause: _openPause),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  _engine.resize(Metrics(c.maxWidth, c.maxHeight));
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: ScenePainter(
                            engine: _engine,
                            sprites: widget.sprites,
                            repaint: _frame,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 8,
                        child: _ResultsColumn(results: _engine.results),
                      ),
                      if (_banner != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ResultBanner(
                            text: _banner!.text,
                            subtitle: _banner!.subtitle,
                            win: _banner!.win,
                          ),
                        ),
                      if (_paused)
                        _PauseOverlay(
                          onResume: _closePause,
                          onExit: () {
                            _closePause();
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
            _ControlPanel(
              engine: _engine,
              wallet: widget.wallet,
              onBuild: _onBuild,
              onCashout: _handleCashout,
              onBetChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner {
  const _Banner(this.text, this.subtitle, this.win);

  final String text;
  final String? subtitle;
  final bool win;
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.wallet, required this.onPause});

  final Wallet wallet;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const ColoredBox(color: Palette.barDark),
          const CustomPaint(painter: StripesPainter()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                _PauseButton(onTap: onPause),
                const Spacer(),
                AnimatedBuilder(
                  animation: wallet,
                  builder: (BuildContext context, _) => Row(
                    children: <Widget>[
                      const Icon(Icons.monetization_on, color: Palette.gold, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        formatCoins(wallet.balance),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'COINS',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsColumn extends StatelessWidget {
  const _ResultsColumn({required this.results});

  final List<double> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        const Text(
          'Results',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            shadows: <Shadow>[Shadow(color: Color(0x88000000), blurRadius: 3)],
          ),
        ),
        for (final double r in results.take(7)) ResultChip(label: _fmt(r)),
      ],
    );
  }

  static String _fmt(double v) {
    String s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return 'x$s';
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.engine,
    required this.wallet,
    required this.onBuild,
    required this.onCashout,
    required this.onBetChanged,
  });

  final SkyEngine engine;
  final Wallet wallet;
  final VoidCallback onBuild;
  final VoidCallback onCashout;
  final VoidCallback onBetChanged;

  @override
  Widget build(BuildContext context) {
    final bool betting = engine.phase == Phase.betting;
    return Container(
      color: const Color(0xFF15171A),
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      child: AnimatedBuilder(
        animation: wallet,
        builder: (BuildContext context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: betting
                  ? _BetRow(wallet: wallet, onChanged: onBetChanged)
                  : const SizedBox(width: double.infinity, height: 0),
            ),
            if (betting) const SizedBox(height: 8),
            Row(
              children: <Widget>[
                if (!betting) ...<Widget>[
                  Expanded(
                    child: BlueButton(
                      height: 68,
                      enabled: engine.canCashout,
                      onTap: onCashout,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Text(
                            'CASHOUT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                          Text(
                            '${formatCoins(engine.payout)} COINS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // BUILD keeps its own natural width, no horizontal stretch.
                Expanded(
                  child: PlateButton(
                    image: const AssetImage(
                      'assets/Skyspire_gameplay_assets/button_main_asset_2.webp',
                    ),
                    enabled: engine.canDrop,
                    onTap: onBuild,
                    height: 72,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.pause_rounded, color: Colors.white, size: 24),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({required this.onResume, required this.onExit});

  final VoidCallback onResume;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onResume,
        child: Container(
          color: Colors.black.withValues(alpha: 0.62),
          alignment: Alignment.center,
          child: Container(
            width: 260,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2126),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            // Absorb taps on the card so the outer resume-on-tap is only
            // triggered when the user actually taps the dimmed background.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'PAUSED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  BlueButton(
                    height: 50,
                    onTap: onResume,
                    child: const Text(
                      'RESUME',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onExit,
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2E35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'MAIN MENU',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BetRow extends StatelessWidget {
  const _BetRow({required this.wallet, required this.onChanged});

  final Wallet wallet;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 82,
          child: BlueButton(
            height: 42,
            onTap: () {
              wallet.allIn();
              onChanged();
            },
            child: const Text(
              'ALL IN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Palette.slot,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Palette.slotEdge, width: 1.2),
            ),
            child: Row(
              children: <Widget>[
                RoundStepButton(
                  icon: Icons.remove,
                  onTap: wallet.bet <= Wallet.minBet
                      ? null
                      : () {
                          wallet.stepBet(-1);
                          onChanged();
                        },
                ),
                Expanded(
                  child: Text(
                    formatCoins(wallet.bet.toDouble()),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                RoundStepButton(
                  icon: Icons.add,
                  onTap: () {
                    wallet.stepBet(1);
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          child: BlueButton(
            height: 42,
            onTap: () {
              wallet.doubleBet();
              onChanged();
            },
            child: const Text(
              'x2',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
