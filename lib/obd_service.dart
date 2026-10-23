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

  // Buffer per la memorizzazione dei log di diagnostica
  final List<String> _logsList = [];
  static const int _maxLogLines = 300;

  void _log(String msg) {
    final timestamp = DateTime.now().toIso8601String().split('T').last.substring(0, 12);
    _logsList.add("[$timestamp] $msg");
    if (_logsList.length > _maxLogLines) {
      _logsList.removeAt(0);
    }
  }

  String getLogs() {
    return _logsList.join("\n");
  }

  void clearLogs() {
    _logsList.clear();
    _log("Log di diagnostica puliti.");
  }

  bool get isConnected => connection != null && connection!.isConnected;

  Future<List<BluetoothDevice>> getBondedDevices() async {
    _log("Scansione dispositivi Bluetooth associati...");
    try {
      List<BluetoothDevice> devs = await FlutterBluetoothSerial.instance.getBondedDevices();
      _log("Trovati ${devs.length} dispositivi associati.");
      return devs;
    } catch (e) {
      _log("Errore recupero dispositivi: $e");
      rethrow;
    }
  }

  Future<bool> connectToDevice(BluetoothDevice d) async {
    _log("Tentativo di connessione a ${d.name ?? 'Dispositivo'} (${d.address})...");
    try {
      connection = await BluetoothConnection.toAddress(d.address);
      _btSub = connection!.input!.listen((data) {
        String incoming = String.fromCharCodes(data);
        _buf += incoming;
      });
      _log("Connessione Bluetooth stabilita. Invio sequenza AT di inizializzazione...");
      for (String c in ["ATZ\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATCAF1\r"]) {
        await queryObd(c, timeoutMs: 250);
      }
      _log("Inizializzazione AT completata con successo.");
      return true;
    } catch (e) {
      _log("Errore critico di connessione: $e");
      return false;
    }
  }

  Future<String> queryObd(String cmd, {int timeoutMs = 180}) async {
    if (connection == null || !connection!.isConnected) return "";
    _buf = "";
    
    _log("TX: ${cmd.replaceAll('\r', '\\r')}");
    connection!.output.add(Uint8List.fromList(cmd.codeUnits));
    await connection!.output.allSent;
    
    Stopwatch sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < timeoutMs) {
      if (_buf.contains('>')) break;
      await Future.delayed(const Duration(milliseconds: 10));
    }
    String r = _buf;
    _buf = "";
    
    String cleanResp = r.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    _log("RX: $cleanResp");
    
    return r.trim();
  }

  Future<void> setChan(String id) async {
    _log("Configurazione canale CAN per centralina ID: $id");
    await queryObd("AT CP 18\r", timeoutMs: 80);
    await queryObd("AT SH DA${id}F1\r", timeoutMs: 80);
    await queryObd("AT CRA 18DAF1$id\r", timeoutMs: 80);
    await queryObd("AT FC SH 18DA${id}F1\r", timeoutMs: 80);
  }

  Future<void> initEcuChannel(String id) async {
    _log("Inizializzazione canale ECU ID: $id");
    stopPolling();
    await queryObd("AT SP 7\r", timeoutMs: 180);
    await setChan(id);
    await queryObd("AT FC SD 30 00 00\r", timeoutMs: 90);
    await queryObd("AT FC SM 1\r", timeoutMs: 90);
    await queryObd("AT ST 19\r", timeoutMs: 90);
    await queryObd("AT AT 2\r", timeoutMs: 90);
    await queryObd("10 03\r", timeoutMs: 200);
    _log("Canale ECU $id inizializzato e pronto.");
  }

  void startPolling(Future<void> Function(int tick) onPollTick) {
    _log("Avvio polling periodico ECU...");
    stopPolling();
    _obdTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
      if (!isConnected) {
        _log("Polling interrotto: connessione persa.");
        t.cancel();
        return;
      }
      if (_busy) return;
      _busy = true;
      try {
        await onPollTick(_tick);
        _tick++;
      } catch (e) {
        _log("Errore durante il ciclo di polling: $e");
      } finally {
        _busy = false;
      }
    });
  }

  void stopPolling() {
    if (_obdTimer != null) {
      _log("Arresto polling periodico.");
    }
    _obdTimer?.cancel();
    _obdTimer = null;
    _busy = false;
    _tick = 0;
  }

  void disconnect() {
    _log("Disconnessione in corso...");
    stopPolling();
    _btSub?.cancel();
    connection?.dispose();
    connection = null;
    _log("Disconnesso correttamente.");
  }
}
