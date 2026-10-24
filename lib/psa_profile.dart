class PsaProfile {
  // Indirizzi ECU per Citroën C3 (2019) 1.5 BlueHDi
  static const Map<String, String> ecuIds = {
    "7E0": "Centralina Motore (1.5 BlueHDi)", // Indirizzo CAN 11-bit standard
    "BSI": "BSI (Body Computer PSA)",         // Placeholder per nodi proprietari
  };

  // PID standard per il 1.5 BlueHDi (Servizio 01)
  static const Map<String, String> pids = {
    "01 0C": "Giri Motore (RPM)",
    "01 0D": "Velocità (km/h)",
    "01 05": "Temperatura Liquido Raffreddamento",
    "01 0B": "Pressione Assoluta Collettore (MAP)",
    "01 10": "Flusso Aria (MAF)",
    "01 33": "Pressione Barometrica",
    "01 23": "Pressione Rail Carburante",
  };
}
