child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
          Row(children: [const Icon(Icons.check_circle, color: Colors.greenAccent, size: 15), const SizedBox(width: 6), Text("Centralina Attiva: $selectedEcu", style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 4),
          Text(ecuResponseInfo, style: const TextStyle(color: Colors.grey, fontSize: 11)),
         ],
        ),
       ),
       const SizedBox(height: 8),
      ],
      Row(
       children: [
        _ddBox("Marca:", selectedBrand, brandList, (v) => setState(() { selectedBrand = v!; selectedModel = (selectedBrand == "Fiat/Stellantis") ? "Tipo Cross 1.0 T3" : ""; })),
        const SizedBox(width: 8),
        _ddBox("Modello:", selectedModel.isEmpty ? null : selectedModel, isFiat ? ["Tipo Cross 1.0 T3"] : [], isFiat ? (v) => setState(() => selectedModel = v!) : null),
       ],
      ),
      const SizedBox(height: 8),
      Expanded(
       child: isEcuConnected
        ? GridView.count(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.45, children: _cardsForEcu())
        : Center(
           child: Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF161A1D), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.3))),
            child: const Column(
             mainAxisSize: MainAxisSize.min,
             children: [
              Icon(Icons.info_outline, color: Color(0xFFFFB74D), size: 40),
              SizedBox(height: 12),
              Text("Connetti l'adattatore OBD via Bluetooth, scegli marca e modello dell'auto, e scegli la centralina a cui vuoi connetterti.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
             ],
            ),
           ),
          ),
      ),
     ],
    ),
   ),
  );
 }
}