// „Plan anpassen“ in der Dosis-Karte: ab heute alles änderbar, Vorschau live, kurz innehalten bei höher/länger.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/logbuch.dart';

import 'hilfen.dart';

/// Plan 10 / 9 / 8 / 7 mg je 14 Tage ab 01.03.; 01.–09.03. eingetragen; heute 10.03. = Tag 10/14.
Future<AppState> stand(WidgetTester t) =>
    starte(t, json: basis(log: {for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(10, 10)}));

String feld(WidgetTester t, String key) => t.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Vorbelegung: Stufen ab heute, erste Zeile = Tage ab heute', (t) async {
    await stand(t);
    expect(find.byKey(const Key('aendern')), findsNothing, reason: 'altes „Ändern“ ist weg');
    await tippe(t, find.byKey(const Key('anpassen')));
    expect(find.text('Plan anpassen'), findsWidgets);
    expect(feld(t, 'anpDosis0'), '10');
    expect(feld(t, 'anpTage0'), '5', reason: '14 − 9 Tage');
    expect(feld(t, 'anpDosis1'), '9');
    expect(feld(t, 'anpTage1'), '14');
    expect(feld(t, 'anpDosis3'), '7');
    expect(find.byKey(const Key('anpTage3')), findsNothing, reason: 'Ziel ohne Tage');
    expect(txt('Ab heute. Bisherige Tage, Einnahmen und Vorrat bleiben.'), findsOneWidget);
  });

  testWidgets('Länger: Vorschau live, kurz innehalten, gilt sofort; Verlauf bleibt', (t) async {
    final app = await stand(t);
    app.taper.setStock(20, 10); // 200 mg
    app.aenderung();
    await tippe(t, find.byKey(const Key('anpassen')));
    // Vorher: 5 × 10 = 50 → 150; 14 × 9 = 126 → 24; 3 × 8 → 0  ⇒ 22 Tage
    expect(t.widget<Text>(find.byKey(const Key('anpVorrat'))).data, 'Vorrat reicht ca. 22 Tage (bis 31.03.2026)');
    await t.enterText(find.byKey(const Key('anpTage0')), '10');
    await t.pump();
    // 10 × 10 = 100 → 100; 11 × 9 = 99 → 1  ⇒ 21 Tage
    expect(t.widget<Text>(find.byKey(const Key('anpVorrat'))).data, 'Vorrat reicht ca. 21 Tage (bis 30.03.2026)');
    expect(txt('bisher reicht ca. 22 Tage'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('anpEnde'))).data, 'Voraussichtlich bei 7 mg: 17.04.2026');
    expect(txt('bisher 12.04.2026'), findsOneWidget);
    await tippe(t, find.byKey(const Key('anpSpeichern')));
    expect(find.byKey(const Key('anpInnehalten')), findsOneWidget);
    expect(txt('Dein angepasster Plan geht höher oder dauert länger.'), findsOneWidget);
    await tippe(t, find.byKey(const Key('anpJa')));
    expect(find.text('Plan angepasst.'), findsOneWidget);
    expect(app.taper.st.days![0], 19);
    expect(app.taper.st.log.length, 9, reason: 'Einnahmen bleiben');
    expect(app.taper.stockInfo()!.days, 21);
    expect(txt('Nächste Stufe in 10 Tagen (20.03.2026)'), findsOneWidget);
    expect(app.taper.st.pend, isNull, reason: 'keine 48 h');
  });

  testWidgets('Kürzer: kein Innehalten', (t) async {
    final app = await stand(t);
    await tippe(t, find.byKey(const Key('anpassen')));
    await t.enterText(find.byKey(const Key('anpTage0')), '1');
    await tippe(t, find.byKey(const Key('anpSpeichern')));
    expect(find.byKey(const Key('anpInnehalten')), findsNothing);
    expect(app.taper.st.days![0], 10);
    expect(txt('Nächste Stufe morgen (11.03.2026)'), findsOneWidget);
  });

  testWidgets('Höher: Innehalten, „Zurück“ ändert nichts; dann doch', (t) async {
    final app = await stand(t);
    await tippe(t, find.byKey(const Key('anpassen')));
    await t.enterText(find.byKey(const Key('anpDosis0')), '12');
    await tippe(t, find.byKey(const Key('anpSpeichern')));
    await tippe(t, find.text('Zurück'));
    expect(app.taper.st.plan, [10, 9, 8, 7], reason: 'nichts geändert');
    expect(find.byKey(const Key('anpSpeichern')), findsOneWidget, reason: 'noch auf der Seite');
    await tippe(t, find.byKey(const Key('anpSpeichern')));
    await tippe(t, find.byKey(const Key('anpJa')));
    expect(app.taper.st.plan, [10, 12, 9, 8, 7]);
    expect(app.taper.st.stage, 1);
    expect(find.byKey(const Key('dosis')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('dosis'))).data ?? (t.widget<Text>(find.byKey(const Key('dosis'))).textSpan!.toPlainText()),
        '12 mg');
  });

  testWidgets('Stufe dazu und weg; Fehler ändert nichts', (t) async {
    final app = await stand(t);
    await tippe(t, find.byKey(const Key('anpassen')));
    await tippe(t, find.byKey(const Key('anpPlus')));
    expect(find.byKey(const Key('anpDosis4')), findsOneWidget);
    await t.enterText(find.byKey(const Key('anpDosis3')), '7,5');
    await tippe(t, find.byKey(const Key('anpWeg1')));
    expect(find.byKey(const Key('anpDosis4')), findsNothing);
    await t.enterText(find.byKey(const Key('anpDosis0')), '');
    await tippe(t, find.byKey(const Key('anpSpeichern')));
    expect(find.byKey(const Key('anpFehler')), findsOneWidget);
    expect(app.taper.st.plan, [10, 9, 8, 7]);
    await t.enterText(find.byKey(const Key('anpDosis0')), '10');
    await tippe(t, find.byKey(const Key('anpSpeichern')));
    if (find.byKey(const Key('anpJa')).evaluate().isNotEmpty) await tippe(t, find.byKey(const Key('anpJa')));
    expect(app.taper.st.plan, [10, 8, 7.5, 7]);
  });

  testWidgets('Beim Halten: Knopf da, Hinweis, danach Halten beendet', (t) async {
    final app = await stand(t);
    await tippe(t, find.byKey(const Key('halten')));
    await tippe(t, find.text('Ohne Enddatum halten'));
    expect(app.taper.st.hold, isTrue);
    await tippe(t, find.byKey(const Key('anpassen')));
    expect(txt('Das Halten endet, ab heute gilt der angepasste Plan.'), findsOneWidget);
    await tippe(t, find.byKey(const Key('anpSpeichern')));
    if (find.byKey(const Key('anpJa')).evaluate().isNotEmpty) await tippe(t, find.byKey(const Key('anpJa')));
    expect(app.taper.st.hold, isFalse);
  });

  testWidgets('Logbuch und Plan-Karte kennen die Anpassung', (t) async {
    final app = await stand(t);
    await tippe(t, find.byKey(const Key('anpassen')));
    await t.enterText(find.byKey(const Key('anpTage0')), '3');
    await tippe(t, find.byKey(const Key('anpSpeichern')));
    expect(logbuchErstellen(app.taper).ereignisse.map((e) => e.$2), contains('Plan angepasst'));
    await reiter(t, 'Plan');
    expect(find.text('Plan gestartet am 01.03.2026 · geändert am 10.03.2026'), findsOneWidget);
  });
}
