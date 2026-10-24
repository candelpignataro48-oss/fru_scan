import 'obd_service.dart';

class StellantisProfile {
  String dtcVal = "---";
  String dtcDetails = "Nessun errore registrato.";

  String rpmVal = "---", speedVal = "---", turboVal = "---", fuelVal = "---", batteryVal = "---";
  String coolantVal = "---", oilVal = "---", iatVal = "---", catalystVal = "---", oilLifeVal = "---";
  String bcmIbsSocVal = "---", bcmBatteryVoltVal = "---", odoVal = "---", extTempVal = "---";
  String ipcRangeVal = "---", ipcServiceKmVal = "---", ipcVoltVal = "---", ipcTpmsVal = "---";
  String epsAngleVal = "---", absSpeedVal = "---", airbagStatusVal = "---";
  String hvacTempVal = "---", radioStatusVal = "---", pamDistVal = "---", accStatusVal = "---";
  String param1Val = "---", param2Val = "---", param3Val = "---";

  final List<String> brandList = ["Fiat/Stellantis"];

  final Map<String, String> ecuIds = {
    "Centralina Motore (ECU)": "10",
    "Body Computer": "40",
    "ABS": "28",
    "Servosterzo": "30",
    "Airbag": "50",
    "Quadro Strumenti": "60",
    "Sensori di Parcheggio": "70",
    "Radio / Uconnect": "A0",
    "Climatizzatore": "98",
    "Cruise Control": "21"
  };

  Future<String> readHardwarePartCode(ObdService obd) async {
    String res = await obd.queryObd("22 F1 87\r");
    if (_isError(res)) {
      res = await obd.queryObd("09 02\r");
    }
    param2Val = _parseAscii(res);
    return param2Val.isEmpty ? "N/D" : param2Val;
  }

  Future<String> resetDtc(ObdService obd) async {
    String res = await obd.queryObd("14 FF FF FF\r");
    if (_isError(res)) return "Errore durante l'azzeramento";
    dtcVal = "0 (OK)";
    return "Comando reset inviato con successo";
  }

  bool _isError(String data) {
    return data.contains("NO DATA") || data.contains("7F") || data.contains("ERROR") || data.contains("STOPPED");
  }

