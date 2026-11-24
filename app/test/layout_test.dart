// Layout: kleine Handys (320/360 dp) und große Schrift (130 %, 200 %) – nirgends darf etwas
// überlaufen (gelb-schwarze Balken) oder abgeschnitten werden.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/store.dart';

/// Echte Schrift laden (Roboto wie auf Android): Die Testschrift macht jedes Zeichen quadratisch breit
/// und würde Überläufe vortäuschen, die es auf dem Handy nicht gibt.
Future<void> schriften() async {
  for (final (fam, dateien) in [
    ('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']),
    ('MaterialIcons', ['MaterialIcons-Regular.otf']),
  ]) {
    final l = FontLoader(fam);
    for (final f in dateien) {
      final pfad = '${Platform.environment['FLUTTER_ROOT']!}'
          '/bin/cache/artifacts/material_fonts/$f';
      l.addFont(Future.value(ByteData.sublistView(File(pfad).readAsBytesSync())));
    }
    await l.load();
  }
}

void main() {
  final szenarien = {
    for (final s
        in (jsonDecode(File('test/paritaet/heute_js.json').readAsStringSync()) as List).cast<Map<String, dynamic>>())
      s['name'] as String: s
  };
  const auswahl = [
    'teilmenge_tabletten_vorrat',
    'ausrutscher_morgen_neue_stufe_woche_tiefer',
    'halten_7_tage',
    'offene_tage_alt_und_neu',
    'vormerkung_abgelaufen',
    'ziel_erreicht_nachsorge',
    'vorrat_reicht_nicht_heute',
    'notiz_und_guter_tag',
  ];

  for (final breite in [320.0, 360.0]) {
    for (final schrift in [1.0, 1.3, 2.0]) {
      testWidgets('Kein Überlauf: $breite dp, Schrift ${(schrift * 100).round()} %', (t) async {
        await t.runAsync(schriften);
        t.view.physicalSize = Size(breite, 9000);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = schrift;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

        Future<void> zeige(String wo) async {
          // Fehler nur während des Zeichnens einsammeln (mit Fundstelle), dann sofort zurückstellen.
          final gesammelt = <String>[];
          final alt = FlutterError.onError;
          FlutterError.onError = (d) {
            final txt = d.toString();
            final ort = RegExp(r'lib/[a-z_]+\.dart:\d+').allMatches(txt).map((m) => m.group(0)).toSet();
            gesammelt.add('${d.exceptionAsString().split('\n').first} $ort');
          };
          try {
            await t.pumpAndSettle(
                const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 30));
          } finally {
            FlutterError.onError = alt;
          }
          if (gesammelt.isNotEmpty)
            fail('$wo ($breite dp, ${(schrift * 100).round()} %): ${gesammelt.toSet().join(' | ')}');
        }

        Future<void> reiter(String n) async {
          await t.tap(find.byKey(ValueKey('reiter-$n')));
          await zeige(n);
        }

        // Ohne Plan
        {
          final app = AppState(MemStore()..disc = true, clock: () => DateTime.utc(2026, 3, 10, 12));
          await t.runAsync(app.laden);
          await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
          await t.pump(const Duration(milliseconds: 50));
          await zeige('Start ohne Plan');
          for (final r in ['Plan', 'Kalender', 'Fortschritt', 'Heute']) {
            await reiter(r);
          }
          await t.tap(find.byKey(const Key('planErstellen')).first);
          await zeige('Plan erstellen: Name');
          await t.tap(find.byKey(const Key('planWeiter')));
          await zeige('Plan erstellen: Abschnitte');
          await t.enterText(find.byKey(const Key('planDosis')), '20');
          await t.enterText(find.byKey(const Key('abSchritt0')), '2,5');
          await t.enterText(find.byKey(const Key('abBis0')), '10');
          await t.tap(find.byKey(const Key('abschnittPlus')));
          await zeige('Plan erstellen: zweiter Abschnitt leer');
          await t.enterText(find.byKey(const Key('abSchritt1')), '1');
          await t.enterText(find.byKey(const Key('abTage1')), '21');
          await t.enterText(find.byKey(const Key('abBis1')), '0');
          await zeige('Plan erstellen: zwei Abschnitte mit Vorschau');
          await t.tap(find.byKey(const Key('planWeiter')));
          await zeige('Plan erstellen: Arzt');
          await t.tap(find.byKey(const Key('planWeiter')));
          await zeige('Plan erstellen: passt sich an');
          await t.tap(find.byKey(const Key('planLos')));
          await t.pump(const Duration(seconds: 5));
          await zeige('PIN nach dem ersten Plan');
          await t.enterText(find.byKey(const Key('pinNeu1')), '1234');
          await t.enterText(find.byKey(const Key('pinNeu2')), '1234');
          await t.enterText(find.byKey(const Key('wortNeu1')), 'Lavendel');
          await t.enterText(find.byKey(const Key('wortNeu2')), 'Lavendel');
          await t.ensureVisible(find.byKey(const Key('pinSpeichern')));
          await t.tap(find.byKey(const Key('pinSpeichern')));
          await zeige('Kalender nach dem ersten Plan');
          await t.tap(find.byTooltip('Mehr'));
          await zeige('Mehr');
          await t.tap(find.text('Sicherung speichern'));
          await zeige('Sicherung speichern');
          await t.pageBack();
          await t.pumpAndSettle();
          await t.ensureVisible(find.byKey(const Key('jetztSperren')));
          await t.tap(find.byKey(const Key('jetztSperren')));
          await zeige('Gesperrt');
          await t.tap(find.text('PIN vergessen?'));
          await zeige('PIN vergessen');
        }

        for (final name in auswahl) {
          final s = szenarien[name]!;
          final jetzt = DateTime.fromMillisecondsSinceEpoch(s['ms'] as int, isUtc: true);
          final st = Map<String, dynamic>.from(s['state'] as Map)..['person'] = 'Maximiliane';
          final app = AppState(
              MemStore()
                ..disc = true
                ..state = jsonEncode(st),
              clock: () => jetzt);
          await t.runAsync(app.laden);
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
          await t.pump(const Duration(milliseconds: 50));
          await zeige('$name: Heute');
          for (final r in ['Plan', 'Kalender', 'Fortschritt']) {
            await reiter(r);
          }
          // Diagramm für den Arzt: Lesen-Seite
          await t.ensureVisible(find.byKey(const Key('berichtLesen')));
          await t.tap(find.byKey(const Key('berichtLesen')));
          for (var i = 0; i < 50 && find.byKey(const Key('berichtBlatt')).evaluate().isEmpty; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
            await t.pump();
          }
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await zeige('$name: Bericht lesen');
          await t.pageBack();
          await zeige('$name: zurück vom Bericht');
          // Verlaufsbericht (Logbuch): Lesen-Seite
          await t.ensureVisible(find.byKey(const Key('logbuchLesen')));
          await t.tap(find.byKey(const Key('logbuchLesen')));
          await zeige('$name: Logbuch lesen');
          await t.pageBack();
          await zeige('$name: zurück vom Logbuch');
          // Vorrat-Karte aufgeklappt (unten in Heute)
          await reiter('Heute');
          final auf = find.textContaining('VORRAT');
          if (auf.evaluate().isNotEmpty) {
            await t.tap(auf.first);
            await zeige('$name: Vorrat aufgeklappt');
          }
          await reiter('Kalender');
          // Ein Tag im Kalender geöffnet
          final heute = jetzt.toIso8601String().substring(0, 10);
          final gestern = jetzt.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
          for (final k in [gestern, heute]) {
            final z = find.byKey(Key('tag-$k'));
            if (z.evaluate().isNotEmpty) {
              await t.tap(z);
              await zeige('$name: Tag $k offen');
            }
          }
          await reiter('Heute');
          await t.tap(find.text('SOS'));
          await t.pump(const Duration(milliseconds: 500));
          final e = t.takeException();
          if (e != null) fail('$name: SOS: $e');
          await t.pumpWidget(const SizedBox());
          await t.pump();
        }
      });
    }
  }
}
