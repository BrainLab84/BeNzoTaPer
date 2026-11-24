// Gleichheit mit eingefrorenen Referenzdaten (test/paritaet/*.json, aufgezeichnet mit einer früheren Fassung):
// Heute und Kalender müssen für dieselben Zustände dieselben Texte zeigen. „Heute eintragen“ steht über dem
// Kalender, „Notizen für heute“ darunter – für „Heute“ werden alle Stellen zusammen geprüft.
// Der Vorrat hat eine neue, einfachere Eingabe und wird nicht mehr verglichen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/heute.dart';
import 'package:tapering_buddy/kalender.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart' show aktuellerReiter;

/// Die App zeigt jedes Datum mit Jahr (TT.MM.JJJJ); die Referenzdaten haben „T.M.“ bzw.
/// „TT.MM.“. Für den Vergleich bekommen die Referenztexte das Jahr, das dem Testtag am nächsten liegt.
String mitJahr(String s, DateTime jetzt) => s.replaceAllMapped(RegExp(r'(?<![\d.])(\d{1,2})\.(\d{1,2})\.(?!\d)'), (m) {
      final t = int.parse(m[1]!), mo = int.parse(m[2]!);
      var j = jetzt.year;
      for (final k in [jetzt.year - 1, jetzt.year + 1]) {
        if (DateTime.utc(k, mo, t).difference(jetzt).abs() < DateTime.utc(j, mo, t).difference(jetzt).abs()) j = k;
      }
      return '${t.toString().padLeft(2, '0')}.${mo.toString().padLeft(2, '0')}.$j';
    });

String norm(String s) => s.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Texte unter [wurzel] – ohne die neue Startkarte oben (Begrüßung, Plan erstellen/importieren),
/// die es in den Referenzdaten nicht gibt.
List<String> texteIn(WidgetTester t, Finder wurzel, {List<String> auchOhne = const []}) {
  // Neu gegenüber den Referenzdaten: Startkarte/Begrüßung, Vorrat-Warnung, Vorrat-Karte (stand dort im
  // Plan-Reiter, jetzt unten in Heute), Befinden-Text.
  final kopf = {
    for (final k in [
      'planKopf',
      'vorratWarnung',
      'vorratKarte',
      'sicherungBanner', // Erinnerung zum Sichern (neu)
      'liveKarte', // Live-Ø seit Stufenbeginn (neu)
      'befindenText',
      'kalenderFortschritt',
      'beispielHinweis',
      ...auchOhne
    ])
      ...find.byKey(Key(k)).evaluate().map((e) => e.widget),
  };
  bool imKopf(Element e) {
    var drin = false;
    e.visitAncestorElements((a) {
      if (kopf.contains(a.widget)) {
        drin = true;
        return false;
      }
      return true;
    });
    return drin;
  }

  final out = <String>[];
  for (final e in find.descendant(of: wurzel, matching: find.byType(RichText)).evaluate()) {
    if (!imKopf(e)) out.add((e.widget as RichText).text.toPlainText());
  }
  for (final e in find.descendant(of: wurzel, matching: find.byType(EditableText)).evaluate()) {
    if (!imKopf(e)) out.add((e.widget as EditableText).controller.text);
  }
  return out;
}

/// Bewusste, kleine Abweichungen (mit Grund).
const erlaubt = <String>{
  // Durch einen neuen Text (BefindenText) ersetzt.
  'Beim Entzug wirkt oft alles paradox. Notiere kurz dein Befinden, so findest du die Ursache für eine plötzliche Verschlechterung. Nicht alles ist Entzug.',
  // Die Referenz setzt die Lösung in eine eigene Zeile, beginnt sie aber mit „· “. Ohne Punkt am Zeilenanfang.
  '· oder 5 ml Lösung',
  // Umbenannt: „Tagebuch heute“ → „Notizen für heute“.
  'Tagebuch heute',
  // Entfernt (Feld hat nur noch einen Platzhalter); im Tag-Fenster stehen
  // Notizen oben, ohne „Befinden“-Überschrift und ohne Links.
  'Notiz zum Befinden (nur wenn was war, z. B. Durchfall, neues Medikament, 4 Kaffee)',
  'Befinden',
  'Mehr dazu:',
  'Befragung zu Langzeitfolgen (PLOS ONE, 2023)',
  'Ashton 1991: verlängerte Symptome',
  '·',
  // Geändert: „voraussichtlich“ bzw. die gehaltene Dosis in mg.
  'Dosis gehalten – Plan pausiert.',
  // „Laut Plan … ab“ → „Voraussichtlich bei … :“ (nichts steht fest).
  'Laut Plan bei 0 mg ab',
  'Laut Plan bei 8 mg ab',
  'Dosis wird gehalten bis 23.11. (4 Tage noch).',
  'Dosis wird gehalten bis 23.11. (7 Tage noch).',
  // Geändert: Knopf heißt „Weiter abdosieren“, Nachsorge nennt „Notizen“ statt „Tagebuch“.
  'Danach geht es automatisch weiter. Bist du früher bereit, drück auf Weiter. Der Plan verschiebt sich automatisch um die gehaltenen Tage nach hinten.',
  'Wenn du bereit bist, weiter abzudosieren, drück auf Weiter. Der Plan verschiebt sich automatisch um die gehaltenen Tage nach hinten.',
  'Nachwellen sind nach dem Absetzen nicht ungewöhnlich und klingen meist ab. Trag weiter ein, auch wenn du nichts genommen hast, dann bleibt auch ein Rückfall nachvollziehbar. Tagebuch, gute Tage und SOS bleiben für dich da.',
  // Gespeicherte Notiz unter dem Kalender nur noch vermerkt (lesbar über den Tag im Kalender).
  'Viel Stress',
  'Gespeichert',
};

