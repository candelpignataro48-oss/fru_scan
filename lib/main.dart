import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'obd_service.dart';
import 'stellantis_profile.dart'; 
import 'psa_profile.dart'; 

void main() {
  runApp(const FruScanApp());
}

class FruScanApp extends StatelessWidget {
  const FruScanApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fru Scan',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const FruScanHome(),
    );
  }
}

class FruScanHome extends StatefulWidget {
  const FruScanHome({Key? key}) : super(key: key);

  @override
  State<FruScanHome> createState() => _FruScanHomeState();
}

class _FruScanHomeState extends State<FruScanHome> {
  final ObdService _obdService = ObdService();
  List<BluetoothDevice> _devices = [];
  String? _selectedDeviceAddress; 
  
  String _selectedBrand = "Fiat";
  String? _selectedEcuId;
  
  bool _isConnecting = false;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _selectedEcuId = currentEcuIds.keys.isNotEmpty ? currentEcuIds.keys.first : null;
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    List<BluetoothDevice> devices = await _obdService.getBondedDevices();
    setState(() {
      _devices = devices;
      if (_devices.isNotEmpty) {
        _selectedDeviceAddress = _devices.first.address;
      }
    });
  }

  Map<String, String> get currentEcuIds {
    if (_selectedBrand == "Citroën") {
      return PsaProfile.ecuIds;
    }
    return StellantisProfile.ecuIds;
  }

  Future<void> _connect() async {
    if (_selectedDeviceAddress == null) return;
    
    try {
      // Dichiarazione sicura al 100% per le regole di Null Safety di Dart
      BluetoothDevice deviceToConnect = _devices.firstWhere((d) => d.address == _selectedDeviceAddress);
      
      setState(() => _isConnecting = true);
      bool success = await _obdService.connectToDevice(deviceToConnect);
      setState(() => _isConnecting = false);
      
      // Inizializza il canale solo se abbiamo una ECU valida e la connessione è riuscita
      if (success && _selectedEcuId != null) {
        await _obdService.initEcuChannel(_selectedEcuId!);
      }
    } catch (_) {
      // Se si verifica un errore durante l'estrazione del dispositivo, si ferma
      return;
    }
  }

  void _disconnect() {
    _obdService.disconnect();
    setState(() {
      _isPolling = false;
    });
  }

  void _togglePolling() {
    if (_isPolling) {
      _obdService.stopPolling();
      setState(() => _isPolling = false);
    } else {
      _obdService.startPolling((tick) async {
        await _obdService.queryObd("22 F1 87\r"); 
      });
      setState(() => _isPolling = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sicurezza per la tendina ECU: se il valore selezionato non fa parte della lista attuale, lo resetta
    if (_selectedEcuId != null && !currentEcuIds.containsKey(_selectedEcuId)) {
      _selectedEcuId = currentEcuIds.keys.isNotEmpty ? currentEcuIds.keys.first : null;
    }

    return Scaffold(
