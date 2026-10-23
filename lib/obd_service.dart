import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

class ObdService {
  BluetoothConnection? connection;
  StreamSubscription<Uint8List>? _btSub;
  Timer? _obdTimer;
  String _buf = "";
  bool _busy = false;
  int _tick = 0;

  bool get isConnected => connection != null && connection!.isConnected;

  Future<List<BluetoothDevice>> getBondedDevices() async {
    return await FlutterBluetoothSerial.instance.getBondedDevices();
  }

  Future<bool> connectToDevice(BluetoothDevice d) async {
    try {
      connection = await BluetoothConnection.toAddress(d.address);
      _btSub = connection!.input!.listen((data) => _buf += String.fromCharCodes(data));
      for (String c in ["ATZ\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATCAF1\r"]) {
        await queryObd(c, timeoutMs: 250);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> queryObd(String cmd, {int timeoutMs = 180}) async {
    if (connection == null || !connection!.isConnected) return "";
    _buf = "";
    connection!.output.add(Uint8List.fromList(cmd.codeUnits));
    await connection!.output.allSent;
    Stopwatch sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < timeoutMs) {
      if (_buf.contains('>')) break;
      await Future.delayed(const Duration(milliseconds: 10));
    }
    String r = _buf;
    _buf = "";
    return r.trim();
  }

  Future<void> setChan(String id) async {
    await queryObd("AT CP 18\r", timeoutMs: 80);
    await queryObd("AT SH DA${id}F1\r", timeoutMs: 80);
    await queryObd("AT CRA 18DAF1$id\r", timeoutMs: 80);
    await queryObd("AT FC SH 18DA${id}F1\r", timeoutMs: 80);
  }

  Future<void> initEcuChannel(String id) async {
    stopPolling();
    await queryObd("AT SP 7\r", timeoutMs: 180);
    await setChan(id);
    await queryObd("AT FC SD 30 00 00\r", timeoutMs: 90);
    await queryObd("AT FC SM 1\r", timeoutMs: 90);
    await queryObd("AT ST 19\r", timeoutMs: 90);
    await queryObd("AT AT 2\r", timeoutMs: 90);
    await queryObd("10 03\r", timeoutMs: 200);
  }

  void startPolling(Future<void> Function(int tick) onPollTick) {
    stopPolling();
    _obdTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
      if (!isConnected) {
        t.cancel();
        return;
      }
      if (_busy) return;
      _busy = true;
      try {
        await onPollTick(_tick);
        _tick++;
      } catch (_) {
      } finally {
        _busy = false;
      }
    });
  }

  void stopPolling() {
    _obdTimer?.cancel();
    _busy = false;
    _tick = 0;
  }

  void disconnect() {
    stopPolling();
    _btSub?.cancel();
    connection?.dispose();
    connection = null;
  }
}
