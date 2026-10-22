import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const FruScanApp());

class FruScanApp extends StatelessWidget {
  const FruScanApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fru Scan',
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF121212)),
    home: const DiagnosticHomeScreen(),
  );
}

class DiagnosticHomeScreen extends StatefulWidget {
  const DiagnosticHomeScreen({Key? key}) : super(key: key);
  @override
  State<DiagnosticHomeScreen> createState() => _DiagnosticHomeScreenState();
}

class _DiagnosticHomeScreenState extends State<DiagnosticHomeScreen> {
  BluetoothConnection? connection;
  bool isConnected = false, _isPolling = false;
  String carb = "-- %", kmServ = "--- km", ggServ = "--- gg", olio = "-- %", ibs = "-- %", volt = "-- V", tExt = "-- °C", tMot = "-- °C";
  Timer? timer;

  Future<String> sendCmd(String tx, String rx, String cmd) async {
    if (connection == null || !isConnected) return "";
    try {
      for (var s in ["AT SP 7", "AT SH $tx", "AT CRA $rx", "AT FCSH $tx", "AT FCSD 300000", "AT FCSM 1", cmd]) {
        connection!.output.add(utf8.encode("$s\r"));
        await connection!.output.allSent;
        await Future.delayed(const Duration(milliseconds: 20));
      }
      String res = "";
      Stopwatch sw = Stopwatch()..start();
      await for (var d in connection!.input!) {
        res += utf8.decode(d);
        if (res.contains('>') || sw.elapsedMilliseconds > 350) break;
      }
      return res;
    } catch (_) { return ""; }
  }

