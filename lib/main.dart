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
  BluetoothDevice? _selectedDevice;
  
  String _selectedBrand = "Fiat";
  String? _selectedEcuId;
  
  bool _isConnecting = false;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    List<BluetoothDevice> devices = await _obdService.getBondedDevices();
    setState(() {
      _devices = devices;
      if (_devices.isNotEmpty) {
        _selectedDevice = _devices.first;
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
    if (_selectedDevice == null) return;
    
    setState(() => _isConnecting = true);
    bool success = await _obdService.connectToDevice(_selectedDevice!);
    setState(() => _isConnecting = false);
    
    if (success && _selectedEcuId != null) {
      await _obdService.initEcuChannel(_selectedEcuId!);
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
        // Invio di una richiesta dati generica o calcolata sui PID
        await _obdService.queryObd("22 F1 87\r"); 
      });
      setState(() => _isPolling = true);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fru Scan - Diagnostica'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButton<BluetoothDevice>(
              isExpanded: true,
              value: _selectedDevice,
              hint: const Text("Seleziona dispositivo Bluetooth"),
              items: _devices.map((d) => DropdownMenuItem(
                value: d,
                child: Text(d.name ?? d.address),
              )).toList(),
              onChanged: (val) => setState(() => _selectedDevice = val),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isConnecting || _obdService.isConnected ? null : _connect,
                  child: Text(_isConnecting ? 'Connessione in corso...' : 'Connetti'),
                ),
                ElevatedButton(
                  onPressed: !_obdService.isConnected ? null : _disconnect,
                  child: const Text('Disconnetti'),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                const Text("Marca Auto: ", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _selectedBrand,
                  items: ["Fiat", "Citroën"].map((b) => DropdownMenuItem(
                    value: b, child: Text(b)
                  )).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedBrand = val!;
                      // Imposta di default la prima ECU della marca scelta
                      _selectedEcuId = currentEcuIds.keys.isNotEmpty ? currentEcuIds.keys.first : null;
                    });
                    // Se siamo già connessi, reinizializza subito il canale
                    if (_obdService.isConnected && _selectedEcuId != null) {
                      _obdService.initEcuChannel(_selectedEcuId!);
                    }
                  },
                ),
              ],
            ),
            DropdownButton<String>(
              isExpanded: true,
              value: _selectedEcuId ?? (currentEcuIds.isNotEmpty ? currentEcuIds.keys.first : null),
              hint: const Text("Seleziona Centralina"),
              items: currentEcuIds.entries.map((e) => DropdownMenuItem(
                value: e.key,
                child: Text("${e.key} - ${e.value}"),
              )).toList(),
              onChanged: (val) async {
                setState(() => _selectedEcuId = val);
                if (_obdService.isConnected && val != null) {
                  await _obdService.initEcuChannel(val);
                }
              },
            ),
            const SizedBox(height: 5),
            ElevatedButton(
              onPressed: !_obdService.isConnected ? null : _togglePolling,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isPolling ? Colors.red.shade300 : Colors.green.shade400,
              ),
              child: Text(_isPolling ? 'Ferma Lettura Dati' : 'Avvia Lettura Dati'),
            ),
            const Divider(),
            const Text("Terminale di Bordo (Log):", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Expanded(
              child: Container(
                color: Colors.black87,
                width: double.infinity,
                padding: const EdgeInsets.all(8.0),
                child: StreamBuilder<String>(
                  stream: _obdService.logStream,
                  builder: (context, snapshot) {
                    return SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        _obdService.getLogs(),
                        style: const TextStyle(
                          color: Colors.greenAccent, 
                          fontFamily: 'monospace', 
                          fontSize: 12
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// fine del codice
