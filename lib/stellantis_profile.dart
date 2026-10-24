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

  // Mappatura corretta degli identificativi CAN 29-bit per l'architettura FCA
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
    String res = await obd.sendCommand("22 F1 87");
    if (_isError(res)) {
      res = await obd.sendCommand("09 02");
    }
    param2Val = _parseAscii(res);
    return param2Val.isEmpty ? "N/D" : param2Val;
  }

  Future<String> resetDtc(ObdService obd) async {
    String res = await obd.sendCommand("14 FF FF FF");
    if (_isError(res)) return "Errore durante l'azzeramento";
    dtcVal = "0 (OK)";
    return "Comando reset inviato con successo";
  }

  bool _isError(String data) {
    return data.contains("NO DATA") || data.contains("7F") || data.contains("ERROR") || data.contains("STOPPED");
  }

  Future<void> pollEcu(ObdService obd, String ecu, int tick) async {
    if (tick % 5 == 0) {
      String dtc = await obd.sendCommand("19 02 09");
      _parseDtc(dtc);
    }

    if (ecu == "Centralina Motore (ECU)") {
      rpmVal = _parse(await obd.sendCommand("01 0C"), (a, b) => (a * 256 + b) / 4, rpmVal);
      speedVal = _parse(await obd.sendCommand("01 0D"), (a, b) => a.toDouble(), speedVal);
      coolantVal = _parse(await obd.sendCommand("01 05"), (a, b) => a - 40.0, coolantVal);
      // Corretto PID usura olio FCA UDS
      oilLifeVal = _parseUds(await obd.sendCommand("22 10 3B"), (a, b) => (a * 100) / 255, oilLifeVal);
      batteryVal = _parse(await obd.sendCommand("ATRV"), null, batteryVal, isVolt: true);
    } 
    else if (ecu == "Body Computer") {
      // Corretto PID IBS FCA UDS
      bcmIbsSocVal = _parseUds(await obd.sendCommand("22 20 02"), (a, b) => a.toDouble(), bcmIbsSocVal);
      odoVal = _parseUds(await obd.sendCommand("22 13 01"), (a, b) => (a * 65536 + b * 256) / 10, odoVal);
      bcmBatteryVoltVal = _parse(await obd.sendCommand("ATRV"), null, bcmBatteryVoltVal, isVolt: true);
    } 
    else if (ecu == "Quadro Strumenti") {
      // Corretto PID Service FCA UDS
      ipcServiceKmVal = _parseUds(await obd.sendCommand("22 15 01"), (a, b) => (a * 256 + b) * 10, ipcServiceKmVal);
      fuelVal = _parse(await obd.sendCommand("01 2F"), (a, b) => a * 100 / 255, fuelVal);
      ipcVoltVal = _parse(await obd.sendCommand("ATRV"), null, ipcVoltVal, isVolt: true);
    } 
    else if (ecu == "ABS") {
      // Corretto PID velocità ruote FCA UDS
      absSpeedVal = _parseUds(await obd.sendCommand("22 10 18"), (a, b) => (a * 256 + b) / 100, absSpeedVal);
      param1Val = _parse(await obd.sendCommand("ATRV"), null, param1Val, isVolt: true);
    } 
    else if (ecu == "Servosterzo") {
      if (param2Val == "---" || param2Val == "N/D") await readHardwarePartCode(obd);
      // Corretto PID Angolo Sterzo FCA UDS
      epsAngleVal = _parseUds(await obd.sendCommand("22 10 11"), (a, b) => ((a * 256 + b) - 32768) * 0.1, epsAngleVal);
      param1Val = _parse(await obd.sendCommand("ATRV"), null, param1Val, isVolt: true);
    } 
    else {
      param1Val = _parse(await obd.sendCommand("ATRV"), null, param1Val, isVolt: true);
      param3Val = "Connesso";
    }
  }

  String _parse(String data, double Function(int, int)? formula, String def, {bool isVolt = false}) {
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
        if (formula != null) return formula(a, b).toStringAsFixed(1);
      } catch (_) {
        return def;
      }
    }
    return def;
  }

  String _parseUds(String data, double Function(int, int) formula, String def) {
    if (_isError(data)) return def;
    
    data = data.replaceAll("\r", " ").replaceAll("\n", " ").replaceAll(">", " ").trim();
    data = data.replaceAll(RegExp(r'\s+'), ' ');
    List<String> hex = data.split(" ");
    
    int idx = hex.indexOf("62");
    if (idx != -1 && hex.length > idx + 3) {
      try {
        int a = int.parse(hex[idx + 3], radix: 16);
        int b = hex.length > idx + 4 ? int.parse(hex[idx + 4], radix: 16) : 0;
        return formula(a, b).toStringAsFixed(1);
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