  void startPolling() {
    if (timer != null && timer!.isActive) return;
    timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!isConnected || connection == null || _isPolling) return;
      _isPolling = true;
      try {
        String r1 = await sendCmd("18DA60F1", "18DAF160", "22 10 04");
        String v1 = parseHex(r1, "62 10 04");
        if (v1.isNotEmpty) { int? i = int.tryParse(v1, radix: 16); if (i != null) setState(() => carb = "$i %"); }
        await Future.delayed(const Duration(milliseconds: 80));

        String rOdo = await sendCmd("18DA60F1", "18DAF160", "22 20 01");
        String rLs = await sendCmd("18DA60F1", "18DAF160", "22 20 13");
        String rDs = await sendCmd("18DA60F1", "18DAF160", "22 20 15");
        if (rOdo.contains("62 20 01") && rLs.contains("62 20 13")) {
          int o = exHex(rOdo, "62 20 01", 4), l = exHex(rLs, "62 20 13", 3);
          if (o > 0 && l > 0) setState(() => kmServ = "${15000 - ((o/10).round() - l)} km");
        }
        if (rDs.contains("62 20 15")) { int d = exHex(rDs, "62 20 15", 2); if (d >= 0) setState(() => ggServ = "$d giorni"); }
        await Future.delayed(const Duration(milliseconds: 80));

        String rTe = await sendCmd("18DA60F1", "18DAF160", "22 10 05");
        String vTe = parseHex(rTe, "62 10 05");
        if (vTe.isNotEmpty) { int? r = int.tryParse(vTe, radix: 16); if (r != null) setState(() => tExt = "${((r/2)-40).toStringAsFixed(1)} °C"); }
        await Future.delayed(const Duration(milliseconds: 80));

        String rIbs = await sendCmd("18DA40F1", "18DAF140", "22 21 0B");
        String vIbs = parseHex(rIbs, "62 21 0B");
        if (vIbs.isNotEmpty && vIbs.length >= 2) { int? r = int.tryParse(vIbs.substring(0, 2), radix: 16); if (r != null) setState(() => ibs = "${((r*100)/255).round()} %"); }
        await Future.delayed(const Duration(milliseconds: 80));

        String rV = await sendCmd("18DA40F1", "18DAF140", "22 20 04");
        String vV = parseHex(rV, "62 20 04");
        if (vV.isNotEmpty) { int? r = int.tryParse(vV, radix: 16); if (r != null) setState(() => volt = "${(r/10).toStringAsFixed(2)} V"); }
        await Future.delayed(const Duration(milliseconds: 80));

        String rOl = await sendCmd("18DA10F1", "18DAF110", "22 38 1B");
        String vOl = parseHex(rOl, "62 38 1B");
        if (vOl.isNotEmpty) { int? r = int.tryParse(vOl, radix: 16); if (r != null) setState(() => olio = "$r %"); }
        await Future.delayed(const Duration(milliseconds: 80));

        String rTm = await sendCmd("18DA60F1", "18DAF160", "22 10 00");
        String vTm = parseHex(rTm, "62 10 00");
        if (vTm.isNotEmpty) { int? r = int.tryParse(vTm, radix: 16); if (r != null) setState(() => tMot = "${r - 40} °C"); }
      } catch (_) {} finally { _isPolling = false; }
    });
  }

  String parseHex(String res, String p) {
    if (!res.contains(p)) return "";
    try {
      List<String> sp = res.substring(res.indexOf(p) + p.length).trim().split(RegExp(r'\s+'));
      return sp.isNotEmpty ? sp[0] : "";
    } catch (_) { return ""; }
  }

  int exHex(String res, String p, int cnt) {
    try {
      List<String> sp = res.substring(res.indexOf(p) + p.length).trim().split(RegExp(r'\s+'));
      if (sp.length >= cnt) {
        String h = "";
        for (int i = 0; i < cnt; i++) h += sp[i];
        return int.parse(h, radix: 16);
      }
    } catch (_) {}
    return -1;
  }

  @override
  void dispose() { timer?.cancel(); connection?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Fru Scan'),
      actions: [IconButton(icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: isConnected ? Colors.green : Colors.red), onPressed: () {
        if (isConnected) { connection?.close(); timer?.cancel(); setState(() => isConnected = false); }
        else { _showDevs(); }
      })],
    ),
    body: Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.count(
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.3,
        children: [
          card("Carburante", carb, Icons.local_gas_station, Colors.orange),
          card("Service Km", kmServ, Icons.build, Colors.blue),
          card("Service Giorni", ggServ, Icons.calendar_today, Colors.blueGrey),
          card("Vita Olio", olio, Icons.opacity, Colors.amber),
          card("Carica IBS", ibs, Icons.battery_charging_full, Colors.green),
          card("Tensione Batt.", volt, Icons.bolt, Colors.purple),
          card("Temp. Esterna", tExt, Icons.thermostat, Colors.cyan),
          card("Temp. Motore", tMot, Icons.whatshot, Colors.redAccent),
        ],
      ),
    ),
  );

  Widget card(String t, String v, IconData i, Color c) => Card(
    color: const Color(0xFF1E1E1E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(i, color: c, size: 22), const SizedBox(width: 8), Expanded(child: Text(t, style: const TextStyle(fontSize: 13, color: Colors.grey)))]),
        const Spacer(),
        Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
      ]),
    ),
  );

  void _showDevs() async {
    List<BluetoothDevice> dev = [];
    try { dev = await FlutterBluetoothSerial.instance.getBondedDevices(); } catch (_) {}
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Seleziona OBD'),
      content: SizedBox(width: double.maxFinite, child: ListView.builder(
        shrinkWrap: true, itemCount: dev.length,
        itemBuilder: (_, idx) => ListTile(title: Text(dev[idx].name ?? ""), subtitle: Text(dev[idx].address), onTap: () {
          Navigator.pop(context);
          setState(() { isConnected = true; connection?.dispose(); });
          BluetoothConnection.toAddress(dev[idx].address).then((c) { connection = c; startPolling(); }).catchError((_) { setState(() => isConnected = false); });
        }),
      )),
    ));
  }
}
