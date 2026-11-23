// Vorratsrechnung (Doc 28/29): feste Referenzfälle und Abläufe, jeweils mit der Rechnung von Hand.
// Regeln: Rest = gezählt − eingetragene Einnahmen nach dem Zählen − geplante Dosis jedes vergangenen Tages
// ohne Eintrag (seit dem Zähltag). Reichweite (inkl. heute) = heute offener Rest, dann Tag für Tag laut Plan
// ab der echten Planposition; Halten mit Enddatum endet dort; 0 mg = „bis Planende“.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  late DateTime jetzt;
  Taper neu([String start = '2026-11-22T09:00:00Z']) {
    jetzt = DateTime.parse(start);
    return Taper(clock: () => jetzt);
  }

  void tag(Taper t, [int n = 1]) {
    jetzt = jetzt.add(Duration(days: n));
    t.refresh();
  }

  void minuten(int n) => jetzt = jetzt.add(Duration(minutes: n));

  void plan(Taper t, List<List<num>> r, {String? start}) {
    final e = t.openEditor(neu: true)
      ..rows = [for (final x in r) EditRow(x[0].toDouble(), x[1].toInt())]
      ..startDatum = start;
    expect(t.applyPlan(e).applied, isTrue);
  }

  // Referenzplan Doc 29: Diazepam 20 → 0 mg.
  const referenz = [
    [20, 2],
    [15, 14],
    [10, 21],
    [7.5, 21],
    [5, 21],
    [2.5, 21],
    [0, 21],
  ];

  group('Referenzfälle (Screenshots 22.11.2026)', () {
    test('A: 500 mg ohne Halten → 42 Tage (bis 02.01.2027), 0 mg ab 02.03.2027', () {
      final t = neu();
      plan(t, referenz);
      t.setStock(50, 10);
      // 2×20 + 14×15 + 21×10 = 460 mg (37 Tage); 40 mg ÷ 7,5 = 5 Tage → 42
      expect(t.stockInfo()!.days, 42);
      expect(addD(t.today, 42 - 1), '2027-01-02');
      expect(t.voraussichtlichesEnde(), '2027-03-02');
    });

    test('B: Halten 20 Tage bei 20 mg → 26 Tage (bis 17.12.2026), 0 mg ab 22.03.2027', () {
      final t = neu();
      plan(t, referenz);
      t.setStock(50, 10);
      expect(t.startHold(20), isTrue);
      // 20×20 = 400 Halten, 2×20 = 40 Stufe 1, 60 ÷ 15 = 4 → 26
      expect(t.stockInfo()!.days, 26);
      expect(addD(t.today, 26 - 1), '2026-12-17');
      expect(t.voraussichtlichesEnde(), '2027-03-22');
    });
  });

  test('615-mg-Fall: 15 × 20 + 21 × 15 = 615 mg reicht genau bis 0 mg; 600 mg = 35 Tage', () {
    final t = neu();
    plan(t, [
      [20, 15],
      [15, 21],
      [0, 21]
    ]);
    t.setStock(61.5, 10);
    expect(t.stockInfo()!.rem, 615);
    expect(t.stockInfo()!.days, double.infinity, reason: 'reicht bis zum Ende des Plans');
    t.setStock(60, 10);
    // 15×20 = 300, 300 ÷ 15 = 20 → 35
    expect(t.stockInfo()!.days, 35);
  });

  test('Empfindlichkeit: weniger 20-mg-Tage → Reichweite steigt genau um die gesparte Menge', () {
    // 500 mg, [20 × n] [15 × 21] [10 × 21] [0]
    final erwartet = {
      21: 26, // 420; 80 ÷ 15 = 5
      15: 28, // 300; 200 ÷ 15 = 13
      12: 29, // 240; 260 ÷ 15 = 17
      9: 30, // 180; 315 (21 × 15); 5 ÷ 10 = 0
      6: 33, // 120; 315; 65 ÷ 10 = 6
    };
    erwartet.forEach((n, tage) {
      final t = neu();
      plan(t, [
        [20, n],
        [15, 21],
        [10, 21],
        [0, 21]
      ]);
      t.setStock(50, 10);
      expect(t.stockInfo()!.days, tage, reason: '20 × $n');
    });
  });

  test('Sehr kleiner und sehr großer Vorrat', () {
    final t = neu();
    plan(t, referenz);
    t.setStock(15, 1);
    expect(t.stockInfo()!.days, 0, reason: '15 < 20: reicht nicht für heute');
    t.setStock(20, 1);
    expect(t.stockInfo()!.days, 1);
    t.setStock(500, 10);
    expect(t.stockInfo()!.days, double.infinity, reason: '5000 mg: bis zum Plan-Ende (0 mg)');
  });

  test('Tage ohne Eintrag: geplante Dosis, auch über einen Stufenwechsel; Nachtragen ersetzt die Schätzung', () {
    final t = neu();
    plan(t, [
      [20, 3],
      [15, 30],
      [0, 10]
    ]);
    t.setStock(50, 10);
    tag(t, 5); // 22.–26.11. nichts eingetragen: 3 × 20 + 2 × 15 = 90
    final si = t.stockInfo()!;
    expect(si.geschaetzt, 5);
    expect(si.rem, 410);
    // Echte Planposition: 27.11. = Tag 3 der 15-mg-Stufe (Plan läuft weiter, auch wenn Anzeigen pausieren).
    expect(t.planPos('2026-11-27'), (1, 2));
    // 410: heute 15, dann 15 × 15 … Stufe 15 noch 28 Tage = 420 > 410 → 410 ÷ 15 = 27
    expect(si.days, 27);
    // Nachtragen: am 23.11. nur 10 statt 20 genommen
    expect(t.addIntake(10, k: '2026-11-23', t: '20:00'), IntakeResult.added);
    expect(t.stockInfo()!.geschaetzt, 4);
    expect(t.stockInfo()!.rem, 420);
    // „Weiß ich nicht mehr“ (nach über 7 Tagen) bleibt bei der geplanten Dosis
    tag(t, 10);
    t.markUnk();
    expect(t.st.unk, isNotEmpty);
    final ohne = t.stockInfo()!.geschaetzt;
    expect(ohne, 14, reason: '4 alte + 10 neue Tage ohne Eintrag');
  });

  test('Zähltag: Einnahme vor dem Zählen zählt nicht, danach (auch in derselben Minute) einmal', () {
    final t = neu();
    plan(t, referenz);
    t.addIntake(10, t: '08:00'); // vor dem Zählen genommen
    minuten(60);
    t.setStock(30, 10); // 300 gezählt um 10:00
    expect(t.stockInfo()!.rem, 300);
    jetzt = jetzt.add(const Duration(seconds: 20));
    t.addIntake(10, t: t.nowHM()); // gleiche Minute, nach dem Zählen
    expect(t.stockInfo()!.rem, 290);
    // Zusatzdosis: einmal gezählt, beim Löschen wieder da
    minuten(30);
    t.addIntake(5, force: true);
    expect(t.stockInfo()!.rem, 285);
    t.delIntake(2);
    expect(t.stockInfo()!.rem, 290);
  });

  test('Aufstocken mitten im Plan, eintragen, nochmal aufstocken (auch am selben Tag, fast leer)', () {
    final t = neu();
    plan(t, [
      [10, 30],
      [5, 30],
      [0, 10]
    ]);
    t.setStock(3, 10); // 30 mg
    minuten(1);
    for (var i = 0; i < 2; i++) {
      t.addIntake(10, force: true);
      tag(t);
    }
    expect(t.stockInfo()!.rem, 10);
    expect(t.stockInfo()!.days, 1, reason: 'nur noch heute');
    t.setStock(2, 10, add: true); // +20
    expect(t.stockInfo()!.rem, 30);
    expect(t.stockInfo()!.days, 3);
    t.addIntake(10, force: true);
    t.setStock(5, 10, add: true); // am selben Tag nochmal +50
    expect(t.stockInfo()!.rem, 70);
    // heute schon genommen; 70 ÷ 10 = 7 weitere Tage + heute
    expect(t.stockInfo()!.days, 8);
    tag(t);
    expect(t.stockInfo()!.rem, 70, reason: 'gestern eingetragen, heute noch nichts: nichts doppelt');
    expect(t.stockInfo()!.days, 7, reason: '70 ÷ 10 inkl. heute');
    // Neu zählen ersetzt alles
    minuten(1);
    t.setStock(4, 10);
    expect(t.stockInfo()!.rem, 40);
    expect(t.stockInfo()!.geschaetzt, 0);
  });

  test('Reihenfolge egal: gleiche Endlage ⇒ gleiche Reichweite', () {
    Taper lauf(bool erstEintragen) {
      final t = neu();
      plan(t, referenz);
      t.setStock(50, 10);
      tag(t, 3);
      final tage = ['2026-11-22', '2026-11-23', '2026-11-24'];
      if (erstEintragen) {
        for (final k in tage) {
          t.addIntake(20, k: k, t: '21:00');
        }
        t.setStock(1, 10, add: true);
      } else {
        t.setStock(1, 10, add: true);
        for (final k in tage.reversed) {
          t.addIntake(k == '2026-11-22' ? 20 : 15, k: k, t: '21:00');
        }
      }
      return t;
    }

    final a = lauf(true), b = lauf(false);
    // a: 20+20+20 (zwei Tage über Plan), b: 20+15+15 (laut Plan): Rest unterscheidet sich genau um 10
    expect(a.stockInfo()!.rem, 510 - 60);
    expect(b.stockInfo()!.rem, 510 - 50);
    // gleiche Endlage prüfen: b mit denselben Mengen
    final c = neu();
    plan(c, referenz);
    c.setStock(50, 10);
    tag(c, 3);
    c.addIntake(20, k: '2026-11-24', t: '21:00');
    c.setStock(1, 10, add: true);
    c.addIntake(20, k: '2026-11-22', t: '21:00');
    c.addIntake(20, k: '2026-11-23', t: '21:00');
    expect(c.stockInfo()!.rem, a.stockInfo()!.rem);
    expect(c.stockInfo()!.days, a.stockInfo()!.days);
  });

  test('Halten ohne Enddatum: gehaltene Dosis bis auf Weiteres; über Monats- und Jahresgrenze', () {
    final t = neu('2026-12-28T09:00:00Z');
    plan(t, [
      [10, 7],
      [5, 7],
      [0, 7]
    ]);
    t.setStock(10, 10); // 100 mg
    t.startHold(null);
    expect(t.stockInfo()!.days, 10, reason: '100 ÷ 10, Halten ohne Ende');
    tag(t, 5); // 02.01.2027, nichts eingetragen: 5 × 10 geschätzt
    expect(t.stockInfo()!.rem, 50);
    expect(t.stockInfo()!.days, 5);
    t.stopHold();
    // Stufe 1 lief 0 Tage vor dem Halten (Start 28.12., Halten ab 28.12.) → ab heute noch 7 Tage 10 mg
    expect(t.stockInfo()!.days, 5);
  });

  test('Neustart (alles löschen, neuer Plan) = frischer Plan', () {
    final t = neu();
    plan(t, referenz);
    t.setStock(50, 10);
    for (var i = 0; i < 4; i++) {
      t.addIntake(20, force: true);
      tag(t);
    }
    t.startHold(3);
    t.wipe();
    plan(t, [
      [20, 15],
      [15, 21],
      [10, 21],
      [0, 21]
    ]);
    expect(t.st.log, isEmpty);
    expect(t.st.stock, isNull);
    expect(t.st.hold, isFalse);
    t.setStock(50, 10);
    expect(t.stockInfo()!.days, 28, reason: 'wie Referenz B frisch');
    expect(t.stockInfo()!.geschaetzt, 0);
  });
}
