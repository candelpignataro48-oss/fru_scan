class StellantisProfile {
  // Deve essere "static" e chiamarsi esattamente "ecuIds" (con la 'e' minuscola e la 'I' maiuscola)
  static const Map<String, String> ecuIds = {
    "10": "Motore (ECM)",
    "21": "ABS / ESP",
    "28": "Servosterzo Elettrico (EPS)",
    "30": "Quadro Strumenti (IPC)",
    "40": "Body Computer (BCM)",
    "50": "Airbag (ORC)",
    "60": "Sensore Imbardata / Moduli Vari",
    "70": "Blind Spot / Sensori Parcheggio (MS-CAN)",
    "98": "Climatizzatore HVAC (MS-CAN)",
    "A0": "Radio / Uconnect (MS-CAN)"
  };

  static const Map<String, String> pids = {
    "01 0C": "Giri Motore (RPM)",
    "01 0D": "Velocità (km/h)",
    "01 05": "Temperatura Liquido Raffreddamento",
    "01 0B": "Pressione Assoluta Collettore (MAP)",
    "01 10": "Flusso Aria (MAF)",
    "01 2F": "Livello Carburante (%)",
    "01 3C": "Temperatura Catalizzatore",
    "01 5C": "Temperatura Olio Motore",
  };
}
