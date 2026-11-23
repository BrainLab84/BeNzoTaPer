import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_core/tapering_core.dart' show LeftResult;

import 'hilfen.dart';

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Erster Tag: Karten, wie geplant eintragen', (t) async {
    final app = await starte(t);
    expect(txt('Trag zuerst ein, was du gerade da hast'), findsOneWidget, reason: 'Vorrat steht unten in Heute');
    expect(txt('Stufe 1 von'), findsOneWidget);
    expect(find.byKey(const Key('dosis')), findsOneWidget);
    expect(txt('Nächste Stufe in 14 Tagen (24.03.2026)'), findsOneWidget);
    expect(find.byKey(const Key('wochenKarte')), findsNothing, reason: 'Wochen-Ø steht im Kalender');
    expect(txt('Tagebuch heute'), findsNothing, reason: 'steht jetzt im Fortschritt');
    expect(titel('Heute eintragen'), findsOneWidget, reason: 'Eintragen steht in Heute');
    expect(find.byKey(const Key('fortschrittBlase')), findsOneWidget);
    expect(txt('Tag 1/14'), findsOneWidget);

    expect(find.byKey(const Key('wieGeplant')), findsNothing, reason: 'nur noch ein Knopf „Einnahme“');
    await nehme(t, '10');
    expect(app.taper.st.log['2026-03-10']!.dose, 10);
    expect(app.taper.st.log['2026-03-10']!.it.single.t, '12:00', reason: 'Uhrzeit automatisch');
    expect(txt('Tagesdosis komplett – im Plan.'), findsOneWidget);
    expect(find.byKey(const Key('einnahme')), findsOneWidget, reason: 'weitere Einnahme jederzeit');
    // Heutiger Tag zählt erst mit, wenn er komplett ist – ist er: 10 mg.
    await reiter(t, 'Kalender');
    expect(find.byKey(const Key('wochenschnitt')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('wochenschnitt'))).data, 'Ø 10');
    expect(t.widget<Text>(find.byKey(const Key('liveSchnitt'))).data, 'Ø 10');
  });

  testWidgets('Aufgeteilt: morgens und abends, je mit eigener Uhrzeit; Löschen', (t) async {
    final app = await starte(t);
    jetzt = DateTime.utc(2026, 3, 10, 8, 15);
    app.auffrischen();
    await nehme(t, '4,5');
    expect(app.taper.st.log['2026-03-10']!.dose, 4.5);
    expect(txt('bisher 4,5 von 10 mg'), findsOneWidget);
    expect(find.text('08:15'), findsWidgets, reason: 'Uhrzeit = jetzt');
    jetzt = DateTime.utc(2026, 3, 10, 20, 30);
    await nehme(t, '5,5');
    expect(app.taper.st.log['2026-03-10']!.dose, 10);
    expect([for (final i in app.taper.st.log['2026-03-10']!.it) i.t], ['08:15', '20:30']);
    expect(find.byKey(const Key('mehrAlsGeplant')), findsNothing, reason: 'genau im Plan: Häkchen');
    expect(txt('Tagesdosis komplett – im Plan.'), findsOneWidget);

    await tippe(t, find.byTooltip('Einnahme löschen').first);
    expect(app.taper.st.log['2026-03-10']!.dose, 5.5);
    await tippe(t, find.byTooltip('Einnahme löschen').first);
    expect(app.taper.st.log['2026-03-10'], isNull);
    expect(find.byKey(const Key('einnahme')), findsOneWidget);
  });

  testWidgets('Ungültige Menge: Fenster bleibt offen, nichts eingetragen; Abbrechen', (t) async {
    final app = await starte(t);
    await nehme(t, 'abc');
    expect(find.byKey(const Key('einnahmeDialog')), findsOneWidget);
    expect(app.taper.st.log, isEmpty);
    await tippe(t, find.text('Abbrechen'));
    expect(find.byKey(const Key('einnahmeDialog')), findsNothing);
    expect(app.taper.st.log, isEmpty);
  });

  testWidgets('Mehr als geplant: Kurz innehalten → Doch nicht / Eintragen / Warten', (t) async {
    final app = await starte(t);
    await nehme(t, '10');
    await nehme(t, '2');
    expect(find.text('Kurz innehalten'), findsWidgets);
    expect(txt('wären es heute 12 statt 10 mg.'), findsOneWidget);

    await tippe(t, find.text('Doch nicht'));
    expect(app.taper.st.log['2026-03-10']!.dose, 10);

    await nehme(t, '2');
    await tippe(t, find.text('Eintragen'));
    expect(app.taper.st.log['2026-03-10']!.dose, 12);
    expect(app.taper.st.log['2026-03-10']!.r, 'lapse');
    // Danach einmal das Fenster „Mehr als geplant“ mit OK.
    expect(find.byKey(const Key('mehrAlsGeplant')), findsOneWidget);
    expect(txt('Mehr als geplant – das kommt vor.'), findsOneWidget);
    await tippe(t, find.byKey(const Key('mehrAlsGeplantOk')));
    expect(find.byKey(const Key('mehrAlsGeplant')), findsNothing);
    expect(txt('genommen statt 10.'), findsOneWidget);
    expect(txt('Morgen gilt wieder 10 mg. Ein Tag ändert den Wochen-Ø nur wenig.'), findsOneWidget);

    // Weitere Einnahme am selben Tag: innehalten ja, das Fenster nicht nochmal.
    await nehme(t, '1');
    await tippe(t, find.text('Eintragen'));
    expect(app.taper.st.log['2026-03-10']!.dose, 13);
    expect(find.byKey(const Key('mehrAlsGeplant')), findsNothing, reason: 'nur einmal pro Tag');

    await nehme(t, '1');
    await t.tap(find.text('Erst 15 Minuten warten'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(txt('Noch durchhalten'), findsOneWidget);
    expect(find.byKey(const Key('sosRest')), findsOneWidget);
    expect((t.widget<Text>(find.byKey(const Key('sosRest'))).data)!, matches(RegExp(r'^1[45]:\d\d$')));
    expect(app.taper.st.log['2026-03-10']!.dose, 13, reason: 'Warten trägt nichts ein');
    await t.tap(find.text('Zurück'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('sosRest')), findsNothing);
  });

  testWidgets('Mehr als geplant beim Nachtragen: nur das Fenster, kein Innehalten; im Plan kein Fenster', (t) async {
    final app = await starte(t, json: basis(log: {for (var d = 1; d <= 8; d++) '2026-03-0$d': eintrag(10, 10)}));
    await tippe(t, find.byKey(const Key('streifen-2026-03-09')));
    await t.enterText(find.byKey(const Key('nachMenge')), '9');
    await tippe(t, find.byKey(const Key('nachPlus')));
    expect(app.taper.st.log['2026-03-09']!.r, 'ok');
    expect(find.byKey(const Key('mehrAlsGeplant')), findsNothing, reason: 'im Plan');
    await t.enterText(find.byKey(const Key('nachMenge')), '3');
    await tippe(t, find.byKey(const Key('nachPlus')));
    expect(find.text('Kurz innehalten'), findsNothing, reason: 'Innehalten nur für heute');
    expect(app.taper.st.log['2026-03-09']!.r, 'lapse');
    expect(find.byKey(const Key('mehrAlsGeplant')), findsOneWidget);
    await tippe(t, find.byKey(const Key('mehrAlsGeplantOk')));
    expect(find.byKey(const Key('mehrAlsGeplant')), findsNothing);
  });

  testWidgets('Stufenlinie: ein Strich pro Tag im aktuellen Abschnitt, vergangene hell, Marker wandert', (t) async {
    // Stufe seit 05.03., heute 10.03. = Tag 6/14
    final app = await starte(t, json: basis(start: '2026-03-05', log: {for (var d = 5; d <= 9; d++) '2026-03-0$d': eintrag(10, 10)}));
    final karte = find.byKey(const Key('dosis')).evaluate().isNotEmpty;
    expect(karte, isTrue);
    Color farbe(int j) => ((t.widget<DecoratedBox>(find.descendant(
                of: find.byKey(Key('strich$j')).first, matching: find.byType(DecoratedBox)))
            .decoration) as BoxDecoration)
        .color!;
    expect(find.byKey(const Key('strich13')), findsWidgets, reason: '13 Striche für 14 Tage');
    expect(find.byKey(const Key('strich14')), findsNothing);
    expect(farbe(5), const Color(0xE6FFFFFF), reason: '5 Tage vorbei');
    expect(farbe(6), const Color(0x99AFAADB), reason: 'heute und später noch offen');
    expect(txt('Tag 6/14'), findsWidgets);
    final vorher = t.getTopLeft(find.byKey(const Key('fortschrittBlase')).first).dx;
    jetzt = DateTime.utc(2026, 3, 11, 12);
    app.taper.addIntake(10, k: '2026-03-10', force: true);
    app.auffrischen();
    await t.pumpAndSettle();
    expect(farbe(6), const Color(0xE6FFFFFF), reason: 'ein Tag weiter');
    expect(t.getTopLeft(find.byKey(const Key('fortschrittBlase')).first).dx, greaterThan(vorher),
        reason: 'Marker wandert mit');
    expect(app.taper.st.stage, 0);
  });

  testWidgets('Live-Ø seit Stufenbeginn: ändert sich mit jedem Eintrag', (t) async {
    final app = await starte(t);
    await reiter(t, 'Kalender');
    expect(txt('In dieser Stufe noch kein abgeschlossener Tag.'), findsOneWidget);
    await reiter(t, 'Heute');
    await nehme(t, '10');
    await reiter(t, 'Kalender');
    expect(find.text('Ø 10'), findsNWidgets(2), reason: 'Live und diese Woche');
    expect(txt('genau im Plan (10 mg) · 1 Tag'), findsOneWidget);
    jetzt = DateTime.utc(2026, 3, 11, 9);
    app.auffrischen();
    await reiter(t, 'Heute');
    await nehme(t, '10');
    await nehme(t, '5');
    await tippe(t, find.text('Eintragen'));
    await tippe(t, find.byKey(const Key('mehrAlsGeplantOk')));
    await reiter(t, 'Kalender');
    expect(t.widget<Text>(find.byKey(const Key('liveSchnitt'))).data, 'Ø 12,5');
    expect(txt('nur 2,5 mg über Plan (10 mg) · 2 Tage'), findsOneWidget);
  });

  testWidgets('Halten 7 Tage: angezeigtes „bis“ ist der letzte Haltetag (Audit 20.11.)', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('halten')));
    await t.enterText(find.byKey(const Key('haltenTage')), '7');
    await tippe(t, find.byKey(const Key('haltenStart')));
    expect(txt('gehalten bis 16.03.2026 (7 Tage noch)'), findsOneWidget);
    jetzt = DateTime.utc(2026, 3, 16, 20);
    app.auffrischen();
    await t.pumpAndSettle();
    expect(app.taper.st.hold, isTrue, reason: '16.03. = letzter Haltetag');
    expect(txt('gehalten bis 16.03.2026 (1 Tag noch)'), findsOneWidget);
    jetzt = DateTime.utc(2026, 3, 17, 8);
    app.auffrischen();
    await t.pumpAndSettle();
    expect(app.taper.st.hold, isFalse, reason: '17.03. = es geht weiter');
    expect(txt('gehalten bis'), findsNothing);
  });

  testWidgets('Dosis halten mit Tagen, dann weiter abdosieren', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('halten')));
    expect(txt('Wie viele Tage willst du die Dosis halten?'), findsOneWidget);
    await t.enterText(find.byKey(const Key('haltenTage')), '0');
    await tippe(t, find.byKey(const Key('haltenStart')));
    expect(app.taper.st.hold, isFalse, reason: '0 Tage ungültig');
    await t.enterText(find.byKey(const Key('haltenTage')), '7');
    await tippe(t, find.byKey(const Key('haltenStart')));
    expect(app.taper.st.hold, isTrue);
    // letzter gehaltener Tag (10.–16.03. = 7 Tage); am 17.03. kommt die nächste Dosis.
    expect(txt('Dosis wird voraussichtlich gehalten bis 16.03.2026 (7 Tage noch).'), findsOneWidget);
    expect(find.byKey(const Key('anpassen')), findsOneWidget, reason: 'Plan anpassen geht auch beim Halten');
    expect(txt('Weiter abdosieren'), findsOneWidget);
    await tippe(t, find.byKey(const Key('halten')));
    expect(app.taper.st.hold, isFalse);
    expect(txt('Nächste Stufe in 14 Tagen'), findsOneWidget);
  });

  testWidgets('Ohne Enddatum halten; Abbrechen', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('halten')));
    await tippe(t, find.text('Abbrechen'));
    expect(find.byKey(const Key('haltenTage')), findsNothing);
    await tippe(t, find.byKey(const Key('halten')));
    await tippe(t, find.text('Ohne Enddatum halten'));
    expect(app.taper.st.hold, isTrue);
    expect(app.taper.st.holdUntil, isNull);
    expect(txt('Dosis wird gehalten – so lange du brauchst.'), findsOneWidget);
  });

  testWidgets('Alte Vormerkung „Stufe verlängern“ (frühere Version): Anzeige und Übernahme nach 48 h', (t) async {
    final app = await starte(t);
    await nehme(t, '10');
    expect(app.taper.saveLeft(3), LeftResult.applied);
    app.aenderung();
    await t.pumpAndSettle();
    expect(txt('Nächste Stufe in 3 Tagen (13.03.2026)'), findsOneWidget);
    // So entstand eine Vormerkung bis v0.2.1 (länger nur mit Begründung, 48 h).
    expect(app.taper.saveLeft(20, why: 'ab'), LeftResult.whyTooShort);
    expect(app.taper.saveLeft(20, why: 'Arbeit stressig'), LeftResult.pended);
    app.aenderung();
    await t.pumpAndSettle();
    expect(app.taper.st.pend, isNotNull);
    expect(txt('Vorgemerkte Änderung'), findsOneWidget);
    expect(txt('Grund: Arbeit stressig'), findsOneWidget);
    expect(txt('Frühestens in 48 Stunden.'), findsOneWidget);
    expect(txt('Nächste Stufe in 3 Tagen'), findsOneWidget, reason: 'bis dahin gilt der alte Plan');

    // 49 Stunden später (Tag 2 der Stufe): übernehmen.
    jetzt = DateTime.utc(2026, 3, 12, 13);
    app.auffrischen();
    await t.pumpAndSettle();
    expect(titel('Offene Tage'), findsOneWidget, reason: 'gestern fehlt');
    expect(txt('Gestern fehlt.'), findsOneWidget);
    app.taper.addIntake(10, k: '2026-03-11');
    app.auffrischen();
    await t.pumpAndSettle();
    expect(txt('Die Bedenkzeit ist vorbei.'), findsOneWidget);
    await tippe(t, find.text('Übernehmen'));
    expect(app.taper.st.pend, isNull);
    expect(txt('Nächste Stufe in 20 Tagen'), findsNothing, reason: 'zwei Tage vergangen');
    expect(txt('Nächste Stufe in 18 Tagen'), findsOneWidget);
  });

  testWidgets('Plan anpassen abbrechen: nichts ändert sich', (t) async {
    final app = await starte(t);
    final vorher = app.taper.st.toJson().toString();
    await tippe(t, find.byKey(const Key('anpassen')));
    await t.enterText(find.byKey(const Key('anpTage0')), '30');
    await tippe(t, find.text('Abbrechen'));
    expect(find.byKey(const Key('anpSpeichern')), findsNothing);
    expect(find.byKey(const Key('anpassen')), findsOneWidget);
    expect(app.taper.st.toJson().toString(), vorher);
  });

  testWidgets('Offene Tage: Anzeigen pausieren, nachtragen im Kalender', (t) async {
    final app = await starte(t,
        json: basis(log: {
          for (var d = 1; d <= 6; d++) '2026-03-0$d': eintrag(10, 10),
        }));
    expect(app.taper.st.frz, isNotNull);
    expect(txt('3 Tage ohne Eintrag.'), findsOneWidget);
    expect(find.byKey(const Key('dosis')), findsNothing, reason: 'Dosis-Karte weg');
    expect(titel('Heute eintragen'), findsNothing);
    expect(txt('Nachtragen: 07.03.2026 (+2 weitere)'), findsOneWidget);

    // Springt in den Kalender und öffnet den Tag im Fenster von unten.
    await tippe(t, find.byKey(const Key('nachtragenOffen')));
    expect(find.byKey(const Key('monat')), findsOneWidget);
    expect(titel('Auswertung pausiert'), findsOneWidget, reason: 'Wochen-Ø im Kalender pausiert');
    expect(find.byKey(const Key('tagFenster')), findsOneWidget);
    expect(find.text('07.03.2026'), findsOneWidget, reason: 'Kopf des Tag-Fensters');
    expect(txt('Nichts eingetragen.'), findsOneWidget);
    await tippe(t, find.text('Nachtragen: 10 mg wie geplant'));
    expect(app.taper.st.log['2026-03-07']!.dose, 10);
    expect(txt('im Plan'), findsOneWidget);
    expect(txt('2 Tage ohne Eintrag.'), findsOneWidget, reason: 'Karte auch im Kalender');

    // Schließen, dann über „Nachtragen“ der Karte im Kalender den nächsten Tag.
    await tippe(t, find.byTooltip('Schließen'));
    expect(find.byKey(const Key('tagFenster')), findsNothing);
    await tippe(t, find.byKey(const Key('nachtragenOffen')));
    expect(find.text('08.03.2026'), findsOneWidget);
    await t.enterText(find.byKey(const Key('nachMenge')), '9,5');
    await tippe(t, find.byKey(const Key('nachPlus')));
    expect(app.taper.st.log['2026-03-08']!.dose, 9.5);
    expect(txt('Gestern fehlt.'), findsOneWidget);
    await tippe(t, find.byTooltip('Schließen'));

    await reiter(t, 'Heute');
    expect(txt('Gestern fehlt.'), findsOneWidget);
    // Über den Wochenstreifen.
    await tippe(t, find.byKey(const Key('streifen-2026-03-09')));
    expect(find.text('09.03.2026'), findsOneWidget);
    await tippe(t, find.text('Nachtragen: 10 mg wie geplant'));
    expect(app.taper.st.frz, isNull);
    expect(titel('Offene Tage'), findsNothing);
    await tippe(t, find.byTooltip('Schließen'));
    await reiter(t, 'Heute');
    expect(find.byKey(const Key('dosis')), findsOneWidget);
    expect(titel('Offene Tage'), findsNothing);
    expect(titel('Heute eintragen'), findsOneWidget, reason: 'nach dem Nachtragen wieder eintragbar');
  });

  testWidgets('Offene Tage älter als 7: „Weiß ich nicht mehr“ mit Rückfrage', (t) async {
    final app = await starte(t,
        json: basis(start: '2026-02-20', log: {
          for (var d = 20; d <= 25; d++) '2026-02-$d': eintrag(10, 10),
          for (var d = 3; d <= 9; d++) '2026-03-0$d': eintrag(10, 10),
        }));
    expect(txt('5 Tage ohne Eintrag.'), findsOneWidget);
    expect(txt('5 Tage liegen mehr als 7 Tage zurück'), findsOneWidget);
    expect(find.byKey(const Key('nachtragenOffen')), findsNothing);
    await tippe(t, find.text('Weiß ich nicht mehr'));
    expect(txt('Sicher? Diese Tage bleiben dauerhaft ein ?'), findsOneWidget);
    await tippe(t, find.text('Abbrechen'));
    expect(app.taper.st.unk, isEmpty);
    await tippe(t, find.text('Weiß ich nicht mehr'));
    await tippe(t, find.text('Ja, weiß ich nicht mehr'));
    expect(app.taper.st.unk.length, 5);
    expect(app.taper.st.frz, isNull);
    expect(find.byKey(const Key('dosis')), findsOneWidget);
    await reiter(t, 'Kalender');
    expect(txt('Ø der eingetragenen Tage'), findsOneWidget);
  });

  testWidgets('Vorrat unten in Heute: Anzahl × Stärke, sofort ausgerechnet, Nachkauf; Warnung oben', (t) async {
    final app = await starte(t);
    expect(txt('Trag zuerst ein, was du gerade da hast'), findsOneWidget);
    await reiter(t, 'Plan');
    expect(find.byKey(const Key('vorratKarte')), findsNothing, reason: 'nicht mehr im Plan-Reiter');
    await reiter(t, 'Heute');
    await t.enterText(find.byKey(const Key('anzahl0')), '20');
    await t.enterText(find.byKey(const Key('staerke0')), '5');
    await t.pumpAndSettle();
    // Sofort: mg und Reichweite beim aktuellen Plan (100 mg, 14 Tage à 10 → 10 Tage, heute bis 19.3.).
    expect(find.text('= 100 mg · beim aktuellen Plan reicht ca. 10 Tage (bis 19.03.2026)'), findsOneWidget);
    await tippe(t, find.byKey(const Key('staerkePlus')));
    await t.enterText(find.byKey(const Key('staerke1')), '2,5');
    await t.pumpAndSettle();
    expect(find.text('= 100 mg · beim aktuellen Plan reicht ca. 10 Tage (bis 19.03.2026)'), findsOneWidget,
        reason: 'Zeile ohne Anzahl zählt nicht mit');
    await tippe(t, find.byKey(const Key('vorratSpeichern')));
    expect(app.taper.st.tabs!.str, [5, 2.5], reason: 'Stärken nur einmal eingegeben, mitgespeichert');
    expect(app.taper.st.stock!.mg, 100);
    // 100 mg: 14 Tage à 10 = 140 > 100 → 10 Tage (heute bis 19.03.).
    expect(find.text('Reicht noch ca. 10 Tage (bis 19.03.2026)'), findsNWidgets(2), reason: 'Karte + Warnung oben');
    expect(txt('Rest: 100 mg (≈ 20 Tbl à 5)'), findsOneWidget);

    // Oben die Warnung (≤ 14 Tage), mit Tablettenkombination auf der Dosis-Karte.
    expect(find.byKey(const Key('vorratWarnung')), findsOneWidget);
    expect(find.text('Reicht noch ca. 10 Tage (bis 19.03.2026)'), findsNWidgets(2), reason: 'Warnung + Karte');
    expect(txt('2 × 5 mg'), findsOneWidget, reason: 'Tablettenkombination für 10 mg');
    await tippe(t, find.byKey(const Key('vorratWarnung')));
    expect(find.byKey(const Key('vorratKarte')), findsOneWidget, reason: 'Warnung scrollt zur Vorrat-Karte');

    await tippe(t, find.text('VORRAT ÄNDERN'));
    await t.enterText(find.byKey(const Key('anzahl0')), '20');
    await t.pumpAndSettle();
    expect(txt('Als Nachkauf dazu: reicht ca. 20 Tage'), findsOneWidget);
    await tippe(t, find.byKey(const Key('nachkauf')));
    expect(app.taper.st.stock!.mg, 200);
    expect(find.byKey(const Key('vorratWarnung')), findsNothing, reason: 'reicht jetzt über 14 Tage');

    jetzt = DateTime.utc(2026, 3, 10, 12, 1); // Einnahme nach dem Zählen
    await nehme(t, '10');
    expect(txt('Rest: 190 mg'), findsOneWidget, reason: 'Einnahme wird abgezogen');
  });

  testWidgets('Vorrat überzogen: ehrlicher Hinweis, Nachkauf-Vorschau = Ergebnis nach dem Speichern', (t) async {
    final app = await starte(t);
    app.taper.setStock(1, 10); // 10 mg gezählt
    jetzt = DateTime.utc(2026, 3, 10, 12, 1);
    app.taper.addIntake(10, force: true);
    app.taper.addIntake(20, force: true); // 20 mg mehr als gezählt
    app.aenderung();
    await t.pumpAndSettle();
    expect(app.taper.stockInfo()!.rem, -20);
    expect(txt('Rest: 0 mg'), findsOneWidget);
    expect(find.byKey(const Key('vorratUeberzogen')), findsOneWidget);
    expect(txt('Rechnerisch 20 mg mehr genommen als gezählt'), findsOneWidget);
    await tippe(t, find.text('VORRAT ÄNDERN'));
    await t.enterText(find.byKey(const Key('anzahl0')), '10');
    await t.enterText(find.byKey(const Key('staerke0')), '10');
    await t.pumpAndSettle();
    // 100 dazu → 80 mg: heute ist schon alles genommen (zählt mit), ab morgen 8 × 10 mg → 9 Tage, bis 18.03.
    expect(txt('Als Nachkauf dazu: reicht ca. 9 Tage (bis 18.03.2026)'), findsOneWidget);
    await tippe(t, find.byKey(const Key('nachkauf')));
    expect(app.taper.stockInfo()!.rem, 80);
    expect(find.byKey(const Key('vorratUeberzogen')), findsNothing);
    expect(txt('Reicht noch ca. 9 Tage (bis 18.03.2026)'), findsWidgets);
  });

  testWidgets('Tagebuch heute: Befinden + Notiz speichern, guter Tag', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('sym3')));
    await schreibe(t, find.byKey(const Key('notiz')), '4 Kaffee');
    await tippe(t, find.byKey(const Key('notizSpeichern')));
    final n = app.taper.st.notes['2026-03-10']!;
    expect(n.sym, 3);
    expect(n.text, '4 Kaffee');
    expect(find.byKey(const Key('notizVersteckt')), findsOneWidget, reason: 'nach dem Speichern ausgeblendet');
    expect(find.text('4 Kaffee'), findsNothing);
    expect(find.byKey(const Key('notiz')), findsNothing);
    await tippe(t, find.text('Heute war ein guter Tag'));
    expect(app.taper.st.good, contains('2026-03-10'));
    expect(find.text('Guter Tag'), findsOneWidget);
    await tippe(t, find.text('Guter Tag'));
    expect(app.taper.st.good, isEmpty);
  });

  testWidgets('Notiz im Tag-Fenster: unter dem Kalender nur vermerkt, im Tag-Fenster lesbar', (t) async {
    await starte(t);
    await tippe(t, find.byKey(const Key('streifen-2026-03-10')));
    expect(find.byKey(const Key('monat')), findsOneWidget);
    final fenster = find.byKey(const Key('tagFenster'));
    expect(find.descendant(of: fenster, matching: find.text('Notizen für heute')), findsOneWidget);
    await t.enterText(find.descendant(of: fenster, matching: find.byKey(const Key('notiz'))), 'Kopfweh');
    await tippe(t, find.descendant(of: fenster, matching: find.byKey(const Key('notizSpeichern'))));
    await tippe(t, find.byTooltip('Schließen'));
    final unten = find.byKey(const Key('tagebuchHeute'));
    expect(find.descendant(of: unten, matching: find.byKey(const Key('notizVersteckt'))), findsOneWidget);
    expect(find.text('Kopfweh'), findsNothing, reason: 'unter dem Kalender nicht angezeigt');
    // Tag antippen: dort steht sie zum Lesen und Bearbeiten.
    await tippe(t, find.byKey(const Key('streifen-2026-03-10')));
    expect(find.descendant(of: fenster, matching: find.byKey(const Key('notizLesen'))), findsOneWidget);
    expect(find.descendant(of: fenster, matching: find.text('Kopfweh')), findsOneWidget);
  });

  testWidgets('Mitternacht: neuer Tag, neue Stufe als Banner', (t) async {
    final app = await starte(t,
        json: basis(start: '2026-02-25', log: {
          for (var d = 25; d <= 28; d++) '2026-02-$d': eintrag(10, 10),
          for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(10, 10),
          '2026-03-10': eintrag(10, 10),
        }));
    expect(txt('Nächste Stufe morgen (11.03.2026)'), findsOneWidget);
    jetzt = DateTime.utc(2026, 3, 11, 0, 5);
    app.auffrischen();
    await t.pumpAndSettle();
    expect(app.taper.st.stage, 1);
    expect(txt('Neue Stufe ab heute:'), findsOneWidget);
    expect(txt('9 mg pro Tag'), findsOneWidget);
    expect(find.byKey(const Key('einnahme')), findsOneWidget);
    jetzt = DateTime.utc(2026, 3, 12, 9);
    app.auffrischen();
    await t.pumpAndSettle();
    expect(txt('Neue Stufe seit gestern:'), findsOneWidget);
  });

  testWidgets('Ziel erreicht: 0 mg, Nachsorge, „Heute nichts genommen“', (t) async {
    final j = basis(start: '2026-02-20', plan: [1, 0]);
    j['stage'] = 1;
    j['stageStart'] = '2026-03-08';
    j['log'] = {
      for (var d = 20; d <= 28; d++) '2026-02-$d': eintrag(1, 1),
      for (var d = 1; d <= 7; d++) '2026-03-0$d': eintrag(1, 1),
      for (var d = 8; d <= 9; d++) '2026-03-0$d': eintrag(0, 0, stage: 1),
    };
    final app = await starte(t, json: j);
    expect(txt('Ziel erreicht'), findsOneWidget);
    expect(titel('Nachsorge'), findsOneWidget);
    expect(txt('bei 0 mg'), findsOneWidget);
    expect(txt('Tag 3'), findsWidgets);
    expect(find.byKey(const Key('halten')), findsNothing, reason: 'letzte Stufe: kein Halten');
    await tippe(t, find.text('Heute nichts genommen'));
    expect(app.taper.st.log['2026-03-10']!.dose, 0);
    expect(txt('Heute nichts genommen – im Plan.'), findsOneWidget);
  });

  testWidgets('Rückfall nach 0 mg: Kurz innehalten', (t) async {
    final j = basis(start: '2026-03-01', plan: [1, 0]);
    j['stage'] = 1;
    j['stageStart'] = '2026-03-09';
    j['log'] = {
      for (var d = 1; d <= 8; d++) '2026-03-0$d': eintrag(1, 1),
      '2026-03-09': eintrag(0, 0, stage: 1),
    };
    final app = await starte(t, json: j);
    await nehme(t, '0,5');
    expect(txt('wären es heute 0,5 statt 0 mg.'), findsOneWidget);
    await tippe(t, find.text('Eintragen'));
    expect(app.taper.st.log['2026-03-10']!.r, 'lapse');
  });

  testWidgets('Wochenstreifen: Tage vor dem Start leer und nicht tippbar', (t) async {
    await starte(t);
    final vorStart = find.byKey(const Key('streifen-2026-03-08'));
    expect(vorStart, findsOneWidget);
    await t.tap(vorStart);
    await t.pumpAndSettle();
    expect(find.text('08.03.2026'), findsNothing);
  });

  testWidgets('Gespeicherter Stand nach Eintrag (JSON)', (t) async {
    final app = await starte(t);
    await nehme(t, '10');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    final raw = (app.store as MemStore).state!;
    final j = jsonDecode(raw) as Map;
    expect((j['log'] as Map).containsKey('2026-03-10'), isTrue);
  });

  testWidgets('Vorrat-Warnung: genau bei 14 Tagen an, bei 15 aus; folgt Nachkauf und Einnahmen', (t) async {
    final app = await starte(t); // 10 mg pro Tag, heute noch nichts genommen
    app.taper.setStock(150, 1);
    app.aenderung();
    await t.pumpAndSettle();
    expect(app.taper.stockInfo()!.days, 15);
    expect(find.byKey(const Key('vorratWarnung')), findsNothing, reason: '15 Tage: keine Warnung');
    jetzt = jetzt.add(const Duration(minutes: 1));
    app.taper.addIntake(10);
    app.aenderung();
    await t.pumpAndSettle();
    expect(app.taper.stockInfo()!.days, 15, reason: 'heute genommen: Rest 140 reicht heute + 14 Tage');
    app.taper.setStock(130, 1); // heute schon genommen: 130 mg = heute + 13 Tage
    app.aenderung();
    await t.pumpAndSettle();
    expect(app.taper.stockInfo()!.days, 14);
    expect(find.byKey(const Key('vorratWarnung')), findsOneWidget, reason: '14 Tage: Warnung');
    expect(txt('Reicht noch ca. 14 Tage'), findsWidgets);
  });
}
