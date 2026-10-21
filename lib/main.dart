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

  String rpmVal = "---";
  String speedVal = "---";
  String turboVal = "---";
  String batteryVal = "---";
  String coolantVal = "---";
  String oilVal = "---";
  String iatVal = "---";
  String catalystVal = "---";

  Timer? _obdTimer;
  StreamSubscription<Uint8List>? _bluetoothSubscription;
  String _buffer = "";

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

  Future<String> queryObdCommand(String cmd, {int timeoutMs = 400}) async {
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

  void connectToSelectedEcu(String ecuName) async {
    setState(() {
      selectedEcu = ecuName;
      isEcuConnected = true;
      ecuResponseInfo = "Connessione in corso a $selectedEcu...";
    });

    if (selectedEcu == "Centralina Motore (ECU)") {
      String testResp = await queryObdCommand("0100\r", timeoutMs: 800);
      setState(() {
        ecuResponseInfo = testResp.isNotEmpty 
            ? "Risposta ECU Motore: ${testResp.replaceAll('\r', ' ').replaceAll('\n', ' ')}" 
            : "ECU Motore Connessa (Pronta)";
      });
      startObdLoop();
    } else {
      String testResp = await queryObdCommand("10 03\r", timeoutMs: 600);
      setState(() {
        ecuResponseInfo = "Risposta ECU ($selectedEcu):${testResp.isNotEmpty ? testResp.replaceAll('\r', ' ').replaceAll('\n', ' ') : 'Pronta'}";
      });
    }
  }

  void startObdLoop() {
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
          });
        }
      } catch (_) {}
    });
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
    return "0";
  }

  String parseTurbo(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("0B");
      if (idx != -1 && parts.length > idx + 1) {
        int kPa = int.parse(parts[idx + 1], radix: 16);
        double bar = (kPa - 100) / 100.0;
        if (bar < 0) bar = 0.0;
        return bar.toStringAsFixed(2);
      }
    } catch (_) {}
    return "0.00";
  }

  String parseCoolant(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("05");
      if (idx != -1 && parts.length > idx + 1) {
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
      if (idx != -1 && parts.length > idx + 1) {
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
      if (idx != -1 && parts.length > idx + 1) {
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
      if (idx != -1 && parts.length > idx + 2) {
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
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161A1D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor.withOpacity(0.9),
          width: 2.8,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accentColor, size: 28),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 18,
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
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // 1. Box principale Bluetooth e Seleziona ECU
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
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
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isConnected ? Colors.red[800] : const Color(0xFFFFB74D),
                            foregroundColor: isConnected ? Colors.white : Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
                                  padding: const EdgeInsets.symmetric(vertical: 10),
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
                                  padding: const EdgeInsets.symmetric(vertical: 10),
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
            const SizedBox(height: 12),

            // 2. Riquadro Info Centralina Connessa (Sopra a Modello e Marca)
            if (isEcuConnected) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF161A1D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          "Centralina Attiva: $selectedEcu",
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ecuResponseInfo,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 3. Riquadri Modello e Marca (Invertiti)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A1D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Modello Auto", style: TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(height: 4),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: modelDropdownValue,
                            hint: const Text("Nessun modello", style: TextStyle(color: Colors.grey, fontSize: 13)),
                            isExpanded: true,
                            dropdownColor: const Color(0xFF161A1D),
                            style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 14, fontWeight: FontWeight.bold),
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161A1D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Marca Auto", style: TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(height: 4),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedBrand,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF161A1D),
                            style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 14, fontWeight: FontWeight.bold),
                            items
