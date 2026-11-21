import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Erster Tag: Karten, wie geplant eintragen', (t) async {
    final app = await starte(t);
    expect(txt('Trag zuerst ein, was du gerade da hast'), findsNothing, reason: 'Vorrat ist im Plan-Reiter');
    expect(txt('Stufe 1 von'), findsOneWidget);
    expect(find.byKey(const Key('dosis')), findsOneWidget);
    expect(txt('Nächste Stufe in 14 Tagen (24.03.2026)'), findsOneWidget);
    expect(txt('Noch keine Einträge in den letzten 7 Tagen.'), findsOneWidget);
    expect(txt('Tagebuch heute'), findsNothing, reason: 'steht jetzt im Fortschritt');
    expect(titel('Heute eintragen'), findsNothing, reason: 'steht jetzt über dem Kalender');
    expect(find.byKey(const Key('fortschrittBlase')), findsOneWidget);
    expect(txt('Tag 1/14'), findsOneWidget);

    await tippe(t, find.byKey(const Key('wieGeplant')));
    expect(app.taper.st.log['2026-03-10']!.dose, 10);
    expect(txt('Tagesdosis komplett – im Plan.'), findsOneWidget);
    expect(txt('Weitere Einnahme (mg · Uhrzeit)'), findsOneWidget);
    // Heutiger Tag zählt erst mit, wenn er komplett ist – ist er: 10 mg.
    await reiter(t, 'Heute');
    expect(find.byKey(const Key('wochenschnitt')), findsOneWidget);
    expect(txt('Ø 10'), findsOneWidget);
  });

  testWidgets('Teilmenge, Rest genommen, Löschen', (t) async {
    final app = await starte(t);
    await schreibe(t, find.byKey(const Key('menge')), '4,5');
    await tippe(t, find.byKey(const Key('plus')));
    expect(app.taper.st.log['2026-03-10']!.dose, 4.5);
    expect(txt('bisher 4,5 von 10 mg'), findsOneWidget);
    expect(find.text('12:00'), findsWidgets, reason: 'Uhrzeit = jetzt');
    await tippe(t, find.byKey(const Key('rest')));
    expect(app.taper.st.log['2026-03-10']!.dose, 10);
    expect(txt('Tagesdosis komplett – im Plan.'), findsOneWidget);

    await tippe(t, find.byTooltip('Einnahme löschen').first);
    expect(app.taper.st.log['2026-03-10']!.dose, 5.5);
    await tippe(t, find.byTooltip('Einnahme löschen').first);
    expect(app.taper.st.log['2026-03-10'], isNull);
    expect(find.byKey(const Key('wieGeplant')), findsOneWidget);
  });

  testWidgets('Ungültige Menge: rot, nichts eingetragen', (t) async {
    final app = await starte(t);
    await schreibe(t, find.byKey(const Key('menge')), 'abc');
    await tippe(t, find.byKey(const Key('plus')));
    expect(app.taper.st.log, isEmpty);
  });

  testWidgets('Mehr als geplant: Kurz innehalten → Doch nicht / Eintragen / Warten', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('wieGeplant')));
    await schreibe(t, find.byKey(const Key('menge')), '2');
    await tippe(t, find.byKey(const Key('plus')));
    expect(find.text('Kurz innehalten'), findsWidgets);
    expect(txt('wären es heute 12 statt 10 mg.'), findsOneWidget);

    await tippe(t, find.text('Doch nicht'));
    expect(app.taper.st.log['2026-03-10']!.dose, 10);

    await tippe(t, find.byKey(const Key('plus')));
    await tippe(t, find.text('Eintragen'));
    expect(app.taper.st.log['2026-03-10']!.dose, 12);
    expect(app.taper.st.log['2026-03-10']!.r, 'lapse');
    expect(txt('genommen statt 10.'), findsOneWidget);
    expect(txt('Morgen gilt wieder 10 mg. Ein Tag ändert den Wochen-Ø nur wenig.'), findsOneWidget);

    await schreibe(t, find.byKey(const Key('menge')), '1');
    await tippe(t, find.byKey(const Key('plus')));
    await t.tap(find.text('Erst 15 Minuten warten'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(txt('Noch durchhalten'), findsOneWidget);
    expect(find.byKey(const Key('sosRest')), findsOneWidget);
    expect((t.widget<Text>(find.byKey(const Key('sosRest'))).data)!, matches(RegExp(r'^1[45]:\d\d$')));
    expect(app.taper.st.log['2026-03-10']!.dose, 12, reason: 'Warten trägt nichts ein');
    await t.tap(find.text('Zurück'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('sosRest')), findsNothing);
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
    expect(find.byKey(const Key('aendern')), findsNothing);
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

  testWidgets('Ändern: kürzer sofort, länger nur mit Begründung → Vormerkung', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('wieGeplant')));
    await tippe(t, find.byKey(const Key('aendern')));
    expect(txt('In wie vielen Tagen soll die nächste Stufe beginnen?'), findsOneWidget);
    await t.enterText(find.byKey(const Key('linksTage')), '3');
    await tippe(t, find.byKey(const Key('linksOk')));
    expect(txt('Nächste Stufe in 3 Tagen (13.03.2026)'), findsOneWidget);
    expect(app.taper.st.pend, isNull);

    await tippe(t, find.byKey(const Key('aendern')));
    await t.enterText(find.byKey(const Key('linksTage')), '20');
    await tippe(t, find.byKey(const Key('linksOk')));
    expect(txt('48 Stunden Bedenkzeit'), findsOneWidget);
    await t.enterText(find.byKey(const Key('linksWarum')), 'ab');
    await tippe(t, find.byKey(const Key('vormerken')));
    expect(app.taper.st.pend, isNull, reason: 'Begründung zu kurz');
    await t.enterText(find.byKey(const Key('linksWarum')), 'Arbeit stressig');
    await tippe(t, find.byKey(const Key('vormerken')));
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

  testWidgets('Ändern abbrechen', (t) async {
    await starte(t);
    await tippe(t, find.byKey(const Key('aendern')));
    await tippe(t, find.byTooltip('Abbrechen'));
    expect(find.byKey(const Key('linksTage')), findsNothing);
    expect(find.byKey(const Key('aendern')), findsOneWidget);
  });

  testWidgets('Offene Tage: Anzeigen pausieren, nachtragen im Kalender', (t) async {
    final app = await starte(t,
        json: basis(log: {
          for (var d = 1; d <= 6; d++) '2026-03-0$d': eintrag(10, 10),
        }));
    expect(app.taper.st.frz, isNotNull);
    expect(txt('3 Tage ohne Eintrag.'), findsOneWidget);
    expect(find.byKey(const Key('dosis')), findsNothing, reason: 'Dosis-Karte weg');
    expect(titel('Auswertung pausiert'), findsOneWidget);
    expect(titel('Heute eintragen'), findsNothing);
    expect(txt('Nachtragen: 07.03.2026 (+2 weitere)'), findsOneWidget);

    // Springt in den Kalender und öffnet den Tag im Fenster von unten.
    await tippe(t, find.byKey(const Key('nachtragenOffen')));
    expect(find.byKey(const Key('monat')), findsOneWidget);
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
    await reiter(t, 'Kalender');
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
    expect(txt('Ø der eingetragenen Tage'), findsOneWidget);
  });

  testWidgets('Vorrat im Plan-Reiter: Anzahl × Stärke, sofort ausgerechnet, Nachkauf; Warnung auf Heute', (t) async {
    final app = await starte(t, aufReiter: 'Plan');
    expect(txt('Trag zuerst ein, was du gerade da hast'), findsOneWidget);
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
    expect(txt('Reicht noch ca. 10 Tage (bis 19.03.2026)'), findsOneWidget);
    expect(txt('Rest: 100 mg (≈ 20 Tbl à 5)'), findsOneWidget);

    // Heute: nur die Warnung (≤ 14 Tage), mit Tablettenkombination auf der Dosis-Karte.
    await reiter(t, 'Heute');
    expect(find.byKey(const Key('vorratWarnung')), findsOneWidget);
    expect(txt('Reicht noch ca. 10 Tage (bis 19.03.2026)'), findsOneWidget);
    expect(txt('2 × 5 mg'), findsOneWidget, reason: 'Tablettenkombination für 10 mg');
    await tippe(t, find.byKey(const Key('vorratWarnung')));
    expect(find.byKey(const Key('planKarte')), findsOneWidget, reason: 'Warnung öffnet den Plan-Reiter');

    await tippe(t, find.text('VORRAT ÄNDERN'));
    await t.enterText(find.byKey(const Key('anzahl0')), '20');
    await t.pumpAndSettle();
    expect(txt('Als Nachkauf dazu: reicht ca. 20 Tage'), findsOneWidget);
    await tippe(t, find.byKey(const Key('nachkauf')));
    expect(app.taper.st.stock!.mg, 200);
    await reiter(t, 'Heute');
    expect(find.byKey(const Key('vorratWarnung')), findsNothing, reason: 'reicht jetzt über 14 Tage');

    jetzt = DateTime.utc(2026, 3, 10, 12, 1); // Einnahme nach dem Zählen
    await tippe(t, find.byKey(const Key('wieGeplant')));
    await reiter(t, 'Plan');
    expect(txt('Rest: 190 mg'), findsOneWidget, reason: 'Einnahme wird abgezogen');
  });

  testWidgets('Tagebuch heute: Befinden + Notiz speichern, guter Tag', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('sym3')));
    await schreibe(t, find.byKey(const Key('notiz')), '4 Kaffee');
    await tippe(t, find.byKey(const Key('notizSpeichern')));
    final n = app.taper.st.notes['2026-03-10']!;
    expect(n.sym, 3);
    expect(n.text, '4 Kaffee');
    expect(find.text('Gespeichert'), findsOneWidget);
    await tippe(t, find.text('Heute war ein guter Tag'));
    expect(app.taper.st.good, contains('2026-03-10'));
    expect(find.text('Guter Tag'), findsOneWidget);
    await tippe(t, find.text('Guter Tag'));
    expect(app.taper.st.good, isEmpty);
  });

  testWidgets('Notiz im Tag-Fenster: „Notizen für heute“ unter dem Kalender zeigt sie danach', (t) async {
    await starte(t);
    await tippe(t, find.byKey(const Key('streifen-2026-03-10')));
    expect(find.byKey(const Key('monat')), findsOneWidget);
    final fenster = find.byKey(const Key('tagFenster'));
    expect(find.descendant(of: fenster, matching: find.text('Notizen für heute')), findsOneWidget);
    await t.enterText(find.descendant(of: fenster, matching: find.byKey(const Key('notiz'))), 'Kopfweh');
    await tippe(t, find.descendant(of: fenster, matching: find.byKey(const Key('notizSpeichern'))));
    await tippe(t, find.byTooltip('Schließen'));
    final unten = find.byKey(const Key('tagebuchHeute'));
    expect(find.descendant(of: unten, matching: find.widgetWithText(TextField, 'Kopfweh')), findsOneWidget);
    expect(find.descendant(of: unten, matching: find.text('Notiz speichern')), findsOneWidget);
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
    await reiter(t, 'Kalender');
    expect(find.byKey(const Key('wieGeplant')), findsOneWidget);
    expect(txt('9 mg wie geplant genommen'), findsOneWidget);
    await reiter(t, 'Heute');
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
    await schreibe(t, find.byKey(const Key('menge')), '0,5');
    await tippe(t, find.byKey(const Key('plus')));
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
    await tippe(t, find.byKey(const Key('wieGeplant')));
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