/// Bewusst entfallen (mit Grund): Eintragen geht nur noch über „Einnahme“ → Menge → OK, die Uhrzeit
/// speichert sich selbst. „wie geplant genommen“, „Rest genommen“ und das Feld „Menge · Uhrzeit“ mit „+“
/// gibt es in Heute nicht mehr.
final erlaubtMuster = [
  RegExp(r'^[\d,]+ \S+ wie geplant genommen$'),
  RegExp(r'^Rest genommen \([\d,]+ \S+\)$'),
  RegExp(r'^(Weitere|Oder einzelne) Einnahme \(\S+ · Uhrzeit\)$'),
  RegExp(r'^\+$'),
  // „Ändern“ ist „Plan anpassen“ gewichen (eigene Seite, gilt sofort).
  RegExp(r'^Ändern$'),
];

/// Was die neue App zusätzlich zeigen darf: Feldinhalte (Platzhalter, Uhrzeit, Auswahl),
/// die in der Referenz als Attribut statt als Text stehen.
final zusaetzlichErlaubt = [
  RegExp(r'^z\. b\. [\d,]+$'),
  RegExp(r'^\d\d:\d\d$'),
  RegExp(r'^andere menge$'),
  RegExp(r'^--:--$'),
  RegExp(r'^(nur ganz|halbierbar|viertelbar)$'),
  RegExp(r'^à [\d,]+ \S+$'),
  // Überschrift + Hinweis der Notizen
  RegExp(r'^notizen für heute$'),
  RegExp(r'^(notiz|notiz nachtragen|einnahmen)$'),
  RegExp(r'^z\. b\. 4 kaffee, neues medikament$'),
  RegExp(r'^du kannst jederzeit nachtragen'),
  RegExp(r'^einnahme$'),
  RegExp(r'^plan anpassen$'),
  // Hinweis über „Dosis halten“ (geht erst am letzten Stufentag)
  RegExp(r'^wenn die nächste stufe beginnt und du noch nicht bereit bist'),
  RegExp(r'^beginnt morgen die nächste stufe und du bist noch nicht bereit'),
  RegExp(r'^notiz für heute gespeichert\. tipp auf den tag im kalender'),
  // Halten mit „voraussichtlich“ und mg
  RegExp(r'^dosis wird voraussichtlich gehalten bis \d+\.\d+\.\d{4} \(noch \d+ tage?\)\.$'),
  RegExp(r'^(danach geht es automatisch weiter\. bist du früher bereit|wenn du bereit bist), drück auf „weiter abdosieren“\. der plan verschiebt sich'),
  // Zukünftiger Tag im Tag-Fenster: voraussichtliche Dosis statt leerem Fenster
  RegExp(r'^voraussichtlich [\d,]+ mg\. eintragen geht ab diesem tag\.$'),
  RegExp(r'^nachwellen sind nach dem absetzen .* notizen, gute tage und sos bleiben für dich da\.$'),
  RegExp(r'^dosis [\d,]+ mg gehalten – plan pausiert\.$'),
  // immer „voraussichtlich“ statt „Laut Plan … ab“ bzw. „Plan pausiert“
  RegExp(r'^voraussichtlich bei [\d,]+ mg: \d\d\.\d\d\.\d{4}( \(dosis wird gehalten\))?$'),
  RegExp(r'^voraussichtlich\nbei [\d,]+ mg$'),
];

/// Text in Stücke ohne Icons (Material-Icons liegen im privaten Unicode-Bereich, eingebettete Icons als U+FFFC).
List<String> stuecke(String x, {int mindestens = 2}) => x
    .split(RegExp('[\uFFFC\uE000-\uF8FF\u{F0000}-\u{FFFFD}]', unicode: true))
    .map(norm)
    .where((p) => p.length >= mindestens)
    .toList();

