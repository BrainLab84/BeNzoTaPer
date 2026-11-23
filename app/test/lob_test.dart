// Lob beim Halten: frühestens nach 3 Tagen, dann nach Zufall alle 3–5 Tage,
// nie am oder nach dem Halten-Ende, jede Halten-Phase neu, zwei Texte im Wechsel, mit X weg (bleibt weg).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/lob.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_core/tapering_core.dart';

import 'hilfen.dart';

const _lang = 'Weiter so. Stabilität beim Abdosieren ist das A und O.';

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  test('Lob-Tage: erstes nach 3–5 Tagen, dann alle 3–5 Tage, fest je Halten-Beginn', () {
    final ersteTage = <int>{};
    var k = '2026-01-01';
    for (var i = 0; i < 400; i++) {
      final l = lobTage(k, bis: 120);
      expect(l.first, inInclusiveRange(3, 5), reason: k);
      ersteTage.add(l.first);
      for (var j = 1; j < l.length; j++) {
        expect(l[j] - l[j - 1], inInclusiveRange(3, 5), reason: '$k: $l');
      }
      expect(lobTage(k, bis: 120), l, reason: 'gleicher Beginn = gleiche Tage');
      k = addD(k, 1);
    }
    expect(ersteTage, {3, 4, 5}, reason: 'wirklich zufällig verteilt');
  });

  test('Lob-Texte im Wechsel', () {
    expect(lobText(4, 0), 'Glückwunsch – 4 Tage gehalten.');
    expect(lobText(8, 1), 'Du machst das super – 8 Tage gehalten. $_lang');
    expect(lobText(12, 2), 'Glückwunsch – 12 Tage gehalten.');
  });

  Future<void> naechsterTag(WidgetTester t, AppState app) async {
    jetzt = jetzt.add(const Duration(days: 1));
    app.auffrischen();
    await t.pumpAndSettle();
  }

  testWidgets('Ohne Enddatum: Lob genau an den Lob-Tagen, über „Heute eintragen“, Texte im Wechsel', (t) async {
    final app = await starte(t);
    app.taper.startHold(null);
    app.aenderung();
    await t.pumpAndSettle();
    final seit = app.taper.st.holdSince!;
    final tage = lobTage(seit, bis: 30);
    var gesehen = 0;
    for (var d = 0; d <= 30; d++) {
      final karte = find.byKey(const Key('haltenLob'));
      if (tage.contains(d)) {
        expect(karte, findsOneWidget, reason: 'Tag $d');
        final nr = tage.indexOf(d);
        expect(txt(lobText(d, nr)), findsOneWidget);
        expect(t.getTopLeft(karte).dy, lessThan(t.getTopLeft(find.byKey(const Key('heuteEintragen'))).dy),
            reason: 'über „Heute eintragen“');
        gesehen++;
      } else {
        expect(karte, findsNothing, reason: 'Tag $d ist kein Lob-Tag ($tage)');
      }
      if (d < 3) expect(karte, findsNothing, reason: 'nie vor 3 Tagen');
      await naechsterTag(t, app);
    }
    expect(gesehen, greaterThanOrEqualTo(5));
    expect(txt('Glückwunsch'), findsNothing);
  });

  testWidgets('Mit Enddatum: nie am oder nach dem Ende (dann ist die nächste Dosis dran)', (t) async {
    final app = await starte(t);
    for (final dauer in [3, 4, 5, 7, 9]) {
      app.taper.startHold(dauer);
      app.aenderung();
      await t.pumpAndSettle();
      final seit = app.taper.st.holdSince!;
      final tage = lobTage(seit, bis: 40);
      for (var d = 0; d <= dauer + 6; d++) {
        final soll = d < dauer && tage.contains(d);
        expect(find.byKey(const Key('haltenLob')), soll ? findsOneWidget : findsNothing,
            reason: 'Halten $dauer Tage, Tag $d, Lob-Tage $tage');
        // Einträge, damit nach dem Halten keine offenen Tage stören
        if (app.taper.st.log[app.taper.today] == null) app.taper.addIntake(app.taper.st.plan[app.taper.st.stage]);
        await naechsterTag(t, app);
      }
      expect(app.taper.st.hold, isFalse);
    }
  });

  testWidgets('Neue Halten-Phase (neue Dosis) zählt neu ab Tag 0', (t) async {
    final app = await starte(t);
    app.taper.startHold(null);
    for (var i = 0; i < 20; i++) {
      app.taper.addIntake(app.taper.st.plan[app.taper.st.stage]);
      await naechsterTag(t, app);
    }
    app.taper.stopHold();
    for (var i = 0; i < 16; i++) {
      app.taper.addIntake(app.taper.st.plan[app.taper.st.stage]);
      await naechsterTag(t, app);
    }
    expect(app.taper.st.stage, greaterThan(0), reason: 'neue Stufe');
    app.taper.startHold(null);
    app.aenderung();
    await t.pumpAndSettle();
    final tage = lobTage(app.taper.st.holdSince!, bis: 10);
    for (var d = 0; d <= 10; d++) {
      expect(find.byKey(const Key('haltenLob')), tage.contains(d) ? findsOneWidget : findsNothing, reason: 'Tag $d');
      if (tage.contains(d)) expect(txt('– $d Tage gehalten'), findsOneWidget);
      await naechsterTag(t, app);
    }
  });

  testWidgets('X: Lob weg und bleibt weg (auch nach Neustart), das nächste kommt wieder', (t) async {
    final store = MemStore()..disc = true;
    var app = AppState(store, clock: () => jetzt);
    await t.runAsync(app.laden);
    app.taper.setup(dose: 10, step: 1, minStep: 0.5, days: 14, goal: 0);
    app.taper.startHold(null);
    final tage = lobTage(app.taper.st.holdSince!, bis: 30);
    jetzt = jetzt.add(Duration(days: tage[0]));
    app.auffrischen();
    t.view.physicalSize = const Size(1000, 7000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('haltenLob')), findsOneWidget);
    await t.tap(find.byKey(const Key('haltenLobWeg')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('haltenLob')), findsNothing);
    expect((jsonDecode(store.einstellungen!) as Map)['lobWeg'], isNotNull);

    // Neustart mit demselben Speicher: bleibt weg
    await t.pumpWidget(const SizedBox());
    app = AppState(store, clock: () => jetzt);
    await t.runAsync(app.laden);
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('haltenLob')), findsNothing);

    // Nächster Lob-Tag: wieder da
    jetzt = jetzt.add(Duration(days: tage[1] - tage[0]));
    app.auffrischen();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('haltenLob')), findsOneWidget);
    expect(txt('Du machst das super – ${tage[1]} Tage gehalten.'), findsOneWidget);
  });

  testWidgets('Lob gilt den abgeschlossenen Tagen: Ausrutscher bis gestern streicht es, heute zählt fürs nächste',
      (t) async {
    final app = await starte(t);
    app.taper.startHold(null);
    final tage = lobTage(app.taper.st.holdSince!, bis: 40);
    final dosis = app.taper.st.plan[app.taper.st.stage];
    Future<void> bis(int lobTag, {int? ausrutscherAm}) async {
      while (dBetween(app.taper.st.holdSince!, app.taper.today) < lobTag) {
        final d = dBetween(app.taper.st.holdSince!, app.taper.today);
        app.taper.addIntake(d == ausrutscherAm ? dosis + 1 : dosis, force: true);
        jetzt = jetzt.add(const Duration(days: 1));
        app.auffrischen();
      }
      await t.pumpAndSettle();
    }

    // 1. Lob: alles sauber → ab Mitternacht da (noch nichts eingetragen)
    await bis(tage[0]);
    expect(find.byKey(const Key('haltenLob')), findsOneWidget);
    // Ausrutscher heute (am Lob-Tag): das heutige Lob bleibt, es galt den Tagen davor …
    app.taper.addIntake(dosis + 1, force: true);
    app.aenderung();
    await t.pumpAndSettle();
    expect(app.taper.st.log[app.taper.today]!.r, 'lapse');
    expect(find.byKey(const Key('haltenLob')), findsOneWidget, reason: 'schon verdient');
    // … aber das nächste fällt aus
    jetzt = jetzt.add(const Duration(days: 1));
    app.auffrischen();
    await bis(tage[1]);
    expect(find.byKey(const Key('haltenLob')), findsNothing, reason: 'Ausrutscher seit dem letzten Lob');
    // Durchgehalten → das übernächste kommt
    await bis(tage[2]);
    expect(find.byKey(const Key('haltenLob')), findsOneWidget);
    // Ausrutscher genau am Tag vor einem Lob-Tag streicht dieses Lob
    await bis(tage[3], ausrutscherAm: tage[3] - 1);
    expect(find.byKey(const Key('haltenLob')), findsNothing, reason: 'Ausrutscher gestern');
    await bis(tage[4]);
    expect(find.byKey(const Key('haltenLob')), findsOneWidget);
    expect(txt('${tage[4]} Tage gehalten'), findsOneWidget);
  });

  testWidgets('Ausrutscher am Tag, an dem das Halten beginnt, zählt nicht gegen das erste Lob', (t) async {
    final app = await starte(t);
    final dosis = app.taper.st.plan[app.taper.st.stage];
    app.taper.addIntake(dosis + 2, force: true);
    app.taper.startHold(null);
    final tage = lobTage(app.taper.st.holdSince!, bis: 30);
    for (var d = 0; d < tage[0]; d++) {
      jetzt = jetzt.add(const Duration(days: 1));
      app.auffrischen();
      app.taper.addIntake(dosis, force: true);
    }
    app.aenderung();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('haltenLob')), findsOneWidget);
  });

  testWidgets('Ohne Halten und im Beispiel kein Lob', (t) async {
    final app = await starte(t);
    for (var d = 0; d < 20; d++) {
      expect(find.byKey(const Key('haltenLob')), findsNothing);
      app.taper.addIntake(app.taper.st.plan[app.taper.st.stage]);
      await naechsterTag(t, app);
    }
    final b = await starte(t, einrichten: false);
    expect(b.beispiel, isTrue);
    expect(find.byKey(const Key('haltenLob')), findsNothing);
  });
}
