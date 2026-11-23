import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'hilfen.dart';

Finder inZelle(String k, Finder f) => find.descendant(of: find.byKey(Key('tag-$k')), matching: f);

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Monat, Plan-Ende, Vorschau der Dosis, Blättern', (t) async {
    await starte(t);
    await reiter(t, 'Kalender');
    expect(find.text('März 2026'), findsOneWidget);
    expect(txt('Voraussichtlich bei 0 mg: 28.07.2026'), findsOneWidget);
    expect(inZelle('2026-03-11', find.text('10')), findsOneWidget, reason: 'Vorschau morgen');
    expect(inZelle('2026-03-24', find.text('9')), findsOneWidget, reason: 'neue Stufe');
    expect(find.byKey(const Key('zurueckHeute')), findsNothing);

    await t.tap(find.text('›'));
    await t.pumpAndSettle();
    expect(find.text('April 2026'), findsOneWidget);
    expect(inZelle('2026-04-07', find.text('8')), findsOneWidget);
    await tippe(t, find.byKey(const Key('zurueckHeute')));
    expect(find.text('März 2026'), findsOneWidget);
    await t.tap(find.text('‹'));
    await t.tap(find.text('‹'));
    await t.tap(find.text('‹'));
    await t.pumpAndSettle();
    expect(find.text('Dezember 2025'), findsOneWidget, reason: 'über den Jahreswechsel');
  });

  testWidgets('Zellen: im Plan, mehr genommen, offen, Notiz, guter Tag', (t) async {
    final j = basis(log: {
      for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(d == 4 ? 12 : 10, 10),
    });
    j['notes'] = {
      '2026-03-02': {'sx': [], 'sym': 2, 'text': 'x'}
    };
    j['good'] = {'2026-03-03': 1};
    await starte(t, json: j);
    await reiter(t, 'Kalender');
    expect(inZelle('2026-03-01', find.byIcon(Icons.check)), findsOneWidget);
    expect(inZelle('2026-03-04', find.byIcon(Icons.close)), findsOneWidget);
    expect(inZelle('2026-03-04', find.text('12')), findsOneWidget);
    expect(inZelle('2026-03-03', find.byIcon(Icons.wb_sunny_outlined)), findsOneWidget);
    expect(inZelle('2026-02-28', find.text('?')), findsNothing, reason: 'vor dem Start kein ?');
  });

  testWidgets('Tag antippen: Fenster von unten, Vergangenheit nachtragen, Zukunft nur Kopf, Schließen', (t) async {
    final app = await starte(t,
        json: basis(log: {
          for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(10, 10),
        }));
    await reiter(t, 'Kalender');
    await tippe(t, find.byKey(const Key('tag-2026-03-05')));
    expect(find.byKey(const Key('tagFenster')), findsOneWidget, reason: 'Fenster von unten');
    expect(find.text('05.03.2026'), findsOneWidget);
    expect(txt('Einnahme an diesem Tag'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('tagFenster')), matching: find.text('im Plan', findRichText: true)),
        findsOneWidget);
    await tippe(t, find.byTooltip('Einnahme löschen'));
    expect(app.taper.st.log['2026-03-05'], isNull);
    expect(txt('Nichts eingetragen.'), findsOneWidget);
    await tippe(t, find.text('Nachtragen: 10 mg wie geplant'));
    expect(app.taper.st.log['2026-03-05']!.dose, 10);
    expect(find.descendant(of: find.byKey(const Key('tagFenster')), matching: find.text('im Plan', findRichText: true)),
        findsOneWidget,
        reason: 'Fenster baut sich nach dem Nachtragen neu auf');
    await tippe(t, find.byTooltip('Schließen'));
    expect(find.byKey(const Key('tagFenster')), findsNothing);
    expect(inZelle('2026-03-05', find.byIcon(Icons.check)), findsOneWidget, reason: 'Häkchen im Kalender');

    await tippe(t, find.byKey(const Key('tag-2026-03-20')));
    expect(find.text('20.03.2026 · Zukunft'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('tagFenster')), matching: txt('Befinden')), findsNothing);
    await tippe(t, find.byTooltip('Schließen'));
    expect(find.text('20.03.2026 · Zukunft'), findsNothing);
    expect(find.byKey(const Key('tagFenster')), findsNothing);

    // Älter als 7 Tage: nur noch ansehen.
    await t.tap(find.text('‹'));
    await t.pumpAndSettle();
    await tippe(t, find.byKey(const Key('tag-2026-02-25')));
    expect(txt('Nachtragen geht bis 7 Tage zurück.'), findsOneWidget);
  });

  testWidgets('Tag-Fenster: Notiz eines Tages anzeigen und ändern', (t) async {
    final j = basis(log: {
      for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(10, 10),
    });
    j['notes'] = {
      '2026-03-04': {'sx': [], 'sym': 2, 'text': '4 Kaffee'}
    };
    final app = await starte(t, json: j);
    await reiter(t, 'Kalender');
    await tippe(t, find.byKey(const Key('tag-2026-03-04')));
    // Vorhandene Notiz steht fest, erst „Bearbeiten“ öffnet das Feld
    final lesen = find.byKey(const Key('notizLesen'));
    expect(find.descendant(of: lesen, matching: find.text('4 Kaffee')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('tagFenster')), matching: find.byType(TextField)), findsWidgets,
        reason: 'nur die Einnahme-Felder');
    expect(find.descendant(of: find.byKey(const Key('tagFenster')), matching: find.byKey(const Key('notiz'))),
        findsNothing);
    await tippe(t, find.byKey(const Key('notizBearbeiten')));
    final notiz = find.descendant(of: find.byKey(const Key('tagFenster')), matching: find.byKey(const Key('notiz')));
    expect(find.descendant(of: notiz, matching: find.text('4 Kaffee')), findsOneWidget);
    await t.enterText(notiz, '4 Kaffee, schlecht geschlafen');
    await tippe(
        t, find.descendant(of: find.byKey(const Key('tagFenster')), matching: find.byKey(const Key('notizSpeichern'))));
    expect(app.taper.st.notes['2026-03-04']!.text, '4 Kaffee, schlecht geschlafen');
    expect(find.descendant(of: find.byKey(const Key('tagFenster')), matching: find.byKey(const Key('notiz'))),
        findsNothing,
        reason: 'nach dem Speichern wieder feststehend');
    expect(
        find.descendant(of: find.byKey(const Key('notizLesen')), matching: find.text('4 Kaffee, schlecht geschlafen')),
        findsOneWidget);
  });

  testWidgets('Halten: voraussichtliches Ende mit „(Dosis wird gehalten)“', (t) async {
    final app = await starte(t);
    app.taper.startHold(null);
    app.aenderung();
    await reiter(t, 'Kalender');
    expect(txt('Voraussichtlich bei 0 mg: 28.07.2026 (Dosis wird gehalten)'), findsOneWidget);
    expect(txt('Plan pausiert'), findsNothing);
    expect(inZelle('2026-03-24', find.text('10')), findsOneWidget, reason: 'beim Halten bleibt die Dosis');
  });

  testWidgets('Offene Tage: Hinweis, Karte, „Nachtragen“ öffnet den Tag im Fenster', (t) async {
    await starte(t,
        json: basis(log: {
          for (var d = 1; d <= 6; d++) '2026-03-0$d': eintrag(10, 10),
        }));
    await reiter(t, 'Kalender');
    expect(txt('Offene Tage – Anzeigen pausieren bis zum Nachtragen.'), findsOneWidget);
    expect(titel('Offene Tage'), findsOneWidget);
    expect(find.byKey(const Key('tagebuchHeute')), findsNothing, reason: 'bei offenen Tagen ausgeblendet');
    await tippe(t, find.byKey(const Key('nachtragenOffen')));
    expect(find.text('07.03.2026'), findsOneWidget);
    await tippe(t, find.byTooltip('Schließen'));
    expect(inZelle('2026-03-11', find.text('10')), findsNothing, reason: 'keine Vorschau bei offenen Tagen');
  });

  testWidgets('Mitternacht am Monatsende: Kalender springt in den neuen Monat', (t) async {
    jetzt = DateTime.utc(2026, 3, 31, 23, 50);
    final app = await starte(t);
    await reiter(t, 'Kalender');
    expect(find.text('März 2026'), findsOneWidget);
    app.taper.addIntake(10);
    jetzt = DateTime.utc(2026, 4, 1, 0, 5);
    app.auffrischen();
    await t.pumpAndSettle();
    expect(find.text('April 2026'), findsOneWidget);
  });

  testWidgets('Tag-Fenster: Notiz oben – „Notiz nachtragen“ ohne Notiz –, Einnahmen klein darunter',
      (t) async {
    final j = basis(log: {for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(10, 10)});
    j['notes'] = {
      '2026-03-04': {'sx': [], 'sym': 2, 'text': '4 Kaffee'}
    };
    await starte(t, json: j);
    await reiter(t, 'Kalender');
    final fenster = find.byKey(const Key('tagFenster'));
    await tippe(t, find.byKey(const Key('tag-2026-03-05')));
    expect(find.descendant(of: fenster, matching: find.text('Notiz nachtragen')), findsOneWidget);
    final kopf = t.getTopLeft(find.byKey(const Key('notizKopf'))).dy;
    final einnahmen = t.getTopLeft(find.descendant(of: fenster, matching: find.text('Einnahmen'))).dy;
    expect(kopf < einnahmen, isTrue, reason: 'Notizen oben, Einnahmen darunter');
    expect(find.descendant(of: fenster, matching: find.text('Mehr dazu: ')), findsNothing);
    expect(find.descendant(of: fenster, matching: txt('Notiz zum Befinden')), findsNothing);
    await tippe(t, find.byTooltip('Schließen'));
    await tippe(t, find.byKey(const Key('tag-2026-03-04')));
    expect(find.descendant(of: fenster, matching: find.text('Notiz')), findsOneWidget);
    expect(find.descendant(of: fenster, matching: find.text('4 Kaffee')), findsOneWidget);
    expect(find.descendant(of: fenster, matching: find.byKey(const Key('notizBearbeiten'))), findsOneWidget);
    await tippe(t, find.byTooltip('Schließen'));
    // Hinweis „jederzeit nachtragen“ als eigener Block unter den Notizen für heute
    final karte = t.getBottomLeft(find.byKey(const Key('tagebuchHeute'))).dy;
    expect(t.getTopLeft(find.byKey(const Key('notizenHinweis'))).dy >= karte, isTrue);
  });
}
