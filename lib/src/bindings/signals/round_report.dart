// ignore_for_file: type=lint, type=warning
part of 'signals.dart';

/// Authoritative round result returned on cash-out.
@immutable
class RoundReport {
  /// An async broadcast stream that listens for signals from Rust.
  /// It supports multiple subscriptions.
  /// Make sure to cancel the subscription when it's no longer needed,
  /// such as when a widget is disposed.
  static final rustSignalStream =
      _roundReportStreamController.stream.asBroadcastStream();
        
  /// The latest signal value received from Rust.
  /// This is updated every time a new signal is received.
  /// It can be null if no signals have been received yet.
  static RustSignalPack<RoundReport>? latestRustSignal = null;

  const RoundReport({
    required this.payout,
    required this.totalMult,
    required this.rating,
    required this.blocks,
  });

  static RoundReport deserialize(BinaryDeserializer deserializer) {
    deserializer.increaseContainerDepth();
    final instance = RoundReport(
      payout: deserializer.deserializeFloat64(),
      totalMult: deserializer.deserializeFloat64(),
      rating: deserializer.deserializeUint32(),
      blocks: deserializer.deserializeUint32(),
    );
    deserializer.decreaseContainerDepth();
    return instance;
  }

  static RoundReport bincodeDeserialize(Uint8List input) {
    final deserializer = BincodeDeserializer(input);
    final value = RoundReport.deserialize(deserializer);
    if (deserializer.offset < input.length) {
      throw Exception('Some input bytes were not read');
    }
    return value;
  }

  final double payout;
  final double totalMult;
  final int rating;
  final int blocks;

  RoundReport copyWith({
    double? payout,
    double? totalMult,
    int? rating,
    int? blocks,
  }) {
    return RoundReport(
      payout: payout ?? this.payout,
      totalMult: totalMult ?? this.totalMult,
      rating: rating ?? this.rating,
      blocks: blocks ?? this.blocks,
    );
  }

  void serialize(BinarySerializer serializer) {
    serializer.increaseContainerDepth();
    serializer.serializeFloat64(payout);
    serializer.serializeFloat64(totalMult);
    serializer.serializeUint32(rating);
    serializer.serializeUint32(blocks);
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

    return other is RoundReport
      && payout == other.payout
      && totalMult == other.totalMult
      && rating == other.rating
      && blocks == other.blocks;
  }

  @override
  int get hashCode => Object.hash(
        payout,
        totalMult,
        rating,
        blocks,
      );

  @override
  String toString() {
    String? fullString;

    assert(() {
      fullString = '$runtimeType('
        'payout: $payout, '
        'totalMult: $totalMult, '
        'rating: $rating, '
        'blocks: $blocks'
        ')';
      return true;
    }());

    return fullString ?? 'RoundReport';
  }
}

final _roundReportStreamController =
    StreamController<RustSignalPack<RoundReport>>();
