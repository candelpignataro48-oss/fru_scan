import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'obd_service.dart';
import 'stellantis_profile.dart';

void main() => runApp(const FruScanApp());

class FruScanApp extends StatelessWidget {
  const FruScanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Fru Scan',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0E1113),
          primaryColor: const Color(0xFFFFB74D),
        ),
        home: const DashboardScreen(),
      );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ObdService obd = ObdService();
  final StellantisProfile profile = StellantisProfile();

  bool isConnecting = false, isConnected = false, isEcuConnected = false;
  String statusMessage = "Disconnesso", selectedEcu = "Nessuna", connectedDeviceName = "";
  String ecuResponseInfo = "Nessuna ECU interrogata";
  String selectedBrand = "Fiat/Stellantis", selectedModel = "Tipo Cross 1.0 T3";

  String liveStatusText = "Pronto: Connetti l'adattatore Bluetooth OBD";
  Color liveStatusColor = Colors.orangeAccent;
  IconData liveStatusIcon = Icons.info_outline;

  void _updateLiveStatus(String text, StatusType type) {
    setState(() {
      liveStatusText = text;
      switch (type) {
        case StatusType.info:
          liveStatusColor = Colors.orangeAccent;
          liveStatusIcon = Icons.sync;
          break;
        case StatusType.success:
          liveStatusColor = Colors.greenAccent;
          liveStatusIcon = Icons.check_circle_outline;
          break;
        case StatusType.error:
          liveStatusColor = Colors.redAccent;
          liveStatusIcon = Icons.error_outline;
          break;
      }
    });
  }

  void _showInfoMenu() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A1D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, color: Color(0xFFFFB74D), size: 22),
            SizedBox(width: 8),
            Text("Informazioni & Compatibilità",
                style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Fru Scan",
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text("Applicazione di diagnostica avanzata dedicata ai veicoli del gruppo Stellantis.",
                  style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.3)),
              SizedBox(height: 12
