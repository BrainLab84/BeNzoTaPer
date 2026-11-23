// „Neuen Plan erstellen“ / „Plan importieren“ bei bestehendem Plan = Neustart: wie eine neu installierte App,
// nichts vom alten Stand wirkt nach. Gelöscht wird erst beim Speichern. Dazu Zurücksetzen und Sicherung.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/erinnerung.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';
import 'plan_neu_test.dart' show abschnitt, weiter;
import 'sicherung_ui_test.dart' show FakeDateien;

/// Ein voller Stand: 5 Tage Einnahmen (einer über Plan), Vorrat, Notiz, guter Tag, Notizbuch, PIN mit Wort,
/// Halten, Einstellungen geändert, eine offene Lücke.
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

/// Neuen Plan über die Oberfläche anlegen (Plan-Reiter → Neuer Plan → Bestätigen → Fragebogen).
Future<void> neuerPlanUi(WidgetTester t,
    {String dosis = '20', List<List<String>> ab = const [['5', '15', '15'], ['5', '21', '0']], bool bestaetigen = true}) async {
  await reiter(t, 'Plan');
  await tippe(t, find.byKey(const Key('planErstellen')));
  if (bestaetigen) {
    expect(find.byKey(const Key('planSicherDialog')), findsOneWidget);
    await planSicherBestaetigen(t);
  }
  await t.enterText(find.byKey(const Key('planPerson')), 'Sam');
  await weiter(t);
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

  testWidgets('Neuer Plan: nichts vom alten Stand bleibt, Rechnung wie frisch, PIN wird wieder angeboten', (t) async {
    final app = await vollerStand(t);
    final ta = app.taper;
    expect(ta.st.log, isNotEmpty);
    expect(app.hatPin, isTrue);
    // Entsperrt arbeiten (PIN ist gesetzt, aber die App ist offen).
    await neuerPlanUi(t);
    expect(find.text('Möchtest du die App mit einer PIN schützen?'), findsOneWidget, reason: 'wie beim ersten Plan');
    await tippe(t, find.text('Überspringen'));

    final s = ta.st;
    expect(s.person, 'Sam');
    expect(s.plan, [20, 15, 10, 5, 0]);
    expect(s.days, [15, 21, 21, 21, 21]);
    expect(s.stage, 0);
    expect(s.stageStart, '2026-03-10', reason: 'Stufentage ab dem Start neu');
    expect(s.t0, '2026-03-10');
    expect(s.log, isEmpty, reason: 'Einnahmen weg');
    expect(s.stock, isNull, reason: 'Vorrat weg');
    expect(s.tabs, isNull, reason: 'Tabletten weg');
    expect(s.notes, isEmpty);
    expect(s.good, isEmpty);
    expect(s.unk, isEmpty);
    expect(s.hold, isFalse);
    expect(s.holdSince, isNull);
    expect(s.holdUntil, isNull);
    expect(s.pend, isNull);
    expect(s.frz, isNull);
    expect(s.adv, isNull);
    expect(s.pin, isNull, reason: 'PIN weg');
    expect(s.chg.where((c) => !c.t.startsWith('Plan')), isEmpty, reason: 'alte Historie weg');
    expect(app.hatWort, isFalse);
    expect(app.notizbuch, isEmpty);
    expect(app.sperrMinuten, 2);
    expect(app.erinnerung.an, isFalse);
    expect(app.beispiel, isFalse);
    // Rechnungen wie bei einem frischen Plan: nichts Altes im Wochen-Ø, Live-Ø, Verlauf, offenen Tagen.
    expect(ta.weekAvgs(null, 4).every((w) => w.avg == null), isTrue);
    expect(ta.stufenSchnitt().avg, isNull);
    expect(ta.openDays(), isEmpty);
    expect(ta.verlauf().start, '2026-03-10');
    // Vorrat neu eintragen: Referenz B (500 mg, 15 × 20 mg, dann 15 mg) = 28 Tage wie frisch.
    ta.setStock(50, 10);
    expect(ta.stockInfo()!.rem, 500);
    expect(ta.stockInfo()!.days, 28);
    expect(ta.stockInfo()!.geschaetzt, 0);
    // Gespeichert ist nur der neue Stand.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    final roh = jsonDecode((app.store as MemStore).state!) as Map;
    expect((roh['log'] as Map), isEmpty);
    expect((app.store as MemStore).notizbuch, '[]');
    // Neustart der App: derselbe neue Stand.
    final a2 = AppState(app.store, clock: () => jetzt);
    await t.runAsync(a2.laden);
    expect(a2.taper.st.log, isEmpty);
    expect(a2.hatPin, isFalse);
    expect(a2.hatWort, isFalse);
    expect(a2.sperrMinuten, 2);
    expect(a2.notizbuch, isEmpty);
  });

  testWidgets('Abbrechen: im Bestätigungsfenster oder im Fragebogen → alles bleibt', (t) async {
    final app = await vollerStand(t);
    final vorher = jsonEncode(app.taper.exportJson());
    await reiter(t, 'Plan');
    await tippe(t, find.byKey(const Key('planErstellen')));
    await tippe(t, find.text('Abbrechen'));
    expect(jsonEncode(app.taper.exportJson()), vorher);
    // Bestätigt, dann im Fragebogen zurück.
    await tippe(t, find.byKey(const Key('planErstellen')));
    await planSicherBestaetigen(t);
    await weiter(t);
    await t.enterText(find.byKey(const Key('planDosis')), '20');
    await t.pageBack(); // zurück zur Namensseite
    await t.pumpAndSettle();
    await t.pageBack(); // Fragebogen verlassen
    await t.pumpAndSettle();
    expect(jsonEncode(app.taper.exportJson()), vorher, reason: 'erst beim Speichern wird gelöscht');
    expect(app.hatWort, isTrue);
    expect(app.notizbuch, hasLength(1));
    expect(app.sperrMinuten, 10);
  });

  testWidgets('Fehler im neuen Plan: nichts gelöscht', (t) async {
    final app = await vollerStand(t);
    final vorher = jsonEncode(app.taper.exportJson());
    await reiter(t, 'Plan');
    await tippe(t, find.byKey(const Key('planErstellen')));
    await planSicherBestaetigen(t);
    await weiter(t);
    await t.enterText(find.byKey(const Key('planDosis')), '20');
    await abschnitt(t, 0, '5', '15', '0');
    await weiter(t);
    expect(find.byKey(const Key('planFehler')), findsNothing);
    expect(jsonEncode(app.taper.exportJson()), vorher, reason: 'noch nichts gespeichert');
  });

  testWidgets('Höhere Dosis oder langsamer: gilt sofort (Neustart, keine 48 h)', (t) async {
    final app = await vollerStand(t); // bisher 10 mg
    await neuerPlanUi(t, dosis: '25', ab: const [['5', '30', '0']]);
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.plan.first, 25);
    expect(app.taper.st.pend, isNull);
    expect(find.text('Dein Plan ist gespeichert.'), findsOneWidget);
  });

  testWidgets('Neustart mit späterem Startdatum', (t) async {
    final app = await vollerStand(t);
    await reiter(t, 'Plan');
    await tippe(t, find.byKey(const Key('planErstellen')));
    await planSicherBestaetigen(t);
    await weiter(t);
    expect(find.byKey(const Key('planStart')), findsOneWidget, reason: 'Startdatum wie beim ersten Plan');
    await t.enterText(find.byKey(const Key('planDosis')), '10');
    await abschnitt(t, 0, '1', '14', '0');
    await tippe(t, find.byKey(const Key('planStart')));
    await tippe(t, find.text('15'));
    await tippe(t, find.text('OK'));
    await weiter(t);
    await weiter(t);
    await tippe(t, find.byKey(const Key('planLos')));
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.t0, '2026-03-15');
    expect(app.taper.vorStart, isTrue);
    expect(app.taper.st.log, isEmpty);
  });

  testWidgets('Import über bestehenden Plan: ebenfalls Neustart', (t) async {
    final app = await vollerStand(t);
    await reiter(t, 'Plan');
    await tippe(t, find.byKey(const Key('planImportieren')));
    await planSicherBestaetigen(t);
    await weiter(t);
    await t.enterText(find.byKey(const Key('importText')), '20 mg 14 Tage\n15 mg 14 Tage\n0 mg 14 Tage');
    await tippe(t, find.byKey(const Key('textAuslesen')));
    await weiter(t);
    await weiter(t);
    await tippe(t, find.byKey(const Key('planLos')));
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.plan, [20, 15, 0]);
    expect(app.taper.st.log, isEmpty);
    expect(app.taper.st.stock, isNull);
    expect(app.hatPin, isFalse);
    expect(app.notizbuch, isEmpty);
  });

  testWidgets('A → B → C: jeder Neustart frisch; Vorrat jedes Mal wie frisch gerechnet', (t) async {
    final app = await vollerStand(t);
    final ta = app.taper;
    for (final (n, erwartet) in [('21', 26.0), ('15', 28.0), ('9', 30.0)]) {
      await neuerPlanUi(t, ab: [['5', n, '15'], ['5', '21', '0']]);
      await tippe(t, find.text('Überspringen'));
      expect(ta.st.log, isEmpty);
      expect(ta.st.stock, isNull);
      ta.setStock(50, 10);
      jetzt = jetzt.add(const Duration(seconds: 30)); // Einnahme kurz nach dem Zählen, in derselben Minute
      await nehme(t, '20');
      expect(ta.stockInfo()!.rem, 480);
      expect(ta.stockInfo()!.days, erwartet, reason: '20 × $n: die heutige Dosis war schon eingerechnet');
      jetzt = jetzt.add(const Duration(days: 2));
      app.auffrischen();
      await t.pumpAndSettle();
    }
  });

  testWidgets('Zurücksetzen: alles weg → Beispiel; danach erster Plan ohne Altlasten', (t) async {
    final app = await vollerStand(t);
    await tippe(t, find.byTooltip('Mehr'));
    await tippe(t, find.byKey(const Key('zuruecksetzen')));
    await t.enterText(find.byKey(const Key('planSicherText')), 'Ich bin mir sicher');
    await tippe(t, find.byKey(const Key('planBackupHaken')));
    await tippe(t, find.byKey(const Key('planSicherWeiter')));
    expect(app.beispiel, isTrue);
    expect(app.hatPin, isFalse);
    expect(app.hatWort, isFalse);
    expect(app.notizbuch, isEmpty);
    expect(app.sperrMinuten, 2);
    expect(app.erinnerung, const ErinnerungEinstellung());
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect((app.store as MemStore).state, isNull);
    await t.pageBack();
    await t.pumpAndSettle();
    await reiter(t, 'Heute');
    await tippe(t, find.byKey(const Key('planErstellen')));
    expect(find.byKey(const Key('planSicherDialog')), findsNothing, reason: 'Beispiel: keine Bestätigung');
    await weiter(t);
    await t.enterText(find.byKey(const Key('planDosis')), '20');
    await abschnitt(t, 0, '5', '21', '0');
    await weiter(t);
    await weiter(t);
    await tippe(t, find.byKey(const Key('planLos')));
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.log, isEmpty);
    expect(app.taper.st.stock, isNull);
    expect(app.taper.st.t0, '2026-03-10');
    // Vorrat-Karte ohne die Tablettenstärken des Beispiels (5 / 2 mg)
    await reiter(t, 'Heute');
    await finde(t, find.byKey(const Key('staerke0')));
    expect(t.widget<TextField>(find.byKey(const Key('staerke0'))).controller!.text, '');
    expect(find.byKey(const Key('staerke1')), findsNothing);
    await t.enterText(find.byKey(const Key('anzahl0')), '10');
    await t.enterText(find.byKey(const Key('staerke0')), '10');
    await tippe(t, find.byKey(const Key('vorratSpeichern')));
    expect(app.taper.st.tabs!.str, [10]);
    expect(app.taper.stockInfo()!.rem, 100);
  });

  testWidgets('Neustart: Fragebogen ohne alte Angaben, Vorrat-Karte ohne alte Stärken', (t) async {
    final app = await vollerStand(t);
    app.taper.st.person = 'Alex';
    await reiter(t, 'Plan');
    await tippe(t, find.byKey(const Key('planErstellen')));
    await planSicherBestaetigen(t);
    expect(t.widget<TextField>(find.byKey(const Key('planPerson'))).controller!.text, '');
    await weiter(t);
    expect(t.widget<TextField>(find.byKey(const Key('planMed'))).controller!.text, 'Diazepam', reason: 'Vorgabe wie neu');
    expect(t.widget<TextField>(find.byKey(const Key('planDosis'))).controller!.text, '');
    await t.enterText(find.byKey(const Key('planDosis')), '20');
    await abschnitt(t, 0, '5', '21', '0');
    await weiter(t);
    await weiter(t);
    await tippe(t, find.byKey(const Key('planLos')));
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.person, isNull);
    await reiter(t, 'Heute');
    await finde(t, find.byKey(const Key('staerke0')));
    expect(t.widget<TextField>(find.byKey(const Key('staerke0'))).controller!.text, '');
    expect(find.byKey(const Key('staerke1')), findsNothing);
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

  testWidgets('Sicherung vorher gespeichert: nach dem Neustart zurückholbar', (t) async {
    final d = FakeDateien();
    final app = await vollerStand(t, d: d);
    d.zumOeffnen = await t.runAsync<String?>(() => app.sicherungErstellen());
    final alt = jsonEncode(app.taper.exportJson());
    await neuerPlanUi(t);
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.log, isEmpty);
    await t.runAsync(() => app.sicherungLaden(d.zumOeffnen!));
    await t.pumpAndSettle();
    expect(jsonEncode(app.taper.exportJson()), alt);
    expect(app.notizbuch, hasLength(1), reason: 'Notizbuch kommt mit der Sicherung zurück');
  });
}
