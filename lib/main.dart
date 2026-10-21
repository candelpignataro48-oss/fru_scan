import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const FruScanApp());
}

class FruScanApp extends StatelessWidget {
  const FruScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fru Scan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E1113),
        primaryColor: const Color(0xFFFFB74D),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  BluetoothConnection? connection;
  bool isConnecting = false;
  bool isConnected = false;
  bool isEcuConnected = false;
  String statusMessage = "Disconnesso";
  String selectedEcu = "Nessuna";
  String connectedDeviceName = "";
  String ecuResponseInfo = "Nessuna ECU interrogata";

  String selectedBrand = "Fiat/Stellantis";
  String selectedModel = "Tipo Cross 1.0 T3";

  // Parametri Generici / Multi-ECU in tempo reale
  String param1Val = "---";
  String param2Val = "---";
  String param3Val = "---";
  String param4Val = "---";
  String param5Val = "---";
  String param6Val = "---";

  // Specifici Centralina Motore
  String rpmVal = "---";
  String speedVal = "---";
  String turboVal = "0.00";
  String batteryVal = "---";
  String alternatorVal = "---";
  String coolantVal = "---";
  String oilVal = "---";
  String iatVal = "---";
  String catalystVal = "---";
  String oilDegradationVal = "---";

  // Specifici Body Computer
  String bcmIbsSocVal = "---";
  String bcmBatteryVoltVal = "---";
  String bcmOdometerVal = "---";
  String bcmLightsStatusVal = "OK";
  String bcmProxyStatusVal = "Regolare";

  Timer? _obdTimer;
  StreamSubscription<Uint8List>? _bluetoothSubscription;
  String _buffer = "";

  // Header CAN dedicati per ogni centralina (Standard Fiat/Alfa/Jeep UDS)
  final Map<String, Map<String, String>> ecuHeaders = {
    "Centralina Motore (ECU)": {"tx": "7E0", "rx": "7E8", "fc": "7E0"},
    "Body Computer": {"tx": "720", "rx": "728", "fc": "720"},
    "Quadro Strumenti": {"tx": "710", "rx": "718", "fc": "710"},
    "Sensori di Parcheggio": {"tx": "740", "rx": "748", "fc": "740"},
    "Servosterzo": {"tx": "730", "rx": "738", "fc": "730"},
    "Cruise Control": {"tx": "750", "rx": "758", "fc": "750"},
    "Climatizzatore": {"tx": "760", "rx": "768", "fc": "760"},
    "Radio": {"tx": "770", "rx": "778", "fc": "770"},
    "ABS": {"tx": "7A0", "rx": "7A8", "fc": "7A0"},
    "Airbag": {"tx": "7C0", "rx": "7C8", "fc": "7C0"},
    "Blind Spot": {"tx": "780", "rx": "788", "fc": "780"},
    "Telecamere": {"tx": "790", "rx": "798", "fc": "790"},
    "Radar": {"tx": "7B0", "rx": "7B8", "fc": "7B0"},
  };

  final List<String> ecuList = [
    "Centralina Motore (ECU)",
    "Body Computer",
    "Quadro Strumenti",
    "Sensori di Parcheggio",
    "Servosterzo",
    "Cruise Control",
    "Climatizzatore",
    "Radio",
    "ABS",
    "Airbag",
    "Blind Spot",
    "Telecamere",
    "Radar",
  ];

  final List<String> brandList = [
    "Fiat/Stellantis",
    "Alfa Romeo",
  ];

  @override
  void dispose() {
    _obdTimer?.cancel();
    _bluetoothSubscription?.cancel();
    connection?.dispose();
    super.dispose();
  }

  Future<void> requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
  }

  void _showBluetoothDeviceSelector() async {
    setState(() {
      isConnecting = true;
      statusMessage = "Richiesta permessi...";
    });

    await requestPermissions();

    setState(() {
      statusMessage = "Lettura dispositivi associati...";
    });

    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      
      setState(() {
        isConnecting = false;
        statusMessage = "Seleziona interfaccia";
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF161A1D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              "Dispositivi Bluetooth Associati",
              style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: devices.isEmpty
                  ? const Center(
                      child: Text(
                        "Nessun dispositivo associato trovato.\nAssocia l'interfaccia nelle impostazioni Bluetooth del telefono.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        BluetoothDevice device = devices[index];
                        return ListTile(
                          leading: const Icon(Icons.bluetooth, color: Color(0xFFFFB74D)),
                          title: Text(
                            device.name ?? "Dispositivo Senza Nome",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            device.address,
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            connectToDevice(device);
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Annulla", style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        },
      );
    } catch (e) {
      setState(() {
        isConnecting = false;
        statusMessage = "Errore scansione Bluetooth";
      });
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    setState(() {
      isConnecting = true;
      statusMessage = "Connessione a ${device.name ?? device.address}...";
    });

    try {
      connection = await BluetoothConnection.toAddress(device.address);
      
      setState(() {
        isConnected = true;
        isConnecting = false;
        connectedDeviceName = device.name ?? device.address;
        statusMessage = "Bluetooth Connesso";
      });

      _bluetoothSubscription = connection!.input!.listen((data) {
        _buffer += String.fromCharCodes(data);
      });

      await sendCommand("ATZ\r");
      await Future.delayed(const Duration(milliseconds: 300));
      await sendCommand("ATE0\r");
      await Future.delayed(const Duration(milliseconds: 150));
      await sendCommand("ATSP0\r");
      await Future.delayed(const Duration(milliseconds: 150));

    } catch (e) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = "Errore di connessione";
      });
    }
  }

  void disconnectBluetooth() {
    _obdTimer?.cancel();
    _bluetoothSubscription?.cancel();
    connection?.dispose();
    setState(() {
      isConnected = false;
      isEcuConnected = false;
      selectedEcu = "Nessuna";
      statusMessage = "Disconnesso";
      connectedDeviceName = "";
      ecuResponseInfo = "Nessuna ECU interrogata";
    });
  }

  void disconnectEcu() {
    _obdTimer?.cancel();
    sendCommand("AT D\r");
    setState(() {
      isEcuConnected = false;
      selectedEcu = "Nessuna";
      ecuResponseInfo = "ECU disconnessa";
    });
  }

  Future<void> sendCommand(String cmd) async {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(Uint8List.fromList(cmd.codeUnits));
      await connection!.output.allSent;
    }
  }

  Future<String> queryObdCommand(String cmd, {int timeoutMs = 450}) async {
    if (connection == null || !connection!.isConnected) return "";
    
    _buffer = "";
    connection!.output.add(Uint8List.fromList(cmd.codeUnits));
    await connection!.output.allSent;

    Stopwatch stopwatch = Stopwatch()..start();
    while (stopwatch.elapsedMilliseconds < timeoutMs) {
      if (_buffer.contains('>')) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }

    String response = _buffer;
    _buffer = "";
    return response.trim();
  }

  String decodeUdsAscii(String rawResp) {
    try {
      final clean = rawResp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      
      int idx = parts.indexOf("62");
      if (idx != -1 && parts.length > idx + 2) {
        List<int> asciiCodes = [];
        for (int i = idx + 3; i < parts.length; i++) {
          if (parts[i].length == 2) {
            int? val = int.tryParse(parts[i], radix: 16);
            if (val != null && val >= 32 && val <= 126) {
              asciiCodes.add(val);
            }
          }
        }
        if (asciiCodes.isNotEmpty) {
          return String.fromCharCodes(asciiCodes);
        }
      }
    } catch (_) {}
    return rawResp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  }

  // Motore di connessione multi-ECU stile AlfaOBD con configurazione canali ISO-TP
  void connectToSelectedEcu(String ecuName) async {
    setState(() {
      selectedEcu = ecuName;
      isEcuConnected = true;
      ecuResponseInfo = "Inizializzazione sessione UDS per $ecuName...";
    });

    final header = ecuHeaders[ecuName] ?? {"tx": "7E0", "rx": "7E8", "fc": "7E0"};

    // Configurazione ELM327 / vLinker per la specifica centralina
    await queryObdCommand("AT SP 6\r", timeoutMs: 250);
    await queryObdCommand("AT SH ${header['tx']}\r", timeoutMs: 250);
    await queryObdCommand("AT CRA ${header['rx']}\r", timeoutMs: 250);
    await queryObdCommand("AT CP 25\r", timeoutMs: 200);
    await queryObdCommand("AT FC SH ${header['fc']}\r", timeoutMs: 200);
    await queryObdCommand("AT FC SD 30 00 00\r", timeoutMs: 200);
    await queryObdCommand("AT FC SM 1\r", timeoutMs: 200);
    await queryObdCommand("AT AT 1\r", timeoutMs: 200);

    // Apertura sessione diagnostica UDS (Extended Diagnostic Session)
    await queryObdCommand("10 03\r", timeoutMs: 400);

    // Lettura codice parte identificativo ECU (Servizio UDS 22 F187)
    String partResp = await queryObdCommand("22 F1 87\r", timeoutMs: 500);
    String decodedPart = decodeUdsAscii(partResp);

    setState(() {
      ecuResponseInfo = "$selectedEcu (TX:${header['tx']} / RX:${header['rx']})\nHardware/Part Code:$decodedPart";
    });

    // Avvio del loop di polling dedicato in base alla centralina selezionata
    if (selectedEcu == "Centralina Motore (ECU)") {
      startEngineLoop();
    } else if (selectedEcu == "Body Computer") {
      startBcmLoop();
    } else {
      startGenericEcuLoop();
    }
  }

  void startEngineLoop() {
    _obdTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!isEcuConnected || connection == null || selectedEcu != "Centralina Motore (ECU)") {
        timer.cancel();
        return;
      }

      try {
        String rpmResp = await queryObdCommand("010C\r");
        String speedResp = await queryObdCommand("010D\r");
        String turboResp = await queryObdCommand("010B\r");
        String coolantResp = await queryObdCommand("0105\r");
        String oilResp = await queryObdCommand("015C\r");
        String iatResp = await queryObdCommand("010F\r");
        String catalystResp = await queryObdCommand("013C\r");
        String batteryResp = await queryObdCommand("ATRV\r");
        String altResp = await queryObdCommand("ATRV\r");
        String oilDegResp = await queryObdCommand("22 18 08\r");

        if (mounted) {
          setState(() {
            rpmVal = parseRpm(rpmResp);
            speedVal = parseSpeed(speedResp);
            turboVal = parseTurbo(turboResp);
            coolantVal = parseCoolant(coolantResp);
            oilVal = parseOil(oilResp);
            iatVal = parseIat(iatResp);
            catalystVal = parseCatalyst(catalystResp);
            batteryVal = parseBattery(batteryResp);
            alternatorVal = parseBattery(altResp);
            oilDegradationVal = parseOilDegradation(oilDegResp);
          });
        }
      } catch (_) {}
    });
  }

  void startBcmLoop() {
    _obdTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!isEcuConnected || connection == null || selectedEcu != "Body Computer") {
        timer.cancel();
        return;
      }

      try {
        String voltResp = await queryObdCommand("ATRV\r");
        String ibsResp = await queryObdCommand("22 90 01\r"); 
        String odoResp = await queryObdCommand("22 F1 C1\r");

        if (mounted) {
          setState(() {
            bcmBatteryVoltVal = parseBattery(voltResp);
            bcmIbsSocVal = parseBcmIbsSoc(ibsResp);
            bcmOdometerVal = parseBcmOdometer(odoResp);
            bcmLightsStatusVal = "OK";
            bcmProxyStatusVal = "Regolare";
          });
        }
      } catch (_) {}
    });
  }

  // Loop generico per interrogare dinamicamente qualsiasi altra centralina (ABS, Airbag, Quadro, ecc.)
  void startGenericEcuLoop() {
    _obdTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!isEcuConnected || connection == null) {
        timer.cancel();
        return;
      }

      try {
        String voltResp = await queryObdCommand("ATRV\r");
        String statusResp = await queryObdCommand("22 F1 90\r"); // Routine generica UDS stato centralina

        if (mounted) {
          setState(() {
            param1Val = parseBattery(voltResp);
            param2Val = decodeUdsAscii(statusResp);
            param3Val = "Attiva";
            param4Val = "OK";
          });
        }
      } catch (_) {}
    });
  }

  String parseOilDegradation(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("62");
      if (idx != -1 && parts.length > idx + 3) {
        int val = int.parse(parts[idx + 3], radix: 16);
        return val.toString();
      }
    } catch (_) {}
    return "---";
  }

  String parseBcmIbsSoc(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("62");
      if (idx != -1 && parts.length > idx + 3) {
        int val = int.parse(parts[idx + 3], radix: 16);
        return val.toString();
      }
    } catch (_) {}
    return "---";
  }

  String parseBcmOdometer(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("62");
      if (idx != -1 && parts.length > idx + 5) {
        int a = int.parse(parts[idx + 3], radix: 16);
        int b = int.parse(parts[idx + 4], radix: 16);
        int c = int.parse(parts[idx + 5], radix: 16);
        int odo = (a * 65536) + (b * 256) + c;
        if (odo > 0) {
          return odo.toString();
        }
      }
    } catch (_) {}
    return "---";
  }

  String parseRpm(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("0C");
      if (idx != -1 && parts.length > idx + 2) {
        int a = int.parse(parts[idx + 1], radix: 16);
        int b = int.parse(parts[idx + 2], radix: 16);
        return (((a * 256) + b) / 4).round().toString();
      }
    } catch (_) {}
    return rpmVal;
  }

  String parseSpeed(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("0D");
      if (idx != -1 && parts.length > idx + 1) {
        int a = int.parse(parts[idx + 1], radix: 16);
        return a.toString();
      }
    } catch (_) {}
    return speedVal;
  }

  String parseTurbo(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("0B");
      if (idx != -1 && parts.length > idx + 1) {
        int kPa = int.parse(parts[idx + 1], radix: 16);
        double bar = (kPa - 100) / 100.0;
        
        if (bar < -1.0) bar = -1.0;
        if (bar > 1.6) bar = 1.6;
        
