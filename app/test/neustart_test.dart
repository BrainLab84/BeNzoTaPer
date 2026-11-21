// Plan über den Fragebogen anlegen, App neu starten (selber Speicher): Plan und Name müssen da sein.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/store.dart';

void main() {
  // Plan über den Fragebogen anlegen, App „neu starten“ mit demselben Speicher.
  for (final (name, dosis, schritt, tage, bis) in [
    ('20→10 2,5/7, dann 1/21', '20', '2,5', '7', '10'),
    ('10→0 1/14', '10', '1', '14', '0'),
    ('7,5→0 0,5/10', '7,5', '0,5', '10', '0'),
  ]) {
    testWidgets('Neustart behält Plan: $name', (t) async {
      t.view.physicalSize = const Size(1000, 7000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = MemStore()..disc = true;
      final jetzt = DateTime.utc(2026, 11, 18, 18);
      final app = AppState(store, clock: () => jetzt);
      await t.runAsync(app.laden);
      await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('planErstellen')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('planPerson')), 'Alex');
      await t.tap(find.byKey(const Key('planWeiter')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('planDosis')), dosis);
      await t.enterText(find.byKey(const Key('abSchritt0')), schritt);
      await t.enterText(find.byKey(const Key('abTage0')), tage);
      await t.enterText(find.byKey(const Key('abBis0')), bis);
      if (bis != '0') {
        await t.tap(find.byKey(const Key('abschnittPlus')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('abSchritt1')), '1');
        await t.enterText(find.byKey(const Key('abTage1')), '21');
        await t.enterText(find.byKey(const Key('abBis1')), '0');
      }
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('planWeiter')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('planWeiter')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('planLos')));
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(app.taper.s, isNotNull, reason: 'Plan angelegt');
      // Eintragen, damit auch ein Tag drin ist
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      final gespeichert = store.state;
      expect(gespeichert, isNotNull, reason: 'gespeichert');
      // „Neustart“
      final app2 = AppState(store, clock: () => jetzt.add(const Duration(days: 1)));
      await t.runAsync(app2.laden);
      expect(app2.taper.s, isNotNull, reason: 'Plan nach Neustart weg! Gespeichert: $gespeichert');
      expect(app2.taper.st.person, 'Alex');
    });
  }
}
