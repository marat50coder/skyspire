// ignore_for_file: type=lint, type=warning
part of 'signals.dart';

/// A block settled on the tower. `accuracy_bp` is the landing accuracy in
/// permille (0..1000): 1000 = dead-centre, 0 = at the very edge of tolerance.
@immutable
class BlockLanded {
  const BlockLanded({
    required this.accuracyBp,
  });

  static BlockLanded deserialize(BinaryDeserializer deserializer) {
    deserializer.increaseContainerDepth();
    final instance = BlockLanded(
      accuracyBp: deserializer.deserializeUint32(),
    );
    deserializer.decreaseContainerDepth();
    return instance;
  }

  static BlockLanded bincodeDeserialize(Uint8List input) {
    final deserializer = BincodeDeserializer(input);
    final value = BlockLanded.deserialize(deserializer);
    if (deserializer.offset < input.length) {
      throw Exception('Some input bytes were not read');
    }
    return value;
  }

  final int accuracyBp;

  BlockLanded copyWith({
    int? accuracyBp,
  }) {
    return BlockLanded(
      accuracyBp: accuracyBp ?? this.accuracyBp,
    );
  }

  void serialize(BinarySerializer serializer) {
    serializer.increaseContainerDepth();
    serializer.serializeUint32(accuracyBp);
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

    return other is BlockLanded
      && accuracyBp == other.accuracyBp;
  }

  @override
  int get hashCode => accuracyBp.hashCode;

  @override
  String toString() {
    String? fullString;

    assert(() {
      fullString = '$runtimeType('
        'accuracyBp: $accuracyBp'
        ')';
      return true;
    }());

    return fullString ?? 'BlockLanded';
  }
}

extension BlockLandedDartSignalExt on BlockLanded {
  /// Sends the signal to Rust.
  /// Passing data from Rust to Dart involves a memory copy
  /// because Rust cannot own data managed by Dart's garbage collector.
  void sendSignalToRust() {
    final messageBytes = bincodeSerialize();
    final binary = Uint8List(0);
    sendDartSignal(
      'rinf_send_dart_signal_block_landed',
      messageBytes,
      binary,
    );
  }
}
