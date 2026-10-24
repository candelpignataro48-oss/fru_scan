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
    _selectedEcuId = null;
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
      BluetoothDevice deviceToConnect = _devices.firstWhere((d) => d.address == _selectedDeviceAddress);
      
      setState(() => _isConnecting = true);
      bool success = await _obdService.connectToDevice(deviceToConnect);
      setState(() => _isConnecting = false);
      
      if (success && _selectedEcuId != null) {
        await _obdService.initEcuChannel(_selectedEcuId!);
      }
    } catch (e) {
      setState(() => _isConnecting = false);
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
    // Controllo di sicurezza: resetta o assegna automaticamente la ECU se cambia marca o è nulla
    if (_selectedEcuId != null && !currentEcuIds.containsKey(_selectedEcuId)) {
      _selectedEcuId = currentEcuIds.keys.isNotEmpty ? currentEcuIds.keys.first : null;
    }
    if (_selectedEcuId == null && currentEcuIds.keys.isNotEmpty) {
      _selectedEcuId = currentEcuIds.keys.first;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fru Scan - Diagnostica'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButton<String>(
              isExpanded: true,
              value: _selectedDeviceAddress,
              hint: const Text("Seleziona dispositivo Bluetooth"),
              items: _devices.map((d) {
                return DropdownMenuItem<String>(
                  value: d.address,
                  child: Text(d.name ?? d.address),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedDeviceAddress = val;
                });
              },
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
                  items: ["Fiat", "Citroën"].map((b) {
                    return DropdownMenuItem<String>(
                      value: b,
                      child: Text(b),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedBrand = val;
                        _selectedEcuId = null; // Forza il ricalcolo al primo render
                      });
                      if (_obdService.isConnected) {
                        String? newEcu = _selectedBrand == "Citroën" 
                            ? PsaProfile.ecuIds.keys.first 
                            : StellantisProfile.ecuIds.keys.first;
                        if (newEcu != null) {
                          _obdService.initEcuChannel(newEcu);
                        }
                      }
                    }
                  },
                ),
              ],
            ),
            DropdownButton<String>(
              isExpanded: true,
              value: _selectedEcuId,
              hint: const Text("Seleziona Centralina"),
              items: currentEcuIds.entries.map((e) {
                return DropdownMenuItem<String>(
                  value: e.key,
                  child: Text("${e.key} - ${e.value}"),
                );
              }).toList(),
              onChanged: (val) async {
                setState(() {
                  _selectedEcuId = val;
                });
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
// Fix applicato: risolta l'integrità del layout e delle chiamate ai profili.
