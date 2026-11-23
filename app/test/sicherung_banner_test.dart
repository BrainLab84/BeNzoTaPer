// Dezente Erinnerung zum Sichern (Banner in Heute).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';

import 'hilfen.dart';

void main() {
  group('Erinnerung zum Sichern', () {
    setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

    testWidgets('14 Tage, nur mit Änderungen, Wegtippen verschiebt, Sicherung setzt zurück', (t) async {
      final app = await starte(t);
      Future<void> tag(int n) async {
        jetzt = jetzt.add(Duration(days: n));
        app.auffrischen();
        await t.pumpAndSettle();
      }

      final banner = find.byKey(const Key('sicherungBanner'));
      expect(banner, findsNothing);
      await tag(13);
      expect(banner, findsNothing, reason: 'erst nach 14 Tagen');
      await tag(1);
      expect(banner, findsOneWidget);
      expect(find.text('Seit einer Weile nicht gesichert.'), findsOneWidget);
      await tippe(t, find.byKey(const Key('sicherungBannerWeg')));
      expect(banner, findsNothing);
      await tag(13);
      expect(banner, findsNothing, reason: 'weggetippt: 14 Tage Ruhe');
      await tag(1);
      expect(banner, findsOneWidget);

      app.sicherungGemacht();
      await t.pumpAndSettle();
      expect(banner, findsNothing);
      await tag(20);
      expect(banner, findsNothing, reason: 'nichts geändert seit der Sicherung');
      app.taper.setStock(20, 5);
      app.aenderung();
      await t.pumpAndSettle();
      expect(banner, findsOneWidget, reason: 'Änderung und über 14 Tage her');

      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      final a2 = AppState(app.store, clock: () => jetzt);
      await t.runAsync(a2.laden);
      expect(a2.sicherungErinnern, isTrue, reason: 'überlebt Neustart');
    });
  });
}
