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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, color: Color(0xFFFFB74D), size: 22),
            SizedBox(width: 8),
            Text("Informazioni & Compatibilità",
                style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
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
      String part = await profile.readHardwarePartCode(obd);

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

  Color _getLedColor(String title, String val) {
    if (val == "---" || val == "N/D" || val.isEmpty) return Colors.grey;
    
    if (title.contains("Errori")) {
      return (val == "0 (OK)") ? Colors.greenAccent : Colors.redAccent;
    }

    try {
      double numVal = double.parse(val.replaceAll(RegExp(r'[^0-9.-]'), ''));
      
      if (title.contains("Tensione")) {
        if (numVal < 11.8 || numVal > 15.2) return Colors.redAccent;
        if (numVal < 12.2) return Colors.orangeAccent;
        return Colors.greenAccent;
      }
      if (title == "Temp. Refrigerante") {
        if (numVal > 110) return Colors.redAccent;
        if (numVal >= 100) return Colors.orangeAccent;
        return Colors.greenAccent;
      }
      if (title == "Temp. Olio") {
        if (numVal > 130) return Colors.redAccent;
        if (numVal >= 115) return Colors.orangeAccent;
        return Colors.greenAccent;
      }
      if (title == "Carburante Residuo" || title == "Vita Restante Olio") {
        if (numVal <= 10) return Colors.redAccent;
        if (numVal <= 20) return Colors.orangeAccent;
        return Colors.greenAccent;
      }
      
      return Colors.greenAccent;
    } catch (e) {
      return Colors.greenAccent;
    }
  }

  Widget _c(IconData ic, String title, String val, String unit, Color col, {VoidCallback? onTap}) {
    Color ledColor = _getLedColor(title, val);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
            color: const Color(0xFF161A1D),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: col.withOpacity(0.9), width: 2.5)),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ledColor,
                  boxShadow: [
                    BoxShadow(
                      color: ledColor.withOpacity(0.6),
                      blurRadius: 5,
                      spreadRadius: 1,
                    )
                  ]
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
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
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _cardsForEcu() {
    Color dtcColor = (profile.dtcVal == "0 (OK)" || profile.dtcVal == "---") ? Colors.greenAccent : Colors.redAccent;
    Widget dtcWidget = _c(Icons.shield_outlined, "Errori Rilevati (DTC)", profile.dtcVal, "", dtcColor, onTap: () {
      if (profile.dtcVal != "0 (OK)" && profile.dtcVal != "---") {
        _showDtcDetails();
      }
    });

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
        dtcWidget,
      ];
    } else if (selectedEcu == "Body Computer") {
      return [
        _c(Icons.battery_charging_full, "Carica Batteria (IBS)", profile.bcmIbsSocVal, "%", Colors.greenAccent),
        _c(Icons.bolt, "Tensione BCM", profile.bcmBatteryVoltVal, "V", Colors.purpleAccent),
        _c(Icons.pin_drop, "Contachilometri (Odo)", profile.odoVal, "km", Colors.blueAccent),
        _c(Icons.local_gas_station, "Carburante Residuo", profile.fuelVal, "%", Colors.amber),
        _c(Icons.thermostat, "Temperatura Esterna", profile.extTempVal, "°C", Colors.cyanAccent),
        dtcWidget,
      ];
    } else if (selectedEcu == "Quadro Strumenti") {
      return [
        _c(Icons.local_gas_station, "Carburante Residuo", profile.fuelVal, "%", Colors.amber),
        _c(Icons.route, "Autonomia Carburante", profile.ipcRangeVal, "km", Colors.orangeAccent),
        _c(Icons.thermostat, "Temperatura Esterna", profile.extTempVal, "°C", Colors.cyanAccent),
        _c(Icons.build, "Service", profile.ipcServiceKmVal, "km", Colors.deepOrangeAccent),
        _c(Icons.bolt, "Tensione Quadro", profile.ipcVoltVal, "V", Colors.purpleAccent),
        _c(Icons.tire_repair, "Pressione Gomme (TPMS)", profile.ipcTpmsVal, "", Colors.greenAccent),
        dtcWidget,
      ];
    } else if (selectedEcu == "Servosterzo") {
      return [
        _c(Icons.compare_arrows, "Angolo Sterzo", profile.epsAngleVal, "°", Colors.blueAccent),
        _c(Icons.bolt, "Tensione EPS", profile.param1Val, "V", Colors.purpleAccent),
        _c(Icons.info, "Hardware ID", profile.param2Val, "", Colors.greenAccent),
        dtcWidget,
      ];
    } else if (selectedEcu == "ABS") {
      return [
        _c(Icons.speed, "Velocità Ruote", profile.absSpeedVal, "km/h", Colors.orangeAccent),
        _c(Icons.bolt, "Tensione ABS", profile.param1Val, "V", Colors.purpleAccent),
        _c(Icons.info, "Hardware ID", profile.param2Val, "", Colors.greenAccent),
        dtcWidget,
      ];
    } else if (selectedEcu == "Airbag") {
      return [
        _c(Icons.airline_seat_recline_normal, "Stato Sistema", profile.airbagStatusVal, "", Colors.cyanAccent),
        _c(Icons.bolt, "Tensione SRS", profile.param1Val, "V", Colors.purpleAccent),
        _c(Icons.info, "Hardware ID", profile.param2Val, "", Colors.greenAccent),
        dtcWidget,
      ];
    } else if (selectedEcu == "Climatizzatore") {
      return [
        _c(Icons.ac_unit, "Temp. Abitacolo", profile.hvacTempVal, "°C", Colors.lightBlueAccent),
        _c(Icons.bolt, "Tensione HVAC", profile.param1Val, "V", Colors.purpleAccent),
        _c(Icons.info, "Hardware ID", profile.param2Val, "", Colors.greenAccent),
        dtcWidget,
      ];
    } else if (selectedEcu == "Radio / Uconnect") {
      return [
        _c(Icons.radio, "Stato Sistema", profile.radioStatusVal, "", Colors.amber),
        _c(Icons.bolt, "Tensione Radio", profile.param1Val, "V", Colors.purpleAccent),
        _c(Icons.info, "Hardware ID", profile.param2Val, "", Colors.greenAccent),
        dtcWidget,
      ];
    } else if (selectedEcu == "Sensori di Parcheggio") {
      return [
        _c(Icons.sensors, "Distanza Ostacoli", profile.pamDistVal, "cm", Colors.tealAccent),
        _c(Icons.bolt, "Tensione PAM", profile.param1Val, "V", Colors.purpleAccent),
        _c(Icons.info, "Hardware ID", profile.param2Val, "", Colors.greenAccent),
        dtcWidget,
      ];
    } else if (selectedEcu == "Cruise Control") {
      return [
        _c(Icons.add_road, "Stato Cruise", profile.accStatusVal, "", Colors.greenAccent),
        _c(Icons.bolt, "Tensione ACC", profile.param1Val, "V", Colors.purpleAccent),
        _c(Icons.info, "Hardware ID", profile.param2Val, "", Colors.greenAccent),
        dtcWidget,
      ];
    }

    return [
      _c(Icons.bolt, "Tensione Linea ECU", profile.param1Val, "V", Colors.purpleAccent),
      _c(Icons.info, "VIN / Identificativo", profile.param2Val, "", Colors.greenAccent),
      _c(Icons.check_circle_outline, "Stato Connessione", profile.param3Val, "", Colors.cyanAccent),
      dtcWidget,
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
        leading: IconButton(
          icon: const Icon(Icons.info_outline, color: Color(0xFFFFB74D)),
          onPressed: _showInfoMenu,
          tooltip: "Informazioni e Compatibilità",
        ),
        title: const Text('FRU SCAN',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFFB74D))),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161A1D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: liveStatusColor.withOpacity(0.6), width: 1),
              ),
              child: Row(
                children: [
                  Icon(liveStatusIcon, color: liveStatusColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      liveStatusText,
                      style: TextStyle(color: liveStatusColor, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
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
                      children: _cardsForEcu(),
                    )
                  : Center(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: const Color(0xFF161A1D),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.withOpacity(0.3))),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFFFFB74D), size: 40),
                            SizedBox(height: 12),
                            Text(
                                "Connetti l'adattatore OBD via Bluetooth, scegli marca e modello dell'auto, e scegli la centralina a cui vuoi connetterti.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey, fontSize: 13)),
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
