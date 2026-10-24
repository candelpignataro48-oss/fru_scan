import 'obd_service.dart';

class StellantisProfile {
  // Stato errori DTC
  String dtcVal = "---";
  String dtcDetails = "Nessun errore registrato.";

  // Parametri Motore & Sensori Generali
  String rpmVal = "---", speedVal = "---", turboVal = "---", fuelVal = "---", batteryVal = "---";
  String coolantVal = "---", oilVal = "---", iatVal = "---", catalystVal = "---", oilLifeVal = "---";
  
  // Parametri specifici Body & Quadro
  String bcmIbsSocVal = "---", bcmBatteryVoltVal = "---", odoVal = "---", extTempVal = "---";
  String ipcRangeVal = "---", ipcServiceKmVal = "---", ipcVoltVal = "---", ipcTpmsVal = "---";
  
  // Parametri Servosterzo, ABS, Airbag, Clima, Radio, PAM, Cruise
  String epsAngleVal = "---", absSpeedVal = "---", airbagStatusVal = "---";
  String hvacTempVal = "---", radioStatusVal = "---", pamDistVal = "---", accStatusVal = "---";
  String param1Val = "---", param2Val = "---", param3Val = "---";

  final List<String> brandList = ["Fiat/Stellantis"];

  // Mappatura ID UDS / CAN 29-bit standard per architettura FCA
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

  /// Interroga il codice parte hardware (DID F187) o fallback su identificativo motore (09 02)
  Future<String> readHardwarePartCode(ObdService obd, String ecu) async {
    String res = await obd.queryObd("22 F1 87\r");
    if ((res.contains("7F") || res.contains("NO DATA")) && ecu == "Centralina Motore (ECU)") {
      res = await obd.queryObd("09 02\r");
    }
    String val = _parseAscii(res);
    return val.isEmpty ? "N/D" : val;
  }

  /// Comando universale di reset/cancellazione DTC (Servizio UDS 14)
  Future<String> resetDtc(ObdService obd) async {
    String res = await obd.queryObd("14 FF FF FF\r");
    if (res.contains("NO DATA") || (res.contains("7F") && !res.contains("78"))) {
      return "Errore durante l'azzeramento";
    }
    dtcVal = "0 (OK)";
    return "Comando reset inviato con successo";
  }

  /// Ciclo di polling periodico ottimizzato per evitare conflitti sul bus
  Future<void> pollEcu(ObdService obd, String ecu, int tick) async {
    // Al primo tick puliamo i parametri specifici per evitare cross-data tra centraline
    if (tick == 0) {
      param2Val = "---";
      param1Val = "---";
      param3Val = "---";
    }

    // Interrogazione DTC a cadenza controllata (ogni 5 cicli)
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
      // Per tutte le altre ECU leggiamo l'Hardware ID dedicato se non ancora acquisito
      if (param2Val == "---" || param2Val == "N/D") {
        param2Val = await readHardwarePartCode(obd, ecu);
      }
      
      String volt = _parse(await obd.queryObd("ATRV\r"), null, "---", isVolt: true);
      param1Val = volt;

      if (ecu == "Body Computer") {
        bcmBatteryVoltVal = volt;
        fuelVal = "---"; // Evita letture PID motore su nodi non compatibili
      }
      if (ecu == "Quadro Strumenti") {
        ipcVoltVal = volt;
      }
      
      param3Val = param2Val != "N/D" ? "Connesso" : "In attesa";
    }
  }

  /// Parser matematico standard SAE J1979 per PID numerici
  String _parse(String data, double Function(int, int)? formula, String def, {bool isVolt = false, int decimals = 1}) {
    if (data.contains("NO DATA") || data.contains("STOPPED")) return def;
    if (isVolt && data.contains("V")) return data.replaceAll(RegExp(r'[^0-9.]'), '');
    if (data.contains("7F") && !data.contains("78")) return def;
    
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

  /// Parser robusto per flussi UDS multi-frame e conversione ASCII pulita
  String _parseAscii(String data) {
    if (data.contains("NO DATA") || data.contains("STOPPED")) return "";
    
    // Rimuove i metadati di sequenza ISO-TP (es. 0:, 1:, 2:) e codici CAN spuri
    data = data.replaceAll(RegExp(r'[0-9]:'), ' ');
    data = data.replaceAll(RegExp(r'\b[0-9A-Fa-f]{3}\b'), ' ');
    data = data.replaceAll("\r", " ").replaceAll("\n", " ").replaceAll(">", " ").trim();
    data = data.replaceAll(RegExp(r'\s+'), ' ');
    
    List<String> hex = data.split(" ");
    String ascii = "";
    
    int startIdx = 0;
    // Cerca l'header di risposta positiva UDS (62 per DID o 49 per Info veicolo)
    for (int i = 0; i < hex.length; i++) {
      if ((hex[i] == "62" || hex[i] == "49") && i + 2 < hex.length) {
        startIdx = i + 3; 
        break;
      }
    }

    for (int i = startIdx; i < hex.length; i++) {
      if (hex[i].length == 2) {
        int? val = int.tryParse(hex[i], radix: 16);
        // Filtra solo caratteri stampabili ASCII validi
        if (val != null && val >= 32 && val <= 126) {
          ascii += String.fromCharCode(val);
        }
      }
    }
    return ascii.trim();
  }

  /// Parser diagnostico DTC con gestione dei messaggi di attesa (Response Pending 7F ... 78)
  void _parseDtc(String data) {
    if (data.contains("NO DATA") || data.contains("STOPPED")) {
      dtcVal = "---";
      dtcDetails = "Nessuna risposta.";
      return;
    }

    List<String> hex = data.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll('>', ' ').split(RegExp(r'\s+'));
    hex.removeWhere((e) => e.isEmpty);
    
    int idx = hex.indexOf("59");
    if (idx != -1 && hex.length > idx + 1 && hex[idx+1] == "02") {
      if (hex.length <= idx + 3) {
        dtcVal = "0 (OK)";
        dtcDetails = "Nessun codice errore rilevato.";
      } else {
        dtcVal = "Rilevati";
        dtcDetails = data;
      }
    } else if (data.contains("7F 19 78") || data.contains("78")) {
      dtcVal = "---";
      dtcDetails = "In attesa elaborazione centralina (Response Pending).";
    } else if (data.contains("7F")) {
      dtcVal = "---";
      dtcDetails = "Risposta negativa dalla centralina.";
    } else {
      dtcVal = "---";
      dtcDetails = "Formato dati sconosciuto.";
    }
  }
}
