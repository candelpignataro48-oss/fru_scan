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
  String connectedDeviceName = "";

  // Valori dei parametri
  String rpmVal = "---";
  String speedVal = "---";
  String turboVal = "---";
  String batteryVal = "---";
  String coolantVal = "---";
  String oilVal = "---";
  String iatVal = "---";

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

  // Mostra il popup con tutti i dispositivi Bluetooth associati
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

  // Connessione al dispositivo scelto dall'utente
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
        statusMessage = "Connesso";
      });

      // Inizializzazione ELM327
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
      
      if (selectedEcu != "Centralina Motore (ECU)") {
        return; 
      }

      try {
        String rpm = await queryPid("010C\r");
        String speed = await queryPid("010D\r");
        String turbo = await queryPid("010B\r");
        String coolant = await queryPid("0105\r");
        String oil = await queryPid("015C\r");
        String iat = await queryPid("010F\r");
        
        await sendCommand("ATRV\r");
        String battery = await readResponse();

        if (mounted) {
          setState(() {
            rpmVal = parseRpm(rpm);
            speedVal = parseSpeed(speed);
            turboVal = parseTurbo(turbo);
            coolantVal = parseCoolant(coolant);
            oilVal = parseOil(oil);
            iatVal = parseIat(iat);
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

  String parseIat(String resp) {
    try {
      final clean = resp.replaceAll(">", "").trim();
      final parts = clean.split(RegExp(r'\s+'));
      int idx = parts.indexOf("0F");
      if (idx != -1 && parts.length > idx + 1) {
        int a = int.parse(parts[idx + 1], radix: 16);
        return (a - 40).toString();
      }
    } catch (_) {}
    return iatVal;
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
                          if (selectedEcu != "Centralina Motore (ECU)") {
                            rpmVal = "---";
                            speedVal = "---";
                            turboVal = "---";
                            coolantVal = "---";
                            oilVal = "---";
                            iatVal = "---";
                          }
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
              const SizedBox(width: 4
