import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/start.dart';
import 'package:tapering_buddy/store.dart';

Future<AppState> start(WidgetTester t, MemStore st) async {
  final app = AppState(st, clock: () => DateTime.utc(2026, 3, 10, 12));
  await t.runAsync(app.laden);
  await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
  await t.pump(const Duration(milliseconds: 50));
  return app;
}

void main() {
  testWidgets('Splash: großes Logo (85 % Breite, max. 420 dp) + Urheber-Zeilen unten', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Splash(weiter: () {}, dauer: const Duration(hours: 1))));
    final b = t.getSize(find.byKey(const ValueKey('splashLogo'))).width;
    expect(b, closeTo(1080 / 2.625 * .85, 0.5));
    expect(find.text('Designed & Developed by Benzo Brain'), findsOneWidget);
    expect(find.text('© 2026 Benzo Brain'), findsOneWidget);
    // Zeilen liegen unter dem Logo, am unteren Rand.
    expect(t.getTopLeft(find.byKey(const ValueKey('impressum'))).dy,
        greaterThan(t.getBottomLeft(find.byKey(const ValueKey('splashLogo'))).dy));
    // Tablet: nicht größer als 420 dp.
    t.view.physicalSize = const Size(2400, 2400);
    t.view.devicePixelRatio = 2;
    await t.pump();
    expect(t.getSize(find.byKey(const ValueKey('splashLogo'))).width, 420);
  });

  testWidgets('Hinweis: Weiter erst nach Häkchen, dann Kalender ohne Zwang', (t) async {
    t.view.physicalSize = const Size(900, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final st = MemStore();
    await start(t, st);
    expect(find.text('Medizinischer Disclaimer'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Weiter'));
    await t.pumpAndSettle();
    expect(st.disc, isTrue);
    // Kein Zwang: direkt der Kalender mit Startkarte, ohne Plan.
    expect(find.text('Kalender'), findsWidgets);
    expect(find.text('Schön, dass du da bist.'), findsOneWidget);
    expect(find.byKey(const Key('planErstellen')), findsOneWidget);
    expect(find.byKey(const Key('planImportieren')), findsOneWidget);
    expect(find.byKey(const Key('monat')), findsOneWidget);
    // Heute ohne Plan: keine zweite Startkarte.
    await t.tap(find.byKey(const ValueKey('reiter-Heute')));
    await t.pumpAndSettle();
    expect(find.text('Schön, dass du da bist.'), findsNothing);
    expect(find.byKey(const Key('planErstellen')), findsNothing);
    expect(find.byKey(const Key('beispielHinweis')), findsOneWidget, reason: 'Beispiel zum Umschauen');
    expect(st.state, isNull, reason: 'nichts gespeichert, solange es keinen Plan gibt');
  });

  testWidgets('Zurück-Taste: Reiter -> Kalender', (t) async {
    final st = MemStore()..disc = true;
    final app = await start(t, st);
    app.taper.setup(dose: 10, step: 0.5, minStep: 0.25, days: 14, goal: 0);
    app.aenderung();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('reiter-Heute')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('dosis')), findsOneWidget, reason: 'Heute-Reiter');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('monat')), findsOneWidget, reason: 'Zurück → Kalender');
  });
}
