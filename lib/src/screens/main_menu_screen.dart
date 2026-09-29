import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../data/wallet.dart';
import '../game/game_screen.dart';
import '../game/sprites.dart';
import '../ui/palette.dart';
import '../ui/widgets.dart';
import 'settings_screen.dart';
import 'web_page.dart';

/// Main menu of the app. Reached right after the loading screen, offers
/// Play, Settings, Privacy Policy and Support entry points.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({
    super.key,
    required this.sprites,
    required this.wallet,
    required this.settings,
  });

  final Sprites sprites;
  final Wallet wallet;
  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3FA8E0),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final bool portrait = c.maxHeight >= c.maxWidth;
          final String bg = portrait
              ? 'assets/Skyspire_additional_assets/Vertical_Loading_Screen.webp'
              : 'assets/Skyspire_additional_assets/Horizontal_Loading_Screen.webp';
          final double buttonWidth = (c.maxWidth * 0.72).clamp(240.0, 420.0);

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(bg, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0x00000000), Color(0x99000913)],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
                  child: Column(
                    children: <Widget>[
                      const Spacer(flex: 5),
                      SizedBox(
                        width: buttonWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            _MenuButton(
                              label: 'PLAY',
                              onTap: () => _play(context),
                            ),
                            const SizedBox(height: 12),
                            _MenuButton(
                              label: 'SETTINGS',
                              onTap: () => _openSettings(context),
                            ),
                            const SizedBox(height: 12),
                            _MenuButton(
                              label: 'PRIVACY POLICY',
                              onTap: () => _open(
                                context,
                                'Privacy Policy',
                                'https://skyspirre.com/privacy-policy.html',
                              ),
                            ),
                            const SizedBox(height: 12),
                            _MenuButton(
                              label: 'SUPPORT',
                              onTap: () => _open(
                                context,
                                'Support',
                                'https://skyspirre.com/support.html',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(flex: 1),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _play(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (BuildContext context, Animation<double> a, Animation<double> s) =>
            GameScreen(
              sprites: sprites,
              wallet: wallet,
              settings: settings,
            ),
        transitionsBuilder: (
          BuildContext context,
          Animation<double> a,
          Animation<double> s,
          Widget child,
        ) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            SettingsScreen(settings: settings, wallet: wallet),
      ),
    );
  }

  void _open(BuildContext context, String title, String url) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => WebPage(title: title, url: url),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BlueButton(
      height: 56,
      radius: 14,
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          shadows: <Shadow>[
            Shadow(color: Palette.blueDeep, blurRadius: 3, offset: Offset(0, 2)),
          ],
        ),
      ),
    );
  }
}
