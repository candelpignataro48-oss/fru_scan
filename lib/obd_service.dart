import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

class ObdService {
  BluetoothConnection? _connection;
  bool _isConnected = false;
  final StreamController<String> _logController = StreamController.broadcast();
  Stream<String> get logStream => _logController.stream;
  
  String _internalLogs = "";
  Timer? _pollingTimer;

  StreamSubscription<Uint8List>? _incomingSub;
  String _rxBuffer = "";

  bool get isConnected => _isConnected;

  void _log(String text) {
    String timestamp = DateTime.now().toString().split(' ').last.substring(0, 12);
    String line = "[$timestamp] $text";
    _internalLogs += "$line\n";
    _logController.add(line);
    if (kDebugMode) {
      print(line);
    }
  }

  String getLogs() => _internalLogs;
  void clearLogs() => _internalLogs = "";

  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      return devices;
    } catch (e) {
      _log("Errore recupero dispositivi associati: $e");
      return [];
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _log("Connessione a ${device.name ?? device.address}...");
      _connection = await BluetoothConnection.toAddress(device.address);
      _isConnected = true;
      _log("Connessione Bluetooth stabilita con successo.");

      // Ascolto permanente e unico del flusso dati in ingresso
      _rxBuffer = "";
      _incomingSub?.cancel();
      _incomingSub = _connection!.input?.listen((Uint8List data) {
        _rxBuffer += String.fromCharCodes(data);
      });

      // Inizializzazione base adattatore ELM327 / vLinker
      await queryObd("AT Z\r"); // Reset adattatore
      await queryObd("AT E0\r"); // Echo off
      await queryObd("AT S0\r"); // Spazi off
      await queryObd("AT H0\r"); // Headers off (iniziale)
      await queryObd("AT SP 0\r"); // Auto protocol
      
      return true;
    } catch (e) {
      _log("Errore connessione Bluetooth: $e");
      _isConnected = false;
      return false;
    }
  }

  void disconnect() {
    stopPolling();
    _incomingSub?.cancel();
    try {
      _connection?.close();
    } catch (_) {}
    _isConnected = false;
    _log("Disconnesso correttamente.");
  }

  Future<bool> initEcuChannel(String ecuId) async {
    if (!_isConnected) return false;

    _log("Inizializzazione canale ECU ID: $ecuId");

    bool isMsCan = (ecuId == "70" || ecuId == "A0" || ecuId == "98");

    try {
      // 1. Selezione protocollo CAN 29-bit 500k standard
      await queryObd("AT SP 7\r");

      if (isMsCan) {
        _log("Attivazione routing MS-CAN (pin 3/11) per centralina ID: $ecuId");
        await queryObd("AT CS 1\r"); 
      } else {
        await queryObd("AT CS 0\r");
      }

      // 2. Configurazione parametri CAN & UDS ISO-TP
      await queryObd("AT CP 18\r");
      await queryObd("AT SH DA${ecuId}F1\r");
      await queryObd("AT CRA 18DAF1$ecuId\r");
      await queryObd("AT FC SH 18DA${ecuId}F1\r");
      await queryObd("AT FC SD 30 00 00\r");
      await queryObd("AT FC SM 1\r");
      await queryObd("AT ST 19\r");
      await queryObd("AT AT 2\r");

      // 3. Apertura sessione diagnostica estesa (UDS Service 10 03)
      String resp = await queryObd("10 03\r");
      _log("Canale ECU $ecuId inizializzato e pronto. Risposta: $resp");
      return true;
    } catch (e) {
      _log("Errore inizializzazione canale ECU $ecuId: $e");
      return false;
    }
  }

  Future<String> queryObd(String command) async {
    if (!_isConnected || _connection == null) return "NO DATA";

    try {
      _log("TX: $command");
      // Pulisce il buffer prima di ogni comando
      _rxBuffer = "";

      _connection!.output.add(Uint8List.fromList(command.codeUnits));
      await _connection!.output.allSent;

      Completer<String> completer = Completer();
      Timer? checkTimer;
      Timer? timeoutTimer;

      void finish(String result) {
        if (!completer.isCompleted) {
          checkTimer?.cancel();
          timeoutTimer?.cancel();
          completer.complete(result);
        }
      }

      // Controlla il buffer finché non arriva il prompt di fine risposta '>'
      checkTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
        if (_rxBuffer.contains(">")) {
          finish(_rxBuffer);
        }
      });

      // Timeout di sicurezza di 1.2 secondi
      timeoutTimer = Timer(const Duration(milliseconds: 1200), () {
        finish(_rxBuffer.isEmpty ? "NO DATA" : _rxBuffer);
      });

      String res = await completer.future;
      res = res.replaceAll("\u0000", "").trim();
      _log("RX: $res");
      return res;
    } catch (e) {
      _log("Errore query OBD ($command): $e");
      return "NO DATA";
    }
  }

  void startPolling(Function(int tick) onTick) {
    stopPolling();
    int tickCount = 0;
    _log("Avvio polling periodico ECU...");
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      try {
        onTick(tickCount++);
      } catch (e) {
        _log("Errore durante il polling: $e");
      }
    });
  }

  void stopPolling() {
    if (_pollingTimer != null) {
      _pollingTimer!.cancel();
      _pollingTimer = null;
      _log("Arresto polling periodico.");
    }
  }
}
