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

  Future<String> readHardwarePartCode(ObdService obd, String ecu) async {
    String res = await obd.queryObd("22 F1 87\r");
    // Se la centralina rifiuta il comando UDS, tentiamo il Mode 09 SOLO se è la centralina motore
    if ((res.contains("7F") || res.contains("NO DATA")) && ecu == "Centralina Motore (ECU)") {
      res = await obd.queryObd("09 02\r");
    }
    String val = _parseAscii(res);
    return val.isEmpty ? "N/D" : val;
  }

  Future<String> resetDtc(ObdService obd) async {
    String res = await obd.queryObd("14 FF FF FF\r");
    if (res.contains("NO DATA") || res.contains("7F") && !res.contains("78")) {
      return "Errore durante l'azzeramento";
    }
    dtcVal = "0 (OK)";
    return "Comando reset inviato con successo";
  }

  Future<void> pollEcu(ObdService obd, String ecu, int tick) async {
    // Lettura errori ogni 5 cicli
    if (tick % 5 == 0) {
      String dtc = await obd.queryObd("19 02 09\r");
      _parseDtc(dtc);
    }

    if (ecu == "Centralina Motore (ECU)") {
      rpmVal = _parse(await obd.queryObd("01 0C\r"), (a, b) => (a * 256 + b) / 4, rpmVal, decimals: 0);
      speedVal = _parse(await obd.queryObd("01 0D\r"), (a, b) => a.toDouble(), speedVal, decimals: 0);
      turboVal = _parse(await obd.queryObd("01 0B\r"), (a, b) => (a - 100) / 100, turboVal, decimals: 2);
      fuelVal = _parse(await obd.queryObd("01 2F\r"), (a, b) => a * 100 / 255, fuelVal, decimals: 0);
      coolantVal = _parse(await obd.queryObd("01 05\r"), (a, b) => a - 40.0, coolantVal, decimals: 0);
      oilVal = _parse(await obd.queryObd("01 5C\r"), (a, b) => a - 40.0, oilVal, decimals: 0);
      iatVal = _parse(await obd.queryObd("01 0F\r"), (a, b) => a - 40.0, iatVal, decimals: 0);
      catalystVal = _parse(await obd.queryObd("01 3C\r"), (a, b) => ((a * 256 + b) / 10) - 40.0, catalystVal, decimals: 0);
      batteryVal = _parse(await obd.queryObd("ATRV\r"), null, batteryVal, isVolt: true);
    } 
    else {
      // PER TUTTE LE ALTRE CENTRALINE (Evita l'errore 7F 01 11 bloccante)
      // Leggiamo solo la tensione generica e l'Hardware ID se assente
      if (param2Val == "---" || param2Val == "N/D") {
        param2Val = await readHardwarePartCode(obd, ecu);
      }
      String volt = _parse(await obd.queryObd("ATRV\r"), null, "---", isVolt: true);
      param1Val = volt;

      // Aggiorna le card di tensione specifiche in base alla centralina selezionata
      if (ecu == "Body Computer") bcmBatteryVoltVal = volt;
      if (ecu == "Quadro Strumenti") ipcVoltVal = volt;
      
      param3Val = "Connesso";
    }
  }

  String _parse(String data, double Function(int, int)? formula, String def, {bool isVolt = false, int decimals = 1}) {
    if (data.contains("NO DATA") || data.contains("STOPPED")) return def;
    if (isVolt && data.contains("V")) return data.replaceAll(RegExp(r'[^0-9.]'), '');
    if (data.contains("7F")) return def; // Richiesta non supportata
    
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
    if (data.contains("NO DATA") || data.contains("STOPPED") || data.contains("7F")) return "";
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
    if (data.contains("NO DATA") || data.contains("STOPPED")) {
      dtcVal = "---";
      dtcDetails = "Nessuna risposta.";
      return;
    }

    // Pulizia dei byte
    List<String> hex = data.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll('>', ' ').split(RegExp(r'\s+'));
    hex.removeWhere((e) => e.isEmpty);
    
    int idx = hex.indexOf("59");
    if (idx != -1 && hex.length > idx + 1 && hex[idx+1] == "02") {
      // Se la risposta è corta (es. 59 02 4F), non ci sono DTC
      if (hex.length <= idx + 3) {
        dtcVal = "0 (OK)";
        dtcDetails = "Nessun codice errore rilevato.";
      } else {
        dtcVal = "Rilevati";
        dtcDetails = data;
      }
    } else if (data.contains("7F 19")) {
      dtcVal = "---";
      dtcDetails = "Lettura momentaneamente non disponibile.";
    } else {
      dtcVal = "---";
      dtcDetails = "Formato dati sconosciuto.";
    }
  }
}
// === FINE DEL CODICE ===
