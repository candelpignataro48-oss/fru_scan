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
  String statusMessage = "Disconnesso";
  String selectedEcu = "Centralina Motore (ECU)";

  // Valori dei parametri
  String rpmVal = "---";
  String speedVal = "---";
  String turboVal = "---";
  String batteryVal = "---";
  String coolantVal = "---";
  String oilVal = "---";

  Timer? _obdTimer;

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

  @override
  void dispose() {
    _obdTimer?.cancel();
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

  void connectToDevice() async {
    setState(() {
      isConnecting = true;
      statusMessage = "Richiesta permessi...";
    });

    await requestPermissions();

    setState(() {
      statusMessage = "Ricerca vLinker MC+...";
    });

    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      BluetoothDevice vlinker = devices.firstWhere(
        (d) => (d.name ?? "").toUpperCase().contains("VLINKER") || (d.name ?? "").toUpperCase().contains("OBD"),
        orElse: () => devices.first,
      );

      setState(() {
        statusMessage = "Connessione a ${vlinker.name ?? vlinker.address}...";
      });

      connection = await BluetoothConnection.toAddress(vlinker.address);
      
      setState(() {
        isConnected = true;
        isConnecting = false;
        statusMessage = "Connesso";
      });

      await sendCommand("ATZ\r");
      await Future.delayed(const Duration(milliseconds: 250));
      await sendCommand("ATE0\r");
      await Future.delayed(const Duration(milliseconds: 100));
      await sendCommand("ATSP0\r");
      await Future.delayed(const Duration(milliseconds: 100));

      startObdLoop();

    } catch (e) {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = "Errore di connessione";
      });
    }
  }

  Future<void> sendCommand(String cmd) async {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(Uint8List.fromList(cmd.codeUnits));
      await connection!.output.allSent;
    }
  }

  void startObdLoop() {
    _obdTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) async {
      if (!isConnected || connection == null) {
        timer.cancel();
        return;
      }
      try {
        // Interrogazione PID standard OBD2
        String rpm = await queryPid("010C\r");
        String speed = await queryPid("010D\r");
        String turbo = await queryPid("010B\r");
        String coolant = await queryPid("0105\r");
        String oil = await queryPid("015C\r");
        
        // Tensione batteria tramite comando ELM327 AT RV
        await sendCommand("ATRV\r");
        String battery = await readResponse();

        if (mounted) {
          setState(() {
            rpmVal = parseRpm(rpm);
            speedVal = parseSpeed(speed);
            turboVal = parseTurbo(turbo);
            coolantVal = parseCoolant(coolant);
            oilVal = parseOil(oil);
            batteryVal = parseBattery(battery);
          });
        }
      } catch (_) {}
    });
  }

  Future<String> queryPid(String cmd) async {
    if (connection == null || !connection!.isConnected) return "";
    connection!.output.add(Uint8List.fromList(cmd.codeUnits));
    await connection!.output.allSent;
    return await readResponse();
  }

  Future<String> readResponse() async {
    List<int> data = await connection!.input!.first.timeout(
      const Duration(milliseconds: 250),
      onTimeout: () => Uint8List(0),
    );
    return String.fromCharCodes(data);
  }

  String parseRpm(String resp) {
    try {
      final clean = resp.replaceAll(">", "").trim();
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
      final clean = resp.replaceAll(">", "").trim();
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
      final clean = resp.replaceAll(">", "").trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("0B");
      if (idx != -1 && parts.length > idx + 1) {
        int a = int.parse(parts[idx + 1], radix: 16);
        double bar = a / 100.0;
        return bar.toStringAsFixed(2);
      }
    } catch (_) {}
    return turboVal;
  }

  String parseCoolant(String resp) {
    try {
      final clean = resp.replaceAll(">", "").trim();
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
      final clean = resp.replaceAll(">", "").trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("5C");
      if (idx != -1 && parts.length > idx + 1) {
        int a = int.parse(parts[idx + 1], radix: 16);
        return (a - 40).toString();
      }
    } catch (_) {}
    return oilVal;
  }

  String parseBattery(String resp) {
    try {
      final clean = resp.replaceAll(">", "").replaceAll("V", "").trim();
      if (clean.isNotEmpty) {
        return double.parse(clean).toStringAsFixed(1);
      }
    } catch (_) {}
    return batteryVal;
  }

  void _showEcuSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161A1D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: 400,
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
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: ecuList.length,
                  itemBuilder: (context, index) {
                    final ecu = ecuList[index];
                    return ListTile(
                      title: Text(
                        ecu,
                        style: TextStyle(
                          color: selectedEcu == ecu ? const Color(0xFFFFB74D) : Colors.white,
                          fontWeight: selectedEcu == ecu ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: selectedEcu == ecu
                          ? const Icon(Icons.check, color: Color(0xFFFFB74D))
                          : null,
                      onTap: () {
                        setState(() {
                          selectedEcu = ecu;
                        });
                        Navigator.pop(context);
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
          color: borderColor.withOpacity(0.6),
          width: 1.5,
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFB74D),
                side: const BorderSide(color: Color(0xFFFFB74D), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _showEcuSelector,
              icon: const Icon(Icons.bluetooth_connected, size: 18),
              label: const Text(
                "SELEZIONA ECU",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Box di Stato / Connessione
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
                        isConnected ? Icons.check_circle : Icons.info_outline,
                        color: isConnected ? Colors.greenAccent : Colors.orangeAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "Stato: ${isConnected ? 'Connesso' : statusMessage}",
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Centralina: $selectedEcu (${isConnected ? 'Pronta' : 'In attesa'})",
                    style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 12),
                  ),
                  if (!isConnected) ...[
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB74D),
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(36),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: isConnecting ? null : connectToDevice,
                      child: Text(
                        isConnecting ? "Connessione in corso..." : "Connetti vLinker MC+",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Griglia dei parametri
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
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
                    accentColor: Colors.greenAccent,
                  ),
                  buildMetricCard(
                    icon: Icons.compress,
                    title: "Pressione Turbina",
                    value: turboVal,
                    unit: "bar",
                    borderColor: Colors.cyanAccent,
                    accentColor: Colors.cyanAccent,
                  ),
                  buildMetricCard(
                    icon: Icons.bolt,
                    title: "Tensione Batteria",
                    value: batteryVal,
                    unit: "V",
                    borderColor: Colors.purpleAccent,
                    accentColor: Colors.purpleAccent,
                  ),
                  buildMetricCard(
                    icon: Icons.thermostat,
                    title: "Temp. Refrigerante",
                    value: coolantVal,
                    unit: "°C",
                    borderColor: Colors.blueAccent,
                    accentColor: Colors.blueAccent,
                  ),
                  buildMetricCard(
                    icon: Icons.water_drop,
                    title: "Temp. Olio",
                    value: oilVal,
                    unit: "°C",
                    borderColor: Colors.amber,
                    accentColor: Colors.amber,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
