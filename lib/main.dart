import 'package:flutter/material.dart';
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

  @override
  void dispose() {
    obd.disconnect();
    super.dispose();
  }

  void _showBluetoothDeviceSelector() async {
    setState(() {
      isConnecting = true;
      statusMessage = "Richiesta permessi...";
    });
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location
    ].request();
    setState(() => statusMessage = "Lettura dispositivi...");
    try {
      List<BluetoothDevice> devs = await obd.getBondedDevices();
      setState(() {
        isConnecting = false;
        statusMessage = "Seleziona interfaccia";
      });
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161A1D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Dispositivi Bluetooth",
              style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: devs.isEmpty
                ? const Center(
                    child: Text("Nessun dispositivo associato.",
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)))
                : ListView.builder(
                    itemCount: devs.length,
                    itemBuilder: (c, i) => ListTile(
                      leading: const Icon(Icons.bluetooth, color: Color(0xFFFFB74D)),
                      title: Text(devs[i].name ?? "Dispositivo",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(devs[i].address, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(ctx);
                        connectToDevice(devs[i]);
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annulla", style: TextStyle(color: Colors.grey)))
          ],
        ),
      );
    } catch (_) {
      setState(() {
        isConnecting = false;
        statusMessage = "Errore scansione Bluetooth";
      });
    }
  }

  void connectToDevice(BluetoothDevice d) async {
    setState(() {
      isConnecting = true;
      statusMessage = "Connessione a ${d.name ?? d.address}...";
    });
    bool ok = await obd.connectToDevice(d);
    if (ok) {
      setState(() {
        isConnected = true;
        isConnecting = false;
        connectedDeviceName = d.name ?? d.address;
        statusMessage = "Bluetooth Connesso";
      });
    } else {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = "Errore di connessione";
      });
    }
  }

  void disconnectBluetooth() {
    obd.disconnect();
    setState(() {
      isConnected = false;
      isEcuConnected = false;
      selectedEcu = "Nessuna";
      statusMessage = "Disconnesso";
      connectedDeviceName = "";
      ecuResponseInfo = "Nessuna ECU interrogata";
    });
  }

  void disconnectEcu() {
    obd.stopPolling();
    setState(() {
      isEcuConnected = false;
      selectedEcu = "Nessuna";
      ecuResponseInfo = "ECU disconnessa";
    });
  }

  void connectToSelectedEcu(String ecuName) async {
    String id = profile.ecuIds[ecuName] ?? "10";
    setState(() {
      selectedEcu = ecuName;
      isEcuConnected = true;
      profile.dtcVal = "---";
      ecuResponseInfo = "Connessione 29-bit a $ecuName...";
    });
    await obd.initEcuChannel(id);
    String part = await profile.readHardwarePartCode(obd);
    if (mounted) {
      setState(() {
        ecuResponseInfo = "$selectedEcu (TX:18DA${id}F1 / RX:18DAF1$id)\nHardware/Part Code:$part";
      });
    }
    obd.startPolling((tick) async {
      if (!isEcuConnected) return;
      await profile.pollEcu(obd, selectedEcu, tick);
      if (mounted) setState(() {});
    });
  }

  void _showEcuSelector() {
    if (!isConnected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Prima connetti il Bluetooth OBD!")));
      return;
    }
    final keys = profile.ecuIds.keys.toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161A1D),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: 450,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Seleziona Centralina (ECU)",
                style: TextStyle(color: Color(0xFFFFB74D), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: keys.length,
                itemBuilder: (c, i) {
                  final ecu = keys[i];
                  final bool sel = selectedEcu == ecu && isEcuConnected;
                  return ListTile(
                    title: Text(ecu,
                        style: TextStyle(
                            color: sel ? const Color(0xFFFFB74D) : Colors.white,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                    trailing: sel ? const Icon(Icons.check, color: Color(0xFFFFB74D)) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      connectToSelectedEcu(ecu);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _c(IconData ic, String title, String val, String unit, Color col) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
            color: const Color(0xFF161A1D),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: col.withOpacity(0.9), width: 2.5)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ic, color: col, size: 24),
            const SizedBox(height: 4),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(val, style: TextStyle(color: col, fontSize: 22, fontWeight: FontWeight.bold)),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(unit, style: TextStyle(color: col, fontSize: 15, fontWeight: FontWeight.bold))
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  List<Widget> _cardsForEcu() {
    if (selectedEcu == "Centralina Motore (ECU)") {
      return [
        _c(Icons.speed, "Giri Motore", profile.rpmVal, "RPM", Colors.orangeAccent),
        _c(Icons.directions_car, "Velocità", profile.speedVal, "km/h", Colors.greenAccent),
        _c(Icons.compress, "Pressione Turbina", profile.turboVal, "bar", Colors.cyanAccent),
        _c(Icons.local_gas_station, "Carburante Residuo", profile.fuelVal, "%", Colors.amber),
        _c(Icons.bolt, "Tensione Batteria", profile.batteryVal, "V", Colors.purpleAccent),
        _c(Icons.thermostat, "Temp. Refrigerante", profile.coolantVal, "°C", Colors.blueAccent),
        _c(Icons.water_drop, "Temp. Olio", profile.oilVal, "°C", Colors.amber),
        _c(Icons.air, "Temp. Aria Aspirata", profile.iatVal, "°C", Colors.tealAccent),
        _c(Icons.local_fire_department, "Temp. Catalizzatore", profile.catalystVal, "°C", Colors.deepOrangeAccent),
        _c(Icons.opacity, "Vita Restante Olio", profile.oilLifeVal, "%", Colors.lightGreenAccent),
        _c(Icons.shield_outlined, "Errori Rilevati (DTC)", profile.dtcVal, "", Colors.redAccent),
      ];
    } else if (selectedEcu == "Body Computer") {
      return [
        _c(Icons.battery_charging_full, "Carica Batteria (IBS)", profile.bcmIbsSocVal, "%", Colors.greenAccent),
        _c(Icons.bolt, "Tensione BCM", profile.bcmBatteryVoltVal, "V", Colors.purpleAccent),
        _c(Icons.pin_drop, "Contachilometri (Odo)", profile.odoVal, "km", Colors.blueAccent),
        _c(Icons.local_gas_station, "Carburante Residuo", profile.fuelVal, "%", Colors.amber),
        _c(Icons.thermostat, "Temperatura Esterna", profile.extTempVal, "°C", Colors.cyanAccent),
        _c(Icons.shield_outlined, "Errori Rilevati (DTC)", profile.dtcVal, "", Colors.redAccent),
      ];
    } else if (selectedEcu == "Quadro Strumenti") {
      return [
        _c(Icons.local_gas_station, "Carburante Residuo", profile.fuelVal, "%", Colors.amber),
        _c(Icons.route, "Autonomia Carburante", profile.ipcRangeVal, "km", Colors.orangeAccent),
        _c(Icons.thermostat, "Temperatura Esterna", profile.extTempVal, "°C", Colors.cyanAccent),
        _c(Icons.build, "Service", profile.ipcServiceKmVal, "km", Colors.deepOrangeAccent),
        _c(Icons.bolt, "Tensione Quadro", profile.ipcVoltVal, "V", Colors.purpleAccent),
        _c(Icons.tire_repair, "Pressione Gomme (TPMS)", profile.ipcTpmsVal, "", Colors.greenAccent),
        _c(Icons.shield_outlined, "Errori Rilevati (DTC)", profile.dtcVal, "", Colors.redAccent),
      ];
    }
    return [
      _c(Icons.bolt, "Tensione Linea ECU", profile.param1Val, "V", Colors.purpleAccent),
      _c(Icons.info, "VIN / Identificativo", profile.param2Val, "", Colors.greenAccent),
      _c(Icons.check_circle_outline, "Stato Connessione", profile.param3Val, "", Colors.cyanAccent),
      _c(Icons.shield_outlined, "Errori Rilevati (DTC)", profile.dtcVal, "", Colors.redAccent),
    ];
  }

  Widget _ddBox(String label, String? val, List<String> items, ValueChanged<String?>? onChg) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFF161A1D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 1.2)),
          child: Row(
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: val,
                    hint: const Text("Nessuno", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    isExpanded: true,
                    dropdownColor: const Color(0xFF161A1D),
                    style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13, fontWeight: FontWeight.bold),
                    items: items.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                    onChanged: onChg,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    bool isFiat = selectedBrand == "Fiat/Stellantis";
    return Scaffold(
      appBar: AppBar(
          title: const Text('FRU SCAN',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFFB74D))),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFF161A1D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.3))),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                          color: isConnected ? Colors.greenAccent : Colors.orangeAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(isConnected ? "Connesso a: $connectedDeviceName" : "Stato: $statusMessage",
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: isConnected ? Colors.red[800] : const Color(0xFFFFB74D),
                              foregroundColor: isConnected ? Colors.white : Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 8)),
                          onPressed:
                              isConnecting ? null : (isConnected ? disconnectBluetooth : _showBluetoothDeviceSelector),
                          child: Text(
                              isConnecting
                                  ? "Connessione..."
                                  : (isConnected ? "Disconnetti Bluetooth" : "Scegli Bluetooth"),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: isEcuConnected
                            ? ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange[800],
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(vertical: 8)),
                                onPressed: disconnectEcu,
                                child: const Text("DISCONNETTI ECU",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              )
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFFFB74D),
                                    side: const BorderSide(color: Color(0xFFFFB74D), width: 1.5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(vertical: 8)),
                                onPressed: _showEcuSelector,
                                icon: const Icon(Icons.settings_input_component, size: 16),
                                label: const Text("SELEZIONA ECU",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (isEcuConnected) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFF161A1D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1.5)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.check_circle, color: Colors.greenAccent, size: 15),
                      const SizedBox(width: 6),
                      Text("Centralina Attiva: $selectedEcu",
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold))
                    ]),
                    const SizedBox(height: 4),
                    Text(ecuResponseInfo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                _ddBox("Marca:", selectedBrand, profile.brandList, (v) {
                  setState(() {
                    selectedBrand = v!;
                    selectedModel = (selectedBrand == "Fiat/Stellantis") ? "Tipo Cross 1.0 T3" : "";
                  });
                }),
                const SizedBox(width: 8),
                _ddBox("Modello:", selectedModel.isEmpty ? null : selectedModel,
                    isFiat ? ["Tipo Cross 1.0 T3"] : [], isFiat ? (v) => setState(() => selectedModel = v!) : null),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: isEcuConnected
                  ? GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.45,
                      children: _cardsForEcu())
                  
