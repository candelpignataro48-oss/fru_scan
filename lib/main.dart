import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'obd_service.dart';
import 'stellantis_profile.dart';

enum StatusType { info, success, error }

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
          children: [
            Icon(Icons.info_outline, color: Color(0xFFFFB74D), size: 22),
            Expanded(
              child: Text("Informazioni & Compatibilità",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFFB74D), fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            SizedBox(width: 22), 
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
              SizedBox(height: 12),
              Text("Sviluppatore / Autore:",
                  style: TextStyle(color: Color(0xFFFFB74D), fontSize: 13, fontWeight: FontWeight.bold)),
              Text("Fru\nVersione: 1.0.0 (Release)\n© 2026 Fru Scan. Tutti i diritti riservati.",
                  style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.3)),
              Divider(color: Colors.grey, height: 24),
              Text("Adattatori Bluetooth Compatibili:",
                  style: TextStyle(color: Color(0xFFFFB74D), fontSize: 13, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text(
                "• vLinker MC\n"
                "• vLinker BM\n"
                "• OBDLink MX+\n"
                "• OBDLink CX\n"
                "• ELM327 (solo interfacce con chip PIC18F25K80)",
                style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB74D),
              foregroundColor: Colors.black,
            ),
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
              const Text("Log di Diagnostica OBD",
                  style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                onPressed: () {
                  obd.clearLogs();
                  setStateModal(() {});
                },
                tooltip: "Svuota log",
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  obd.getLogs().isEmpty ? "Nessun log registrato..." : obd.getLogs(),
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: obd.getLogs()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Log copiati negli appunti!")),
                );
              },
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
  void dispose() {
    obd.disconnect();
    super.dispose();
  }

  void _showBluetoothDeviceSelector() async {
    setState(() {
      isConnecting = true;
      statusMessage = "Richiesta permessi...";
    });
    _updateLiveStatus("Richiesta permessi Bluetooth in corso...", StatusType.info);

    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location
    ].request();

    setState(() => statusMessage = "Lettura dispositivi...");
    _updateLiveStatus("Scansione dispositivi Bluetooth associati...", StatusType.info);

    try {
      List<BluetoothDevice> devs = await obd.getBondedDevices();
      setState(() {
        isConnecting = false;
        statusMessage = "Seleziona interfaccia";
      });
      _updateLiveStatus("Seleziona l'interfaccia OBD dalla lista", StatusType.info);

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
            onPressed: () {
              Navigator.pop(ctx);
              _updateLiveStatus("Connessione annullata dall'utente", StatusType.info);
            },
            child: const Text("Annulla", style: TextStyle(color: Colors.grey)))
      ],
    ),
  );
} catch (_) {
  setState(() {
    isConnecting = false;
    statusMessage = "Errore scansione Bluetooth";
  });
  _updateLiveStatus("Errore: Impossibile completare la scansione Bluetooth", StatusType.error);
}
}
  void connectToDevice(BluetoothDevice d) async {
    setState(() {
      isConnecting = true;
      statusMessage = "Connessione a ${d.name ?? d.address}...";
    });
    _updateLiveStatus("Tentativo di connessione a ${d.name ?? d.address}...", StatusType.info);

    bool ok = await obd.connectToDevice(d);
    if (ok) {
      setState(() {
        isConnected = true;
        isConnecting = false;
        connectedDeviceName = d.name ?? d.address;
        statusMessage = "Bluetooth Connesso";
      });
      _updateLiveStatus("Connesso a $connectedDeviceName. Scegli una centralina.", StatusType.success);
    } else {
      setState(() {
        isConnecting = false;
        isConnected = false;
        statusMessage = "Errore di connessione";
      });
      _updateLiveStatus("Errore: Impossibile stabilire il link Bluetooth con l'adattatore", StatusType.error);
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
    _updateLiveStatus("Bluetooth disconnesso correttamente", StatusType.info);
  }

  void disconnectEcu() {
    obd.stopPolling();
    setState(() {
      isEcuConnected = false;
      selectedEcu = "Nessuna";
      ecuResponseInfo = "ECU disconnessa";
    });
    _updateLiveStatus("Centralina disconnessa. Sistema in idle.", StatusType.info);
  }

  void connectToSelectedEcu(String ecuName) async {
    String id = profile.ecuIds[ecuName] ?? "10";
    setState(() {
      selectedEcu = ecuName;
      isEcuConnected = true;
      profile.dtcVal = "---";
      ecuResponseInfo = "Connessione 29-bit a $ecuName...";
    });
    _updateLiveStatus("Apertura canale di comunicazione con $ecuName...", StatusType.info);

    try {
      await obd.initEcuChannel(id);
      String part = await profile.readHardwarePartCode(obd, ecuName); 

      if (part == "N/D" || part.contains("ERROR")) {
        _updateLiveStatus("Avviso: Nessuna risposta valida da $ecuName (Verifica quadro acceso)", StatusType.error);
      } else {
        _updateLiveStatus("Comunicazione stabile con $ecuName", StatusType.success);
      }

      if (mounted) {
        setState(() {
          ecuResponseInfo = "$selectedEcu (TX:18DA${id}F1 / RX:18DAF1$id)\nHardware/Part Code: $part";
        });
      }
    } catch (_) {
      _updateLiveStatus("Errore critico: Mancata risposta o timeout da $ecuName", StatusType.error);
    }

    obd.startPolling((tick) async {
      if (!isEcuConnected) return;
      await profile.pollEcu(obd, selectedEcu, tick);
      if (mounted) setState(() {});
    });
  }
  void _showEcuSelector() {
    if (!isConnected) {
      _updateLiveStatus("Azione bloccata: Connetti prima l'adattatore Bluetooth OBD", StatusType.error);
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

  void _showDtcDetails() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161A1D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Dettagli Errori (DTC)", 
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Codici rilevati in centralina:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              profile.dtcDetails, 
              style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Chiudi", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: () async {
              Navigator.pop(ctx);
              _updateLiveStatus("Invio comando azzeramento errori (DTC)...", StatusType.info);
              String result = await profile.resetDtc(obd);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
                setState(() {
                  profile.dtcVal = "0 (OK)";
                });
                _updateLiveStatus("Errori azzerati con successo sulla centralina", StatusType.success);
              }
            },
            child: const Text("Azzera Errori", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
