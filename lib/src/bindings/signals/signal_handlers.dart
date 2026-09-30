part of 'signals.dart';

final assignRustSignal = <String, void Function(Uint8List, Uint8List)>{
  'RoundReport': (Uint8List messageBytes, Uint8List binary) {
    final message = RoundReport.bincodeDeserialize(messageBytes);
    final rustSignal = RustSignalPack(
      message,
      binary,
    );
    _roundReportStreamController.add(rustSignal);
    RoundReport.latestRustSignal = rustSignal;
  },
};
