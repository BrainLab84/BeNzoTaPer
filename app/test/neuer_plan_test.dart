// Neuer Plan gibt es nur ohne eigenen Plan. Mit Plan: „Plan anpassen“; ganz neu anfangen = Mehr → Zurücksetzen
// (wie eine neu installierte App, nichts vom alten Stand wirkt nach). Dazu die Sicherung: der ganze
// Abdosierverlauf, aber nichts von der App selbst (keine PIN, kein Schlüsselwort, keine Einstellungen).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/erinnerung.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_core/tapering_core.dart';

import 'hilfen.dart';
import 'plan_neu_test.dart' show abschnitt, weiter;
import 'sicherung_ui_test.dart' show FakeDateien;

/// Ein voller Stand: 5 Tage Einnahmen (einer über Plan), Vorrat, Notiz, guter Tag, Notizbuch, PIN mit Wort,
/// Halten, Einstellungen geändert.
Future<AppState> vollerStand(WidgetTester t, {FakeDateien? d}) async {
  final app = await starte(t, json: basis(start: '2026-03-03', log: {
    for (var k = 3; k <= 6; k++) '2026-03-0$k': eintrag(10, 10),
    '2026-03-07': eintrag(12, 10),
  }), dateien: d);
  final ta = app.taper;
  ta.setStock(30, 10);
  ta.saveTabs([10, 5], 0.5, null);
  ta.toggleGood('2026-03-05');
  app.notizSchreiben('Notizbuch: alter Eintrag');
  app.pinSetzen('2468', '2468');
  app.wortSetzen('Lavendel', 'Lavendel');
  await app.sperrZeitSetzen(10);
  app.erinnerung = app.erinnerung.mit(an: true);
  ta.startHold(5);
  app.aenderung();
  await t.pumpAndSettle();
  return app;
}

/// Mehr → Zurücksetzen → Satz + Häkchen → Alles löschen. Danach zurück auf Heute (Beispiel).
Future<void> zuruecksetzenUi(WidgetTester t) async {
  await tippe(t, find.byTooltip('Mehr'));
  await tippe(t, find.byKey(const Key('zuruecksetzen')));
  await t.enterText(find.byKey(const Key('planSicherText')), 'Ich bin mir sicher');
  await tippe(t, find.byKey(const Key('planBackupHaken')));
  await tippe(t, find.byKey(const Key('planSicherWeiter')));
  await zurueck(t);
  await t.pumpAndSettle();
  await reiter(t, 'Heute');
}

