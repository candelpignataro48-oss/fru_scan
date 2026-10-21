import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial.dart';
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
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blue,
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
  String tempVal = "- °C";
  String speedVal = "- km/h";

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
      BluetoothDevice? vlinker = devices.firstWhere(
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

      // Inizializzazione ELM327
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
        // Richiedi RPM (010C)
        String rpm = await queryPid("010C\r");
        // Richiedi Temp Acqua (0105)
        String temp = await queryPid("0105\r");
        // Richiedi Velocità (010D)
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

    // Leggi risposta bufferizzata breve
    List<int> data = await connection!.input.first.timeout(const Duration(milliseconds: 250), onTimeout: () => []);
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
        return "${a - 40} °C";
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
        return "$a km/h";
      }
    } catch (_) {}
    return speedVal;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fru Scan'),
        backgroundColor: Colors.grey[900],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? Colors.green : Colors.blue,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: isConnecting ? null : connectToDevice,
              child: Text(
                isConnecting ? "Connessione in corso..." : (isConnected ? "Dispositivi Connessi" : "Connetti vLinker"),
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(statusMessage, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            
            // RPM Card
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("GIRI MOTORE (RPM)", style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text(rpmVal, style: const TextStyle(color: Colors.greenAccent, fontSize: 56, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Temp & Speed Row
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("TEMPERATURA", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 8),
                          Text(tempVal, style: const TextStyle(color: Colors.orangeAccent, fontSize: 32, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("VELOCITÀ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 8),
                          Text(speedVal, style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 32, fontWeight: FontWeight.bold)),
                        ],
                      ),
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
