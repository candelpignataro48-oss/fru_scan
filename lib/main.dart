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
        scaffoldBackgroundColor: const Color(0xFF090B0E),
        primaryColor: const Color(0xFF00F2FE),
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
  String turboVal = "-";

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
        statusMessage = "Connesso alla Fiat Tipo T3";
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
    _obdTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (!isConnected || connection == null) {
        timer.cancel();
        return;
      }
      try {
        String rpm = await queryPid("010C\r");
        String temp = await queryPid("0105\r");
        String turbo = await queryPid("010B\r");

        if (mounted) {
          setState(() {
            rpmVal = parseRpm(rpm);
            tempVal = parseTemp(temp);
            turboVal = parseTurbo(turbo);
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

  Widget buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required Color accentColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF131720),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withOpacity(0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF8B95A5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: TextStyle(
                  color: accentColor.withOpacity(0.8),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
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
          'FRU SCAN // T3',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
            color: Color(0xFF00F2FE),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Pulsante di connessione sportivo
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected ? const Color(0xFF00C853) : const Color(0xFF131720),
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: isConnected ? const Color(0xFF00C853) : const Color(0xFF00F2FE).withOpacity(0.5),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                onPressed: isConnecting ? null : connectToDevice,
                child: Text(
                  isConnecting ? "CONNESSIONE IN CORSO..." : (isConnected ? "SISTEMA CONNESSO" : "CONNETTI VLINKER"),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              statusMessage.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF626F84),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 20),
            
            // Riquadro Principale: Giri Motore (RPM)
            Expanded(
              flex: 5,
              child: buildMetricCard(
                icon: Icons.speed_rounded,
                title: "Giri Motore",
                value: rpmVal,
                unit: "rpm",
                accentColor: const Color(0xFF00F2FE),
              ),
            ),
            const SizedBox(height: 16),

            // Riquadri Secondari: Temperatura e Pressione Turbina
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Expanded(
                    child: buildMetricCard(
                      icon: Icons.thermostat_rounded,
                      title: "Temperatura",
                      value: tempVal,
                      unit: "°C",
                      accentColor: const Color(0xFFFF9100),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: buildMetricCard(
                      icon: Icons.compress_rounded,
                      title: "Turbina",
                      value: turboVal,
                      unit: "bar",
                      accentColor: const Color(0xFF00E676),
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
