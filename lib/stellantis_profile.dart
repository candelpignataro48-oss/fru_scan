import 'obd_service.dart';

class StellantisProfile {
  final List<String> brandList = ["Fiat/Stellantis", "Alfa Romeo"];

  final Map<String, String> ecuIds = {
    "Centralina Motore (ECU)": "10",
    "Body Computer": "40",
    "Quadro Strumenti": "60",
    "ABS": "28",
    "Servosterzo": "30",
    "Airbag": "51",
    "Climatizzatore": "68",
    "Radio / Uconnect": "62",
    "Sensori di Parcheggio": "76",
    "Cruise Control": "7A",
  };

  String fuelVal = "---", odoVal = "---", extTempVal = "---", dtcVal = "---";
  double? _fuelPct, _avgKml;
  int? _odoKm;

  String param1Val = "---", param2Val = "---", param3Val = "---";
  String rpmVal = "---", speedVal = "---", turboVal = "---", batteryVal = "---";
  String coolantVal = "---", oilVal = "---", iatVal = "---", catalystVal = "---", oilLifeVal = "---";
  String bcmIbsSocVal = "---", bcmBatteryVoltVal = "---";
  String ipcRangeVal = "---", ipcTpmsVal = "---", ipcServiceKmVal = "---", ipcAvgConsVal = "---", ipcVoltVal = "---";

  List<int> bytes(String raw, String m1, [String? m2, String? m3]) {
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
    List<int> b = bytes(raw, "62");
    if (b.length > 2) {
      List<int> a = b.sublist(2).where((x) => x >= 32 && x <= 126).toList();
      if (a.isNotEmpty) return String.fromCharCodes(a).trim();
    }
    try {
      List<int> bAlt = bytes(raw, "62");
      if (bAlt.isNotEmpty) {
        return String.fromCharCodes(bAlt.where((x) => x >= 32 && x <= 126)).trim();
      }
    } catch (_) {}
    String cl = raw.replaceAll(">", "").replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return (cl.isEmpty || cl.contains("NO DATA") || cl.contains("7F")) ? "N/D" : cl;
  }

  String parseVolt(String r) {
    final m = RegExp(r'(\d+\.\d+)').firstMatch(r.replaceAll(">", ""));
    return m != null ? double.parse(m.group(1)!).toStringAsFixed(1) : batteryVal;
  }

  int? _calcOdo(List<int> b) {
    if (b.length >= 4) {
      int v = (b[0] * 16777216) + (b[1] * 65536) + (b[2] * 256) + b[3];
      if (v > 0 && v < 9000000) return v > 600000 ? v ~/ 10 : v;
    } else if (b.length == 3) {
      int v = (b[0] * 65536) + (b[1] * 256) + (b[2]);
      if (v > 0 && v < 9000000) return v > 600000 ? v ~/ 10 : v;
    }
    return null;
  }

  // Corretta logica temperatura esterna: scarta 128 (0x80) e convalida range realistico
  String? _extT(List<int> b) {
    for (int x in b) {
      if (x > 0 && x < 250 && x != 128) {
        int temp = x - 40;
        if (temp >= -40 && temp <= 60) {
          return temp.toString();
        }
      }
    }
    return null;
  }

  Future<String> readHardwarePartCode(ObdService obd) async {
    return decodeAscii(await obd.queryObd("22 F1 87\r", timeoutMs: 280));
  }

  Future<void> _updateDtc(ObdService obd, {bool isEng = false}) async {
    List<int> dB = bytes(await obd.queryObd("19 02 09\r", timeoutMs: 170), "59", "02");
    if (dB.isNotEmpty) {
      int c = (dB