void main() {
  for (final (datei, reiterName) in [
    ('heute_js.json', 'Heute'),
    ('kal_js.json', 'Kalender'),
  ]) {
    final daten = jsonDecode(File('test/paritaet/$datei').readAsStringSync()) as List;
    for (final s in daten.cast<Map<String, dynamic>>()) {
      testWidgets('$reiterName wie Referenz: ${s['name']}', (t) async {
        t.view.physicalSize = const Size(1000, 14000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final jetzt = DateTime.fromMillisecondsSinceEpoch(s['ms'] as int, isUtc: true);
        final store = MemStore()
          ..disc = true
          ..state = jsonEncode(s['state']);
        final app = AppState(store, clock: () => jetzt);
        await t.runAsync(app.laden);
        await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
        await t.pump(const Duration(milliseconds: 50));
        await t.pumpAndSettle();
        Future<void> zu(String r) async {
          await t.tap(find.byKey(ValueKey('reiter-$r')));
          await t.pumpAndSettle();
        }

        await zu(reiterName);
        // Bei „Heute“ stehen manche Knöpfe jetzt über dem Kalender oder im Fortschritt: dort suchen.
        final orte = reiterName == 'Heute' ? ['Heute', 'Kalender'] : [reiterName];
        for (final a in (s['aktionen'] as List? ?? const []).cast<String>()) {
          Finder f() => a.startsWith('key:') ? find.byKey(Key(a.substring(4))) : find.text(a.substring(5));
          for (final r in orte) {
            if (f().evaluate().isNotEmpty) break;
            await zu(r);
          }
          // Gespeicherte Notiz ist unter dem Kalender ausgeblendet: nichts mehr zu speichern.
          if (a == 'text:Notiz speichern' && f().evaluate().isEmpty) continue;
          await t.ensureVisible(f().first);
          await t.tap(f().first);
          await t.pumpAndSettle();
        }
        final List<String> texte;
        if (reiterName == 'Heute') {
          // Zuerst den Reiter auslesen, in dem zuletzt getippt wurde (kurze Meldungen wie „Gespeichert“
          // verschwinden beim Reiterwechsel – wie in der Referenz beim Neuzeichnen).
          final bereiche = {
            'Heute': [find.byType(HeuteSeite)],
            'Kalender': [find.byKey(const Key('wochenKarte')), find.byKey(const Key('tagebuchHeute'))],
          };
          final jetztDa = aktuellerReiter(t);
          texte = [for (final b in bereiche[jetztDa]!) ...texteIn(t, b)];
          for (final r in bereiche.keys.where((r) => r != jetztDa)) {
            await zu(r);
            for (final b in bereiche[r]!) {
              texte.addAll(texteIn(t, b));
            }
          }
        } else {
          // Bei offenen Tagen öffnete die Referenz den ersten nachtragbaren Tag von selbst; jetzt öffnet ihn
          // „Nachtragen“ im Fenster (kein Fenster, das beim Öffnen der App von selbst hochspringt).
          if (find.byKey(const Key('tagFenster')).evaluate().isEmpty &&
              find.byKey(const Key('nachtragenOffen')).evaluate().isNotEmpty) {
            await t.ensureVisible(find.byKey(const Key('nachtragenOffen')));
            await t.tap(find.byKey(const Key('nachtragenOffen')));
            await t.pumpAndSettle();
          }
          // Tag-Karte steht im Fenster von unten (`tagFenster`) statt unter dem Monat.
          texte = [
            ...texteIn(t, find.byType(KalenderSeite),
                auchOhne: ['wochenKarte', 'tagebuchHeute', 'kalPlanDatum', 'notizenHinweis']),
            if (find.byKey(const Key('tagFenster')).evaluate().isNotEmpty)
              ...texteIn(t, find.byKey(const Key('tagFenster'))),
          ];
        }
        final alles = norm(texte.join('\n'));
        final fehlt = <String>[
          for (final f in (s['frags'] as List).cast<String>())
            if (!alles.contains(norm(mitJahr(f, jetzt))) && !erlaubt.contains(f) && !erlaubtMuster.any((r) => r.hasMatch(f))) f,
        ];
        expect(fehlt, isEmpty, reason: 'Flutter-Texte:\n${texte.join(' | ')}');
        final js = norm(mitJahr((s['frags'] as List).join('\n'), jetzt));
        final extra = <String>{
          for (final x in texte)
            for (final p in stuecke(x))
              if (!js.contains(p) && !zusaetzlichErlaubt.any((r) => r.hasMatch(p))) p,
        };
        expect(extra, isEmpty, reason: 'Text nur in der neuen App');
        // Kalender: jede Tageszelle einzeln (Tageszahl, ?, Dosis) – prüft auch die Lage.
        final zellen = (s['zellen'] as Map?)?.cast<String, String>() ?? const {};
        final falsch = <String>[];
        zellen.forEach((tag, erwartet) {
          final f = find.byKey(Key('tag-$tag'));
          if (f.evaluate().isEmpty) {
            falsch.add('$tag fehlt');
            return;
          }
          final ist = [
            for (final e in find.descendant(of: f, matching: find.byType(RichText)).evaluate())
              ...stuecke((e.widget as RichText).text.toPlainText(), mindestens: 1),
          ].join(' ');
          if (ist != norm(erwartet)) falsch.add('$tag: Referenz „$erwartet“, neu „$ist“');
        });
        expect(falsch, isEmpty);
      });
    }
  }
}
