// PIN-Sperre: einrichten in „Mehr“, sperren, entsperren, Hintergrund, Neustart, vergessen.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/pin.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';

Future<void> pinEinrichten(WidgetTester t, String a, String b) async {
  await tippe(t, find.byTooltip('Mehr'));
  await tippe(t, find.byKey(const Key('pinEinrichten')));
  await t.enterText(find.byKey(const Key('pinNeu1')), a);
  await t.enterText(find.byKey(const Key('pinNeu2')), b);
  await tippe(t, find.byKey(const Key('pinSpeichern')));
}

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Einrichten: 4–8 Ziffern, zweimal gleich', (t) async {
    final app = await starte(t);
    await pinEinrichten(t, '12', '12');
    expect(find.text('4 bis 8 Ziffern.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('pinNeu1')), '123456789');
    await t.enterText(find.byKey(const Key('pinNeu2')), '123456789');
    await tippe(t, find.byKey(const Key('pinSpeichern')));
    expect(find.text('4 bis 8 Ziffern.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('pinNeu1')), '1234');
    await t.enterText(find.byKey(const Key('pinNeu2')), '1235');
    await tippe(t, find.byKey(const Key('pinSpeichern')));
    expect(find.text('Die beiden PINs stimmen nicht überein.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('pinNeu2')), '1234');
    await tippe(t, find.byKey(const Key('pinSpeichern')));
    expect(app.hatPin, isTrue);
    expect(find.text('PIN-Sperre ist an'), findsOneWidget);
    expect(app.gesperrt, isFalse, reason: 'nach dem Einrichten nicht gleich gesperrt');
  });

  testWidgets('Jetzt sperren, falsche PIN, richtige PIN; liegt über allem', (t) async {
    final app = await starte(t);
    await pinEinrichten(t, '2468', '2468');
    await tippe(t, find.byKey(const Key('jetztSperren')));
    expect(find.byType(SperrSeite), findsOneWidget);
    expect(find.text('Mehr'), findsNothing, reason: 'Mehr liegt unsichtbar darunter');
    await t.enterText(find.byKey(const Key('pinEingabe')), '1111');
    await tippe(t, find.byKey(const Key('entsperren')));
    expect(find.text('Falsche PIN.'), findsOneWidget);
    expect(app.gesperrt, isTrue);
    await t.enterText(find.byKey(const Key('pinEingabe')), '2468');
    await tippe(t, find.byKey(const Key('entsperren')));
    expect(app.gesperrt, isFalse);
    expect(find.byType(SperrSeite), findsNothing);
    expect(find.text('PIN-Sperre ist an'), findsOneWidget, reason: 'wieder in „Mehr“, wo man war');
  });

  testWidgets('Hintergrund: unter 1 Minute offen, darüber gesperrt', (t) async {
    final app = await starte(t);
    await pinEinrichten(t, '2468', '2468');
    app.hintergrund();
    jetzt = jetzt.add(const Duration(seconds: 50));
    app.vordergrund();
    await t.pumpAndSettle();
    expect(app.gesperrt, isFalse);
    app.hintergrund();
    jetzt = jetzt.add(const Duration(seconds: 61));
    app.vordergrund();
    await t.pumpAndSettle();
    expect(find.byType(SperrSeite), findsOneWidget);
  });

  testWidgets('Neustart: mit PIN gesperrt, ohne PIN nicht', (t) async {
    final store = MemStore()..disc = true;
    final a1 = AppState(store, clock: () => jetzt);
    await t.runAsync(a1.laden);
    expect(a1.taper.setup(dose: 10, step: 1, minStep: .5, days: 14, goal: 0), isNull);
    expect(a1.gesperrt, isFalse);
    expect(a1.pinSetzen('1234', '1234'), isNull);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect(jsonDecode(store.state!)['pin'], isNotNull);
    final a2 = AppState(store, clock: () => jetzt);
    await t.runAsync(a2.laden);
    expect(a2.gesperrt, isTrue);
    await t.pumpWidget(TaperingBuddy(app: a2, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.byType(SperrSeite), findsOneWidget);
    expect(find.byKey(const Key('sosKnopf')).evaluate().isNotEmpty || find.textContaining('SOS').evaluate().isNotEmpty,
        isTrue,
        reason: 'SOS auch im Sperrbildschirm');
  });

  testWidgets('PIN vergessen: Abbrechen oder alles löschen → Beispiel', (t) async {
    final app = await starte(t);
    await pinEinrichten(t, '2468', '2468');
    await tippe(t, find.byKey(const Key('jetztSperren')));
    await tippe(t, find.text('PIN vergessen?'));
    expect(txt('Ohne PIN kommt niemand an die Daten'), findsOneWidget);
    await tippe(t, find.text('Abbrechen'));
    expect(find.byKey(const Key('pinEingabe')), findsOneWidget);
    await tippe(t, find.text('PIN vergessen?'));
    await tippe(t, find.byKey(const Key('allesLoeschen')));
    expect(app.gesperrt, isFalse);
    expect(app.beispiel, isTrue, reason: 'danach wieder das Beispiel');
    expect(app.hatPin, isFalse);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect((app.store as MemStore).state, isNull, reason: 'gespeicherter Stand gelöscht');
  });

  testWidgets('PIN-Sperre aus; im Beispiel keine PIN', (t) async {
    final app = await starte(t);
    await pinEinrichten(t, '2468', '2468');
    await tippe(t, find.byKey(const Key('pinAus')));
    expect(app.hatPin, isFalse);
    expect(find.byKey(const Key('pinEinrichten')), findsOneWidget);
  });

  testWidgets('Beispiel: PIN-Sperre erst mit eigenem Plan', (t) async {
    await starte(t, einrichten: false, aufReiter: null);
    await tippe(t, find.byTooltip('Mehr'));
    expect(find.text('Geht, sobald du deinen eigenen Plan angelegt hast.'), findsNWidgets(2),
        reason: 'PIN + Erinnerung');
    expect(find.byKey(const Key('pinEinrichten')), findsNothing);
  });

  testWidgets('Zurücksetzen: erst Satz + Häkchen, dann alles weg → Beispiel', (t) async {
    final app = await starte(t);
    await tippe(t, find.byTooltip('Mehr'));
    await tippe(t, find.byKey(const Key('zuruecksetzen')));
    expect(find.byKey(const Key('resetSicherDialog')), findsOneWidget);
    expect(app.eingerichtet, isTrue, reason: 'Tippen allein löscht nichts');
    await tippe(t, find.text('Abbrechen'));
    expect(find.byKey(const Key('resetSicherDialog')), findsNothing);
    expect(app.eingerichtet, isTrue);

    await tippe(t, find.byKey(const Key('zuruecksetzen')));
    FilledButton weiter() => t.widget<FilledButton>(find.byKey(const Key('planSicherWeiter')));
    expect(weiter().onPressed, isNull, reason: 'ohne Satz und Häkchen gesperrt');
    await t.enterText(find.byKey(const Key('planSicherText')), 'ich bin mir');
    await tippe(t, find.byKey(const Key('planBackupHaken')));
    expect(weiter().onPressed, isNull, reason: 'Satz unvollständig');
    await t.enterText(find.byKey(const Key('planSicherText')), '  ICH bin mir sicher. ');
    await t.pump();
    expect(weiter().onPressed, isNotNull, reason: 'Groß/Klein, Punkt, Leerzeichen egal');
    await tippe(t, find.byKey(const Key('planSicherWeiter')));
    expect(app.beispiel, isTrue);
    expect(find.byKey(const Key('zuruecksetzen')), findsNothing, reason: 'im Beispiel nichts zu löschen');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    expect((app.store as MemStore).state, isNull);
  });
}