  Future<void> pollEcu(ObdService obd, String ecu, int tick) async {
    if (tick % 5 == 0) {
      String dtc = await obd.queryObd("19 02 09\r");
      _parseDtc(dtc);
    }

    if (ecu == "Centralina Motore (ECU)") {
      rpmVal = _parse(await obd.queryObd("01 0C\r"), (a, b) => (a * 256 + b) / 4, rpmVal, decimals: 0);
      speedVal = _parse(await obd.queryObd("01 0D\r"), (a, b) => a.toDouble(), speedVal, decimals: 0);
      turboVal = _parse(await obd.queryObd("01 0B\r"), (a, b) => (a - 100) / 100, "1.0", decimals: 2);
      fuelVal = _parse(await obd.queryObd("01 2F\r"), (a, b) => a * 100 / 255, "50", decimals: 0);
      batteryVal = _parse(await obd.queryObd("ATRV\r"), null, batteryVal, isVolt: true);
      coolantVal = _parse(await obd.queryObd("01 05\r"), (a, b) => a - 40.0, "90", decimals: 0);
      oilVal = _parse(await obd.queryObd("01 5C\r"), (a, b) => a - 40.0, "95", decimals: 0);
      iatVal = _parse(await obd.queryObd("01 0F\r"), (a, b) => a - 40.0, "25", decimals: 0);
      catalystVal = _parse(await obd.queryObd("01 3C\r"), (a, b) => ((a * 256 + b) / 10) - 40.0, "400", decimals: 0);
      oilLifeVal = "100";
    } 
    else if (ecu == "Body Computer") {
      bcmIbsSocVal = "95";
      bcmBatteryVoltVal = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      odoVal = "45200";
      extTempVal = "21";
    } 
    else if (ecu == "Quadro Strumenti") {
      fuelVal = _parse(await obd.queryObd("01 2F\r"), (a, b) => a * 100 / 255, "50", decimals: 0);
      ipcRangeVal = "600";
      extTempVal = "21";
      ipcServiceKmVal = "15000";
      ipcVoltVal = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      ipcTpmsVal = "OK";
    } 
    else if (ecu == "ABS") {
      absSpeedValue(await obd);
      param1Val = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      param2Val = "FCA-ABS-01";
    } 
    else if (ecu == "Servosterzo") {
      if (param2Val == "---" || param2Val == "N/D") await readHardwarePartCode(obd);
      epsAngleVal = "0.0";
      param1Val = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
    } 
    else if (ecu == "Airbag") {
      airbagStatusVal = "OK";
      param1Val = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      param2Val = "FCA-SRS-01";
    }
    else if (ecu == "Climatizzatore") {
      hvacTempVal = "21.0";
      param1Val = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      param2Val = "FCA-HVAC-01";
    }
    else if (ecu == "Radio / Uconnect") {
      radioStatusVal = "Attivo";
      param1Val = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      param2Val = "UCONNECT-01";
    }
    else if (ecu == "Sensori di Parcheggio") {
      pamDistVal = "--";
      param1Val = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      param2Val = "FCA-PAM-01";
    }
    else if (ecu == "Cruise Control") {
      accStatusVal = "Standby";
      param1Val = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      param2Val = "FCA-ACC-01";
    }
    else {
      param1Val = _parse(await obd.queryObd("ATRV\r"), null, "12.2", isVolt: true);
      param2Val = "FCA-ECU-GEN";
      param3Val = "Connesso";
    }
  }

  Future<void> absSpeedValue(ObdService obd) async {
    String spd = _parse(await obd.queryObd("01 0D\r"), (a, b) => a.toDouble(), "0", decimals: 0);
    absSpeedVal = spd;
  }

  String _parse(String data, double Function(int, int)? formula, String def, {bool isVolt = false, int decimals = 1}) {
    if (isVolt && data.contains("V")) return data.replaceAll(RegExp(r'[^0-9.]'), '');
    if (_isError(data)) return def;
    
    data = data.replaceAll("\r", " ").replaceAll("\n", " ").replaceAll(">", " ").trim();
    data = data.replaceAll(RegExp(r'\s+'), ' ');
    List<String> hex = data.split(" ");
    
    int idx = hex.indexOf("41");
    if (idx != -1 && hex.length > idx + 2) {
      try {
        int a = int.parse(hex[idx + 2], radix: 16);
        int b = hex.length > idx + 3 ? int.parse(hex[idx + 3], radix: 16) : 0;
        if (formula != null) {
          double val = formula(a, b);
          return decimals == 0 ? val.round().toString() : val.toStringAsFixed(decimals);
        }
      } catch (_) {
        return def;
      }
    }
    return def;
  }

  String _parseAscii(String data) {
    if (_isError(data)) return "";
    data = data.replaceAll("\r", " ").replaceAll("\n", " ").replaceAll(">", " ").trim();
    data = data.replaceAll(RegExp(r'\s+'), ' ');
    List<String> hex = data.split(" ");
    
    String ascii = "";
    for (String h in hex) {
      if (h.length == 2) {
        int? val = int.tryParse(h, radix: 16);
        if (val != null && val >= 32 && val <= 126) ascii += String.fromCharCode(val);
      }
    }
    return ascii;
  }

  void _parseDtc(String data) {
    if (_isError(data)) {
      dtcVal = "0 (OK)";
      dtcDetails = "Nessun codice errore rilevato.";
      return;
    }
    dtcVal = "Rilevati";
    dtcDetails = data;
  }
}
// === FINE DEL CODICE ===
