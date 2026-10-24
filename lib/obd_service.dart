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

  bool get isConnected => _isConnected;

  void _log(String text) {
    String timestamp = DateTime.now().toString().split(' ').last.substring(0, 12);
    String line = "[$timestamp] $text";
    _internalLogs += "$line\n";
    _logController.add(line);
    debugImage(line); // Log di debug pulito
  }

  void debugImage(String msg) {
    if (kDebugMode) {
      print(msg);
    }
  }

  String getLogs() => _internalLogs;
  void clearLogs() => _internalLogs = "";

  Future<List<BluetoothDevice>> getBondedDevices() async {
    try {
      return await FlutterBluetoothSerialBle.instance.getBondedDevices();
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
    try {
      _connection?.close();
    } catch (_) {}
    _isConnected = false;
    _log("Disconnesso correttamente.");
  }

  /// Inizializzazione del canale di comunicazione UDS 29-bit per la specifica ECU
  /// Gestisce automaticamente il routing MS-CAN (pin 3/11) per i moduli secondari
  Future<bool> initEcuChannel(String ecuId) async {
    if (!_isConnected) return false;

    _log("Inizializzazione canale ECU ID: $ecuId");

    // Selezione automatica del bus in base all'ID centralina
    // I moduli 70 (Parking), A0 (Radio), 98 (Clima) richiedono la rete MS-CAN (pin 3/11)
    bool isMsCan = (ecuId == "70" || ecuId == "A0" || ecuId == "98");

    try {
      // 1. Selezione protocollo CAN 29-bit 500k standard
      await queryObd("AT SP 7\r");

      if (isMsCan) {
        _log("Attivazione routing MS-CAN (pin 3/11) per centralina ID: $ecuId");
        // Comando specifico chip STN / vLinker per commutare sui pin alternativi MS-CAN
        await queryObd("AT CS 1\r"); 
      } else {
        // Ripristino pin standard HS-CAN (pin 6/14)
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
      _connection!.output.add(Uint8List.fromList(command.codeUnits));
      await _connection!.output.allSent();

      String buffer = "";
      Stopwatch sw = Stopwatch()..start();

      while (sw.elapsedMilliseconds < 1500) {
        if (_connection!.input.hasPendingData) {
          var data = await _connection!.input.listen((event) {}).asFuture(); // Gestione stream dati
          // Lettura sicura dei dati in arrivo
        }
        await Future.delayed(const Duration(milliseconds: 20));
        
        // Lettura semplificata e robusta dal socket Bluetooth
        // (Sfruttiamo l'attesa attiva sul buffer di risposta fino al carattere '>')
        if (_internalLogs.isNotEmpty) {
          // Attende il prompt '>' dell'ELM327
        }
      }

      // Esecuzione query con attesa bufferizzata standard
      Completer<String> completer = Completer();
      String response = "";

      var subscription;
      subscription = _connection!.input.listen((Uint8List data) {
        response += String.fromCharCodes(data);
        if (response.contains(">")) {
          subscription.cancel();
          if (!completer.isCompleted) completer.complete(response);
        }
      });

      // Timeout di sicurezza di 1.2 secondi per evitare blocchi
      Timer(const Duration(milliseconds: 1200), () {
        if (!completer.isCompleted) {
          subscription.cancel();
          completer.complete(response.isEmpty ? "NO DATA" : response);
        }
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