/// Erster Plan über die Startkarte auf Heute (Beispiel sichtbar, keine Bestätigung).
Future<void> ersterPlanUi(WidgetTester t,
    {String dosis = '20', List<List<String>> ab = const [['5', '15', '15'], ['5', '21', '0']]}) async {
  await tippe(t, find.byKey(const Key('planErstellen')));
  expect(find.byKey(const Key('planSicherDialog')), findsNothing, reason: 'erster Plan: keine Bestätigung');
  expect(t.widget<TextField>(find.byKey(const Key('planPerson'))).controller!.text, '', reason: 'nichts vorbelegt');
  await t.enterText(find.byKey(const Key('planPerson')), 'Sam');
  await weiter(t);
  expect(t.widget<TextField>(find.byKey(const Key('planDosis'))).controller!.text, '', reason: 'keine alte Dosis');
  await t.enterText(find.byKey(const Key('planDosis')), dosis);
  for (var i = 0; i < ab.length; i++) {
    if (i > 0) await tippe(t, find.byKey(const Key('abschnittPlus')));
    await abschnitt(t, i, ab[i][0], ab[i][1], ab[i][2]);
  }
  await weiter(t);
  await weiter(t);
  await tippe(t, find.byKey(const Key('planLos')));
}

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Mit Plan: kein „Neuen Plan erstellen“ / „Plan importieren“, nur der Hinweis zum Neuanfang', (t) async {
    final app = await vollerStand(t);
    for (final r in ['Heute', 'Kalender', 'Plan', 'Fortschritt']) {
      await reiter(t, r);
      expect(find.byKey(const Key('planErstellen')), findsNothing, reason: r);
      expect(find.byKey(const Key('planImportieren')), findsNothing, reason: r);
    }
    await reiter(t, 'Plan');
    expect(find.byKey(const Key('neuAnfangen')), findsOneWidget);
    expect(txt('Ganz neu anfangen? Erst sichern, dann Mehr → Zurücksetzen.'), findsOneWidget);
    expect(app.eingerichtet, isTrue);
  });

  testWidgets('Zurücksetzen, dann erster Plan: nichts vom alten Stand bleibt, Rechnung wie frisch', (t) async {
    final app = await vollerStand(t);
    final ta = app.taper;
    expect(ta.st.log, isNotEmpty);
    expect(app.hatPin, isTrue);
    await zuruecksetzenUi(t);
    expect(app.beispiel, isTrue);
    expect(app.hatPin, isFalse);
    expect(app.hatWort, isFalse);
    expect(app.notizbuch, isEmpty);
    expect(app.sperrMinuten, 2);
    expect(app.erinnerung, const ErinnerungEinstellung());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect((app.store as MemStore).state, isNull);

    await ersterPlanUi(t);
    expect(find.text('Möchtest du die App mit einer PIN schützen?'), findsOneWidget, reason: 'wie beim ersten Plan');
    await tippe(t, find.text('Überspringen'));

    final s = ta.st;
    expect(s.person, 'Sam');
    expect(s.plan, [20, 15, 10, 5, 0]);
    expect(s.days, [15, 21, 21, 21, 21]);
    expect(s.stage, 0);
    expect(s.stageStart, '2026-03-10');
    expect(s.t0, '2026-03-10');
    expect(s.log, isEmpty, reason: 'Einnahmen weg');
    expect(s.stock, isNull, reason: 'Vorrat weg');
    expect(s.tabs, isNull, reason: 'Tabletten weg');
    expect(s.notes, isEmpty);
    expect(s.good, isEmpty);
    expect(s.unk, isEmpty);
    expect(s.hold, isFalse);
    expect(s.pend, isNull);
    expect(s.frz, isNull);
    expect(s.pin, isNull);
    expect(s.chg.where((c) => !c.t.startsWith('Plan')), isEmpty, reason: 'alte Historie weg');
    expect(app.beispiel, isFalse);
    // Rechnungen wie bei einem frischen Plan: nichts Altes im Wochen-Ø, Live-Ø, Verlauf, offenen Tagen.
    expect(ta.weekAvgs(null, 4).every((w) => w.avg == null), isTrue);
    expect(ta.stufenSchnitt().avg, isNull);
    expect(ta.openDays(), isEmpty);
    expect(ta.verlauf().start, '2026-03-10');
    // Vorrat-Karte ohne die Tablettenstärken des Beispiels (5 / 2 mg)
    await finde(t, find.byKey(const Key('staerke0')));
    expect(t.widget<TextField>(find.byKey(const Key('staerke0'))).controller!.text, '');
    expect(find.byKey(const Key('staerke1')), findsNothing);
    await t.enterText(find.byKey(const Key('anzahl0')), '50');
    await t.enterText(find.byKey(const Key('staerke0')), '10');
    await tippe(t, find.byKey(const Key('vorratSpeichern')));
    expect(ta.st.tabs!.str, [10]);
    // Referenz B (500 mg, 15 × 20 mg, dann 15 mg) = 28 Tage wie frisch.
    expect(ta.stockInfo()!.rem, 500);
    expect(ta.stockInfo()!.days, 28);
    expect(ta.stockInfo()!.geschaetzt, 0);
    // App neu öffnen: derselbe neue Stand.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    final a2 = AppState(app.store, clock: () => jetzt);
    await t.runAsync(a2.laden);
    expect(a2.taper.st.log, isEmpty);
    expect(a2.hatPin, isFalse);
    expect(a2.hatWort, isFalse);
    expect(a2.sperrMinuten, 2);
    expect(a2.notizbuch, isEmpty);
  });

  testWidgets('Zurücksetzen abbrechen: alles bleibt', (t) async {
    final app = await vollerStand(t);
    final vorher = jsonEncode(app.taper.exportJson());
    await tippe(t, find.byTooltip('Mehr'));
    await tippe(t, find.byKey(const Key('zuruecksetzen')));
    await tippe(t, find.text('Abbrechen'));
    expect(jsonEncode(app.taper.exportJson()), vorher);
    expect(app.hatPin, isTrue);
    expect(app.notizbuch, hasLength(1));
  });

  testWidgets('Sicherung vor dem Zurücksetzen: Verlauf kommt zurück, PIN gehört zur App', (t) async {
    final d = FakeDateien();
    final app = await vollerStand(t, d: d);
    final text = await t.runAsync<String?>(() => app.sicherungErstellen());
    final roh = jsonDecode(text!) as Map;
    expect(roh.containsKey('pin'), isFalse, reason: 'keine PIN in der Sicherung');
    expect(roh['log'], isNotEmpty);
    expect(roh['notizbuch'], hasLength(1));
    final alt = (jsonDecode(jsonEncode(app.taper.exportJson())) as Map)..remove('pin');
    await zuruecksetzenUi(t);
    expect(app.beispiel, isTrue);
    // Sicherung laden über die Startkarte
    d.zumOeffnen = text;
    await t.runAsync(() => app.sicherungLaden(text));
    await t.pumpAndSettle();
    expect(jsonEncode(app.taper.exportJson()!..remove('pin')), jsonEncode(alt), reason: 'ganzer Verlauf zurück');
    expect(app.notizbuch, hasLength(1), reason: 'Notizbuch kommt mit');
    expect(app.hatPin, isFalse, reason: 'PIN wird neu vergeben');
    expect(app.hatWort, isFalse);
    // Jetzt eine neue PIN; erneutes Laden lässt sie stehen (auch eine ältere Sicherung mit PIN ändert sie nicht).
    app.pinSetzen('1357', '1357');
    final mitAlterPin = jsonEncode({...roh, 'pin': Taper.hashPin('2468')});
    await t.runAsync(() => app.sicherungLaden(mitAlterPin));
    expect(app.hatPin, isTrue);
    expect(app.taper.st.pin, Taper.hashPin('1357'));
  });

  testWidgets('Sicherung mit leerem Notizbuch: Laden leert auch das jetzige Notizbuch', (t) async {
    final d = FakeDateien();
    final app = await vollerStand(t, d: d);
    app.notizLoeschen(app.notizbuch.single.id);
    expect(app.notizbuch, isEmpty);
    final text = await t.runAsync<String?>(() => app.sicherungErstellen());
    expect((jsonDecode(text!) as Map).containsKey('notizbuch'), isTrue, reason: 'auch leer in der Sicherung');
    app.notizSchreiben('später geschrieben');
    expect(app.notizbuch, hasLength(1));
    await t.runAsync(() => app.sicherungLaden(text));
    expect(app.notizbuch, isEmpty);
    // Alte Sicherung ohne Notizbuch-Schlüssel: Notizbuch bleibt, wie es ist
    app.notizSchreiben('bleibt');
    final alt = jsonEncode(app.taper.exportJson());
    await t.runAsync(() => app.sicherungLaden(alt));
    expect(app.notizbuch.single.text, 'bleibt');
  });
}
