// Querverbindungen zwischen den Reitern und Randfälle.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_buddy/verlauf.dart';
import 'package:tapering_core/util.dart' show dmy;

import 'hilfen.dart';
import 'sicherung_ui_test.dart' show FakeDateien;

Finder imPlan(Finder f) => find.descendant(of: find.byKey(const Key('planKarte')), matching: f);
Finder imWeg(Finder f) => find.descendant(of: find.byKey(const Key('wegKarte')), matching: f);

VerlaufMaler maler(WidgetTester t) => t
    .widget<CustomPaint>(find.descendant(
        of: find.byKey(const Key('diagramm')),
        matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is VerlaufMaler)))
    .painter! as VerlaufMaler;

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Eintrag auf Heute: Fortschritt, Kalender und Plan ziehen mit', (t) async {
    final app = await starte(t, json: basis(log: {for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(10, 10)}));
    await reiter(t, 'Fortschritt');
    expect(txt('zuletzt 10 mg'), findsOneWidget);
    final vorher = maler(t).tage.firstWhere((x) => x.tag == '2026-03-10');
    expect(vorher.dosis, isNull);

    await reiter(t, 'Heute');
    await schreibe(t, find.byKey(const Key('menge')), '12');
    await tippe(t, find.byKey(const Key('plus')));
    await tippe(t, find.text('Eintragen'));
    await tippe(t, find.byKey(const Key('mehrAlsGeplantOk')));
    expect(app.taper.st.log['2026-03-10']!.dose, 12);

    await reiter(t, 'Fortschritt');
    final nachher = maler(t).tage.firstWhere((x) => x.tag == '2026-03-10');
    expect(nachher.dosis, 12, reason: 'roter Punkt heute');
    expect(nachher.schnitt7, closeTo((9 * 10 - 30 + 12) / 7, 1e-9), reason: '7 Tage: 6 × 10 + 12');

    await reiter(t, 'Kalender');
    expect(find.descendant(of: find.byKey(const Key('tag-2026-03-10')), matching: find.text('12')), findsOneWidget);
  });

  testWidgets('Halten: Plan-Karte und Fortschritt zeigen die Pause', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('halten')));
    await tippe(t, find.text('Ohne Enddatum halten'));
    expect(app.taper.st.hold, isTrue);
    await reiter(t, 'Plan');
    expect(imPlan(find.text('Voraussichtlich bei 0 mg: 28.07.2026 (Dosis wird gehalten)')), findsOneWidget,
        reason: 'Halten am ersten Tag: noch nichts verschoben');
    await reiter(t, 'Fortschritt');
    expect(imWeg(find.text('28.07.2026')), findsOneWidget, reason: 'voraussichtlich, auch beim Halten');
    final m = maler(t);
    expect(m.tage.last.tag, '2026-04-09', reason: 'heute + 30 Tage');
    expect(m.tage.where((x) => x.zukunft).every((x) => x.plan == 10), isTrue, reason: 'gehaltene Dosis');

    await reiter(t, 'Heute');
    await tippe(t, find.byKey(const Key('halten')));
    expect(app.taper.st.hold, isFalse);
    await reiter(t, 'Plan');
    expect(imPlan(txt('Voraussichtlich bei 0 mg: 28.07.2026')), findsOneWidget,
        reason: 'am selben Tag gehalten → keine Verschiebung');
  });

  testWidgets('Offene Tage: Plan-Karte, Fortschritt ohne Zukunft', (t) async {
    await starte(t, json: basis(log: {for (var d = 1; d <= 6; d++) '2026-03-0$d': eintrag(10, 10)}), aufReiter: 'Plan');
    expect(imPlan(find.text('Offene Tage – Anzeigen pausieren bis zum Nachtragen.')), findsOneWidget);
    await reiter(t, 'Fortschritt');
    expect(txt('Offene Tage – Anzeigen pausieren'), findsOneWidget);
    expect(maler(t).tage.last.tag, '2026-03-10');
    expect(maler(t).tage.any((x) => x.zukunft), isFalse);
  });

  testWidgets('Neuer Plan aus dem Plan-Reiter: alle Reiter zeigen ihn', (t) async {
    final app = await starte(t, aufReiter: 'Plan');
    await tippe(t, find.byKey(const Key('planErstellen')));
    await planSicherBestaetigen(t);
    await tippe(t, find.byKey(const Key('planWeiter')));
    await t.enterText(find.byKey(const Key('planDosis')), '10');
    await t.enterText(find.byKey(const Key('abSchritt0')), '2');
    await t.enterText(find.byKey(const Key('abTage0')), '7');
    await t.enterText(find.byKey(const Key('abBis0')), '0');
    await tippe(t, find.byKey(const Key('planWeiter')));
    await tippe(t, find.byKey(const Key('planWeiter')));
    await tippe(t, find.byKey(const Key('planLos')));
    expect(app.taper.st.plan, [10, 8, 6, 4, 2, 0]);
    expect(imPlan(txt('Stufe 1 von 6')), findsOneWidget);
    await reiter(t, 'Fortschritt');
    expect(imWeg(find.text('1 von 6')), findsOneWidget);
    await reiter(t, 'Heute');
    expect(txt('Stufe 1 von 6'), findsOneWidget);
  });

  testWidgets('Sicherung laden: offene Vorrat-Karte zeigt danach die neuen Stärken', (t) async {
    final d = FakeDateien();
    final quelle = AppState(MemStore(), dateien: d, clock: () => jetzt);
    await t.runAsync(quelle.laden);
    quelle.taper.setup(dose: 20, step: 1, minStep: 0.5, days: 7, goal: 0);
    quelle.taper.saveTabs([10, 2], 0.5, null);
    d.zumOeffnen = await t.runAsync<String?>(() => quelle.sicherungErstellen());

    t.view.physicalSize = const Size(1000, 7000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final app = AppState(MemStore()..disc = true, clock: () => jetzt, dateien: d);
    await t.runAsync(app.laden);
    app.taper.setup(dose: 10, step: 1, minStep: 0.5, days: 14, goal: 0);
    app.taper.saveTabs([5], 1, null);
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    if (find.byKey(const Key('staerke0')).evaluate().isEmpty) await tippe(t, find.text('VORRAT EINTRAGEN'));
    expect(t.widget<TextField>(find.byKey(const Key('staerke0'))).controller!.text, '5');

    await tippe(t, find.byTooltip('Mehr'));
    await tippe(t, find.text('Sicherung laden'));
    await t.enterText(find.byKey(const Key('planSicherText')), 'Ich bin mir sicher');
    await t.pump();
    await tippe(t, find.widgetWithText(FilledButton, 'Laden'));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(app.taper.st.plan.first, 20);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('dosis')), findsOneWidget, reason: 'nach dem Laden frisch in Heute');
    await reiter(t, 'Plan');
    expect(imPlan(txt('20 → 0 mg')), findsOneWidget);
    await reiter(t, 'Heute');
    if (find.byKey(const Key('staerke0')).evaluate().isEmpty) await tippe(t, find.text('VORRAT EINTRAGEN'));
    expect(t.widget<TextField>(find.byKey(const Key('staerke0'))).controller!.text, '10',
        reason: 'Felder dürfen nicht den alten Stand zeigen');
    expect(t.widget<TextField>(find.byKey(const Key('staerke1'))).controller!.text, '2');
  });

  testWidgets('Ziel erreicht: Fortschritt „Erreicht“', (t) async {
    await starte(t,
        json: basis(start: '2026-02-10', plan: [
          2,
          1,
          0
        ], log: {
          for (var d = 10; d <= 28; d++) '2026-02-$d': eintrag(d < 24 ? 2 : 1, d < 24 ? 2 : 1, stage: d < 24 ? 0 : 1),
          for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(d < 10 ? 1 : 0, 1, stage: 1),
        })
          ..['days'] = [14, 14, 14]
          ..['stage'] = 2
          ..['stageStart'] = '2026-03-10',
        aufReiter: 'Fortschritt');
    expect(imWeg(find.text('Erreicht')), findsOneWidget);
    expect(imWeg(find.text('3 von 3')), findsOneWidget);
    expect(find.text('Von 2 mg auf 0 mg'), findsOneWidget);
  });

  testWidgets('Letzte Stufe nicht 0 mg: kein Zieldatum in der Vergangenheit', (t) async {
    await starte(t,
        json: basis(start: '2026-02-01', plan: [
          10,
          8
        ], log: {
          for (var d = 1; d <= 28; d++) '2026-02-${d.toString().padLeft(2, '0')}': eintrag(10, 10),
          for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(8, 8, stage: 1),
        })
          ..['days'] = [14, 14]
          ..['stage'] = 1
          ..['stageStart'] = '2026-02-15',
        aufReiter: 'Fortschritt');
    expect(imWeg(find.text('Ziel 8 mg')), findsOneWidget);
    expect(imWeg(find.text('Erreicht')), findsOneWidget,
        reason: 'letzte Stufe = Ziel, kein Datum in der Vergangenheit');
  });

  testWidgets('Plan mit nur einer Stufe: nichts bricht', (t) async {
    await starte(t,
        json: basis(plan: [5], log: {for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(5, 5)})..['days'] = [14],
        aufReiter: 'Plan');
    expect(imPlan(txt('Stufe 1 von 1')), findsOneWidget);
    await reiter(t, 'Fortschritt');
    expect(find.text('Start bei 5 mg'), findsOneWidget);
    await reiter(t, 'Heute');
    expect(find.byKey(const Key('dosis')), findsOneWidget);
    await reiter(t, 'Kalender');
    expect(find.byKey(const Key('monat')), findsOneWidget);
  });

  testWidgets('Sehr langer Plan und lange Vorgeschichte: Diagramm bleibt bei heute', (t) async {
    // Start vor gut 3 Jahren, Plan noch ewig lang.
    final plan = [for (var i = 0; i < 400; i++) 100 - i * 0.25];
    final j = basis(start: '2023-01-01', plan: plan)
      ..['days'] = [for (final _ in plan) 14]
      ..['stage'] = 92
      ..['stageStart'] = '2026-03-03';
    final log = <String, dynamic>{};
    var k = DateTime.utc(2026, 1, 1);
    while (k.isBefore(DateTime.utc(2026, 3, 10))) {
      final s = k.toIso8601String().substring(0, 10);
      log[s] = eintrag(77, 77, stage: 92);
      k = k.add(const Duration(days: 1));
    }
    j['log'] = log;
    final sw = Stopwatch()..start();
    await starte(t, json: j, aufReiter: 'Fortschritt');
    sw.stop();
    final m = maler(t);
    expect(m.tage.length, lessThanOrEqualTo(2000));
    expect(m.heuteIdx, greaterThanOrEqualTo(0), reason: 'heute muss im Diagramm liegen');
    final bis = find.descendant(of: find.byKey(const Key('diagramm')), matching: find.byType(Text));
    final daten = [for (final e in bis.evaluate()) (e.widget as Text).data ?? ''];
    expect(
        daten,
        contains(dmy(m.tage.last.tag)),
        reason: 'Enddatum unter dem Diagramm = letzter gezeichneter Tag');
    expect(sw.elapsedMilliseconds, lessThan(5000));
  });

  testWidgets('Wischen wechselt Reiter und Titel; Mitternacht zählt „Tage geschafft“ weiter', (t) async {
    final app = await starte(t,
        json: basis(log: {for (var d = 1; d <= 9; d++) '2026-03-0$d': eintrag(10, 10)}), aufReiter: 'Fortschritt');
    expect(aktuellerReiter(t), 'Fortschritt');
    expect(imWeg(find.text('9')), findsOneWidget, reason: 'seit 01.03.');
    app.taper.addIntake(10);
    jetzt = DateTime.utc(2026, 3, 11, 0, 1);
    app.auffrischen();
    await t.pumpAndSettle();
    expect(imWeg(find.text('10')), findsOneWidget);

    await t.fling(find.byType(PageView), const Offset(600, 0), 2000);
    await t.pumpAndSettle();
    expect(aktuellerReiter(t), 'Plan');
    final nav = t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.selectedIndex, 2, reason: 'Kalender · Heute · Plan · Fortschritt');
  });
}
