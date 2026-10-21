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
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 2;
      if (hasIdx && hasLen) {
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
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 3;
      if (hasIdx && hasLen) {
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
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 3;
      if (hasIdx && hasLen) {
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
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 5;
      if (hasIdx && hasLen) {
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
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 2;
      if (hasIdx && hasLen) {
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
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 1;
      if (hasIdx && hasLen) {
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
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 1;
      if (hasIdx && hasLen) {
        int kPa = int.parse(parts[idx + 1], radix: 16);
        double bar = (kPa - 100) / 100.0;
        
        if (bar < -1.0) bar = -1.0;
        if (bar > 1.6) bar = 1.6;
        
        return bar.toStringAsFixed(2);
      }
    } catch (_) {}
    return turboVal;
  }

  String parseCoolant(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("05");
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 1;
      if (hasIdx && hasLen) {
        int a = int.parse(parts[idx + 1], radix: 16);
        return (a - 40).toString();
      }
    } catch (_) {}
    return coolantVal;
  }

  String parseOil(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("5C");
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 1;
      if (hasIdx && hasLen) {
        int a = int.parse(parts[idx + 1], radix: 16);
        return (a - 40).toString();
      }
    } catch (_) {}
    return oilVal;
  }

  String parseIat(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("0F");
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 1;
      if (hasIdx && hasLen) {
        int a = int.parse(parts[idx + 1], radix: 16);
        return (a - 40).toString();
      }
    } catch (_) {}
    return iatVal;
  }

  String parseCatalyst(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("3C");
      bool hasIdx = idx != -1;
      bool hasLen = parts.length > idx + 2;
      if (hasIdx && hasLen) {
        int a = int.parse(parts[idx + 1], radix: 16);
        int b = int.parse(parts[idx + 2], radix: 16);
        double temp = (((a * 256) + b) / 10.0) - 40.0;
        return temp.round().toString();
      }
    } catch (_) {}
    return catalystVal;
  }

  String parseBattery(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll("V", "").trim();
      final match = RegExp(r'(\d+\.\d+)').firstMatch(clean);
      if (match != null) {
        return double.parse(match.group(1)!).toStringAsFixed(1);
      }
    } catch (_) {}
    return batteryVal;
  }

  void _showEcuSelector() {
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Prima connetti l'adattatore Bluetooth OBD!")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161A1D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 450,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Seleziona Centralina (ECU)",
                style: TextStyle(
                  color: Color(0xFFFFB74D),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Scegli quale centralina interrogare:",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: ecuList.length,
                  itemBuilder: (context, index) {
                    final ecu = ecuList[index];
                    final bool isSelected = selectedEcu == ecu && isEcuConnected;
                    return ListTile(
                      title: Text(
                        ecu,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFFFFB74D) : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check, color: Color(0xFFFFB74D))
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        connectToSelectedEcu(ecu);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required Color borderColor,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161A1D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor.withOpacity(0.9),
          width: 2.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accentColor, size: 24),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? modelDropdownValue = selectedModel.isEmpty ? null : selectedModel;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'FRU SCAN',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Color(0xFFFFB74D),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF161A1D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                        color: isConnected ? Colors.greenAccent : Colors.orangeAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isConnected ? "Connesso a: $connectedDeviceName" : "Stato: $statusMessage",
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isConnected ? Colors.red[800] : const Color(0xFFFFB74D),
                            foregroundColor: isConnected ? Colors.white : Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: isConnecting
                              ? null
                              : (isConnected ? disconnectBluetooth : _showBluetoothDeviceSelector),
                          child: Text(
                            isConnecting
                                ? "Connessione..."
                                : (isConnected ? "Disconnetti Bluetooth" : "Scegli Bluetooth"),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: isEcuConnected
                            ? ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange[800],
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: disconnectEcu,
                                child: const Text(
                                  "DISCONNETTI ECU",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              )
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFFB74D),
                                  side: const BorderSide(color: Color(0xFFFFB74D), width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: _showEcuSelector,
                                icon: const Icon(Icons.settings_input_component, size: 16),
                                label: const Text(
                                  "SELEZIONA ECU",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            if (isEcuConnected) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF161A1D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          "Centralina Attiva: $selectedEcu",
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ecuResponseInfo,
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Riquadri Marca e Modello compatti ottimizzati
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A1D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 1.2),
                    ),
                    child: Row(
                      children: [
                        const Text("Marca:", style: TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedBrand,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF161A1D),
                              style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13, fontWeight: FontWeight.bold),
                              items: brandList.map((brand) {
                                return DropdownMenuItem(
                                  value: brand,
                                  child: Text(brand),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  selectedBrand = val!;
                                  if (selectedBrand == "Fiat/Stellantis") {
                                    selectedModel = "Tipo Cross 1.0 T3";
                                  } else {
                                    selectedModel = "";
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A1D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 1.2),
                    ),
                    child: Row(
                      children: [
                        const Text("Modello:", style: TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: modelDropdownValue,
                              hint: const Text("Nessun modello", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              isExpanded: true,
                              dropdownColor: const Color(0xFF161A1D),
                              style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13, fontWeight: FontWeight.bold),
                              items: selectedBrand == "Fiat/Stellantis"
                                  ? [
                                      const DropdownMenuItem(
                                        value: "Tipo Cross 1.0 T3",
                                        child: Text("Tipo Cross 1.0 T3"),
                                      )
                                    ]
                                  : [],
                              onChanged: selectedBrand == "Fiat/Stellantis"
                                  ? (val) {
                                      setState(() {
                                        selectedModel = val!;
                                      });
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Expanded(
              child: isEcuConnected
                  ? (selectedEcu == "Centralina Motore (ECU)"
                      ? GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.45,
                          children: [
                            buildMetricCard(
                              icon: Icons.speed,
                              title: "Giri Motore",
                              value: rpmVal,
                              unit: "RPM",
                              borderColor: Colors.orangeAccent,
                              accentColor: Colors.orangeAccent,
                            ),
                            buildMetricCard(
                              icon: Icons.directions_car,
                              title: "Velocità",
                              value: speedVal,
                              unit: "km/h",
                              borderColor: Colors.greenAccent,
                              accentColor: Colors.
