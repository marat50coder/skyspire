// ignore_for_file: type=lint, type=warning
part of 'signals.dart';

/// A fresh scoring round begins (first bet placed / after a crash or cash-out).
@immutable
class RoundReset {
  const RoundReset({
    required this.bet,
  });

  static RoundReset deserialize(BinaryDeserializer deserializer) {
    deserializer.increaseContainerDepth();
    final instance = RoundReset(
      bet: deserializer.deserializeUint32(),
    );
    deserializer.decreaseContainerDepth();
    return instance;
  }

  static RoundReset bincodeDeserialize(Uint8List input) {
    final deserializer = BincodeDeserializer(input);
    final value = RoundReset.deserialize(deserializer);
    if (deserializer.offset < input.length) {
      throw Exception('Some input bytes were not read');
    }
    return value;
  }

  final int bet;

  RoundReset copyWith({
    int? bet,
  }) {
    return RoundReset(
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

    return other is RoundReset
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

    return fullString ?? 'RoundReset';
  }
}

extension RoundResetDartSignalExt on RoundReset {
  /// Sends the signal to Rust.
  /// Passing data from Rust to Dart involves a memory copy
  /// because Rust cannot own data managed by Dart's garbage collector.
  void sendSignalToRust() {
    final messageBytes = bincodeSerialize();
    final binary = Uint8List(0);
    sendDartSignal(
      'rinf_send_dart_signal_round_reset',
      messageBytes,
      binary,
    );
  }
}
