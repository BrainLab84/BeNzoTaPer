// PIN-Sperre: einrichten in „Mehr“, sperren, entsperren, Hintergrund, Neustart, vergessen.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/pin.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';

Future<void> pinEinrichten(WidgetTester t, String a, String b, {String wort = 'Lavendel'}) async {
  await tippe(t, find.byTooltip('Mehr'));
  await tippe(t, find.byKey(const Key('pinEinrichten')));
  await t.enterText(find.byKey(const Key('pinNeu1')), a);
  await t.enterText(find.byKey(const Key('pinNeu2')), b);
  await t.enterText(find.byKey(const Key('wortNeu1')), wort);
  await t.enterText(find.byKey(const Key('wortNeu2')), wort);
  await tippe(t, find.byKey(const Key('pinSpeichern')));
}

Future<void> sperrenUndVergessen(WidgetTester t) async {
  await tippe(t, find.byKey(const Key('jetztSperren')));
  await tippe(t, find.text('PIN vergessen?'));
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
    await t.enterText(find.byKey(const Key('wortNeu2')), 'anders');
    await tippe(t, find.byKey(const Key('pinSpeichern')));
    expect(find.text('Die beiden Schlüsselwörter sind nicht gleich.'), findsOneWidget);
    expect(app.hatPin, isFalse, reason: 'nie eine PIN ohne Schlüsselwort');
    await t.enterText(find.byKey(const Key('wortNeu1')), 'ab');
    await t.enterText(find.byKey(const Key('wortNeu2')), 'ab');
    await tippe(t, find.byKey(const Key('pinSpeichern')));
    expect(find.text('Das Schlüsselwort braucht mindestens 3 Zeichen.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('wortNeu1')), 'Lavendel');
    await t.enterText(find.byKey(const Key('wortNeu2')), 'lavendel ');
    await tippe(t, find.byKey(const Key('pinSpeichern')));
    expect(app.hatPin, isTrue);
    expect(app.hatWort, isTrue, reason: 'Groß/Klein und Leerzeichen am Rand egal');
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

  testWidgets('Hintergrund: Standard 2 Minuten, wählbar 2/5/10/30, bleibt gespeichert', (t) async {
    final app = await starte(t);
    await pinEinrichten(t, '2468', '2468');
    expect(app.sperrMinuten, 2);
    Future<void> weg(Duration d) async {
      app.hintergrund();
      jetzt = jetzt.add(d);
      app.vordergrund();
      await t.pumpAndSettle();
    }

    await weg(const Duration(seconds: 119));
    expect(app.gesperrt, isFalse, reason: 'unter 2 Minuten offen');
    await weg(const Duration(seconds: 121));
    expect(find.byType(SperrSeite), findsOneWidget);
    await t.enterText(find.byKey(const Key('pinEingabe')), '2468');
    await tippe(t, find.byKey(const Key('entsperren')));

    if (find.byTooltip('Mehr').evaluate().isNotEmpty) await tippe(t, find.byTooltip('Mehr'));
    for (final m in [2, 5, 10, 30]) {
      expect(find.byKey(Key('sperr$m')), findsOneWidget);
    }
    await tippe(t, find.byKey(const Key('sperr10')));
    expect(app.sperrMinuten, 10);
    await weg(const Duration(minutes: 9));
    expect(app.gesperrt, isFalse, reason: '10 Minuten gewählt');
    await weg(const Duration(minutes: 11));
    expect(app.gesperrt, isTrue);

    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    final a2 = AppState(app.store, clock: () => jetzt);
    await t.runAsync(a2.laden);
    expect(a2.sperrMinuten, 10, reason: 'Einstellung überlebt Neustart');
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

  testWidgets('PIN vergessen: Schlüsselwort → neue PIN; falsches Wort nicht', (t) async {
    final app = await starte(t);
    await pinEinrichten(t, '2468', '2468');
    await sperrenUndVergessen(t);
    expect(txt('offline und hat kein Konto'), findsOneWidget);
    await t.enterText(find.byKey(const Key('wortEingabe')), 'Rose');
    await t.enterText(find.byKey(const Key('pinNeu1')), '1357');
    await t.enterText(find.byKey(const Key('pinNeu2')), '1357');
    await tippe(t, find.byKey(const Key('pinZuruecksetzen')));
    expect(find.text('Schlüsselwort stimmt nicht.'), findsOneWidget);
    expect(app.gesperrt, isTrue);
    expect(app.taper.checkPin('2468'), isTrue, reason: 'alte PIN unverändert');
    await t.enterText(find.byKey(const Key('wortEingabe')), '  LAVENDEL ');
    await tippe(t, find.byKey(const Key('pinZuruecksetzen')));
    expect(app.gesperrt, isFalse);
    expect(app.taper.checkPin('1357'), isTrue);
    expect(app.beispiel, isFalse, reason: 'Daten bleiben');
    // Neue PIN gilt.
    await tippe(t, find.byKey(const Key('jetztSperren')));
    await t.enterText(find.byKey(const Key('pinEingabe')), '1357');
    await tippe(t, find.byKey(const Key('entsperren')));
    expect(app.gesperrt, isFalse);
  });

  testWidgets('Bestehende PIN ohne Schlüsselwort: einmal nachfragen, „Später“ fragt nicht wieder', (t) async {
    final app = await starte(t);
    expect(app.pinSetzen('2468', '2468'), isNull, reason: 'wie vor dem Update');
    expect(app.hatWort, isFalse);
    app.sperren();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pinEingabe')), '2468');
    await tippe(t, find.byKey(const Key('entsperren')));
    expect(app.gesperrt, isTrue, reason: 'erst die Nachfrage');
    expect(find.text('Neu: Lege ein Schlüsselwort fest.'), findsOneWidget);
    await tippe(t, find.byKey(const Key('wortSpaeter')));
    expect(app.gesperrt, isFalse);
    app.sperren();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pinEingabe')), '2468');
    await tippe(t, find.byKey(const Key('entsperren')));
    expect(app.gesperrt, isFalse, reason: 'nur einmal gefragt');
    // Ohne Wort: „PIN vergessen“ bietet nur Zurücksetzen.
    app.sperren();
    await t.pumpAndSettle();
    await tippe(t, find.text('PIN vergessen?'));
    expect(find.byKey(const Key('wortEingabe')), findsNothing);
    expect(txt('Ohne Schlüsselwort bleibt nur Zurücksetzen'), findsOneWidget);
  });

  testWidgets('Nachfrage beantwortet: Wort gespeichert, überlebt Neustart, hilft beim Vergessen', (t) async {
    final app = await starte(t);
    app.pinSetzen('2468', '2468');
    app.sperren();
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('pinEingabe')), '2468');
    await tippe(t, find.byKey(const Key('entsperren')));
    await t.enterText(find.byKey(const Key('wortNeu1')), 'Möwe');
    await t.enterText(find.byKey(const Key('wortNeu2')), 'möwe');
    await tippe(t, find.byKey(const Key('wortSpeichern')));
    expect(app.gesperrt, isFalse);
    expect(app.hatWort, isTrue);
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    final a2 = AppState(app.store, clock: () => jetzt);
    await t.runAsync(a2.laden);
    expect(a2.hatWort, isTrue);
    expect(a2.wortPasst('MÖWE'), isTrue);
    expect(a2.wortPasst('Moewe'), isFalse);
  });

  testWidgets('PIN und Wort vergessen: Alles löschen nur mit Bestätigung → Beispiel', (t) async {
    final app = await starte(t);
    await pinEinrichten(t, '2468', '2468');
    await sperrenUndVergessen(t);
    await tippe(t, find.text('Abbrechen'));
    expect(find.byKey(const Key('pinEingabe')), findsOneWidget);
    await tippe(t, find.text('PIN vergessen?'));
    await tippe(t, find.byKey(const Key('allesLoeschen')));
    expect(find.byKey(const Key('resetSicherDialog')), findsOneWidget);
    expect(app.beispiel, isFalse, reason: 'erst nach Bestätigung');
    await t.enterText(find.byKey(const Key('planSicherText')), 'Ich bin mir sicher');
    await tippe(t, find.byKey(const Key('planBackupHaken')));
    await tippe(t, find.byKey(const Key('planSicherWeiter')));
    expect(app.gesperrt, isFalse);
    expect(app.hatWort, isFalse);
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
