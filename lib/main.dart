import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'obd_service.dart';
import 'stellantis_profile.dart';
import 'psa_profile.dart';

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
  final StellantisProfile stellantisProfile = StellantisProfile();
  final PsaProfile psaProfile = PsaProfile();

  bool isConnecting = false, isConnected = false, isEcuConnected = false;
  String statusMessage = "Disconnesso", selectedEcu = "Nessuna", connectedDeviceName = "";
  String ecuResponseInfo = "Nessuna ECU interrogata";
  String selectedBrand = "Fiat/Stellantis", selectedModel = "Tipo Cross 1.0 T3";

  String liveStatusText = "Pronto: Connetti l'adattatore Bluetooth OBD";
  Color liveStatusColor = Colors.orangeAccent;
  IconData liveStatusIcon = Icons.info_outline;

  dynamic get currentProfile => selectedBrand == "Citroën" ? psaProfile : stellantisProfile;

  void _updateLiveStatus(String text, StatusType type) {
    setState(() {
      liveStatusText = text;
      liveStatusColor = type == StatusType.success ? Colors.greenAccent : (type == StatusType.error ? Colors.redAccent : Colors.orangeAccent);
      liveStatusIcon = type == StatusType.success ? Icons.check_circle_outline : (type == StatusType.error ? Icons.error_outline : Icons.sync);
    });
  }

  void _showInfoModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A1D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Informazioni e Compatibilità",
            style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          "Fru Scan - App di Diagnostica Veicoli\n\n"
          "• Protocolli supportati: Fiat/Stellantis (29-bit) e Citroën/PSA (11-bit).\n"
          "• Hardware consigliato: Adattatore Bluetooth OBD (es. vLinker MC+).\n"
          "• Assicurati di avere il quadro dell'auto acceso prima di interrogare le centraline.",
          style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB74D), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Chiudi", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showLogsModal() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) => AlertDialog(
          backgroundColor: const Color(0xFF161A1D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Log di Diagnostica OBD", style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                onPressed: () { obd.clearLogs(); setStateModal(() {}); },
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite, height: 350,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.withOpacity(0.2))),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(obd.getLogs().isEmpty ? "Nessun log registrato..." : obd.getLogs(),
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace')),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () { Clipboard.setData(ClipboardData(text: obd.getLogs())); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Log copiati!"))); },
              child: const Text("Copia Log", style: TextStyle(color: Color(0xFFFFB74D))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB74D), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Chiudi", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() { obd.disconnect(); super.dispose(); }
  void _showBluetoothDeviceSelector() async {
    setState(() { isConnecting = true; statusMessage = "Richiesta permessi..."; });
    _updateLiveStatus("Richiesta permessi Bluetooth...", StatusType.info);
    await [Permission.bluetooth, Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
    setState(() => statusMessage = "Lettura dispositivi...");
    try {
      List<BluetoothDevice> devs = await obd.getBondedDevices();
      setState(() { isConnecting = false; statusMessage = "Seleziona interfaccia"; });
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161A1D),
          title: const Text("Dispositivi Bluetooth", style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite, height: 300,
            child: devs.isEmpty ? const Center(child: Text("Nessun dispositivo.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: devs.length,
                    itemBuilder: (c, i) => ListTile(
                      leading: const Icon(Icons.bluetooth, color: Color(0xFFFFB74D)),
                      title: Text(devs[i].name ?? "Dispositivo", style: const TextStyle(color: Colors.white)),
                      subtitle: Text(devs[i].address, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      onTap: () { Navigator.pop(ctx); connectToDevice(devs[i]); },
                    ),
                  ),
          ),
        ),
      );
    } catch (_) {
      setState(() { isConnecting = false; statusMessage = "Errore scansione"; });
    }
  }

  void connectToDevice(BluetoothDevice d) async {
    setState(() { isConnecting = true; statusMessage = "Connessione a ${d.name ?? d.address}..."; });
    bool ok = await obd.connectToDevice(d);
    setState(() {
      isConnected = ok;
      isConnecting = false;
      connectedDeviceName = ok ? (d.name ?? d.address) : "";
      statusMessage = ok ? "Bluetooth Connesso" : "Errore connessione";
    });
    _updateLiveStatus(ok ? "Connesso a $connectedDeviceName" : "Errore connessione", ok ? StatusType.success : StatusType.error);
  }

  void disconnectBluetooth() {
    obd.disconnect();
    setState(() { isConnected = false; isEcuConnected = false; selectedEcu = "Nessuna"; statusMessage = "Disconnesso"; connectedDeviceName = ""; });
  }

  void disconnectEcu() {
    obd.stopPolling();
    setState(() { isEcuConnected = false; selectedEcu = "Nessuna"; });
  }
  void connectToSelectedEcu(String ecuName) async {
    String id = currentProfile.ecuIds[ecuName] ?? "10";
    setState(() { selectedEcu = ecuName; isEcuConnected = true; currentProfile.dtcVal = "---"; ecuResponseInfo = "Connessione a $ecuName..."; });
    try {
      await obd.initEcuChannel(id);
      String part = await currentProfile.readHardwarePartCode(obd);
      if (mounted) setState(() { ecuResponseInfo = "$selectedEcu (ID: $id)\nPart Code: $part"; });
    } catch (_) {}
    obd.startPolling((tick) async {
      if (!isEcuConnected) return;
      await currentProfile.pollEcu(obd, selectedEcu, tick);
      if (mounted) setState(() {});
    });
  }

  void _showEcuSelector() {
    if (!isConnected) return;
    final keys = currentProfile.ecuIds.keys.toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161A1D),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16), height: 450,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Seleziona Centralina (ECU)", style: TextStyle(color: Color(0xFFFFB74D), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: keys.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(keys[i], style: TextStyle(color: selectedEcu == keys[i] ? const Color(0xFFFFB74D) : Colors.white)),
                  onTap: () { Navigator.pop(ctx); connectToSelectedEcu(keys[i]); },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDtcDetails() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A1D),
        title: const Text("Dettagli Errori (DTC)", style: TextStyle(color: Colors.redAccent)),
        content: Text(currentProfile.dtcDetails, style: const TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Chiudi", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: () async {
              Navigator.pop(ctx);
              await currentProfile.resetDtc(obd);
              setState(() { currentProfile.dtcVal = "0 (OK)"; });
            },
            child: const Text("Azzera Errori"),
          ),
        ],
      ),
    );
  }
  Color _getLedColor(String title, String val) {
    if (val == "---" || val == "N/D" || val.isEmpty) return Colors.grey;
    if (title.contains("Errori")) return val == "0 (OK)" ? Colors.greenAccent : Colors.redAccent;
    try {
      double n = double.parse(val.replaceAll(RegExp(r'[^0-9.-]'), ''));
      if (title.contains("Tensione") && (n < 11.8 || n > 15.2)) return Colors.redAccent;
      if (title.contains("Temp.") && n > 110) return Colors.redAccent;
      return Colors.greenAccent;
    } catch (_) { return Colors.greenAccent; }
  }

  Widget _c(IconData ic, String title, String val, String unit, Color col, {VoidCallback? onTap}) {
    Color led = _getLedColor(title, val);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withOpacity(0.9), width: 2.5)),
        child: Stack(
          children: [
            Positioned(top: 0, right: 2, child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: led))),
            Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(ic, color: col, size: 24),
                  const SizedBox(height: 4),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(val, style: TextStyle(color: col, fontSize: 22, fontWeight: FontWeight.bold)),
                        if (unit.isNotEmpty) ...[const SizedBox(width: 4), Text(unit, style: TextStyle(color: col, fontSize: 15))]
                      ],
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

  List<Widget> _cardsForEcu() {
    Widget dtc = _c(Icons.shield_outlined, "Errori (DTC)", currentProfile.dtcVal, "", currentProfile.dtcVal == "0 (OK)" ? Colors.greenAccent : Colors.redAccent, onTap: _showDtcDetails);
    
    if (selectedBrand == "Fiat/Stellantis") {
      return [
        _c(Icons.speed, "Giri Motore", "0", "RPM", Colors.orangeAccent),
        _c(Icons.directions_car, "Velocità", "0", "km/h", Colors.greenAccent),
        _c(Icons.compress, "Turbina", "0.0", "bar", Colors.cyanAccent),
        _c(Icons.local_gas_station, "Carburante", "---", "%", Colors.amber),
        _c(Icons.bolt, "Batteria", "12.4", "V", Colors.purpleAccent),
        _c(Icons.thermostat, "Refrigerante", "90", "°C", Colors.blueAccent),
        dtc,
      ];
    } else {
      return [
        _c(Icons.speed, "Giri Motore", "0", "RPM", Colors.orangeAccent),
        _c(Icons.directions_car, "Velocità", "0", "km/h", Colors.greenAccent),
        _c(Icons.thermostat, "Refrigerante", "90", "°C", Colors.blueAccent),
        _c(Icons.bolt, "Batteria", "12.4", "V", Colors.purpleAccent),
        dtc,
      ];
    }
  }
  Widget _ddBox(String label, String? val, List<String> items, ValueChanged<String?>? onChg) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6))),
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
        leading: IconButton(
          icon: const Icon(Icons.info_outline, color: Color(0xFFFFB74D)),
          onPressed: _showInfoModal,
          tooltip: "Informazioni e Compatibilità",
        ),
        title: const Text('FRU SCAN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFFB74D))),
        backgroundColor: Colors.transparent, centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFFFFB74D)),
            onPressed: _showLogsModal,
            tooltip: "Log di Diagnostica",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withOpacity(0.3))),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: isConnected ? Colors.greenAccent : Colors.orangeAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(isConnected ? "Connesso: $connectedDeviceName" : "Stato: $statusMessage", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: isConnected ? Colors.red[800] : const Color(0xFFFFB74D), foregroundColor: isConnected ? Colors.white : Colors.black),
                          onPressed: isConnecting ? null : (isConnected ? disconnectBluetooth : _showBluetoothDeviceSelector),
                          child: Text(isConnecting ? "Connessione..." : (isConnected ? "Disconnetti" : "Scegli Bluetooth"), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: isEcuConnected
                            ? ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
                                onPressed: disconnectEcu,
                                child: const Text("DISCONNETTI ECU", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              )
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFFB74D), side: const BorderSide(color: Color(0xFFFFB74D))),
                                onPressed: _showEcuSelector,
                                icon: const Icon(Icons.settings_input_component, size: 16),
                                label: const Text("SELEZIONA ECU", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(8), border: Border.all(color: liveStatusColor.withOpacity(0.6))),
              child: Row(
                children: [
                  Icon(liveStatusIcon, color: liveStatusColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(liveStatusText, style: TextStyle(color: liveStatusColor, fontSize: 12, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (isEcuConnected) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.greenAccent.withOpacity(0.5))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.check_circle, color: Colors.greenAccent, size: 15),
                      const SizedBox(width: 6),
                      Text("ECU Attiva: $selectedEcu", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold))
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
                _ddBox("Marca:", selectedBrand, ["Fiat/Stellantis", "Citroën"], (v) {
                  setState(() {
                    selectedBrand = v!;
                    selectedModel = selectedBrand == "Fiat/Stellantis" ? "Tipo Cross 1.0 T3" : "C3 1.5 BlueHDi";
                    selectedEcu = "Nessuna";
                    isEcuConnected = false;
                  });
                }),
                const SizedBox(width: 8),
                _ddBox("Modello:", selectedModel.isEmpty ? null : selectedModel,
                    isFiat ? ["Tipo Cross 1.0 T3"] : ["C3 1.5 BlueHDi"], (v) => setState(() => selectedModel = v!)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: isEcuConnected
                  ? GridView.count(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.45, children: _cardsForEcu())
                  : Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.3))),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFFFFB74D), size: 40),
                            SizedBox(height: 12),
                            Text("Connetti l'adattatore OBD via Bluetooth e seleziona la centralina.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum StatusType { info, success, error }
