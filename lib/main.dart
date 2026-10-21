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
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              "Dispositivi Bluetooth Associati",
              style: TextStyle(
                color: Color(0xFFFFB74D),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: devices.isEmpty
                  ? const Center(
                      child: Text(
                        "Nessun dispositivo associato trovato.\nAssocia l'interfaccia nelle impostazioni Bluetooth del telefono.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView
