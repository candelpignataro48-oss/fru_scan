import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const FruScanApp());

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
 bool isConnecting = false, isConnected = false, isEcuConnected = false, _busy = false;
 int _tick = 0;
 String statusMessage = "Disconnesso", selectedEcu = "Nessuna", connectedDeviceName = "";
 String ecuResponseInfo = "Nessuna ECU interrogata";
 String selectedBrand = "Fiat/Stellantis", selectedModel = "Tipo Cross 1.0 T3";

 String fuelVal = "---", odoVal = "---", extTempVal = "---";
 double? _fuelPct, _avgKml;
 int? _odoKm;

 String param1Val = "---", param2Val = "---", param3Val = "---", param4Val = "---";
 String rpmVal = "---", speedVal = "---", turboVal = "---", batteryVal = "---";
 String coolantVal = "---", oilVal = "---", iatVal = "---", catalystVal = "---", oilLifeVal = "---";
 String bcmIbsSocVal = "---", bcmBatteryVoltVal = "---", bcmDtcVal = "---";
 String ipcRangeVal = "---", ipcTpmsVal = "---", ipcServiceKmVal = "---", ipcAvgConsVal = "---", ipcVoltVal = "---";

 Timer? _obdTimer;
 StreamSubscription<Uint8List>? _btSub;
 String _buf = "";

 final Map<String, Map<String, String>> ecuHeaders = {
  "Centralina Motore (ECU)": {"tx": "18DA10F1", "rx": "18DAF110"},
  "Body Computer": {"tx": "18DA40F1", "rx": "18DAF140"},
  "Quadro Strumenti": {"tx": "18DA60F1", "rx": "18DAF160"},
  "Sensori di Parcheggio": {"tx": "18DA76F1", "rx": "18DAF176"},
  "Servosterzo": {"tx": "18DA30F1", "rx": "18DAF130"},
  "Cruise Control": {"tx": "18DA7AF1", "rx": "18DAF17A"},
  "Climatizzatore": {"tx": "18DA68F1", "rx": "18DAF168"},
  "Radio": {"tx": "18DA62F1", "rx": "18DAF162"},
  "ABS": {"tx": "18DA28F1", "rx": "18DAF128"},
  "Airbag": {"tx": "18DA51F1", "rx": "18DAF151"},
  "Blind Spot": {"tx": "18DAB8F1", "rx": "18DAF1B8"},
  "Telecamere": {"tx": "18DA72F1", "rx": "18DAF172"},
  "Radar": {"tx": "18DA7AF1", "rx": "18DAF17A"},
 };

 final List<String> ecuList = [
  "Centralina Motore (ECU)", "Body Computer", "Quadro Strumenti",
  "Sensori di Parcheggio", "Servosterzo", "Cruise Control",
  "Climatizzatore", "Radio", "ABS", "Airbag", "Blind Spot", "Telecamere", "Radar"
 ];
 final List<String> brandList = ["Fiat/Stellantis", "Alfa Romeo"];

 @override
 void dispose() {
  _obdTimer?.cancel(); _btSub?.cancel(); connection?.dispose();
  super.dispose();
 }

 Future<void> requestPermissions() async {
  await [Permission.bluetooth, Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
 }

 void _showBluetoothDeviceSelector() async {
  setState(() { isConnecting = true; statusMessage = "Richiesta permessi..."; });
  await requestPermissions();
  setState(() { statusMessage = "Lettura dispositivi..."; });
  try {
   List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
   setState(() { isConnecting = false; statusMessage = "Seleziona interfaccia"; });
   if (!mounted) return;
   showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
     backgroundColor: const Color(0xFF161A1D),
     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
     title: const Text("Dispositivi Bluetooth", style: TextStyle(color: Color(0xFFFFB74D), fontSize: 16, fontWeight: FontWeight.bold)),
     content: SizedBox(
      width: double.maxFinite, height: 300,
      child: devices.isEmpty
       ? const Center(child: Text("Nessun dispositivo associato.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)))
       : ListView.builder(
          itemCount: devices.length,
          itemBuilder: (c, i) => ListTile(
           leading: const Icon(Icons.bluetooth, color: Color(0xFFFFB74D)),
           title: Text(devices[i].name ?? "Dispositivo", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
           subtitle: Text(devices[i].address, style: const TextStyle(color: Colors.grey, fontSize: 12)),
           onTap: () { Navigator.pop(ctx); connectToDevice(devices[i]); },
          ),
         ),
     ),
     actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annulla", style: TextStyle(color: Colors.grey)))],
    ),
   );
  } catch (e) {
   setState(() { isConnecting = false; statusMessage = "Errore scansione Bluetooth"; });
  }
 }

 void connectToDevice(BluetoothDevice device) async {
  setState(() { isConnecting = true; statusMessage = "Connessione a ${device.name ?? device.address}..."; });
  try {
   connection = await BluetoothConnection.toAddress(device.address);
   setState(() { isConnected = true; isConnecting = false; connectedDeviceName = device.name ?? device.address; statusMessage = "Bluetooth Connesso"; });
   _btSub = connection!.input!.listen((data) { _buf += String.fromCharCodes(data); });
   for (String c in ["ATZ\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATCAF1\r"]) {
    await queryObd(c, timeoutMs: 250);
   }
  } catch (e) {
   setState(() { isConnecting = false; isConnected = false; statusMessage = "Errore di connessione"; });
  }
 }

 void disconnectBluetooth() {
  _obdTimer?.cancel(); _busy = false; _btSub?.cancel(); connection?.dispose();
  setState(() { isConnected = false; isEcuConnected = false; selectedEcu = "Nessuna"; statusMessage = "Disconnesso"; connectedDeviceName = ""; ecuResponseInfo = "Nessuna ECU interrogata"; });
 }

 void disconnectEcu() {
  _obdTimer?.cancel(); _busy = false;
  setState(() { isEcuConnected = false; selectedEcu = "Nessuna"; ecuResponseInfo = "ECU disconnessa"; });
 }

 Future<String> queryObd(String cmd, {int timeoutMs = 200}) async {
  if (connection == null || !connection!.isConnected) return "";
  _buf = "";
  connection!.output.add(Uint8List.fromList(cmd.codeUnits));
  await connection!.output.allSent;
  Stopwatch sw = Stopwatch()..start();
  while (sw.elapsedMilliseconds < timeoutMs) {
   if (_buf.contains('>')) break;
   await Future.delayed(const Duration(milliseconds: 10));
  }
  String r = _buf; _buf = "";
  return r.trim();
 }

 Future<void> _setChan(String tx, String rx) async {
  await queryObd("AT CP ${tx.substring(0, 2)}\r", timeoutMs: 90);
  await queryObd("AT SH ${tx.substring(2)}\r", timeoutMs: 90);
  await queryObd("AT CRA $rx\r", timeoutMs: 90);
  await queryObd("AT FC SH $tx\r", timeoutMs: 90);
 }

 List<int> _bytesAfter(String raw, String m1, [String? m2, String? m3]) {
  try {
   String cl = raw.replaceAll(">", "").replaceAll(RegExp(r'[0-9A-Fa-f]:'), ' ').replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
   if (cl.contains("NO DATA") || cl.contains("ERROR") || cl.contains("?")) return [];
   List<String> p = cl.split(RegExp(r'\s+'));
   for (int i = 0; i < p.length; i++) {
    if (p[i].toUpperCase() == m1.toUpperCase()) {
     if (m2 != null && (i + 1 >= p.length || p[i + 1].toUpperCase() != m2.toUpperCase())) continue;
     if (m3 != null && (i + 2 >= p.length || p[i + 2].toUpperCase() != m3.toUpperCase())) continue;
     int st = i + 1 + (m2 != null ? 1 : 0) + (m3 != null ? 1 : 0);
     List<int> out = [];
     for (int j = st; j < p.length; j++) {
      if (p[j].length == 2) {
       int? v = int.tryParse(p[j], radix: 16);
       if (v != null) out.add(v);
      }
     }
     return out;
    }
   }
  } catch (_) {}
  return [];
 }

 String decodeAscii(String raw) {
  List<int> b = _bytesAfter(raw, "62");
  if (b.length > 2) {
   List<int> a = b.sublist(2).where((x) => x >= 32 && x <= 126).toList();
   if (a.isNotEmpty) return String.fromCharCodes(a).trim();
  }
  String cl = raw.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return (cl.isEmpty || cl.contains("NO DATA") || cl.contains("7F")) ? "N/D" : cl;
 }

 void connectToSelectedEcu(String ecuName) async {
  _obdTimer?.cancel(); _busy = false; _tick = 0;
  setState(() { selectedEcu = ecuName; isEcuConnected = true; ecuResponseInfo = "Connessione 29-bit a $ecuName..."; });
  final h = ecuHeaders[ecuName] ?? {"tx": "18DA10F1", "rx": "18DAF110"};
  final String tx = h['tx']!, rx = h['rx']!;
  await queryObd("AT SP 7\r", timeoutMs: 200);
  await _setChan(tx, rx);
  await queryObd("AT FC SD 30 00 00\r", timeoutMs: 100);
  await queryObd("AT FC SM 1\r", timeoutMs: 100);
  await queryObd("AT ST 19\r", timeoutMs: 100);
  await queryObd("AT AT 2\r", timeoutMs: 100);
  await queryObd("10 03\r", timeoutMs: 220);
  String part = decodeAscii(await queryObd("22 F1 87\r", timeoutMs: 300));
  if (mounted) setState(() { ecuResponseInfo = "$selectedEcu (TX:$tx / RX:$rx)\nHardware/Part Code: $part"; });
  if (selectedEcu == "Centralina Motore (ECU)") {
   startEngineLoop();
  } else if (selectedEcu == "Body Computer") {
   startBcmLoop();
  } else if (selectedEcu == "Quadro Strumenti") {
   startIpcLoop();
  } else {
   startGenericLoop();
  }
 }

 int? _calcOdo(List<int> b) {
  if (b.length >= 4) {
   int v = (b[0] * 16777216) + (b[1] * 65536) + (b[2] * 256) + b[3];
   if (v > 0 && v < 9000000) return v > 600000 ? v ~/ 10 : v;
  } else if (b.length == 3) {
   int v = (b[0] * 65536) + (b[1] * 256) + b[2];
   if (v > 0 && v < 9000000) return v > 600000 ? v ~/ 10 : v;
  }
  return null;
 }

 Future<void> _updateShared(String curTx, String curRx) async {
  // Carburante Residuo (%)
  List<int> fB = _bytesAfter(await queryObd("22 20 05\r", timeoutMs: 160), "62", "20", "05");
  if (fB.isNotEmpty && fB[0] <= 100) {
   _fuelPct = fB[0].toDouble(); fuelVal = fB[0].toString();
  } else {
   if (curTx != "18DA10F1") await _setChan("18DA10F1", "18DAF110");
   List<int> obdF = _bytesAfter(await queryObd("012F\r", timeoutMs: 160), "41", "2F");
   if (obdF.isNotEmpty) {
    _fuelPct = (obdF[0] * 100.0) / 255.0;
    fuelVal = _fuelPct!.round().toString();
   }
   if (curTx != "18DA10F1") await _setChan(curTx, curRx);
  }
  // Temperatura Esterna (°C)
  List<int> tB = _bytesAfter(await queryObd("22 10 08\r", timeoutMs: 160), "62", "10", "08");
  if (tB.isNotEmpty && tB[0] < 250) {
   extTempVal = (tB[0] - 40).toString();
  } else {
   if (curTx != "18DA10F1") await _setChan("18DA10F1", "18DAF110");
   List<int> obdT = _bytesAfter(await queryObd("0146\r", timeoutMs: 160), "41", "46");
   if (obdT.isNotEmpty) extTempVal = (obdT[0] - 40).toString();
   if (curTx != "18DA10F1") await _setChan(curTx, curRx);
  }
  // Contachilometri (Odo)
  int? odo = _calcOdo(_bytesAfter(await queryObd("22 20 01\r", timeoutMs: 190), "62", "20", "01"));
  if (odo == null) {
   if (curTx != "18DA60F1") await _setChan("18DA60F1", "18DAF160");
   odo = _calcOdo(_bytesAfter(await queryObd("22 20 01\r", timeoutMs: 190), "62", "20", "01"));
   if (odo == null) {
    await _setChan("18DA10F1", "18DAF110");
    List<int> bA6 = _bytesAfter(await queryObd("01A6\r", timeoutMs: 190), "41", "A6");
    if (bA6.length >= 4) {
     int raw = (bA6[0] * 16777216) + (bA6[1] * 65536) + (bA6[2] * 256) + bA6[3];
     if (raw > 0) odo = raw ~/ 10;
    }
   }
   await _setChan(curTx, curRx);
  }
  if (odo != null && odo > 0) { _odoKm = odo; odoVal = odo.toString(); }
 }

 void startEngineLoop() {
  _obdTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
   if (!isEcuConnected || connection == null || selectedEcu != "Centralina Motore (ECU)") { t.cancel(); return; }
   if (_busy) return;
   _busy = true;
   try {
    String rRpm = await queryObd("010C\r", timeoutMs: 130);
    String rSpd = await queryObd("010D\r", timeoutMs: 130);
    String rTrb = await queryObd("010B\r", timeoutMs: 130);
    String rClt = await queryObd("0105\r", timeoutMs: 130);
    String rIat = await queryObd("010F\r", timeoutMs: 130);
    if (_tick % 4 == 0) {
     List<int> oB = _bytesAfter(await queryObd("015C\r", timeoutMs: 150), "41", "5C");
     if (oB.isNotEmpty) {
      oilVal = (oB[0] - 40).toString();
     } else {
      List<int> uO = _bytesAfter(await queryObd("22 10 09\r", timeoutMs: 150), "62", "10", "09");
      if (uO.isNotEmpty) oilVal = (uO[0] - 40).toString();
     }
     catalystVal = parseCat(await queryObd("013C\r", timeoutMs: 150));
     batteryVal = parseVolt(await queryObd("ATRV\r", timeoutMs: 130));
     await _updateShared("18DA10F1", "18DAF110");
     for (var d in [["19", "42"], ["18", "82"], ["18", "08"], ["38", "1A"]]) {
      List<int> b = _bytesAfter(await queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 150), "62", d[0], d[1]);
      if (b.isNotEmpty) {
       int v = b.length >= 2 ? ((b[0] * 256 + b[1]) > 100 ? (b[0] * 256 + b[1]) ~/ 100 : b[0]) : b[0];
       if (v >= 0 && v <= 100) { oilLifeVal = v.toString(); break; }
      }
     }
     if (oilLifeVal == "---" && _odoKm != null && _odoKm! > 0) {
      int rem = 15000 - (_odoKm! % 15000);
      oilLifeVal = ((rem / 15000.0) * 100.0).clamp(0, 100).round().toString();
     }
    }
    _tick++;
    if (mounted) {
     setState(() {
      rpmVal = parseRpm(rRpm); speedVal = parseSpd(rSpd);
      turboVal = parseTrb(rTrb); coolantVal = parseTemp(rClt, "05", coolantVal);
      iatVal = parseTemp(rIat, "0F", iatVal);
     });
    }
   } catch (_) {} finally { _busy = false; }
  });
 }

 void startBcmLoop() {
  _obdTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
   if (!isEcuConnected || connection == null || selectedEcu != "Body Computer") { t.cancel(); return; }
   if (_busy) return;
   _busy = true;
   try {
    bcmBatteryVoltVal = parseVolt(await queryObd("ATRV\r", timeoutMs: 130));
    for (var d in [["19", "35"], ["40", "24"], ["03", "02"], ["19", "36"], ["21", "15"]]) {
     List<int> b = _bytesAfter(await queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 160), "62", d[0], d[1]);
     if (b.isNotEmpty) {
      for (int x in b) {
       if (x >= 10 && x <= 100) { bcmIbsSocVal = x.toString(); break; }
      }
      if (bcmIbsSocVal != "---") break;
     }
    }
    if (_tick % 3 == 0) {
     await _updateShared("18DA40F1", "18DAF140");
     List<int> dB = _bytesAfter(await queryObd("19 02 09\r", timeoutMs: 180), "59", "02");
     if (dB.isNotEmpty) {
      int c = (dB.length - 1) ~/ 4;
      bcmDtcVal = c <= 0 ? "0 (OK)" : "$c Errori";
     }
    }
    _tick++;
    if (mounted) setState(() {});
   } catch (_) {} finally { _busy = false; }
  });
 }

 void startIpcLoop() {
  _obdTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
   if (!isEcuConnected || connection == null || selectedEcu != "Quadro Strumenti") { t.cancel(); return; }
   if (_busy) return;
   _busy = true;
   try {
    ipcVoltVal = parseVolt(await queryObd("ATRV\r", timeoutMs: 130));
    List<int> sB = _bytesAfter(await queryObd("22 20 10\r", timeoutMs: 160), "62", "20", "10");
    int? remSrv;
    if (sB.length >= 2) {
     int v = (sB[0] * 256) + sB[1];
     if (v > 15000) v = v ~/ 10;
     if (v >= 0 && v <= 15000) remSrv = v;
    }
    if (_tick % 2 == 0) await _updateShared("18DA60F1", "18DAF160");
    if (remSrv == null && _odoKm != null && _odoKm! > 0) remSrv = 15000 - (_odoKm! % 15000);
    if (remSrv != null) ipcServiceKmVal = "$remSrv/15000";

    List<int> cB = _bytesAfter(await queryObd("22 20 0A\r", timeoutMs: 160), "62", "20", "0A");
    if (cB.length >= 2) {
     double v = ((cB[0] * 256) + cB[1]) / 10.0;
     if (v > 2.0 && v < 40.0) { _avgKml = v; ipcAvgConsVal = v.toStringAsFixed(1); }
    } else {
     await _setChan("18DA10F1", "18DAF110");
     List<int> spdB = _bytesAfter(await queryObd("010D\r", timeoutMs: 130), "41", "0D");
     List<int> mafB = _bytesAfter(await queryObd("0110\r", timeoutMs: 130), "41", "10");
     await _setChan("18DA60F1", "18DAF160");
     if (spdB.isNotEmpty && mafB.length >= 2) {
      double spd = spdB[0].toDouble(), lph = (((mafB[0] * 256) + mafB[1]) / 100.0) * 0.3287;
      if (spd > 3.0 && lph > 0.2) {
       double kml = (spd / lph).clamp(3.0, 35.0);
       _avgKml = _avgKml == null ? kml : (_avgKml! * 0.85 + kml * 0.15);
       ipcAvgConsVal = _avgKml!.toStringAsFixed(1);
      }
     }
    }

    List<int> rB = _bytesAfter(await queryObd("22 20 07\r", timeoutMs: 160), "62", "20", "07");
    if (rB.length >= 2) {
     int rKm = (rB[0] * 256) + rB[1];
     if (rKm > 0 && rKm < 1500) ipcRangeVal = rKm.toString();
    } else if (_fuelPct != null) {
     ipcRangeVal = (((_fuelPct! / 100.0) * 50.0) * (_avgKml ?? 15.0)).round().toString();
    }

    if (_tick % 4 == 0) {
     List<int> dB = _bytesAfter(await queryObd("19 02 09\r", timeoutMs: 170), "59", "02");
     if (dB.isNotEmpty) {
      int cnt = (dB.length - 1) ~/ 4;
      ipcTpmsVal = cnt <= 0 ? "Regolare" : "Anomalia ($cnt)";
     }
    }
    _tick++;
    if (mounted) setState(() {});
   } catch (_) {} finally { _busy = false; }
  });
 }

 void startGenericLoop() {
  _obdTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
   if (!isEcuConnected || connection == null) { t.cancel(); return; }
   if (_busy) return;
   _busy = true;
   try {
    String vR = await queryObd("ATRV\r", timeoutMs: 130);
    String sR = await queryObd("22 F1 90\r", timeoutMs: 200);
    List<int> dB = _bytesAfter(await queryObd("19 02 09\r", timeoutMs: 180), "59", "02");
    if (mounted) {
     setState(() {
      param1Val = parseVolt(vR); param2Val = decodeAscii(sR);
      param3Val = param2Val != "N/D" ? "Comunicazione OK" : "In attesa";
      param4Val = dB.isNotEmpty ? "${(dB.length - 1) ~/ 4} Errori" : "---";
     });
    }
   } catch (_) {} finally { _busy = false; }
  });
 }

 String parseRpm(String r) {
  List<int> b = _bytesAfter(r, "41", "0C");
  return b.length >= 2 ? (((b[0] * 256) + b[1]) / 4).round().toString() : rpmVal;
 }

 String parseSpd(String r) {
  List<int> b = _bytesAfter(r, "41", "0D");
  return b.isNotEmpty ? b[0].toString() : speedVal;
 }

 String parseTrb(String r) {
  List<int> b = _bytesAfter(r, "41", "0B");
  if (b.isNotEmpty) return ((b[0] - 100) / 100.0).clamp(-1.0, 1.8).toStringAsFixed(2);
  return turboVal;
 }

 String parseTemp(String r, String pid, String fallback) {
  List<int> b = _bytesAfter(r, "41", pid);
  return b.isNotEmpty ? (b[0] - 40).toString() : fallback;
 }

 String parseCat(String r) {
  List<int> b = _bytesAfter(r, "41", "3C");
  return b.length >= 2 ? (((b[0] * 256) + b[1]) / 10.0 - 40.0).round().toString() : catalystVal;
 }

 String parseVolt(String r) {
  final m = RegExp(r'(\d+\.\d+)').firstMatch(r.replaceAll(">", ""));
  return m != null ? double.parse(m.group(1)!).toStringAsFixed(1) : batteryVal;
 }

 void _showEcuSelector() {
  if (!isConnected) {
   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Prima connetti il Bluetooth OBD!")));
   return;
  }
  showModalBottomSheet(
   context: context, backgroundColor: const Color(0xFF161A1D),
   shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
   builder: (ctx) => Container(
    padding: const EdgeInsets.all(16), height: 450,
    child: Column(
     crossAxisAlignment: CrossAxisAlignment.start,
     children: [
      const Text("Seleziona Centralina (ECU)", style: TextStyle(color: Color(0xFFFFB74D), fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Expanded(
       child: ListView.builder(
        itemCount: ecuList.length,
        itemBuilder: (c, i) {
         final ecu = ecuList[i];
         final bool sel = selectedEcu == ecu && isEcuConnected;
         return ListTile(
          title: Text(ecu, style: TextStyle(color: sel ? const Color(0xFFFFB74D) : Colors.white, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
          trailing: sel ? const Icon(Icons.check, color: Color(0xFFFFB74D)) : null,
          onTap: () { Navigator.pop(ctx); connectToSelectedEcu(ecu); },
         );
        },
       ),
      ),
     ],
    ),
   ),
  );
 }

 Widget _c(IconData ic, String title, String val, String unit, Color col) {
  return Container(
   padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
   decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(14), border: Border.all(color: col.withOpacity(0.9), width: 2.5)),
   child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
     Icon(ic, color: col, size: 24),
     const SizedBox(height: 4),
     Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12, fontWeight: FontWeight.w500)),
     const SizedBox(height: 4),
     FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
       mainAxisAlignment: MainAxisAlignment.center,
       crossAxisAlignment: CrossAxisAlignment.baseline,
       textBaseline: TextBaseline.alphabetic,
       children: [
        Text(val, style: TextStyle(color: col, fontSize: 22, fontWeight: FontWeight.bold)),
        if (unit.isNotEmpty) ...[const SizedBox(width: 4), Text(unit, style: TextStyle(color: col, fontSize: 15, fontWeight: FontWeight.bold))],
       ],
      ),
     ),
    ],
   ),
  );
 }

 List<Widget> _cardsForEcu() {
  if (selectedEcu == "Centralina Motore (ECU)") {
   return [
    _c(Icons.speed, "Giri Motore", rpmVal, "RPM", Colors.orangeAccent),
    _c(Icons.directions_car, "Velocità", speedVal, "km/h", Colors.greenAccent),
    _c(Icons.compress, "Pressione Turbina", turboVal, "bar", Colors.cyanAccent),
    _c(Icons.local_gas_station, "Carburante Residuo", fuelVal, "%", Colors.amber),
    _c(Icons.bolt, "Tensione Batteria", batteryVal, "V", Colors.purpleAccent),
    _c(Icons.thermostat, "Temp. Refrigerante", coolantVal, "°C", Colors.blueAccent),
    _c(Icons.water_drop, "Temp. Olio", oilVal, "°C", Colors.amber),
    _c(Icons.air, "Temp. Aria Aspirata", iatVal, "°C", Colors.tealAccent),
    _c(Icons.local_fire_department, "Temp. Catalizzatore", catalystVal, "°C", Colors.deepOrangeAccent),
    _c(Icons.opacity, "Vita Restante Olio", oilLifeVal, "%", Colors.lightGreenAccent),
   ];
  } else if (selectedEcu == "Body Computer") {
   return [
    _c(Icons.battery_charging_full, "Carica Batteria (IBS)", bcmIbsSocVal, "%", Colors.greenAccent),
    _c(Icons.bolt, "Tensione BCM", bcmBatteryVoltVal, "V", Colors.purpleAccent),
    _c(Icons.pin_drop, "Contachilometri (Odo)", odoVal, "km", Colors.blueAccent),
    _c(Icons.local_gas_station, "Carburante Residuo", fuelVal, "%", Colors.amber),
    _c(Icons.thermostat, "Temperatura Esterna", extTempVal, "°C", Colors.cyanAccent),
    _c(Icons.verified_user_outlined, "Diagnostica BCM", bcmDtcVal, "", Colors.tealAccent),
   ];
  } else if (selectedEcu == "Quadro Strumenti") {
   return [
    _c(Icons.local_gas_station, "Carburante Residuo", fuelVal, "%", Colors.amber),
    _c(Icons.route, "Autonomia Carburante", ipcRangeVal, "km", Colors.orangeAccent),
    _c(Icons.thermostat, "Temperatura Esterna", extTempVal, "°C", Colors.cyanAccent),
    _c(Icons.build, "Service", ipcServiceKmVal, "km", Colors.deepOrangeAccent),
    _c(Icons.eco, "Consumo Medio", ipcAvgConsVal, "km/l", Colors.lightGreenAccent),
    _c(Icons.bolt, "Tensione Quadro", ipcVoltVal, "V", Colors.purpleAccent),
    _c(Icons.tire_repair, "Pressione Gomme (TPMS)", ipcTpmsVal, "", Colors.greenAccent),
   ];
  }
  return [
   _c(Icons.bolt, "Tensione Linea ECU", param1Val, "V", Colors.purpleAccent),
   _c(Icons.info, "VIN / Identificativo", param2Val, "", Colors.greenAccent),
   _c(Icons.check_circle_outline, "Stato Connessione", param3Val, "", Colors.cyanAccent),
   _c(Icons.shield_outlined, "Errori Rilevati (DTC)", param4Val, "", Colors.amber),
  ];
 }

 @override
 Widget build(BuildContext context) {
  String? modelVal = selectedModel.isEmpty ? null : selectedModel;
  return Scaffold(
   appBar: AppBar(
    title: const Text('FRU SCAN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFFB74D))),
    backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
   ),
   body: Padding(
    padding: const EdgeInsets.all(10.0),
    child: Column(
     children: [
      Container(
       width: double.infinity, padding: const EdgeInsets.all(10),
       decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.withOpacity(0.3))),
       child: Column(
        children: [
         Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
           Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: isConnected ? Colors.greenAccent : Colors.orangeAccent, size: 16),
           const SizedBox(width: 6),
           Text(isConnected ? "Connesso a: $connectedDeviceName" : "Stato: $statusMessage", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
         ),
         const SizedBox(height: 10),
         Row(
          children: [
           Expanded(
            child: ElevatedButton(
             style: ElevatedButton.styleFrom(backgroundColor: isConnected ? Colors.red[800] : const Color(0xFFFFB74D), foregroundColor: isConnected ? Colors.white : Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 8)),
             onPressed: isConnecting ? null : (isConnected ? disconnectBluetooth : _showBluetoothDeviceSelector),
             child: Text(isConnecting ? "Connessione..." : (isConnected ? "Disconnetti Bluetooth" : "Scegli Bluetooth"), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
           ),
           const SizedBox(width: 8),
           Expanded(
            child: isEcuConnected
             ? ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 8)),
                onPressed: disconnectEcu,
                child: const Text("DISCONNETTI ECU", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
               )
             : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFFB74D), side: const BorderSide(color: Color(0xFFFFB74D), width: 1.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 8)),
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
      if (isEcuConnected) ...[
       Container(
        width: double.infinity, padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1.5)),
        child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
          Row(
           children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 15),
            const SizedBox(width: 6),
            Text("Centralina Attiva: $selectedEcu", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
           ],
          ),
          const SizedBox(height: 4),
          Text(ecuResponseInfo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
         ],
        ),
       ),
       const SizedBox(height: 8),
      ],
      Row(
       children: [
        Expanded(
         child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 1.2)),
          child: Row(
           children: [
            const Text("Marca:", style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(width: 6),
            Expanded(
             child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
               value: selectedBrand, isExpanded: true, dropdownColor: const Color(0xFF161A1D),
               style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13, fontWeight: FontWeight.bold),
               items: brandList.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
               onChanged: (val) => setState(() { selectedBrand = val!; selectedModel = (selectedBrand == "Fiat/Stellantis") ? "Tipo Cross 1.0 T3" : ""; }),
              ),
             ),
            ),
           ],
          ),
         ),
        ),
        const SizedBox(width: 8),
        Expanded(
         child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 1.2)),
          child: Row(
           children: [
            const Text("Modello:", style: TextStyle(color: Colors.grey, fontSize: 11)),
            const SizedBox(width: 6),
            Expanded(
             child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
               value: modelVal, hint: const Text("Nessun modello", style: TextStyle(color: Colors.grey, fontSize: 12)),
               isExpanded: true, dropdownColor: const Color(0xFF161A1D),
               style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 13, fontWeight: FontWeight.bold),
               items: selectedBrand == "Fiat/Stellantis" ? [const DropdownMenuItem(value: "Tipo Cross 1.0 T3", child: Text("Tipo Cross 1.0 T3"))] : [],
               onChanged: selectedBrand == "Fiat/Stellantis" ? (val) => setState(() { selectedModel = val!; }) : null,
              ),
             ),
            ),
           ],
          ),
         ),
        ),
       ],
      ),
      const SizedBox(height: 8),
      Expanded(
       child: isEcuConnected
        ? GridView.count(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.45, children: _cardsForEcu())
        : Center(
           child: Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.3))),
            child: const Column(
             mainAxisSize: MainAxisSize.min,
             children: [
              Icon(Icons.info_outline, color: Color(0xFFFFB74D), size: 40),
              SizedBox(height: 12),
              Text("Connetti l'adattatore OBD via Bluetooth, scegli marca e modello dell'auto, e scegli la centralina a cui vuoi connetterti.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
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
// === FINE DEL FILE ===
