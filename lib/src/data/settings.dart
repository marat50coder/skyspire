import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences that survive across app launches.
///
/// The class also owns the tiny wrapper around `HapticFeedback` so that
/// turning the setting off actually silences every rumble in the game.
class Settings extends ChangeNotifier {
  Settings._(this._prefs)
    : _vibration = _prefs.getBool(_kVibration) ?? true,
      _reducedFx = _prefs.getBool(_kReducedFx) ?? false;

  static const String _kVibration = 'settings.vibration';
  static const String _kReducedFx = 'settings.reducedFx';

  final SharedPreferences _prefs;
  bool _vibration;
  bool _reducedFx;

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  bool get vibration => _vibration;
  bool get reducedFx => _reducedFx;

  set vibration(bool value) {
    if (value == _vibration) return;
    _vibration = value;
    _prefs.setBool(_kVibration, value);
    notifyListeners();
  }

  set reducedFx(bool value) {
    if (value == _reducedFx) return;
    _reducedFx = value;
    _prefs.setBool(_kReducedFx, value);
    notifyListeners();
  }

  /// Play a rumble unless the user turned vibration off in settings.
  void hapticLight() {
    if (_vibration) HapticFeedback.lightImpact();
  }

  void hapticMedium() {
    if (_vibration) HapticFeedback.mediumImpact();
  }

  void hapticHeavy() {
    if (_vibration) HapticFeedback.heavyImpact();
  }
}
