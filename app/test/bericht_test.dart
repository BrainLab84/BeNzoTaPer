// Diagramm für den Arzt: Knöpfe im Fortschritt, PDF teilen, Lesen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/bericht.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/sicherung.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';

class TeilDateien implements Dateien {
  String? name, mime;
  List<int>? bytes;
  @override
  Future<void> teilen(String n, String inhalt) async {}
  @override
  Future<void> teilenBytes(String n, List<int> b, String m) async {
    name = n;
    bytes = b;
    mime = m;
  }

  @override
  Future<String?> oeffnen() async => null;
  @override
  Future<({String name, List<int> bytes})?> dateiWaehlen() async => null;
}

Future<AppState> los(WidgetTester t, TeilDateien d, {bool plan = true}) async {
  t.view.physicalSize = const Size(1000, 5000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final app = AppState(MemStore()..disc = true, clock: () => jetzt, dateien: d);
  await t.runAsync(app.laden);
  if (plan) {
    expect(app.taper.setup(dose: 10, step: 1, minStep: .5, days: 14, goal: 0), isNull);
    app.aenderung();
  }
  await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpAndSettle();
  return app;
}

Future<void> warte(WidgetTester t, bool Function() fertig) async {
  for (var i = 0; i < 100 && !fertig(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
}

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Fortschritt: „Diagramm als PDF teilen“ teilt ein PDF', (t) async {
    final d = TeilDateien();
    await los(t, d);
    await reiter(t, 'Fortschritt');
    expect(find.byKey(const Key('berichtLesen')), findsOneWidget);
    await t.tap(find.byKey(const Key('berichtTeilen')));
    await warte(t, () => d.bytes != null);
    expect(d.name, 'Verlauf_2026-03-10.pdf');
    expect(d.mime, 'application/pdf');
    expect(String.fromCharCodes(d.bytes!.take(5)), '%PDF-');
    expect(d.bytes!.length, greaterThan(5000), reason: 'mit Diagramm-Bild');
  });

  testWidgets('Lesen zeigt das Blatt, dort auch teilen', (t) async {
    final d = TeilDateien();
    await los(t, d);
    await reiter(t, 'Fortschritt');
    await t.tap(find.byKey(const Key('berichtLesen')));
    await t.pump(); // Seite baut, Bild rechnet noch (Kreisel dreht – kein pumpAndSettle)
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Diagramm für den Arzt'), findsOneWidget);
    await warte(t, () => find.byKey(const Key('berichtBlatt')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('berichtBlatt')), findsOneWidget);
    await t.tap(find.byKey(const Key('berichtTeilenSeite')));
    await warte(t, () => d.bytes != null);
    expect(String.fromCharCodes(d.bytes!.take(5)), '%PDF-');
  });

  testWidgets('Im Beispiel keine Bericht-Knöpfe', (t) async {
    await los(t, TeilDateien(), plan: false);
    await reiter(t, 'Fortschritt');
    expect(find.byKey(const Key('berichtTeilen')), findsNothing);
    expect(find.byKey(const Key('berichtLesen')), findsNothing);
  });

  test('Datumszeile im Bericht: nichts überdeckt sich (Audit 20.11.)', () {
    // Plan seit gestern: „heute“ direkt neben dem Start → Start weicht
    expect(berichtDatumPlatz((0, 30), (900, 940), (5, 80)), (start: false, ende: true));
    // heute kurz vor dem Ende → Ende weicht
    expect(berichtDatumPlatz((0, 30), (900, 940), (860, 935)), (start: true, ende: false));
    // genug Abstand → alles
    expect(berichtDatumPlatz((0, 30), (900, 940), (400, 480)), (start: true, ende: true));
    // ohne „heute“ (offene Tage/letzte Stufe) und sehr kurzer Verlauf → nur Start
    expect(berichtDatumPlatz((0, 30), (20, 50), null), (start: true, ende: false));
    expect(berichtDatumPlatz((0, 30), (900, 940), null), (start: true, ende: true));
  });
}
