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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.cyanAccent,
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

  String rpmVal = "0";
  String tempVal = "-";
  String speedVal = "-";

  Timer? _obdTimer;

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
      statusMessage = "Ricerca dispositivi associati...";
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
      await Future.delayed(const Duration(milliseconds: 200));
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
    _obdTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (!isConnected || connection == null) {
        timer.cancel();
        return;
      }
      try {
        String rpm = await queryPid("010C\r");
        String temp = await queryPid("0105\r");
        String speed = await queryPid("010D\r");

        if (mounted) {
          setState(() {
            rpmVal = parseRpm(rpm);
            tempVal = parseTemp(temp);
            speedVal = parseSpeed(speed);
          });
        }
      } catch (_) {}
    });
  }

  Future<String> queryPid(String cmd) async {
    if (connection == null || !connection!.isConnected) return "";
    connection!.output.add(Uint8List.fromList(cmd.codeUnits));
    await connection!.output.allSent;

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

  String parseTemp(String resp) {
    try {
      final clean = resp.replaceAll(">", "").trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("05");
      if (idx != -1 && parts.length > idx + 1) {
        int a = int.parse(parts[idx + 1], radix: 16);
        return (a - 40).toString();
      }
    } catch (_) {}
    return tempVal;
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

  Widget buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D1D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00838F),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: const Color(0xFF00E5FF),
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF9E9E9E),
              fontSize: 16,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 24,
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
        title: const Text('Fru Scan'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? Colors.green[700] : const Color(0xFF00838F),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: isConnecting ? null : connectToDevice,
              child: Text(
                isConnecting ? "Connessione in corso..." : (isConnected ? "Dispositivi Connessi" : "Connetti vLinker"),
                style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            Text(statusMessage, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            
            Expanded(
              child: buildMetricCard(
                icon: Icons.compress,
                title: "Giri Motore",
                value: rpmVal,
                unit: "rpm",
              ),
            ),
            const SizedBox(height: 14),

            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: buildMetricCard(
                      icon: Icons.thermostat,
                      title: "Temperatura",
                      value: tempVal,
                      unit: "°C",
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: buildMetricCard(
                      icon: Icons.speed,
                      title: "Velocità",
                      value: speedVal,
                      unit: "km/h",
                    ),
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
