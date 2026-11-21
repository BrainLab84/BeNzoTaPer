// Lob beim Halten: „Stabilität beim Abdosieren ist das A und O.“
// Frühestens nach 3 Tagen, dann nach Zufall alle 3–5 Tage (etwa 5, 8, 12, 15). Die Lob-Tage werden je
// Halten-Phase einmal fest ausgelost (Startdatum = Zufallsstart), damit das Lob beim erneuten Öffnen
// nicht mal da ist und mal nicht. Zwei Texte im Wechsel.
import 'i18n/txt.dart';
import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';

/// Kleiner fester Zufallsgenerator (mulberry32) – überall gleich, unabhängig von der Dart-Version.
class _Zufall {
  _Zufall(this._z);
  int _z;
  int naechste(int n) {
    _z = (_z + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _z;
    t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF;
    t ^= (t + (((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) % n;
  }
}

/// Die Lob-Tage einer Halten-Phase, gezählt in gehaltenen Tagen (Tag 0 = Beginn), bis [bis].
List<int> lobTage(String haltenSeit, {int bis = 400}) {
  final z = _Zufall(int.parse(haltenSeit.replaceAll('-', '')));
  final out = <int>[];
  var d = 3 + z.naechste(3); // erstes Lob nach 3–5 Tagen
  while (d <= bis) {
    out.add(d);
    d += 3 + z.naechste(3); // dann alle 3–5 Tage
  }
  return out;
}

/// Text fürs Lob am Tag [tage] (Nummer [nr] = wievieltes Lob, ab 0) – zwei Texte im Wechsel.
String lobText(int tage, int nr) => nr.isEven
    ? tr('Glückwunsch – $tage Tage gehalten.', 'Congratulations – $tage days held.')
    : tr('Du machst das super – $tage Tage gehalten. Weiter so. Stabilität beim Abdosieren ist das A und O.', 'You are doing great – $tage days held. Keep it up. Stability while tapering is what matters most.');

/// Heutiges Lob oder `null`: nur solange gehalten wird (nie am oder nach dem Enddatum – dann ist schon die
/// nächste Dosis dran), an einem Lob-Tag, ohne Ausrutscher vom letzten Lob-Tag bis gestern, und wenn es heute
/// nicht weggetippt wurde. „N Tage gehalten“ = N abgeschlossene Tage seit Beginn des Haltens. Jede neue Halten-Phase
/// (neue Dosis) zählt wieder ab Tag 0 und lost neu aus.
({String text, String schluessel})? lobHeute(AppState app) {
  final s = app.taper.s;
  if (app.beispiel || s == null || !s.hold || s.holdSince == null) return null;
  final heute = app.taper.today;
  if (s.holdUntil != null && heute.compareTo(s.holdUntil!) >= 0) return null;
  final tage = dBetween(s.holdSince!, heute);
  final liste = lobTage(s.holdSince!, bis: tage);
  final nr = liste.indexOf(tage);
  if (nr < 0) return null;
  // Erarbeitet, nicht geschenkt: Das Lob gilt den abgeschlossenen Tagen und steht ab
  // Mitternacht für den neuen Morgen da – man kann es nicht erst einsacken und dann mehr nehmen.
  // Ist seit dem letzten Lob-Tag (bzw. ab dem Tag nach Beginn des Haltens) bis gestern ein Ausrutscher
  // eingetragen, fällt dieses Lob aus – dann bis zum nächsten durchhalten. Was heute eingetragen wird,
  // zählt schon fürs nächste Lob.
  final ab = nr == 0 ? addD(s.holdSince!, 1) : addD(s.holdSince!, liste[nr - 1]);
  for (var k = ab; k.compareTo(heute) < 0; k = addD(k, 1)) {
    if (s.log[k]?.r == 'lapse') return null;
  }
  final schluessel = '${s.holdSince}|$heute';
  if (app.lobWeg == schluessel) return null;
  return (text: lobText(tage, nr), schluessel: schluessel);
}

/// Karte über „Heute eintragen“: den ganzen Lob-Tag sichtbar, mit X weg.
class LobKarte extends StatelessWidget {
  const LobKarte({super.key, required this.app, required this.text, required this.schluessel});
  final AppState app;
  final String text;
  final String schluessel;
  @override
  Widget build(BuildContext context) => Karte(
        key: const Key('haltenLob'),
        rand: F.acRand,
        padding: const EdgeInsets.fromLTRB(18, 10, 6, 10),
        children: [
          Row(children: [
            const Icon(Icons.spa_outlined, color: F.ok, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              key: const Key('haltenLobWeg'),
              tooltip: tr('Schließen', 'Close'),
              icon: const Icon(Icons.close, color: F.mu),
              onPressed: () => app.lobWegtippen(schluessel),
            ),
          ]),
        ],
      );
}
