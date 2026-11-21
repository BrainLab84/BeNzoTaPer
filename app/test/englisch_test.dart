// Englische Fassung: Sprachwahl beim ersten Start, kein deutscher Text sichtbar, Sprachwechsel zur
// Laufzeit, Notruf je Sprache, alle Kern-Meldungen in beiden Sprachen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/i18n/meldungen.dart';
import 'package:tapering_buddy/i18n/txt.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_core/tapering_core.dart';

import 'hilfen.dart';

/// Typische deutsche Wörter/Umlaute, die in der englischen Oberfläche nicht vorkommen dürfen.
final _de = RegExp(
    r'[äöüÄÖÜß]|\b(Heute|Stufe|Stufen|Tage|Tag|Dosis|nicht|oder|und|der|die|das|ich|mit|für|noch|wird|Vorrat|Sicherung|Kalender|Abbrechen|Zurück|Weiter|Notizen?|Einnahme|Wochen?|Verlauf|Hinweise?|Plan erstellen)\b');

List<String> sichtbar(WidgetTester t) => [for (final r in t.widgetList<RichText>(find.byType(RichText))) r.text.toPlainText()];

void keinDeutsch(WidgetTester t, String wo) {
  final bad = sichtbar(t).where(_de.hasMatch).toList();
  expect(bad, isEmpty, reason: '$wo: deutscher Text in der englischen Oberfläche');
}

Future<AppState> startEn(WidgetTester t, {Map<String, dynamic>? json, bool einrichten = true, double hoehe = 7000}) async {
  AppState.spracheStandard = 'en';
  t.view.physicalSize = Size(1000, hoehe);
  t.view.devicePixelRatio = 1;
  addTearDown(() {
    t.view.reset();
    AppState.spracheStandard = 'de';
    Txt.setzen('de');
  });
  final app = AppState(MemStore()..disc = true, clock: () => jetzt);
  await t.runAsync(app.laden);
  await t.runAsync(() => app.spracheWaehlen('en'));
  if (json != null) {
    expect(app.taper.importJson(json), isTrue);
  } else if (einrichten) {
    expect(app.taper.setup(dose: 10, step: 1, minStep: 0.5, days: 14, goal: 0), isNull);
  }
  await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpAndSettle();
  return app;
}

