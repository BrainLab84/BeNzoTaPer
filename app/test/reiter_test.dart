import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_buddy/verlauf.dart';

import 'hilfen.dart';

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Reiter: Kalender · Heute · Plan · Fortschritt, Start in Heute', (t) async {
    await starte(t, aufReiter: null);
    final nav = find.byType(NavigationDestination);
    expect(nav, findsNWidgets(4));
    expect([for (final e in nav.evaluate()) (e.widget as NavigationDestination).label],
        ['Kalender', 'Heute', 'Plan', 'Fortschritt']);
    expect(find.byKey(const Key('dosis')), findsOneWidget, reason: 'Start in Heute');
    expect(aktuellerReiter(t), 'Heute');
  });

  testWidgets('Ordnung: Kalender → Verlauf → Wochen-Ø → Notizen; Heute: Eintragen → Stufe → Vorrat', (t) async {
    await starte(t, aufReiter: 'Kalender');
    final monat = t.getTopLeft(find.byKey(const Key('monat'))).dy;
    final balken = t.getTopLeft(find.byKey(const Key('kalenderFortschritt'))).dy;
    final woche = t.getTopLeft(find.byKey(const Key('wochenKarte'))).dy;
    final tagebuch = t.getTopLeft(find.byKey(const Key('tagebuchHeute'))).dy;
    expect(monat < balken && balken < woche && woche < tagebuch, isTrue,
        reason: 'Kalender ganz oben, darunter Verlauf, Wochen-Ø, Notizen');
    expect(find.byKey(const Key('heuteEintragen')), findsNothing, reason: 'Eintragen steht in Heute');
    expect(find.descendant(of: find.byKey(const Key('tagebuchHeute')), matching: find.text('Notizen für heute')),
        findsOneWidget);
    expect(txt('Du kannst jederzeit nachtragen, falls du etwas vergessen hast.'), findsOneWidget);
    expect(txt('Tagebuch'), findsNothing, reason: 'heißt jetzt „Notizen“');
    expect(find.descendant(of: find.byKey(const Key('tagebuchHeute')), matching: find.byKey(const Key('befindenText'))),
        findsOneWidget,
        reason: 'mit Befinden-Text und Links');
    await reiter(t, 'Heute');
    expect(find.byKey(const Key('einnahme')), findsOneWidget);
    expect(find.byKey(const Key('tagebuchHeute')), findsNothing);
    expect(find.byKey(const Key('wochenKarte')), findsNothing);
    final ein = t.getTopLeft(find.byKey(const Key('heuteEintragen'))).dy;
    final dosis = t.getTopLeft(find.byKey(const Key('dosis'))).dy;
    final vorrat = t.getTopLeft(find.byKey(const Key('vorratKarte'))).dy;
    expect(ein < dosis && dosis < vorrat, isTrue, reason: 'Eintragen → Stufen-Karte → Vorrat');
    await reiter(t, 'Fortschritt');
    expect(find.byKey(const Key('tagebuchHeute')), findsNothing, reason: 'nicht mehr im Fortschritt');
    expect(t.getSize(find.byKey(const Key('diagramm'))).height, greaterThan(340), reason: 'Diagramm größer');
  });

  testWidgets('Runder Kalender-Knopf: aus jedem Reiter und aus „Mehr“ zum Kalender', (t) async {
    await starte(t);
    expect(find.byKey(const Key('dosis')), findsOneWidget);
    await tippe(t, find.byKey(const Key('kalenderKnopf')));
    expect(find.byKey(const Key('monat')), findsOneWidget);
    await reiter(t, 'Fortschritt');
    await tippe(t, find.byTooltip('Mehr'));
    expect(find.text('Mehr'), findsWidgets);
    await tippe(t, find.byKey(const Key('kalenderKnopf')));
    expect(find.byKey(const Key('monat')), findsOneWidget, reason: 'Mehr geschlossen, Kalender offen');
  });

  testWidgets('Fortschritt: Zahlen ohne Prozente, Diagramm, Ausrutscher', (t) async {
    final app = await starte(t,
        json: basis(
            start: '2026-02-17',
            log: {
              for (var d = 17; d <= 28; d++) '2026-02-$d': eintrag(d == 20 ? 12 : 10, 10),
              for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(9, 9, stage: 1),
            }..['2026-03-10'] = eintrag(9, 9, stage: 1)),
        aufReiter: 'Fortschritt');
    expect(app.taper.st.stage, 1);
    expect(find.text('Von 10 mg auf 9 mg'), findsOneWidget);
    expect(find.text('21'), findsOneWidget, reason: 'Tage geschafft seit 17.02.');
    expect(find.text('2 von 4'), findsOneWidget);
    expect(find.text('Voraussichtlich\nbei 7 mg'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(
        find.descendant(
            of: find.byKey(const Key('diagramm')),
            matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is VerlaufMaler)),
        findsOneWidget);
    expect(txt('Ø 7 Tage · zuletzt 9 mg'), findsOneWidget);
    expect(txt('%'), findsNothing);
  });

  test('Diagramm: runde Hilfslinien, höchstens 4 Abschnitte', () {
    expect(VerlaufMaler.schrittweite(10), 2.5);
    expect(VerlaufMaler.schrittweite(11), 5);
    expect(VerlaufMaler.schrittweite(2), 0.5);
    expect(VerlaufMaler.schrittweite(0.6), 0.25);
    expect(VerlaufMaler.schrittweite(60), 20);
    expect(VerlaufMaler.schrittweite(300), 100);
  });

  testWidgets('Fortschritt am ersten Tag und ohne Plan', (t) async {
    await starte(t, aufReiter: 'Fortschritt');
    expect(find.text('Start bei 10 mg'), findsOneWidget);
    expect(txt('Trag deine Einnahmen ein'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('Ohne eigenen Plan: Beispiel in allen Reitern, „Neuen Plan erstellen“ nur oben in Heute', (t) async {
    final app = await starte(t, einrichten: false, aufReiter: null);
    expect(app.beispiel, isTrue);
    expect(app.eingerichtet, isFalse);
    expect(find.text('Schön, dass du da bist.'), findsOneWidget);
    expect(find.byKey(const Key('planErstellen')), findsOneWidget);
    expect(find.byKey(const Key('beispielHinweis')), findsOneWidget);
    expect(find.byKey(const Key('dosis')), findsOneWidget);
    for (final (r, inhalt) in [('Plan', 'planKarte'), ('Kalender', 'kalenderFortschritt'), ('Fortschritt', 'diagramm')]) {
      await reiter(t, r);
      expect(find.text('Schön, dass du da bist.'), findsNothing, reason: r);
      expect(find.byKey(const Key('planErstellen')), findsNothing, reason: r);
      expect(find.byKey(const Key('beispielHinweis')), findsOneWidget, reason: r);
      expect(find.byKey(Key(inhalt)), findsOneWidget, reason: '$r zeigt Inhalt');
    }
    // Im Beispiel eintragen: wird nicht gespeichert.
    await reiter(t, 'Heute');
    await nehme(t, '1');
    expect((app.store as MemStore).state, isNull, reason: 'Beispiel wird nie gespeichert');
  });

  testWidgets('Eigener Plan ersetzt das Beispiel; Abbrechen bringt das Beispiel zurück', (t) async {
    final app = await starte(t, einrichten: false, aufReiter: null);
    await tippe(t, find.byKey(const Key('planErstellen')));
    await t.pageBack();
    await t.pumpAndSettle();
    expect(app.beispiel, isTrue, reason: 'nach Abbrechen wieder das Beispiel');
    await tippe(t, find.byKey(const Key('planErstellen')));
    await tippe(t, find.byKey(const Key('planWeiter')));
    await t.enterText(find.byKey(const Key('planDosis')), '12');
    await t.enterText(find.byKey(const Key('abSchritt0')), '2');
    await t.enterText(find.byKey(const Key('abBis0')), '0');
    await tippe(t, find.byKey(const Key('planWeiter')));
    expect(find.byKey(const Key('planSicher')), findsNothing, reason: 'erster eigener Plan: kein „Ich bin mir sicher“');
    await tippe(t, find.byKey(const Key('planWeiter')));
    await tippe(t, find.byKey(const Key('planLos')));
    expect(app.beispiel, isFalse);
    expect(app.eingerichtet, isTrue);
    expect(app.taper.st.plan.first, 12);
    expect(app.taper.st.log, isEmpty, reason: 'nichts aus dem Beispiel übernommen');
    expect(find.byKey(const Key('beispielHinweis')), findsNothing);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    expect((app.store as MemStore).state, contains('"plan"'), reason: 'eigener Plan wird gespeichert');
  });

  testWidgets('Begrüßung oben in Heute; Kalender: Plandatum, darunter Kalender, darunter Fortschrittsbalken', (t) async {
    final app = await starte(t, aufReiter: null);
    app.taper.st.person = 'Alex';
    app.aenderung();
    await t.pumpAndSettle();
    final hallo = t.getTopLeft(find.byKey(const Key('begruessung'))).dy;
    expect(hallo < t.getTopLeft(find.byKey(const Key('heuteEintragen'))).dy, isTrue, reason: 'ganz oben in Heute');
    await reiter(t, 'Kalender');
    expect(find.byKey(const Key('begruessung')), findsNothing);
    final balken = t.getTopLeft(find.byKey(const Key('kalenderFortschritt'))).dy;
    final monat = t.getTopLeft(find.byKey(const Key('monat'))).dy;
    expect(monat < balken, isTrue);
    final datum = find.byKey(const Key('kalPlanDatum'));
    expect(find.descendant(of: datum, matching: find.text('Plan gestartet am 10.03.2026')), findsOneWidget);
    expect(t.getTopLeft(datum).dy < monat, isTrue, reason: 'dezent über dem Kalender');
    expect(t.getSize(datum).height, lessThan(30), reason: 'nimmt kaum Platz weg');
    expect(find.descendant(of: find.byKey(const Key('kalenderFortschritt')), matching: find.text('Tag 1/14')),
        findsOneWidget);
    expect(find.byKey(const Key('planErstellen')), findsNothing, reason: 'mit Plan keine Startkarte');
  });

  testWidgets('Befinden: Text über den Smileys', (t) async {
    await starte(t, aufReiter: 'Kalender');
    expect(txt('Bei einer Langzeiteinnahme und während des Benzodiazepin-Entzugs kann vieles paradox wirken.'),
        findsOneWidget);
    expect(txt('Mustererkennung statt ständigem Symptomcheck:'), findsOneWidget);
    expect(txt('Persönliche Erfahrung des Entwicklers:'), findsOneWidget);
    expect(txt('Manchmal wird ein Zusammenhang erst durch den Blick auf mehrere Tage deutlich.'), findsOneWidget);
    final text = t.getTopLeft(find.byKey(const Key('befindenText')));
    final smiley = t.getTopLeft(find.byKey(const Key('sym1')));
    final notiz = t.getTopLeft(find.byKey(const Key('notiz')));
    expect(text.dy < smiley.dy && smiley.dy < notiz.dy, isTrue, reason: 'Text über Smileys und Notizfeld');
  });
}
