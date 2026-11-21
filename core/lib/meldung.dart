// Meldungen des Kerns als Code + Werte. Der Kern kennt keine Sprache: die App macht daraus Text
// (Deutsch/Englisch). So bleibt die Logik testbar, ohne den Wortlaut zu prüfen.

enum MeldungCode {
  // Ersteinrichtung per Rechner / Editor-Rechner
  setupDosis,
  setupSchritt,
  setupWerteZiel,
  werteKurz,
  editWerteZiel,
  stufenBerechnet, // [anzahl]
  // Text auslesen
  keineDosierungen,
  schritteErkannt, // [anzahl, davonGeschaetzt]
  // Editor
  vorgemerktPruefen,
  keineSchritte,
  sicherTippen,
  stufeDosisFehlt, // [nr]
  stufeTageFehlen, // [nr]
  stufeMaxTage, // [nr, max]
  begruenden,
  planZuLang,
  // PIN
  pinZiffern,
  pinUngleich,
  // Abschnitts-Plan; Werte beginnen mit [abschnittNr] (0 = ohne Präfix „Abschnitt N: “)
  abschnittStartdosis,
  abschnittKeiner,
  abschnittSchritt, // [nr]
  abschnittTage, // [nr]
  abschnittMaxTage, // [nr, max]
  abschnittBisFehlt, // [nr]
  abschnittBisNegativ, // [nr]
  abschnittEndetBeiNull, // [vorigeNr]  (der betroffene Abschnitt ist vorigeNr + 1)
  abschnittBisUeberStart, // [nr, wert]
  abschnittBisUeberVorigem, // [nr, wert, vorigeNr]
  abschnittZuViele,
}

class Meldung {
  final MeldungCode code;
  final List<Object> werte;
  const Meldung(this.code, [this.werte = const []]);

  @override
  bool operator ==(Object o) =>
      o is Meldung && o.code == code && o.werte.length == werte.length && _gleich(o.werte, werte);

  static bool _gleich(List<Object> a, List<Object> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(code, Object.hashAll(werte));

  @override
  String toString() => 'Meldung($code${werte.isEmpty ? '' : ', $werte'})';
}
