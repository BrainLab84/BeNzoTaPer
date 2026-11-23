// „Plan anpassen“: ab heute alles änderbar, gilt sofort; Verlauf, Einnahmen, Vorrat bleiben.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  late DateTime jetzt;
  late Taper t;

  void tag([int n = 1]) {
    jetzt = jetzt.add(Duration(days: n));
    t.refresh();
  }

  /// Plan 20 × 10, 15 × 14, 10 × 14, Ziel 0; Start 01.12.2026; 500 mg gezählt; 4 Tage à 20 eingetragen.
  /// Heute = 05.12. = Tag 5 der ersten Stufe (Stufentag 4).
  void stand() {
    jetzt = DateTime.parse('2026-12-01T09:00:00Z');
    t = Taper(clock: () => jetzt);
    t.applyPlan(t.openEditor(neu: true)
      ..rows = [EditRow(20, 10), EditRow(15, 14), EditRow(10, 14), EditRow(0, 14)]);
    t.setStock(50, 10);
    jetzt = jetzt.add(const Duration(minutes: 1));
    for (var i = 0; i < 4; i++) {
      t.addIntake(20, force: true);
      tag();
    }
  }

  List<EditRow> zeilen(List<List<num?>> r) => [for (final x in r) EditRow(x[0]?.toDouble(), x[1]?.toInt())];

  setUp(stand);

  test('Vorlage: ab heute, erste Zeile = Tage ab heute inkl. heute', () {
    expect(t.today, '2026-12-05');
    expect(t.stageDay(), 4);
    expect([for (final r in t.anpassenVorlage()) [r.dose, r.days]], [
      [20, 6],
      [15, 14],
      [10, 14],
      [0, 14],
    ]);
    expect(t.stockInfo()!.rem, 420);
    // 6 × 20 = 120 → 300; 14 × 15 = 210 → 90; 9 × 10 → 0  ⇒ 6 + 14 + 9 = 29
    expect(t.stockInfo()!.days, 29);
  });

  test('Nur verlängern: aktuelle Stufe läuft weiter, 10 Tage ab heute; Vorrat sofort neu', () {
    final p = t.anpassenPruefen(zeilen([[20, 10], [15, 14], [10, 14], [0, null]]));
    expect(p.err, isNull);
    expect(p.bremst, isTrue, reason: 'Plan wird länger');
    expect(t.planAnpassen(zeilen([[20, 10], [15, 14], [10, 14], [0, null]])).applied, isTrue);
    expect(t.st.plan, [20, 15, 10, 0]);
    expect(t.st.days, [14, 14, 14, 14]);
    expect(t.st.stage, 0);
    expect(t.st.stageStart, '2026-12-01', reason: 'Stufenbeginn bleibt');
    expect(t.st.log.length, 4, reason: 'Einnahmen bleiben');
    expect(t.stockInfo()!.rem, 420, reason: 'Vorrat bleibt');
    // 10 × 20 = 200 → 220; 14 × 15 = 210 → 10; 1 × 10 → 0  ⇒ 25
    expect(t.stockInfo()!.days, 25);
    expect(t.voraussichtlichesEnde(), addD('2026-12-01', 14 + 14 + 14));
    expect(t.st.chg.last.t, startsWith('Plan angepasst'));
  });

  test('Dosis jetzt erhöhen: bisherige Tage bleiben eigene Stufe, neue beginnt heute', () {
    final ab = zeilen([[25, 7], [15, 14], [10, 14], [0, null]]);
    expect(t.anpassenPruefen(ab).bremst, isTrue, reason: 'höher');
    t.planAnpassen(ab);
    expect(t.st.plan, [20, 25, 15, 10, 0]);
    expect(t.st.days!.sublist(0, 4), [4, 7, 14, 14]);
    expect(t.st.stage, 1);
    expect(t.st.stageStart, '2026-12-05');
    expect(t.planFor('2026-12-02').plan, 20, reason: 'Vergangenheit unverändert');
    expect(t.st.log['2026-12-02']!.plan, 20);
    // 420: 7 × 25 = 175 → 245; 14 × 15 = 210 → 35; 3 × 10 → 5  ⇒ 24
    expect(t.stockInfo()!.days, 24);
    // Lücke vor der Anpassung? Hier keine. Wochen-Ø und Live-Ø: neue Stufe hat noch keinen Tag.
    expect(t.stufenSchnitt().avg, isNull);
  });

  test('Später schneller und eine Stufe dazwischen: gilt sofort, bremst nicht', () {
    final ab = zeilen([[20, 6], [15, 7], [12.5, 7], [10, 14], [0, null]]);
    final p = t.anpassenPruefen(ab);
    expect(p.err, isNull);
    expect(p.bremst, isFalse, reason: 'nicht höher, Ende gleich');
    t.planAnpassen(ab);
    expect(t.st.plan, [20, 15, 12.5, 10, 0]);
    expect(t.st.days!.sublist(0, 4), [10, 7, 7, 14]);
    // 420: 6 × 20 = 120 → 300; 7 × 15 = 105 → 195; 7 × 12,5 = 87,5 → 107,5; 10 × 10 → 7,5  ⇒ 30
    expect(t.stockInfo()!.days, 30);
  });

  test('Während des Haltens: Halten endet heute, Stufentag steht, Plan verschiebt sich um die Haltetage', () {
    t.startHold(null); // ab 05.12., Stufentag 4
    tag(2); // 07.12., zwei Tage gehalten, eingetragen? nein → geschätzt
    t.addIntake(20, k: '2026-12-05', t: '20:00');
    t.addIntake(20, k: '2026-12-06', t: '20:00');
    t.planAnpassen(zeilen([[20, 3], [15, 14], [10, 14], [0, null]]));
    expect(t.st.hold, isFalse);
    expect(t.st.stageStart, '2026-12-03', reason: 'um 2 Haltetage verschoben');
    expect(t.stageDay(), 4);
    expect(t.st.days![0], 7, reason: '4 + 3 Tage ab heute');
    // Rest: 500 − 6 × 20 = 380; 3 × 20 = 60 → 320; 14 × 15 = 210 → 110; 11 × 10 → 0  ⇒ 28
    expect(t.stockInfo()!.rem, 380);
    expect(t.stockInfo()!.days, 28);
  });

  test('Heute schon eingenommen, Dosis erhöht: der heutige Tag gehört zur neuen Stufe', () {
    jetzt = jetzt.add(const Duration(hours: 1));
    t.addIntake(20, force: true);
    t.planAnpassen(zeilen([[25, 7], [0, null]]));
    final e = t.st.log['2026-12-05']!;
    expect(e.plan, 25);
    expect(e.stage, t.st.stage);
    expect(e.r, 'ok');
    expect(t.partToday('2026-12-05', e), isTrue, reason: '20 von 25: Tag noch offen');
    expect(t.stockInfo()!.rem, 400);
    // heute offen 5 → 395; 6 × 25 = 150 → 245; Ziel 0 ⇒ bis Planende
    expect(t.stockInfo()!.days, double.infinity);
  });

  test('Tage ohne Eintrag vor der Anpassung behalten ihre alte geplante Dosis', () {
    tag(2); // 05. und 06.12. ohne Eintrag
    expect(t.stockInfo()!.geschaetzt, 2);
    expect(t.stockInfo()!.rem, 380);
    t.addIntake(20, k: '2026-12-05', t: '20:00');
    t.addIntake(20, k: '2026-12-06', t: '20:00');
    t.planAnpassen(zeilen([[25, 7], [0, null]]));
    expect(t.stockInfo()!.rem, 380);
    tag(); // 08.12. leer → geschätzt mit 25 (neue Stufe)
    expect(t.stockInfo()!.geschaetzt, 1);
    expect(t.stockInfo()!.rem, 355);
  });

  test('Fehler: leer, Dosis fehlt, Tage fehlen – nichts ändert sich', () {
    final vorher = t.st.toJson().toString();
    expect(t.planAnpassen([]).err?.code, MeldungCode.keineSchritte);
    expect(t.planAnpassen(zeilen([[null, 5], [0, null]])).err?.code, MeldungCode.stufeDosisFehlt);
    expect(t.planAnpassen(zeilen([[20, null], [0, null]])).err?.code, MeldungCode.stufeTageFehlen);
    expect(t.st.toJson().toString(), vorher);
  });

  test('Nur noch das Ziel: eine Zeile reicht', () {
    for (var i = 0; i < 60; i++) {
      t.addIntake(t.st.plan[t.st.stage], force: true);
      tag();
    }
    expect(t.st.stage, 3);
    expect(t.planAnpassen(zeilen([[0, 14]])).applied, isTrue);
    expect(t.st.plan.last, 0);
  });

  test('Alte Vormerkung entfällt mit der Anpassung', () {
    t.saveLeft(20, why: 'Brauche mehr Zeit');
    expect(t.st.pend, isNotNull);
    t.planAnpassen(t.anpassenVorlage());
    expect(t.st.pend, isNull);
  });
}
