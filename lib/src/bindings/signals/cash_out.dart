// ignore_for_file: type=lint, type=warning
part of 'signals.dart';

/// The player closed the round; compute the banked payout for this bet.
@immutable
class CashOut {
  const CashOut({
    required this.bet,
  });

  static CashOut deserialize(BinaryDeserializer deserializer) {
    deserializer.increaseContainerDepth();
    final instance = CashOut(
      bet: deserializer.deserializeUint32(),
    );
    deserializer.decreaseContainerDepth();
    return instance;
  }

  static CashOut bincodeDeserialize(Uint8List input) {
    final deserializer = BincodeDeserializer(input);
    final value = CashOut.deserialize(deserializer);
    if (deserializer.offset < input.length) {
      throw Exception('Some input bytes were not read');
    }
    return value;
  }

  final int bet;

  CashOut copyWith({
    int? bet,
  }) {
    return CashOut(
      bet: bet ?? this.bet,
    );
  }

  void serialize(BinarySerializer serializer) {
    serializer.increaseContainerDepth();
    serializer.serializeUint32(bet);
    serializer.decreaseContainerDepth();
  }

  Uint8List bincodeSerialize() {
      final serializer = BincodeSerializer();
      serialize(serializer);
      return serializer.bytes;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;

    return other is CashOut
      && bet == other.bet;
  }

  @override
  int get hashCode => bet.hashCode;

  @override
  String toString() {
    String? fullString;

    assert(() {
      fullString = '$runtimeType('
        'bet: $bet'
        ')';
      return true;
    }());

    return fullString ?? 'CashOut';
  }
}

extension CashOutDartSignalExt on CashOut {
  /// Sends the signal to Rust.
  /// Passing data from Rust to Dart involves a memory copy
  /// because Rust cannot own data managed by Dart's garbage collector.
  void sendSignalToRust() {
    final messageBytes = bincodeSerialize();
    final binary = Uint8List(0);
    sendDartSignal(
      'rinf_send_dart_signal_cash_out',
      messageBytes,
      binary,
    );
  }
}
