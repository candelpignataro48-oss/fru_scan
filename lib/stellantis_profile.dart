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

  String? _extT(List<int> b) {
    for (int x in b) {
      if (x > 0 && x < 250) return (x - 40).toString();
    }
    return null;
  }

  Future<String> readHardwarePartCode(ObdService obd) async {
    return decodeAscii(await obd.queryObd("22 F1 87\r", timeoutMs: 280));
  }

  Future<void> _updateDtc(ObdService obd, {bool isEng = false}) async {
    List<int> dB = bytes(await obd.queryObd("19 02 09\r", timeoutMs: 170), "59", "02");
    if (dB.isNotEmpty) {
      int c = (dB.length - 1) ~/ 4;
      dtcVal = c <= 0 ? "0 (OK)" : "$c Errori";
      return;
    }
    if (isEng) {
      List<int> m1 = bytes(await obd.queryObd("0101\r", timeoutMs: 150), "41", "01");
      if (m1.isNotEmpty) {
        int c = m1[0] & 0x7F;
        dtcVal = c == 0 ? "0 (OK)" : "$c Errori";
      }
    }
  }

  Future<String> resetDtc(ObdService obd) async {
    String res = await obd.queryObd("14 00 00\r", timeoutMs: 300);
    return res.contains("54") ? "Errori azzerati con successo" : "Comando inviato / Risposta: $res";
  }

  Future<void> _updateShared(ObdService obd, String curId) async {
    List<int> fB = bytes(await obd.queryObd("22 20 05\r", timeoutMs: 140), "62", "20", "05");
    if (fB.isNotEmpty && fB[0] >= 0 && fB[0] <= 100) {
      _fuelPct = fB[0].toDouble();
      fuelVal = fB[0].toString();
    } else {
      if (curId != "10") await obd.setChan("10");
      List<int> obdF = bytes(await obd.queryObd("012F\r", timeoutMs: 140), "41", "2F");
      if (obdF.isNotEmpty && obdF[0] >= 0) {
        _fuelPct = (obdF[0] * 100.0) / 255.0;
        fuelVal = _fuelPct!.round().toString();
      }
      if (curId != "10") await obd.setChan(curId);
    }

    String? vT;
    if (curId != "10") await obd.setChan("10");
    vT = _extT(bytes(await obd.queryObd("0146\r", timeoutMs: 140), "41", "46"));
    vT ??= _extT(bytes(await obd.queryObd("22 F4 46\r", timeoutMs: 140), "62", "F4", "46"));
    if (curId != "10") await obd.setChan(curId);
    if (vT == null) {
      for (var d in [["19", "24"], ["20", "03"], ["10", "04"]]) {
        vT = _extT(bytes(await obd.queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 140), "62", d[0], d[1]));
        if (vT != null) break;
      }
    }
    if (vT != null) extTempVal = vT;

    int? odo = _calcOdo(bytes(await obd.queryObd("22 20 01\r", timeoutMs: 160), "62", "20", "01"));
    if (odo == null) {
      if (curId != "60") await obd.setChan("60");
      odo = _calcOdo(bytes(await obd.queryObd("22 20 01\r", timeoutMs: 160), "62", "20", "01"));
      if (odo == null) {
        await obd.setChan("10");
        List<int> bA6 = bytes(await obd.queryObd("01A6\r", timeoutMs: 160), "41", "A6");
        if (bA6.length >= 4) {
          int raw = (bA6[0] * 16777216) + (bA6[1] * 65536) + (bA6[2] * 256) + bA6[3];
          if (raw > 0) odo = raw ~/ 10;
        }
      }
      await obd.setChan(curId);
    }
    if (odo != null && odo > 0) {
      _odoKm = odo;
      odoVal = odo.toString();
    }
  }

  Future<void> pollEcu(ObdService obd, String selectedEcu, int tick) async {
    String curId = ecuIds[selectedEcu] ?? "10";
    if (selectedEcu == "Centralina Motore (ECU)") {
      List<int> bC = bytes(await obd.queryObd("010C\r", timeoutMs: 120), "41", "0C");
      if (bC.length >= 2) rpmVal = (((bC[0] * 256) + bC[1]) / 4).round().toString();
      List<int> bD = bytes(await obd.queryObd("010D\r", timeoutMs: 120), "41", "0D");
      if (bD.isNotEmpty) speedVal = bD[0].toString();
      List<int> bB = bytes(await obd.queryObd("010B\r", timeoutMs: 120), "41", "0B");
      if (bB.isNotEmpty) turboVal = ((bB[0] - 100) / 100.0).clamp(-1.0, 1.8).toStringAsFixed(2);
      List<int> b5 = bytes(await obd.queryObd("0105\r", timeoutMs: 120), "41", "05");
      if (b5.isNotEmpty && b5[0] > 0) coolantVal = (b5[0] - 40).toString();
      List<int> bF = bytes(await obd.queryObd("010F\r", timeoutMs: 120), "41", "0F");
      if (bF.isNotEmpty && bF[0] > 0) iatVal = (bF[0] - 40).toString();

      if (tick % 4 == 0) {
        List<int> oB = bytes(await obd.queryObd("015C\r", timeoutMs: 140), "41", "5C");
        if (oB.isNotEmpty && oB[0] > 0) {
          oilVal = (oB[0] - 40).toString();
        } else {
          List<int> uO = bytes(await obd.queryObd("22 10 09\r", timeoutMs: 140), "62", "10", "09");
          if (uO.isNotEmpty && uO[0] > 0) oilVal = (uO[0] - 40).toString();
        }
        List<int> cB = bytes(await obd.queryObd("013C\r", timeoutMs: 140), "41", "3C");
        if (cB.length >= 2) catalystVal = (((cB[0] * 256) + cB[1]) / 10.0 - 40.0).round().toString();
        batteryVal = parseVolt(await obd.queryObd("ATRV\r", timeoutMs: 120));
        await _updateShared(obd, "10");
        await _updateDtc(obd, isEng: true);

        for (var d in [["18", "08"], ["18", "82"], ["19", "42"], ["19", "03"], ["38", "1A"]]) {
          List<int> b = bytes(await obd.queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 140), "62", d[0], d[1]);
          if (b.isNotEmpty) {
            int v = -1;
            if (b.length >= 2) {
              int raw16 = (b[0] * 256) + b[1];
              if (raw16 >= 0 && raw16 <= 100) v = raw16;
              else if (raw16 > 100 && raw16 <= 1000) v = raw16 ~/ 10;
            }
            if (v == -1 && b[0] >= 0 && b[0] <= 100) v = b[0];
            if (v >= 0 && v <= 100) {
              oilLifeVal = v.toString();
              break;
            }
          }
        }
      }
    } else if (selectedEcu == "Body Computer") {
      bcmBatteryVoltVal = parseVolt(await obd.queryObd("ATRV\r", timeoutMs: 120));
      for (var d in [["40", "24"], ["19", "35"], ["03", "02"], ["19", "36"], ["21", "15"]]) {
        List<int> b = bytes(await obd.queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 140), "62", d[0], d[1]);
        if (b.isNotEmpty) {
          for (int x in b) {
            if (x >= 0 && x <= 100) {
              bcmIbsSocVal = x.toString();
              break;
            }
          }
          if (bcmIbsSocVal != "---") break;
        }
      }
      if (tick % 3 == 0) {
        await _updateShared(obd, "40");
        await _updateDtc(obd);
      }
    } else if (selectedEcu == "Quadro Strumenti") {
      ipcVoltVal = parseVolt(await obd.queryObd("ATRV\r", timeoutMs: 120));
      for (var d in [["21", "01"], ["20", "10"], ["20", "11"], ["F1", "C2"], ["19", "20"]]) {
        List<int> sB = bytes(await obd.queryObd("22 ${d[0]} ${d[1]}\r", timeoutMs: 150), "62", d[0], d[1]);
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
              if (dC > 0 && dC <= 730) daysVal = dC;
              else if (sB.length >= 6) {
                int dAlt = (sB[4] * 256) + sB[5];
                if (dAlt >= 0 && dAlt <= 730) daysVal = dAlt;
              }
            }
            ipcServiceKmVal = daysVal != null ? "$kmVal/15000 ($daysVal gg)" : "$kmVal/15000";
            break;
          }
        }
      }

      if (tick % 2 == 0) await _updateShared(obd, "60");

      List<int> cB = bytes(await obd.queryObd("22 20 0A\r", timeoutMs: 140), "62", "20", "0A");
      if (cB.length >= 2) {
        double v = ((cB[0] * 256) + cB[1]) / 10.0;
        if (v > 2.0 && v < 40.0) {
          _avgKml = v;
          ipcAvgConsVal = v.toStringAsFixed(1);
        }
      } else {
        await obd.setChan("10");
        List<int> spdB = bytes(await obd.queryObd("010D\r", timeoutMs: 120), "41", "0D");
        List<int> mafB = bytes(await obd.queryObd("0110\r", timeoutMs: 120), "41", "10");
        await obd.setChan("60");
        if (spdB.isNotEmpty && mafB.length >= 2) {
          double spd = spdB[0].toDouble(), lph = (((mafB[0] * 256) + mafB[1]) / 100.0) * 0.3287;
          if (spd > 3.0 && lph > 0.2) {
            double kml = (spd / lph).clamp(3.0, 35.0);
            _avgKml = _avgKml == null ? kml : (_avgKml! * 0.85 + kml * 0.15);
            ipcAvgConsVal = _avgKml!.toStringAsFixed(1);
          }
        }
      }
      List<int> rB = bytes(await obd.queryObd("22 20 07\r", timeoutMs: 140), "62", "20", "07");
      if (rB.length >= 2) {
        int rKm = (rB[0] * 256) + rB[1];
        if (rKm > 0 && rKm < 1500) ipcRangeVal = rKm.toString();
      } else if (_fuelPct != null) {
        ipcRangeVal = (((_fuelPct! / 100.0) * 50.0) * (_avgKml ?? 15.0)).round().toString();
      }
      if (tick % 4 == 0) {
        await _updateDtc(obd);
        ipcTpmsVal = dtcVal == "0 (OK)" ? "Regolare" : dtcVal;
      }
    } else {
      param1Val = parseVolt(await obd.queryObd("ATRV\r", timeoutMs: 120));
      param2Val = decodeAscii(await obd.queryObd("22 F1 90\r", timeoutMs: 180));
      param3Val = param2Val != "N/D" ? "Comunicazione OK" : "Attiva";
      if (tick % 3 == 0) await _updateDtc(obd);
    }
  }
}
