import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player coins plus the few flags that survive a restart.
class Wallet extends ChangeNotifier {
  Wallet._(this._prefs)
    : _balance = _prefs.getDouble(_kBalance) ?? startingBalance,
      _bet = _prefs.getInt(_kBet) ?? 100,
      _best = _prefs.getDouble(_kBest) ?? 0,
      _onboarded = _prefs.getBool(_kOnboarded) ?? false;

  static const double startingBalance = 1000;
  static const int minBet = 10;
  static const List<int> steps = <int>[10, 25, 50, 100, 250, 500, 1000, 2500, 5000];

  static const String _kBalance = 'balance';
  static const String _kBet = 'bet';
  static const String _kBest = 'best';
  static const String _kOnboarded = 'onboarded';

  final SharedPreferences _prefs;
  double _balance;
  int _bet;
  double _best;
  bool _onboarded;

  static Future<Wallet> load() async =>
      Wallet._(await SharedPreferences.getInstance());

  double get balance => _balance;
  int get bet => _bet;
  double get best => _best;
  bool get onboarded => _onboarded;

  bool get canBet => _balance >= _bet && _bet >= minBet;

  void setBet(int value) {
    final int clamped = value.clamp(minBet, 100000);
    if (clamped == _bet) return;
    _bet = clamped;
    _prefs.setInt(_kBet, _bet);
    notifyListeners();
  }

  void stepBet(int direction) {
    if (direction > 0) {
      setBet(steps.firstWhere((int s) => s > _bet, orElse: () => _bet + 1000));
    } else {
      setBet(steps.lastWhere((int s) => s < _bet, orElse: () => minBet));
    }
  }

  int get _maxBet => math.max(minBet, _balance.floor());

  void doubleBet() => setBet(math.min(_bet * 2, _maxBet));

  void allIn() => setBet(_maxBet);

  void take(int amount) {
    _balance -= amount;
    if (_balance < 0) _balance = 0;
    _save();
  }

  void give(double amount) {
    _balance += amount;
    if (amount > _best) {
      _best = amount;
      _prefs.setDouble(_kBest, _best);
    }
    _save();
  }

  /// Free top up so the game never dead ends.
  void refill() {
    _balance += 500;
    _save();
  }

  /// Wipes all progress: balance, current bet and best win.
  Future<void> resetProgress() async {
    _balance = startingBalance;
    _bet = 100;
    _best = 0;
    await _prefs.setDouble(_kBalance, _balance);
    await _prefs.setInt(_kBet, _bet);
    await _prefs.setDouble(_kBest, _best);
    notifyListeners();
  }

  void markOnboarded() {
    if (_onboarded) return;
    _onboarded = true;
    _prefs.setBool(_kOnboarded, true);
    notifyListeners();
  }

  void _save() {
    _prefs.setDouble(_kBalance, _balance);
    if (_bet > _balance && _balance >= minBet) {
      _bet = _balance.floor();
      _prefs.setInt(_kBet, _bet);
    }
    notifyListeners();
  }
}

/// 1 234.5 style formatting used across the HUD.
String formatCoins(double v) {
  final double rounded = (v * 100).roundToDouble() / 100;
  final bool whole = rounded == rounded.roundToDouble();
  final String text = whole
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(2);
  final List<String> parts = text.split('.');
  final String intPart = parts.first;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) out.write(' ');
    out.write(intPart[i]);
  }
  return parts.length > 1 ? '$out.${parts[1]}' : out.toString();
}