Future<void> reiterEn(WidgetTester t, String name) async {
  await t.tap(find.byKey(ValueKey('reiter-$name')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Erster Start: Sprachwahl, Englisch gespeichert, danach keine Wahl mehr', (t) async {
    t.view.physicalSize = const Size(900, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.reset();
      AppState.spracheStandard = 'de';
      Txt.setzen('de');
    });
    AppState.spracheStandard = null;
    final st = MemStore();
    var app = AppState(st, clock: () => jetzt);
    await t.runAsync(app.laden);
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Bitte Sprache wählen'), findsOneWidget);
    expect(find.text('Please choose a language'), findsOneWidget);
    await t.tap(find.byKey(const Key('sprache_en')));
    await t.pumpAndSettle();
    expect(find.text('Medical disclaimer'), findsOneWidget);
    keinDeutsch(t, 'Hinweise');
    expect(st.einstellungen, contains('"lang":"en"'));
    // Neustart: Sprache bleibt, keine erneute Wahl.
    app = AppState(st, clock: () => jetzt);
    await t.runAsync(app.laden);
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.text('Please choose a language'), findsNothing);
    expect(find.text('Medical disclaimer'), findsOneWidget);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Continue'));
    await t.pumpAndSettle();
    expect(find.text('Nice to have you here.'), findsOneWidget);
    keinDeutsch(t, 'Kalender ohne Plan');
  });

  testWidgets('Alte Installation (Hinweis schon gelesen) ohne Sprachwahl bleibt Deutsch', (t) async {
    t.view.physicalSize = const Size(900, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(() {
      t.view.reset();
      AppState.spracheStandard = 'de';
    });
    AppState.spracheStandard = null;
    final app = AppState(MemStore()..disc = true, clock: () => jetzt);
    await t.runAsync(app.laden);
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(app.sprache, 'de');
    expect(find.text('Bitte Sprache wählen'), findsNothing);
    expect(find.text('Schön, dass du da bist.'), findsOneWidget);
  });

  testWidgets('Englische Tour: alle Reiter und Seiten ohne deutschen Text', (t) async {
    final app = await startEn(t);
    keinDeutsch(t, 'Calendar');
    await reiterEn(t, 'Today');
    keinDeutsch(t, 'Today');
    await reiterEn(t, 'Plan');
    keinDeutsch(t, 'Plan');
    await reiterEn(t, 'Progress');
    keinDeutsch(t, 'Progress');
    // Mehr
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    keinDeutsch(t, 'More');
    expect(find.text('Language'), findsOneWidget);
    // Anleitung
    await t.tap(find.text('Guide'));
    await t.pumpAndSettle();
    expect(find.text('1. What is this app for?'), findsWidgets);
    keinDeutsch(t, 'Guide');
    await t.tap(find.text('Back to the app'));
    await t.pumpAndSettle();
    // Hinweise nochmal
    await t.ensureVisible(find.byKey(const Key('hinweiseNochmal')));
    await t.tap(find.byKey(const Key('hinweiseNochmal')));
    await t.pumpAndSettle();
    keinDeutsch(t, 'Hinweise');
    await t.tap(find.widgetWithText(FilledButton, 'Continue'));
    await t.pumpAndSettle();
    expect(app.sprache, 'en');
  });

  testWidgets('Englische Tour 2: Tagfenster, Notizbuch, SOS-Seiten, Plan-Assistent, PIN, Sicherung, Vorrat, Halten, Bericht', (t) async {
    final app = await startEn(t, json: basis(start: '2026-03-01', plan: [10, 9, 8, 7], log: {
      '2026-03-05': eintrag(10, 10),
      '2026-03-06': eintrag(11, 10),
      '2026-03-08': eintrag(10, 10),
    }));
    void zurueck() => Navigator.of(t.element(find.byType(Scaffold).last)).pop();
    Future<void> besuche(Finder f, String wo, {bool zu = true}) async {
      await t.ensureVisible(f);
      await t.tap(f);
      await t.pumpAndSettle();
      keinDeutsch(t, wo);
      if (zu) {
        zurueck();
        await t.pumpAndSettle();
      }
    }

    // Kalender: Tag öffnen (fehlender Tag, Tag mit Eintrag), Notizbuch
    await t.tap(find.byKey(const Key('tag-2026-03-06')));
    await t.pumpAndSettle();
    keinDeutsch(t, 'Tagfenster');
    zurueck();
    await t.pumpAndSettle();
    await besuche(find.byKey(const Key('notizbuchKnopf')), 'Notizbuch');
    await t.tap(find.byKey(const Key('sosKnopf')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    keinDeutsch(t, 'SOS');
    zurueck();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();

    // Heute: Halten-Dialog, Eintrag, Nachtragen
    await reiterEn(t, 'Today');
    if (find.text('Hold dose').evaluate().isNotEmpty) {
      await t.ensureVisible(find.text('Hold dose'));
      await t.tap(find.text('Hold dose'));
      await t.pumpAndSettle();
      keinDeutsch(t, 'Halten-Dialog');
      await t.tap(find.text('Cancel').last);
      await t.pumpAndSettle();
    }

    // Plan: Vorrat, Plan-Assistent
    await reiterEn(t, 'Plan');
    keinDeutsch(t, 'Plan-Reiter');
    if (find.text('Enter supply').evaluate().isNotEmpty) {
      await besuche(find.text('Enter supply'), 'Vorrat eintragen', zu: false);
    }
    await reiterEn(t, 'Plan');
    await t.ensureVisible(find.byKey(const Key('planErstellen')));
    await t.tap(find.byKey(const Key('planErstellen')));
    await t.pumpAndSettle();
    keinDeutsch(t, 'Sicher?-Dialog');
    await t.enterText(find.byType(TextField).last, 'Yes, I am sure');
    await t.pump();
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.text('Continue').last);
    await t.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      keinDeutsch(t, 'Plan-Assistent Schritt $i');
      final weiter = find.text('Next');
      if (weiter.evaluate().isEmpty) break;
      await t.tap(weiter.first);
      await t.pumpAndSettle();
    }
    zurueck();
    await t.pumpAndSettle();

    // Fortschritt + Bericht
    await reiterEn(t, 'Progress');
    keinDeutsch(t, 'Progress');
    await t.ensureVisible(find.byKey(const Key('berichtLesen')));
    await t.tap(find.byKey(const Key('berichtLesen')));
    await t.pump(const Duration(milliseconds: 300));
    keinDeutsch(t, 'Bericht');

    // Mehr: PIN, Sicherung
    zurueck();
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    keinDeutsch(t, 'Mehr mit Plan');
    await besuche(find.text('Set up PIN lock'), 'PIN einrichten');
    await besuche(find.text('Save backup'), 'Sicherung speichern');
    await besuche(find.text('Load backup'), 'Sicherung laden', zu: false);
    expect(app.sprache, 'en');
  });

  testWidgets('Notruf: Deutsch mit Telefonseelsorge, Englisch ohne deutsche Hotline', (t) async {
    await startEn(t, hoehe: 3600);
    await t.tap(find.byKey(const Key('sosKnopf')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    final en = sichtbar(t).join('\n');
    expect(en, contains('112'));
    expect(en, contains('local emergency number'));
    expect(en, isNot(contains('0800')));
    expect(en, isNot(contains('Telefonseelsorge')));
    keinDeutsch(t, 'SOS');
  });

  testWidgets('Sprachwechsel zur Laufzeit in „Mehr“ (de → en → de)', (t) async {
    final app = await starte(t, aufReiter: 'Kalender');
    expect(find.byKey(const ValueKey('reiter-Heute')), findsOneWidget);
    await t.tap(find.byTooltip('Mehr'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('spracheWechseln')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sprache_en')));
    await t.pumpAndSettle();
    expect(app.sprache, 'en');
    expect(find.byKey(const ValueKey('reiter-Today')), findsOneWidget);
    keinDeutsch(t, 'nach Wechsel');
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('spracheWechseln')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sprache_de')));
    await t.pumpAndSettle();
    expect(app.sprache, 'de');
    expect(find.byKey(const ValueKey('reiter-Heute')), findsOneWidget);
  });

  test('Alle Kern-Meldungen gibt es in beiden Sprachen', () {
    const sonder = <MeldungCode, List<Object>>{
      MeldungCode.schritteErkannt: [3, 1],
      MeldungCode.abschnittEndetBeiNull: [1],
      MeldungCode.abschnittBisUeberStart: [0, 5.0],
      MeldungCode.abschnittBisUeberVorigem: [2, 5.0, 1],
    };
    for (final c in MeldungCode.values) {
      final m = Meldung(c, sonder[c] ?? [1, 3650]);
      Txt.setzen('de');
      final de = meldungText(m);
      Txt.setzen('en');
      final en = meldungText(m);
      Txt.setzen('de');
      expect(de, isNotEmpty, reason: '$c de');
      expect(en, isNotEmpty, reason: '$c en');
      expect(_de.hasMatch(en), isFalse, reason: '$c: deutscher Text im englischen Satz: $en');
    }
    for (final f in SicherungFehler.values) {
      Txt.setzen('en');
      final en = sicherungFehlerText(f);
      Txt.setzen('de');
      expect(_de.hasMatch(en), isFalse, reason: '$f: $en');
    }
  });

  test('Zahlen und Datum je Sprache', () {
    Txt.setzen('de');
    expect(fz(2.5), '2,5');
    expect(datum('2026-11-20'), '20.11.2026');
    Txt.setzen('en');
    expect(fz(2.5), '2.5');
    expect(datum('2026-11-20'), '20/11/2026');
    Txt.setzen('de');
  });
}
