import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/sicherung.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_core/tapering_core.dart';

class FakeDateien implements Dateien {
  String? name, geteilt, zumOeffnen;
  @override
  Future<void> teilen(String n, String inhalt) async {
    name = n;
    geteilt = inhalt;
  }

  @override
  Future<String?> oeffnen() async => zumOeffnen;

  String? bytesName, bytesMime;
  List<int>? bytes;
  @override
  Future<void> teilenBytes(String n, List<int> b, String mime) async {
    bytesName = n;
    bytes = b;
    bytesMime = mime;
  }

  ({String name, List<int> bytes})? datei;
  @override
  Future<({String name, List<int> bytes})?> dateiWaehlen() async => datei;
}

/// Wartet echte Zeit (Isolate-Rechnung), bis [f] etwas findet.
Future<void> warte(WidgetTester t, Finder f) async {
  for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
  await t.pumpAndSettle();
  expect(f, findsWidgets);
}

Future<AppState> start(WidgetTester t, FakeDateien d, {bool einrichten = true}) async {
  t.view.physicalSize = const Size(900, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final app = AppState(MemStore()..disc = true, clock: () => DateTime.utc(2026, 3, 10, 12), dateien: d);
  await t.runAsync(app.laden);
  if (einrichten) app.taper.setup(dose: 10, step: 0.5, minStep: 0.25, days: 14, goal: 0);
  await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpAndSettle();
  return app;
}

Future<void> zuMehr(WidgetTester t) async {
  await t.tap(find.byTooltip('Mehr'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Speichern: Passwort prüfen, verschlüsselt teilen', (t) async {
    final d = FakeDateien();
    final app = await start(t, d);
    await zuMehr(t);
    await t.tap(find.text('Sicherung speichern'));
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('pw1')), 'kurz');
    await t.tap(find.text('Sicherung erstellen und teilen'));
    await t.pump();
    expect(find.text('Mindestens 8 Zeichen.'), findsOneWidget);

    await t.enterText(find.byKey(const Key('pw1')), 'geheim-123');
    await t.enterText(find.byKey(const Key('pw2')), 'geheim-124');
    await t.tap(find.text('Sicherung erstellen und teilen'));
    await t.pump();
    expect(find.text('Die Passwörter stimmen nicht überein.'), findsOneWidget);
    expect(d.geteilt, isNull);

    await t.enterText(find.byKey(const Key('pw2')), 'geheim-123');
    await t.tap(find.text('Sicherung erstellen und teilen'));
    await warte(t, find.text('Sicherung erstellt.'));
    expect(d.name, matches(RegExp(r'^benzotaper-\d{4}-\d\d-\d\d\.json$')));
    expect(istVerschluesselt(d.geteilt!), isTrue);
    expect(d.geteilt, isNot(contains('"plan"')));
    expect(await t.runAsync(() => sicherungEntschluesseln(d.geteilt!, 'geheim-123')), contains('"plan"'));
    expect(app.eingerichtet, isTrue);
  });

  testWidgets('Speichern ohne Passwort: Warnung, Klartext', (t) async {
    final d = FakeDateien();
    await start(t, d);
    await zuMehr(t);
    await t.tap(find.text('Sicherung speichern'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ohne Passwort speichern'));
    await t.pumpAndSettle();
    expect(find.textContaining('kann jeder, der die Datei bekommt'), findsOneWidget);
    expect(find.byKey(const Key('pw1')), findsNothing);
    await t.tap(find.text('Sicherung erstellen und teilen'));
    await warte(t, find.text('Sicherung erstellt.'));
    expect(istVerschluesselt(d.geteilt!), isFalse);
    expect(d.geteilt, contains('"plan"'));
  });

  testWidgets('Laden in „Mehr“: bestätigen, falsches Passwort, richtiges Passwort', (t) async {
    final d = FakeDateien();
    // Sicherung eines anderen Stands (Dosis 20) erzeugen.
    final quelle = AppState(MemStore(), dateien: d);
    await t.runAsync(quelle.laden);
    quelle.taper.setup(dose: 20, step: 1, minStep: 0.5, days: 7, goal: 0);
    d.zumOeffnen = await t.runAsync<String?>(() => quelle.sicherungErstellen(passwort: 'geheim-123'));

    final app = await start(t, d);
    expect(app.taper.s!.plan.first, 10);
    await zuMehr(t);
    await t.tap(find.text('Sicherung laden'));
    await t.pumpAndSettle();
    expect(find.text('Sicherung laden?'), findsOneWidget);
    await t.tap(find.text('Abbrechen'));
    await t.pumpAndSettle();
    expect(app.taper.s!.plan.first, 10);

    await t.tap(find.text('Sicherung laden'));
    await t.pumpAndSettle();
    FilledButton laden() => t.widget<FilledButton>(find.byKey(const Key('planSicherWeiter')));
    expect(laden().onPressed, isNull, reason: 'erst den Satz eintippen');
    expect(find.byKey(const Key('planBackupHaken')), findsNothing, reason: 'kein Häkchen beim Laden');
    await t.enterText(find.byKey(const Key('planSicherText')), 'Ich bin mir sicher.');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Laden'));
    await t.pumpAndSettle();
    expect(find.text('Passwort für die Sicherung'), findsOneWidget);

    await t.enterText(find.byKey(const Key('pwLaden')), 'falsch-123');
    await t.tap(find.widgetWithText(FilledButton, 'Laden'));
    await warte(t, find.text('Passwort falsch – oder die Datei wurde verändert.'));
    expect(app.taper.s!.plan.first, 10);

    await t.enterText(find.byKey(const Key('pwLaden')), 'geheim-123');
    await t.tap(find.widgetWithText(FilledButton, 'Laden'));
    await warte(t, find.text('Sicherung geladen.'));
    expect(app.taper.s!.plan.first, 20);
    expect((app.store as MemStore).state, contains('"plan"'));
  });

  testWidgets('Neues Handy: Sicherung laden direkt auf der Startkarte (ohne Plan)', (t) async {
    final d = FakeDateien();
    final quelle = AppState(MemStore(), dateien: d);
    await t.runAsync(quelle.laden);
    quelle.taper.setup(dose: 20, step: 1, minStep: 0.5, days: 7, goal: 0);
    d.zumOeffnen = await t.runAsync<String?>(() => quelle.sicherungErstellen());

    final app = await start(t, d, einrichten: false);
    expect(find.text('Schön, dass du da bist.'), findsOneWidget);
    await t.tap(find.byKey(const Key('sicherungLadenStart')));
    await t.pumpAndSettle();
    expect(find.text('Sicherung laden?'), findsNothing, reason: 'nichts zu ersetzen');
    expect(app.taper.s!.plan.first, 20);
    expect(find.byKey(const Key('planKopf')), findsNothing, reason: 'Startkarte weg, Plan da');
  });

  testWidgets('Kaputte Datei: Meldung, Stand bleibt', (t) async {
    final d = FakeDateien()..zumOeffnen = 'Einkaufsliste';
    final app = await start(t, d);
    await zuMehr(t);
    await t.tap(find.text('Sicherung laden'));
    await t.pumpAndSettle();
    // Fehler sofort – nicht erst „Stand ersetzen?“ fragen.
    expect(find.text('Sicherung laden?'), findsNothing);
    expect(find.text('Die Datei ist keine gültige Sicherung oder beschädigt.'), findsOneWidget);
    expect(app.taper.s!.plan.first, 10);
  });

  testWidgets('Sicherung aus neuerer Version: Meldung sofort, keine Ersetzen-Frage (Audit 20.11.)', (t) async {
    final d = FakeDateien()
      ..zumOeffnen = jsonEncode({'format': sicherungFormat, 'v': sicherungVersion + 1, 'kdf': 'argon2id'});
    final app = await start(t, d);
    await zuMehr(t);
    await t.tap(find.text('Sicherung laden'));
    await t.pumpAndSettle();
    expect(find.text('Sicherung laden?'), findsNothing);
    expect(find.textContaining('neueren App-Version'), findsOneWidget);
    expect(app.taper.s!.plan.first, 10);
  });
}
