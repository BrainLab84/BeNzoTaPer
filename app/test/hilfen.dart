// Gemeinsame Helfer für die Oberflächen-Tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/sicherung.dart';
import 'package:tapering_buddy/store.dart';

/// Uhr, die der Test vorstellen kann.
DateTime jetzt = DateTime.utc(2026, 3, 10, 12);

Map<String, dynamic> eintrag(double v, double plan, {int stage = 0}) => {
      'it': [
        {'t': '08:00', 'v': v, 'ts': 0}
      ],
      'dose': v,
      'plan': plan,
      'stage': stage,
      'r': v > plan + 1e-9 ? 'lapse' : 'ok',
    };

/// Startet die App. Sie öffnet in Heute; [aufReiter] wechselt danach (Standard: Heute).
Future<AppState> starte(WidgetTester t,
    {Map<String, dynamic>? json, bool einrichten = true, String? aufReiter = 'Heute', Dateien? dateien}) async {
  t.view.physicalSize = const Size(1000, 7000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final store = MemStore()..disc = true;
  final app = AppState(store, clock: () => jetzt, dateien: dateien);
  await t.runAsync(app.laden);
  if (json != null) {
    expect(app.taper.importJson(json), isTrue);
  } else if (einrichten) {
    expect(app.taper.setup(dose: 10, step: 1, minStep: 0.5, days: 14, goal: 0), isNull);
  }
  await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpAndSettle();
  if (aufReiter != null && aufReiter != 'Heute') await reiter(t, aufReiter);
  return app;
}

Finder txt(String s) => find.textContaining(s, findRichText: true);

/// Kartentitel stehen in Großbuchstaben.
Finder titel(String s) => find.text(s.toUpperCase());

/// Wechselt in den Reiter, in dem [f] steht (aktueller Reiter zuerst). „Heute eintragen“ steht
/// über dem Kalender und „Tagebuch heute“ im Fortschritt; wo genau, prüft `reiter_test.dart`.
Future<void> finde(WidgetTester t, Finder f) async {
  if (f.evaluate().isNotEmpty || find.byType(NavigationBar).evaluate().isEmpty) return;
  for (final r in ['Kalender', 'Heute', 'Fortschritt', 'Plan']) {
    await reiter(t, r);
    if (f.evaluate().isNotEmpty) return;
  }
}

/// Text in ein Feld schreiben – das Feld wird in den Reitern gesucht.
Future<void> schreibe(WidgetTester t, Finder f, String text) async {
  await finde(t, f);
  await t.enterText(f, text);
}

/// „Einnahme“ antippen, Menge eingeben, OK (Uhrzeit = jetzt).
Future<void> nehme(WidgetTester t, String menge) async {
  await tippe(t, find.byKey(const Key('einnahme')));
  await t.enterText(find.byKey(const Key('menge')), menge);
  await tippe(t, find.byKey(const Key('plus')));
}

Future<void> tippe(WidgetTester t, Finder f) async {
  await finde(t, f);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Map<String, dynamic> basis({String start = '2026-03-01', Map<String, dynamic>? log, List<num>? plan}) => {
      'name': 'Diazepam',
      'unit': 'mg',
      'step': 1,
      'min': 0.5,
      'target': 14,
      'plan': plan ?? [10, 9, 8, 7],
      'days': [
        for (var i = 0; i < (plan ?? [10, 9, 8, 7]).length; i++) 14
      ],
      'stage': 0,
      'stageStart': start,
      't0': start,
      'log': log ?? {},
      'notes': {},
    };

/// Über die untere Leiste zu einem Reiter wechseln.
Future<void> reiter(WidgetTester t, String name) async {
  await t.tap(find.byKey(ValueKey('reiter-$name')));
  await t.pumpAndSettle();
}

/// Name des gerade gewählten Reiters (steht nur noch unten in der Leiste, oben ist SOS).
String aktuellerReiter(WidgetTester t) {
  final nb = t.widget<NavigationBar>(find.byType(NavigationBar));
  return (nb.destinations[nb.selectedIndex] as NavigationDestination).label;
}

/// Fenster „Bist du dir sicher?“ vor einem neuen Plan ausfüllen und weiter.
Future<void> planSicherBestaetigen(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('planSicherText')), 'Ja, ich bin mir sicher');
  await t.tap(find.byKey(const Key('planBackupHaken')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('planSicherWeiter')));
  await t.pumpAndSettle();
}
