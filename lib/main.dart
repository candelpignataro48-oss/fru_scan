// Fru Scan - Codice Sorgente main.dart (PARTE 1 di 3)
// Aggiornato con DID nativi FCA / AlfaOBD e gestione sincronizzazione anti-sfarfallio
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const FruScanApp());
}

class FruScanApp extends StatelessWidget {
  const FruScanApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fru Scan - Fiat Tipo Cross',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const DiagnosticHomeScreen(),
    );
  }
}

class DiagnosticHomeScreen extends StatefulWidget {
  const DiagnosticHomeScreen({Key? key}) : super(key: key);

  @override
  State<DiagnosticHomeScreen> createState() => _DiagnosticHomeScreenState();
}

class _DiagnosticHomeScreenState extends State<DiagnosticHomeScreen> {
  BluetoothConnection? connection;
  bool isConnecting = false;
  bool isConnected = false;
  bool _isPolling = false; // Semaforo per bloccare sovrapposizioni di cicli di lettura
  String selectedDeviceAddress = "";

  // Variabili per i dati reali estratti da AlfaOBD
  String carburanteResiduo = "-- %";
  String kmService = "--- km";
  String giorniService = "--- giorni";
  String vitaOlio = "-- %";
  String caricaIbs = "-- %";
  String tensioneBatt = "-- V";
  String tempEsterna = "-- °C";
  String tempMotore = "-- °C";

  Timer? pollingTimer;

