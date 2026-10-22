import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const FruScanApp());

class FruScanApp extends StatelessWidget {
 const FruScanApp({super.key});
 @override
 Widget build(BuildContext context) => MaterialApp(
  title: 'Fru Scan', debugShowCheckedModeBanner: false,
  theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0E1113), primaryColor: const Color(0xFFFFB74D)),
  home: const DashboardScreen(),
 );
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

 String fuelVal = "---", odoVal = "---", extTempVal = "---", dtcVal = "---";
 double? _fuelPct, _avgKml;
 int? _odoKm;

 String param1Val = "---", param2Val = "---", param3Val = "---";
 String rpmVal = "---", speedVal = "---", turboVal = "---", batteryVal = "---";
 String coolantVal = "---", oilVal = "---", iatVal = "---", catalystVal = "---", oilLifeVal = "---";
 String bcmIbsSocVal = "---", bcmBatteryVoltVal = "---";
 String ipcRangeVal = "---", ipcTpmsVal = "---", ipcServiceKmVal = "---", ipcAvgConsVal = "---", ipcVoltVal = "---";

 Timer? _obdTimer;
 StreamSubscription<Uint8List>? _btSub;
 String _buf = "";

 final Map<String, String> ecuIds = {
  "Centralina Motore (ECU)": "10", "Body Computer": "40", "Quadro Strumenti": "60",
  "Sensori di Parcheggio": "76", "Servosterzo": "30", "Cruise Control": "7A",
  "Climatizzatore": "68", "Radio": "62", "ABS": "28", "Airbag": "51",
  "Blind Spot": "B8", "Telecamere": "72", "Radar": "7A",
 };
 final List<String> brandList = ["Fiat/Stellantis", "Alfa Romeo"];

 @override
 void dispose() {
  _obdTimer?.cancel(); _btSub?.cancel(); connection?.dispose();
  super.dispose();
 }

 void _showBluetoothDeviceSelector() async {
  setState(() { isConnecting = true; statusMessage = "Richiesta permessi..."; });
  await [Permission.bluetooth, Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
  setState(() { statusMessage = "Lettura dispositivi..."; });
  try {
   List<BluetoothDevice> devs = await FlutterBluetoothSerial.instance.getBondedDevices();
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
      child: devs.isEmpty
       ? const Center(child: Text("Nessun dispositivo associato.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)))
       : ListView.builder(
          itemCount: devs.length,
          itemBuilder: (c, i) => ListTile(
           leading: const Icon(Icons.bluetooth, color: Color(0xFFFFB74D)),
           title: Text(devs[i].name ?? "Dispositivo", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
           subtitle: Text(devs[i].address, style: const TextStyle(color: Colors.grey, fontSize: 12)),
           onTap: () { Navigator.pop(ctx); connectToDevice(devs[i]); },
          ),
         ),
     ),
     actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annulla", style: TextStyle(color: Colors.grey)))],
    ),
   );
  } catch (_) {
   setState(() { isConnecting = false; statusMessage = "Errore scansione Bluetooth"; });
  }
 }
 void connectToDevice(BluetoothDevice d) async {
  setState(() { isConnecting = true; statusMessage = "Connessione a ${d.name ?? d.address}..."; });
  try {
   connection = await BluetoothConnection.toAddress(d.address);
   setState(() { isConnected = true; isConnecting = false; connectedDeviceName = d.name ?? d.address; statusMessage = "Bluetooth Connesso"; });
   _btSub = connection!.input!.listen((data) => _buf += String.fromCharCodes(data));
   for (String c in ["ATZ\r", "ATE0\r", "ATL0\r", "ATS1\r", "ATH0\r", "ATCAF1\r"]) {
    await queryObd(c, timeoutMs: 250);
   }
  } catch (_) {
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

 Future<String> queryObd(String cmd, {int timeoutMs = 180}) async {
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

 Future<void> _setChan(String id) async {
  await queryObd("AT CP 18\r", timeoutMs: 80);
  await queryObd("AT SH DA${id}F1\r", timeoutMs: 80);
  await queryObd("AT CRA 18DAF1$id\r", timeoutMs: 80);
  await queryObd("AT FC SH 18DA${id}F1\r", timeoutMs: 80);
 }

 List<int> _bytes(String raw, String m1, [String? m2, String? m3]) {
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
  List<int> b = _bytes(raw, "62");
  if (b.length > 2) {
   List<int> a = b.sublist(2).where((x) => x >= 32 && x <= 126).toList();
   if (a.isNotEmpty) return String.fromCharCodes(a).trim();
  }
  String cl = raw.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return (cl.isEmpty || cl.contains("NO DATA") || cl.contains("7F")) ? "N/D" : cl;
 }

 Future<void> _updateDtc({bool isEng = false}) async {
  List<int> dB = _bytes(await queryObd("19 02 09\r", timeoutMs: 170), "59", "02");
  if (dB.isNotEmpty) {
   int c = (dB.length - 1) ~/ 4;
   dtcVal = c <= 0 ? "0 (OK)" : "$c Errori";
   return;
  }
  if (isEng) {
   List<int> m1 = _bytes(await queryObd("0101\r", timeoutMs: 150), "41", "01");
   if (m1.isNotEmpty) {
    int c = m1[0] & 0x7F;
    dtcVal = c == 0 ? "0 (OK)" : "$c Errori";
   }
  }
 }
 void connectToSelectedEcu(String ecuName) async {
  _obdTimer?.cancel(); _busy = false; _tick = 0;
  String id = ecuIds[ecuName] ?? "10";
  setState(() { selectedEcu = ecuName; isEcuConnected = true; dtcVal = "---"; ecuResponseInfo = "Connessione 29-bit a $ecuName..."; });
  await queryObd("AT SP 7\r", timeoutMs: 180);
  await _setChan(id);
  await queryObd("AT FC SD 30 00 00\r", timeoutMs: 90);
  await queryObd("AT FC SM 1\r", timeoutMs: 90);
  await queryObd("AT ST 19\r", timeoutMs: 90);
  await queryObd("AT AT 2\r", timeoutMs: 90);
  await queryObd("10 03\r", timeoutMs: 200);
  String part = decodeAscii(await queryObd("22 F1 87\r", timeoutMs: 280));
  if (mounted) setState(() { ecuResponseInfo = "$selectedEcu (TX:18DA${id}F1 / RX:18DAF1$id)\nHardware/Part Code: $part"; });
  _startPollingLoop();
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

 String? _extT(List<int> b) {
  for (int x in b) {
   if (x >= 18 && x <= 110) return (x - 40).toString();
  }
  return null;
 }

 Future<void> _updateShared(String curId) async {
  List<int> fB = _bytes(await queryObd("22 20 05\r", timeoutMs: 140), "62", "20", "05");
  if (fB.isNotEmpty && fB[0] > 0 && fB[0] <= 100) {
   _fuelPct = fB[0].toDouble(); fuelVal = fB[0].toString();
  } else {
   if (curId != "10") await _setChan("10");
   List<int> obdF = _bytes(await queryObd("012F\r", timeoutMs: 140), "41", "2F");
   if (obdF.isNotEmpty && obdF[0] > 0) {
    _fuelPct = (obdF[0] * 100.0) / 255.0;
    fuelVal = _fuelPct!.round().toString();
   }
   if (curId != "10") await _setChan(curId);
  }

  String? vT;
  if (curId != "10") await _setChan("10");
  vT = _extT(_bytes(await queryObd("0146\r", timeoutMs: 140), "41", "46"));
  vT ??= _extT(_bytes(await queryObd("22 F4 46\r", timeoutMs: 140), "62", "F4", "46"));
  if (curId != "10") await _setChan(curId);
  if (vT == null) {
   for (var d in [["19", "24"], ["20", "03"], ["10", "04"]]) {
    vT = _extT(_bytes(await queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 140), "62", d[0], d[1]));
    if (vT != null) break;
   }
  }
  if (vT != null) extTempVal = vT;

  int? odo = _calcOdo(_bytes(await queryObd("22 20 01\r", timeoutMs: 160), "62", "20", "01"));
  if (odo == null) {
   if (curId != "60") await _setChan("60");
   odo = _calcOdo(_bytes(await queryObd("22 20 01\r", timeoutMs: 160), "62", "20", "01"));
   if (odo == null) {
    await _setChan("10");
    List<int> bA6 = _bytes(await queryObd("01A6\r", timeoutMs: 160), "41", "A6");
    if (bA6.length >= 4) {
     int raw = (bA6[0] * 16777216) + (bA6[1] * 65536) + (bA6[2] * 256) + bA6[3];
     if (raw > 0) odo = raw ~/ 10;
    }
   }
   await _setChan(curId);
  }
  if (odo != null && odo > 0) { _odoKm = odo; odoVal = odo.toString(); }
 }

 void _startPollingLoop() {
  _obdTimer = Timer.periodic(const Duration(milliseconds: 500), (t) async {
   if (!isEcuConnected || connection == null) { t.cancel(); return; }
   if (_busy) return;
   _busy = true;
   try {
    String curId = ecuIds[selectedEcu] ?? "10";
    if (selectedEcu == "Centralina Motore (ECU)") {
     List<int> bC = _bytes(await queryObd("010C\r", timeoutMs: 120), "41", "0C");
     if (bC.length >= 2) rpmVal = (((bC[0] * 256) + bC[1]) / 4).round().toString();
     List<int> bD = _bytes(await queryObd("010D\r", timeoutMs: 120), "41", "0D");
     if (bD.isNotEmpty) speedVal = bD[0].toString();
     List<int> bB = _bytes(await queryObd("010B\r", timeoutMs: 120), "41", "0B");
     if (bB.isNotEmpty) turboVal = ((bB[0] - 100) / 100.0).clamp(-1.0, 1.8).toStringAsFixed(2);
     List<int> b5 = _bytes(await queryObd("0105\r", timeoutMs: 120), "41", "05");
     if (b5.isNotEmpty && b5[0] > 0) coolantVal = (b5[0] - 40).toString();
     List<int> bF = _bytes(await queryObd("010F\r", timeoutMs: 120), "41", "0F");
     if (bF.isNotEmpty && bF[0] > 0) iatVal = (bF[0] - 40).toString();

     if (_tick % 4 == 0) {
      List<int> oB = _bytes(await queryObd("015C\r", timeoutMs: 140), "41", "5C");
      if (oB.isNotEmpty && oB[0] > 0) {
       oilVal = (oB[0] - 40).toString();
      } else {
       List<int> uO = _bytes(await queryObd("22 10 09\r", timeoutMs: 140), "62", "10", "09");
       if (uO.isNotEmpty && uO[0] > 0) oilVal = (uO[0] - 40).toString();
      }
      List<int> cB = _bytes(await queryObd("013C\r", timeoutMs: 140), "41", "3C");
      if (cB.length >= 2) catalystVal = (((cB[0] * 256) + cB[1]) / 10.0 - 40.0).round().toString();
      batteryVal = parseVolt(await queryObd("ATRV\r", timeoutMs: 120));
      await _updateShared("10");
      await _updateDtc(isEng: true);

      bool foundOil = false;
      for (var d in [["18", "08"], ["18", "82"], ["19", "42"], ["19", "03"], ["38", "1A"]]) {
       List<int> b = _bytes(await queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 140), "62", d[0], d[1]);
       if (b.isNotEmpty) {
        int v = -1;
        if (b.length >= 2) {
         int raw16 = (b[0] * 256) + b[1];
         if (raw16 >= 0 && raw16 <= 100) v = raw16;
         else if (raw16 > 100 && raw16 <= 1000) v = raw16 ~/ 10;
        }
        if (v == -1 && b[0] >= 0 && b[0] <= 100) v = b[0];
        if (v >= 0 && v <= 100) { oilLifeVal = v.toString(); foundOil = true; break; }
       }
      }
      if (!foundOil) oilLifeVal = "---";
     }
    } else if (selectedEcu == "Body Computer") {
     bcmBatteryVoltVal = parseVolt(await queryObd("ATRV\r", timeoutMs: 120));
     for (var d in [["19", "35"], ["40", "24"], ["03", "02"], ["19", "36"], ["21", "15"]]) {
      List<int> b = _bytes(await queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 140), "62", d[0], d[1]);
      if (b.isNotEmpty) {
       for (int x in b) {
        if (x >= 10 && x <= 100) { bcmIbsSocVal = x.toString(); break; }
       }
       if (bcmIbsSocVal != "---") break;
      }
     }
     if (_tick % 3 == 0) { await _updateShared("40"); await _updateDtc(); }
    } else if (selectedEcu == "Quadro Strumenti") {
     ipcVoltVal = parseVolt(await queryObd("ATRV\r", timeoutMs: 120));
     
     bool foundSrv = false;
     for (var d in [["21", "01"], ["20", "10"], ["20", "11"], ["F1", "C2"], ["19", "20"]]) {
      List<int> sB = _bytes(await queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 150), "62", d[0], d[1]);
      if (sB.length >= 2) {
       int kmVal = -1;
       int? daysVal;
       int rawWord = (sB[0] * 256) + sB[1];
       if (rawWord <= 15000) kmVal = rawWord;
       else if (rawWord > 15000 && rawWord <= 150000) kmVal = rawWord ~/ 10;
       else if (sB.length >= 4) {
        int alt = (sB[2] * 256) + sB[3];
        if (alt >= 0 && alt <= 15000) kmVal = alt;
       }
       if (kmVal >= 0 && kmVal <= 15000) {
        if (sB.length >= 4) {
         int dC = (sB[2] * 256) + sB[3];
         if (dC > 15000 && dC <= 730) daysVal = dC;
         else if (sB.length >= 6) {
          int dAlt = (sB[4] * 256) + sB[5];
          if (dAlt >= 0 && dAlt <= 730) daysVal = dAlt;
         }
        }
        ipcServiceKmVal = daysVal != null ? "$kmVal/15000 ($daysVal gg)" : "$kmVal/15000";
        foundSrv = true;
        break;
       }
      }
     }
     if (!foundSrv) ipcServiceKmVal = "---/15000";

     if (_tick % 2 == 0) await _updateShared("60");

     List<int> cB = _bytes(await queryObd("22 20 0A\r", timeoutMs: 140), "62", "20", "0A");
     if (cB.length >= 2) {
      double v = ((cB[0] * 256) + cB[1]) / 10.0;
      if (v > 2.0 && v < 40.0) { _avgKml = v; ipcAvgConsVal = v.toStringAsFixed(1); }
     } else {
      await _setChan("10");
      List<int> spdB = _bytes(await queryObd("010D\r", timeoutMs: 120), "41", "0D");
      List<int> mafB = _bytes(await queryObd("0110\r", timeoutMs: 120), "41", "10");
      await _setChan("60");
      if (spdB.isNotEmpty && mafB.length >= 2) {
       double spd = spdB[0].toDouble(), lph = (((mafB[0] * 256) + mafB[1]) / 100.0) * 0.3287;
       if (spd > 3.0 && lph > 0.2) {
        double kml = (spd / lph).clamp(3.0, 35.0);
        _avgKml = _avgKml == null ? kml : (_avgKml! * 0.85 + kml * 0.15);
        ipcAvgConsVal = _avgKml!.toStringAsFixed(1);
       }
      }
     }
     List<int> rB = _bytes(await queryObd("22 20 07\r", timeoutMs: 140), "62", "20", "07");
     if (rB.length >= 2) {
      int rKm = (rB[0] * 256) + rB[1];
      if (rKm > 0 && rKm < 1500) ipcRangeVal = rKm.toString();
     } else if (_fuelPct != null) {
      ipcRangeVal = (((_fuelPct! / 100.0) * 50.0) * (_avgKml ?? 15.0)).round().toString();
     }
     if (_tick % 4 == 0) {
      await _updateDtc();
      ipcTpmsVal = dtcVal == "0 (OK)" ? "Regolare" : dtcVal;
     }
    } else {
     param1Val = parseVolt(await queryObd("ATRV\r", timeoutMs: 120));
     param2Val = decodeAscii(await queryObd("22 F1 90\r", timeoutMs: 180));
     param3Val = param2Val != "N/D" ? "Comunicazione OK" : "Attiva";
     if (_tick % 3 == 0) await _updateDtc();
    }
    _tick++;
    if (mounted) setState(() {});
   } catch (_) {} finally { _busy = false; }
  });
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
  final keys = ecuIds.keys.toList();
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
        itemCount: keys.length,
        itemBuilder: (c, i) {
         final ecu = keys[i];
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

 Widget _c(IconData ic, String title, String val, String unit, Color col) => Container(
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
      mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
      children: [
       Text(val, style: TextStyle(color: col, fontSize: 22, fontWeight: FontWeight.bold)),
       if (unit.isNotEmpty) ...[const SizedBox(width: 4), Text(unit, style: TextStyle(color: col, fontSize: 15, fontWeight: FontWeight.bold))],
      ],
     ),
    ),
   ],
  ),
 );

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
    _c(Icons.shield_outlined, "Errori Rilevati (DTC)", dtcVal, "", Colors.redAccent),
   ];
  } else if (selectedEcu == "Body Computer") {
   return [
    _c(Icons.battery_charging_full, "Carica Batteria (IBS)", bcmIbsSocVal, "%", Colors.greenAccent),
    _c(Icons.bolt, "Tensione BCM", bcmBatteryVoltVal, "V", Colors.purpleAccent),
    _c(Icons.pin_drop, "Contachilometri (Odo)", odoVal, "km", Colors.blueAccent),
    _c(Icons.local_gas_station, "Carburante Residuo", fuelVal, "%", Colors.amber),
    _c(Icons.thermostat, "Temperatura Esterna", extTempVal, "°C", Colors.cyanAccent),
    _c(Icons.shield_outlined, "Errori Rilevati (DTC)", dtcVal, "", Colors.redAccent),
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
    _c(Icons.shield_outlined, "Errori Rilevati (DTC)", dtcVal, "", Colors.redAccent),
   ];
  }
  return [
   _c(Icons.bolt, "Tensione Linea ECU", param1Val, "V", Colors.purpleAccent),
   _c(Icons.info, "VIN / Identificativo", param2Val, "", Colors.greenAccent),
   _c(Icons.check_circle_outline, "Stato Connessione", param3Val, "", Colors.cyanAccent),
   _c(Icons.shield_outlined, "Errori Rilevati (DTC)", dtcVal, "", Colors.redAccent),
  ];
 }

 Widget _ddBox(String label, String? val, List<String> items, ValueChanged<String?>? onChg) => Expanded(
  child: Container(
   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
   decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.6), width: 1.2)),
   child: Row(
    children: [
     Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
     const SizedBox(width: 6),
     Expanded(
      child: DropdownButtonHideUnderline(
       child: DropdownButton<String>(
        value: val, hint: const Text("Nessuno", style: TextStyle(color: Colors.grey, fontSize: 12)),
        isExpanded: true, dropdownColor: const Color(0xFF161A1D),
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
   appBar: AppBar(title: const Text('FRU SCAN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Color(0xFFFFB74D))), backgroundColor: Colors.transparent, elevation: 0, centerTitle: true),
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
          Row(children: [const Icon(Icons.check_circle, color: Colors.greenAccent, size: 15), const SizedBox(width: 6), Text("Centralina Attiva: $selectedEcu", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 4),
          Text(ecuResponseInfo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
         ],
        ),
       ),
       const SizedBox(height: 8),
      ],
      Row(
       children: [
        _ddBox("Marca:", selectedBrand, brandList, (v) => setState(() { selectedBrand = v!; selectedModel = (selectedBrand == "Fiat/Stellantis") ? "Tipo Cross 1.0 T3" : ""; })),
        const SizedBox(width: 8),
        _ddBox("Modello:", selectedModel.isEmpty ? null : selectedModel, isFiat ? ["Tipo Cross 1.0 T3"] : [], isFiat ? (v) => setState(() => selectedModel = v!) : null),
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