  // Funzione sicura per inviare comandi UDS con configurazione CAN e Flow Control
  Future<String> sendObdCommand(String txHeader, String rxHeader, String command) async {
    if (connection == null || !isConnected) return "";
    try {
      connection!.output.add(utf8.encode("AT SP 7\r"));
      await connection!.output.allSent;
      await Future.delayed(const Duration(milliseconds: 20));

      connection!.output.add(utf8.encode("AT SH $txHeader\r"));
      await connection!.output.allSent;
      await Future.delayed(const Duration(milliseconds: 20));

      connection!.output.add(utf8.encode("AT CRA $rxHeader\r"));
      await connection!.output.allSent;
      await Future.delayed(const Duration(milliseconds: 20));

      connection!.output.add(utf8.encode("AT FCSH $txHeader\r"));
      await connection!.output.allSent;
      await Future.delayed(const Duration(milliseconds: 20));

      connection!.output.add(utf8.encode("AT FCSD 300000\r"));
      await connection!.output.allSent;
      await Future.delayed(const Duration(milliseconds: 20));

      connection!.output.add(utf8.encode("AT FCSM 1\r"));
      await connection!.output.allSent;
      await Future.delayed(const Duration(milliseconds: 20));

      // Invio comando UDS effettivo
      connection!.output.add(utf8.encode("$command\r"));
      await connection!.output.allSent;

      String response = "";
      Stopwatch stopwatch = Stopwatch()..start();
      
      await for (Uint8List data in connection!.input!) {
        response += utf8.decode(data);
        if (response.contains('>') || stopwatch.elapsedMilliseconds > 350) {
          break;
        }
      }
      return response;
    } catch (e) {
      return "ERRORE: $e";
    }
  }
  // Ciclo di polling principale ottimizzato per evitare accavallamenti e sfarfallii
  void startPolling() {
    if (pollingTimer != null && pollingTimer!.isActive) return;

    pollingTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      if (!isConnected || connection == null || _isPolling) return;
      _isPolling = true;

      try {
        // --- 1. QUADRO STRUMENTI (18DA60F1 / 18DAF160) ---
        String respIpcCarb = await sendObdCommand("18DA60F1", "18DAF160", "22 10 04");
        String carbIpcVal = parseHexResponse(respIpcCarb, "62 10 04");
        if (carbIpcVal.isNotEmpty) {
          int? val = int.tryParse(carbIpcVal, radix: 16);
          if (val != null) {
            setState(() { carburanteResiduo = "$val %"; });
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));

        // Service: Odometro (22 20 01) e Distanza Ultimo Servizio (22 20 13) per calcolo km residui Service
        String respOdo = await sendObdCommand("18DA60F1", "18DAF160", "22 20 01");
        String respLastServ = await sendObdCommand("18DA60F1", "18DAF160", "22 20 13");
        String respDaysServ = await sendObdCommand("18DA60F1", "18DAF160", "22 20 15"); // Giorni residui Service (219)

        if (respOdo.contains("62 20 01") && respLastServ.contains("62 20 13")) {
          int odoVal = extractHexValue(respOdo, "62 20 01", 4); // decimi di km
          int lastServVal = extractHexValue(respLastServ, "62 20 13", 3);
          if (odoVal > 0 && lastServVal > 0) {
            int currentKm = (odoVal / 10).round();
            int kmResidui = 15000 - (currentKm - lastServVal);
            setState(() { kmService = "$kmResidui km"; });
          }
        }

        if (respDaysServ.contains("62 20 15")) {
          int giorniVal = extractHexValue(respDaysServ, "62 20 15", 2);
          if (giorniVal >= 0) {
            setState(() { giorniService = "$giorniVal giorni"; });
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));

        // Temperatura Esterna da IPC (22 10 05)
        String respTempExt = await sendObdCommand("18DA60F1", "18DAF160", "22 10 05");
        String tempExtHex = parseHexResponse(respTempExt, "62 10 05");
        if (tempExtHex.isNotEmpty) {
          int? raw = int.tryParse(tempExtHex, radix: 16);
          if (raw != null) {
            double c = (raw / 2.0) - 40.0;
            setState(() { tempEsterna = "${c.toStringAsFixed(1)} °C"; });
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));


        // --- 2. BODY COMPUTER APTIV (18DA40F1 / 18DAF140) ---
        String respIbs = await sendObdCommand("18DA40F1", "18DAF140", "22 21 0B");
        String ibsHex = parseHexResponse(respIbs, "62 21 0B");
        if (ibsHex.isNotEmpty && ibsHex.length >= 2) {
          int? rawIbs = int.tryParse(ibsHex.substring(0, 2), radix: 16);
          if (rawIbs != null) {
            int soc = ((rawIbs * 100) / 255.0).round();
            setState(() { caricaIbs = "$soc %"; });
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));

        // Tensione Batteria Body (+30): 22 20 04
        String respVolt = await sendObdCommand("18DA40F1", "18DAF140", "22 20 04");
        String voltHex = parseHexResponse(respVolt, "62 20 04");
        if (voltHex.isNotEmpty) {
          int? rawVolt = int.tryParse(voltHex, radix: 16);
          if (rawVolt != null) {
            double v = rawVolt / 10.0;
            setState(() { tensioneBatt = "${v.toStringAsFixed(2)} V"; });
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));


        // --- 3. CENTRALINA MOTORE GSE (18DA10F1 / 18DAF110) ---
        // Vita restante olio motore: 22 38 1B
        String respOlio = await sendObdCommand("18DA10F1", "18DAF110", "22 38 1B");
        String olioHex = parseHexResponse(respOlio, "62 38 1B");
        if (olioHex.isNotEmpty) {
          int? rawOlio = int.tryParse(olioHex, radix: 16);
          if (rawOlio != null) {
            setState(() { vitaOlio = "$rawOlio %"; });
          }
        }
        await Future.delayed(const Duration(milliseconds: 100));

        // Temperatura Liquido Motore: 22 10 00 da IPC o Motore
        String respTempMot = await sendObdCommand("18DA60F1", "18DAF160", "22 10 00");
        String tempMotHex = parseHexResponse(respTempMot, "62 10 00");
        if (tempMotHex.isNotEmpty) {
          int? rawMot = int.tryParse(tempMotHex, radix: 16);
          if (rawMot != null) {
            int tMot = rawMot - 40;
            setState(() { tempMotore = "$tMot °C"; });
          }
        }

      } catch (e) {
        // Gestione silenziata errori di polling per evitare blocchi UI
      } finally {
        _isPolling = false;
      }
    });
  }

  // Funzioni di supporto per il parsing esadecimale UDS
  String parseHexResponse(String response, String headerPrefix) {
    if (!response.contains(headerPrefix)) return "";
    try {
      int idx = response.indexOf(headerPrefix);
      String sub = response.substring(idx + headerPrefix.length).trim();
      List<String> parts = sub.split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        return parts[0];
      }
    } catch (_) {}
    return "";
  }

  int extractHexValue(String response, String headerPrefix, int byteCount) {
    try {
      int idx = response.indexOf(headerPrefix);
      if (idx == -1) return -1;
      String sub = response.substring(idx + headerPrefix.length).trim();
      List<String> parts = sub.split(RegExp(r'\s+'));
      if (parts.length >= byteCount) {
        String hexStr = "";
        for (int i = 0; i < byteCount; i++) {
          hexStr += parts[i];
        }
        return int.parse(hexStr, radix: 16);
      }
    } catch (_) {}
    return -1;
  }
  @override
  void dispose() {
    pollingTimer?.cancel();
    connection?.dispose();
    super.dispose();
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() { isConnecting = true; });
    try {
      connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        isConnected = true;
        isConnecting = false;
        selectedDeviceAddress = device.address;
      });
      startPolling();
    } catch (e) {
      setState(() {
        isConnected = false;
        isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fru Scan - Fiat Tipo Cross'),
        actions: [
          IconButton(
            icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
            color: isConnected ? Colors.green : Colors.red,
            onPressed: () {
              // Schermata di selezione o disconnessione
              if (isConnected) {
                connection?.close();
                pollingTimer?.cancel();
                setState(() { isConnected = false; });
              } else {
                _showDeviceSelectionDialog();
              }
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.3,
          children: [
            buildDashboardCard("Carburante Residuo", carburanteResiduo, Icons.local_gas_station, Colors.orange),
            buildDashboardCard("Service Km", kmService, Icons.build, Colors.blue),
            buildDashboardCard("Service Giorni", giorniService, Icons.calendar_today, Colors.blueGrey),
            buildDashboardCard("Vita Restante Olio", vitaOlio, Icons.opacity, Colors.amber),
            buildDashboardCard("Carica Batteria (IBS)", caricaIbs, Icons.battery_charging_full, Colors.green),
            buildDashboardCard("Tensione Batteria", tensioneBatt, Icons.bolt, Colors.purple),
            buildDashboardCard("Temperatura Esterna", tempEsterna, Icons.thermostat, Colors.cyan),
            buildDashboardCard("Temperatura Motore", tempMotore, Icons.whatshot, Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget buildDashboardCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceSelectionDialog() async {
    List<BluetoothDevice> devices = [];
    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (_) {}

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Seleziona Adattatore OBD'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                BluetoothDevice device = devices[index];
                return ListTile(
                  title: Text(device.name ?? "Dispositivo sconosciuto"),
                  subtitle: Text(device.address),
                  onTap: () {
                    Navigator.pop(context);
                    connectToDevice(device);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

