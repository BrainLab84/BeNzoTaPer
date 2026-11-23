// Szenarien aus tests/scen.js, hold.js, ed.js und chg.js, ohne Oberfläche.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';
import 'sim.dart';

bool near(double? a, double? b, [double e = 1e-6]) => a != null && b != null && (a - b).abs() < e;

void main() {
  test('S1 Planmäßig abdosieren, komplett durch', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final P = List<double>.from(w.st.plan);
    final N = P.length;
    final end0 = addD(w.today, 14 * (N - 1));
    expect(P.first, 10);
    expect(P.last, 0);
    expect(w.st.days!.every((d) => d == 14), isTrue);
    expect(w.endCalc(), end0);
    expect(w.endShown(), end0);
    w.at(7);
    w.st.tabs = Tabs(str: [5, 2], split: 0.5);
    w.st.stock = Stock(5000, w.now.millisecondsSinceEpoch, w.today);
    w.at(9);
    var taken = 0.0;
    double? prevAvg;
    var avgUp = 0;
    for (var d = 0; d < 14 * (N - 1) + 3; d++) {
      final sg = d ~/ 14 < N - 1 ? d ~/ 14 : N - 1;
      expect(w.st.stage, sg, reason: 'Stufe an Tag $d');
      if (sg < N - 1) {
        final dIn = 14 - (d % 14);
        expect(w.e.stageDay() + 1, (d % 14) + 1, reason: 'Balken Tag $d');
        expect(w.st.plan[w.st.stage] > 0 ? dIn : dIn, dIn);
        expect(w.endShown(), end0, reason: 'Enddatum stabil Tag $d');
      }
      if (P[sg] > 0) {
        w.at(8);
        w.take(P[sg] / 2, '08:00');
        final a = w.e.weekAvgs(w.now, 1)[0].avg;
        if (prevAvg != null) {
          expect(a == null || a >= prevAvg - 1.0001, isTrue, reason: 'Ø mittags Tag $d');
        }
        w.at(20);
        w.take(P[sg] / 2, '20:00');
        taken += P[sg];
      } else {
        w.e.addIntake(0);
      }
      final a = w.e.weekAvgs(w.now, 1)[0].avg;
      if (prevAvg != null && a != null && a > prevAvg + 1e-9) avgUp++;
      prevAvg = a;
      w.day(1);
    }
    expect(avgUp, 0);
    expect(w.st.stage, N - 1);
    final si = w.e.stockInfo()!;
    expect(near(si.rem, 5000 - taken), isTrue, reason: '${si.rem} vs ${5000 - taken}');
  });

  test('S2 Mehr genommen: Plan bleibt, ✗', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e2 = w.endCalc();
    for (var d = 0; d < 5; d++) {
      w.take(d < 3 ? 12 : 10);
      w.day();
    }
    expect(w.endCalc(), e2);
    expect(w.st.log.values.where((e) => e.r == 'lapse').length, 3);
    expect(near(w.e.weekAvgs(w.now, 1)[0].avg, (36 + 20) / 5), isTrue);
  });

  test('S3 Weniger genommen', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e3 = w.endCalc();
    w.take(5);
    w.day();
    w.take(10);
    expect(w.st.log[addD(w.today, -1)]!.r, 'ok');
    expect(w.endCalc(), e3);
  });

  test('S4 Halten mit Tagen', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e4 = w.endCalc();
    for (var d = 0; d < 3; d++) {
      w.take(10);
      w.day();
    }
    expect(w.e.startHold(5), isTrue);
    expect(w.st.hold, isTrue);
    expect(w.st.holdUntil, addD(w.today, 5));
    for (var d = 0; d < 5; d++) {
      w.take(10);
      if (d == 2) expect(w.e.stageDay() + 1, 4, reason: 'Tageszähler friert');
      w.day();
    }
    expect(w.st.hold, isFalse, reason: 'Halten endet automatisch');
    expect(w.endCalc(), addD(e4!, 5));
    expect(w.endShown(), addD(e4, 5));
    expect(w.e.stageDay() + 1, 4);
  });

  test('S5 Halten offen, Weiter', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e5 = w.endCalc();
    w.take(10);
    w.day();
    w.e.startHold(null);
    for (var d = 0; d < 7; d++) {
      w.take(10);
      w.day();
    }
    expect(w.st.hold && w.st.stage == 0, isTrue);
    w.e.stopHold();
    expect(w.st.hold, isFalse);
    expect(w.endCalc(), addD(e5!, 7));
  });

  test('S5b Halten über Stufenwechsel hinweg', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e = w.endCalc();
    for (var d = 0; d < 13; d++) {
      w.take(10);
      w.day();
    }
    w.e.startHold(10);
    for (var d = 0; d < 10; d++) {
      w.take(10);
      w.day();
    }
    expect(w.st.stage, 0);
    expect(w.st.hold, isFalse);
    w.take(10);
    w.day();
    expect(w.st.stage, 1);
    expect(w.endCalc(), addD(e!, 10));
  });

  test('S6 Offener Tag / ?-Prinzip', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e6 = w.endCalc();
    w.take(10);
    w.day();
    w.day(); // Tag 2 vergessen
    expect(w.st.frz, addD(w.today, -1));
    expect(w.endShown(), isNull);
    w.take(10, '', addD(w.today, -1));
    expect(w.st.frz, isNull);
    expect(w.endCalc(), e6);
  });

  test('S6b 12 Tage weg, Weiß ich nicht mehr', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e = w.endCalc();
    w.take(10);
    w.day(12);
    expect(w.st.stage, 0, reason: 'Anzeige friert, kein Stufensprung solange offen');
    w.e.markUnk();
    expect(w.st.unk.length, 4);
    for (var i = 7; i >= 1; i--) {
      w.take(10, '', addD(w.today, -i));
    }
    expect(w.st.frz, isNull);
    expect(w.endCalc(), e);
    expect(w.st.stage, 0);
    expect(near(w.e.weekAvgs(w.now, 2)[1].avg, 10), isTrue, reason: '?-Tage nicht als 0');
  });

  test('S7 Ändern: kürzer sofort, länger 48 h', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e7 = w.endCalc()!;
    w.take(10);
    w.day();
    expect(w.e.saveLeft(3), LeftResult.applied);
    expect(w.endCalc(), addD(e7, -10));
    expect(w.e.saveLeft(10), LeftResult.needsWhy);
    expect(w.e.saveLeft(10, why: 'Urlaub'), LeftResult.pended);
    expect(w.st.pend, isNotNull);
    expect(w.endCalc(), addD(e7, -10), reason: 'Plan noch unverändert');
    for (var i = 0; i < 3; i++) {
      w.take(10);
      w.day();
    }
    expect(w.st.pend == null || w.e.pendLeftMs() <= 0, isTrue);
    if (w.st.pend != null) {
      w.e.usePend();
      expect(w.endCalc(), addD(e7, -3));
    }
  });

  test('S8 Editor: Bestätigung, schneller sofort, langsamer vorgemerkt', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e8 = w.endCalc()!;
    var r = w.editor((e) => e.rows[3].days = 7, conf: false);
    expect(r.$2.err?.code, MeldungCode.sicherTippen);
    r = w.editor((e) => e.rows[3].days = 7);
    expect(r.$2.applied, isTrue);
    expect(w.endCalc(), addD(e8, -7));
    expect(w.st.pend, isNull);
    // langsamer: fragt nach Grund
    final ed = w.e.openEditor();
    ed.rows[3].days = 21;
    ed.conf = 'Ich bin mir sicher';
    var ar = w.e.applyPlan(ed);
    expect(ar.askWhy, isTrue);
    ed.why = 'Test';
    ar = w.e.applyPlan(ed);
    expect(ar.pended, isTrue);
    expect(w.st.pend?.kind, 'plan');
    expect(w.endCalc(), addD(e8, -7));
    for (var d = 0; d < 3; d++) {
      w.take(10);
      w.day();
    }
    final back = w.e.usePend()!;
    back.conf = 'ich bin mir sicher';
    expect(w.e.applyPlan(back).applied, isTrue);
    expect(w.endCalc(), addD(e8, 7));
    expect(w.st.pend, isNull);
    // Dosis rauf
    final up = w.e.openEditor();
    up.rows[w.st.stage].dose = 12;
    up.conf = 'Ich bin mir sicher';
    expect(w.e.applyPlan(up).askWhy, isTrue);
    // Neuer Plan per Rechner, Daten bleiben
    final logN = w.st.log.length;
    w.take(10);
    final ne = w.e.openEditor(neu: true);
    w.e.editCalc(ne, dose: 10, step: 20, minStep: 0.25, days: 7, goal: 0);
    ne.conf = 'Ich bin mir sicher';
    expect(w.e.applyPlan(ne).applied, isTrue);
    expect(w.st.plan.length, makePlan(10, 20, 0.25, 0).length);
    expect(w.st.days!.every((d) => d == 7), isTrue);
    expect(w.st.log.length >= logN, isTrue);
  });

  test('S9 Halten + Vormerkung / Planänderung im Halten', () {
    var w = Sim();
    w.setup(10, 10, 14);
    w.take(10);
    w.day();
    expect(w.e.saveLeft(20), LeftResult.needsWhy);
    expect(w.e.saveLeft(20, why: 'Stress'), LeftResult.pended);
    w.e.startHold(null);
    for (var d = 0; d < 4; d++) {
      w.take(10);
      w.day();
    }
    w.e.stopHold();
    final before = w.e.need(w.st.stage);
    w.e.usePend();
    expect(w.e.need(w.st.stage) > before, isTrue, reason: 'Vormerkung nach Halten wirkt');
    expect(w.st.stageStart! <= w.today, isTrue);
    w = Sim();
    w.setup(10, 10, 14);
    w.take(10);
    w.day();
    w.e.startHold(null);
    for (var d = 0; d < 3; d++) {
      w.take(10);
      w.day();
    }
    w.editor((e) {
      e.rows[0].dose = 9.5;
      e.start = 0;
    });
    w.day(2);
    w.e.stopHold();
    expect(w.st.stageStart! <= w.today, isTrue, reason: 'kein Zukunftsstart');
  });

  test('S10 Sichern/Laden', () {
    final w = Sim();
    w.setup(10, 10, 14);
    for (var d = 0; d < 20; d++) {
      w.take(d % 5 != 0 ? 10 : 11);
      w.day();
    }
    final dump = w.e.exportJson()!;
    final w2 = Sim(start: w.now.toIso8601String());
    w2.setup(5);
    expect(w2.e.importJson(dump), isTrue);
    expect(w2.st.plan.length, w.st.plan.length);
    expect(w2.st.log.length, w.st.log.length);
  });

  test('S12 Halten mit Lücke darin: keine Doppelverschiebung', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e12 = w.endCalc()!;
    w.take(10);
    w.day();
    w.e.startHold(null);
    w.day(12);
    expect(w.st.hold && w.st.frz == null, isTrue, reason: 'im Halten kein Stillstand');
    w.e.stopHold();
    expect(w.st.frz, w.today);
    for (var i = 7; i >= 1; i--) {
      w.take(10, '', addD(w.today, -i));
    }
    w.e.markUnk();
    expect(w.st.frz, isNull);
    expect(w.endCalc(), addD(e12, 12));
  });

  test('S12b Auto-Ende während Abwesenheit', () {
    final w = Sim();
    w.setup(10, 10, 14);
    final e = w.endCalc()!;
    w.take(10);
    w.day();
    w.e.startHold(5);
    w.day(9);
    expect(!w.st.hold && w.st.frz != null, isTrue);
    for (var i = 7; i >= 1; i--) {
      w.take(10, '', addD(w.today, -i));
    }
    if (w.st.frz != null) w.e.markUnk();
    expect(w.st.frz, isNull);
    expect(w.endCalc(), addD(e, 5));
  });

  // ===== chg.js: Querverbindungen =====

  /// Vorrat-Tage unabhängig nachgerechnet.
  double stockDaysIndep(Sim w) {
    final S = w.st;
    int need(int i) => S.days != null && S.days![i] > 0 ? S.days![i] : S.target;
    final te = S.log[w.today];
    var rem = S.stock!.mg;
    for (final e in S.log.values) {
      for (final x in e.it) {
        if (x.ts > S.stock!.ts) rem -= x.v;
      }
    }
    var s = S.stage;
    var left = need(s) - w.e.stageDay();
    if (left < 1) left = 1;
    final rest = S.plan[s] - (te?.dose ?? 0);
    if (rest > 0) {
      rem -= rest;
      if (rem < -1e-9) return 0;
    }
    // Halten: Tage bis zum Halte-Ende (ohne Ende: unbegrenzt) bleibt die Dosis, der Stufentag steht.
    final haltBis = S.hold ? (S.holdUntil ?? '9999-12-31') : w.today;
    var tag = w.today;
    var days = 1;
    if (tag.compareTo(haltBis) >= 0) left--;
    for (var i = 0; i < 3000; i++) {
      tag = addD(tag, 1);
      final gehalten = tag.compareTo(haltBis) < 0;
      if (!gehalten && left <= 0 && s < S.plan.length - 1) {
        s++;
        left = need(s);
      }
      final d = S.plan[s];
      if (!(d > 0)) return double.infinity;
      if (rem < d - 1e-9) break;
      rem -= d;
      days++;
      if (!gehalten) left--;
    }
    return days.toDouble();
  }

  test('V1 Vorrat-Tage unabhängig nachgerechnet', () {
    for (final cfg in [
      [10.0, 10.0, 14],
      [20.0, 10.0, 7],
      [6.0, 10.0, 21]
    ]) {
      final w = Sim();
      w.setup(cfg[0] as double, cfg[1] as double, cfg[2] as int);
      w.st.tabs = Tabs(str: [5, 2, 1], split: 0.5);
      w.st.stock = Stock(300, w.now.millisecondsSinceEpoch - 1000, w.today);
      for (var d = 0; d < 60; d++) {
        final pl = w.st.plan[w.st.stage];
        if (pl > 0) {
          w.take(pl);
        } else {
          w.e.addIntake(0);
        }
        if (d == 10) w.e.startHold(5);
        final si = w.e.stockInfo()!;
        expect(si.days, stockDaysIndep(w), reason: 'cfg $cfg Tag $d');
        w.at(23, 59);
        w.day(1, 7);
      }
    }
  });

  test('D1 Löschen/Nachtragen in der Vergangenheit', () {
    final w = Sim();
    w.setup(10, 10, 14);
    w.st.tabs = Tabs(str: [5], split: 1);
    w.st.stock = Stock(100, w.now.millisecondsSinceEpoch - 1000, w.today);
    for (var d = 0; d < 5; d++) {
      w.take(10);
      w.at(23, 59);
      w.day(1, 7);
    }
    final before = w.e.stockInfo()!.rem;
    final k3 = addD(w.today, -3);
    final wkBefore = w.e.weekAvgs(w.now, 1)[0].n;
    w.e.delIntake(0, k3);
    // Seit v0.2.2: ein Tag ohne Eintrag zählt mit der geplanten Dosis (10) – der Rest bleibt gleich,
    // statt fälschlich um 10 mg zu steigen. Nachtragen ersetzt die Schätzung durch die echte Menge.
    expect(w.e.stockInfo()!.rem, before);
    expect(w.e.stockInfo()!.geschaetzt, 1);
    expect(w.e.weekAvgs(w.now, 1)[0].n, wkBefore - 1);
    expect(w.st.frz, isNotNull, reason: 'Lücke löst Stillstand aus');
    expect(w.endCalc(), isNull);
    w.take(10, '', k3);
    expect(w.st.frz, isNull);
    expect(w.e.stockInfo()!.rem, before);
  });

  test('B1 alte Sicherung mit Prozent/Meilensteinen/Tags lädt', () {
    final w = Sim();
    w.setup(10, 10, 14);
    for (var d = 0; d < 4; d++) {
      w.take(10);
      w.at(23, 59);
      w.day(1, 7);
    }
    final old = Map<String, dynamic>.from(w.e.exportJson()!);
    old['pct'] = 10;
    old.remove('step');
    old['msSeen'] = ['d7', 's1'];
    old['rew'] = {'d7': 'Eis'};
    (old['notes'] as Map)[addD(w.today, -1)] = {
      'tags': ['Vaping', 'Koffein'],
      'sx': [],
      'sym': 3,
      'text': 'x'
    };
    expect(w.e.importJson(old), isTrue);
    expect(w.st.plan, w.st.plan);
    expect(w.st.notes[addD(w.today, -1)]!.text, 'x');
    final n = w.st.notes[addD(w.today, -1)]!;
    w.e.saveNote(addD(w.today, -1), n);
    expect(w.st.notes[addD(w.today, -1)]!.text, 'x');
  });

  test('E1–E9 Setup-Eingaben', () {
    String? trySetup(double? dose, double? step, [double tgt = 0]) {
      final w = Sim();
      final err = w.e.setup(dose: dose ?? double.nan, step: step ?? double.nan, minStep: 0.25, days: 14, goal: tgt);
      return err?.code.name ?? 'ok:${w.st.plan.length}:${w.st.plan.last}';
    }

    expect(trySetup(10, 0.5), 'ok:21:0.0');
    expect(trySetup(10, null), isNot(startsWith('ok')));
    expect(trySetup(10, -1), isNot(startsWith('ok')));
    expect(trySetup(10, 0), isNot(startsWith('ok')));
    expect(trySetup(0, 1), isNot(startsWith('ok')));
    expect(trySetup(10, 1, 10), isNot(startsWith('ok')));
    expect(trySetup(40, 0.25), startsWith('ok'));
    final w = Sim();
    w.e.setup(dose: 10, step: 0.7, minStep: 0.25, days: 14, goal: 0);
    final p = w.st.plan;
    final avg = (p[0] - p[p.length - 2]) / (p.length - 2);
    expect((avg - 0.7).abs() < 0.1, isTrue, reason: 'Schritt 0,7 im Mittel: $avg');
    final w40 = Sim();
    w40.e.setup(dose: 40, step: 0.25, minStep: 0.25, days: 14, goal: 0);
    expect(w40.st.plan.last, 0);
  });

  // ===== Änderungen mitten im Verlauf: alles muss mitgehen =====
  Sim fresh() {
    final w = Sim();
    w.setup(10, 10, 14);
    w.st.tabs = Tabs(str: [5, 2, 1], split: 0.5);
    w.st.stock = Stock(500, w.now.millisecondsSinceEpoch - 1000, w.today);
    for (var d = 0; d < 20; d++) {
      w.take(w.st.plan[w.st.stage]);
      w.at(23, 59);
      w.day(1, 7);
    }
    return w;
  }

  List<double> projected(Sim w, int n) {
    final S = w.st;
    int need(int i) => S.days != null && S.days![i] > 0 ? S.days![i] : S.target;
    var s = S.stage;
    var st = S.stageStart!;
    final out = <double>[];
    for (var i = 1; i <= n; i++) {
      final k = addD(w.today, i);
      while (s < S.plan.length - 1 && k >= addD(st, need(s))) {
        st = addD(st, need(s));
        s++;
      }
      out.add(S.plan[s]);
    }
    return out;
  }

  List<double> calFuture(Sim w, int n) {
    final pj = w.e.projMap(addD(w.today, n));
    return [for (var i = 1; i <= n; i++) pj.map[addD(w.today, i)]!.v];
  }

  void agePend(Sim w) => w.st.pend!.at -= 49 * 3600000;

  void finishEdit(Sim w, PlanEdit ed, ApplyResult r, String why) {
    if (r.askWhy) {
      ed.why = why;
      r = w.e.applyPlan(ed);
    }
    if (w.st.pend != null) {
      agePend(w);
      final back = w.e.usePend();
      if (back != null) {
        back.conf = 'Ich bin mir sicher';
        w.e.applyPlan(back);
      }
    }
  }

  test('A laufende Stufe schneller -> sofort überall', () {
    final w = fresh();
    final S0 = w.st;
    final cur = S0.plan[S0.stage];
    final res = w.editor((e) => e.rows[S0.stage].dose = cur - 0.5);
    finishEdit(w, res.$1, res.$2, 'will schneller');
    expect(w.st.plan[w.st.stage], cur - 0.5);
    final cf = calFuture(w, 60);
    expect(cf, projected(w, 60));
    expect(w.e.stockInfo()!.days, stockDaysIndep(w));
    expect(w.endShown(), w.endCalc());
  });

  test('B aktuelle Stufe verlängern per saveLeft', () {
    final w = fresh();
    final end0 = w.endCalc()!;
    final left = w.e.need(w.st.stage) - w.e.stageDay();
    expect(w.e.saveLeft(left + 6), LeftResult.needsWhy);
    expect(w.e.saveLeft(left + 6, why: 'brauche mehr Zeit'), LeftResult.pended);
    expect(w.st.pend!.kind, 'left');
    w.at(9);
    agePend(w);
    w.e.usePend();
    expect(w.endCalc(), addD(end0, 6));
    expect(calFuture(w, 60), projected(w, 60));
    expect(w.endShown(), w.endCalc());
  });

  test('C Halten 5 Tage -> Enddatum + 5, Dosis bleibt', () {
    final w = fresh();
    final end0 = w.endCalc()!;
    final dose0 = w.st.plan[w.st.stage];
    w.e.startHold(5);
    expect(w.st.plan[w.st.stage], dose0);
    for (var d = 0; d < 5; d++) {
      w.take(w.st.plan[w.st.stage]);
      w.at(23, 59);
      w.day(1, 7);
    }
    expect(w.st.hold, isFalse);
    expect(w.endCalc(), addD(end0, 5));
    expect(w.endShown(), w.endCalc());
  });

  test('D spätere Stufe verlängern (Editor) -> Enddatum + Delta', () {
    final w = fresh();
    final end0 = w.endCalc()!;
    final stk0 = w.e.stockInfo()!.days;
    final i = w.st.stage + 3;
    final res = w.editor((e) => e.rows[i].days = e.rows[i].days! + 7);
    finishEdit(w, res.$1, res.$2, 'weil ich es will');
    expect(w.endCalc(), addD(end0, 7));
    expect((w.e.stockInfo()!.days - stk0).abs() < 30, isTrue);
    expect(w.endShown(), w.endCalc());
  });

  test('E Dosis RAUF -> 48-h-Vormerkung, nichts ändert sich sofort', () {
    final w = fresh();
    final cur = w.st.plan[w.st.stage];
    final before = List<double>.from(w.st.plan);
    final res = w.editor((e) => e.rows[w.st.stage].dose = cur + 1);
    expect(res.$2.askWhy, isTrue);
    res.$1.why = 'geht nicht anders';
    expect(w.e.applyPlan(res.$1).pended, isTrue);
    expect(w.st.plan, before);
    expect(w.st.pend, isNotNull);
    expect(w.st.plan[w.st.stage], cur);
  });

  test('G Einheit/Name ändern', () {
    final w = fresh();
    final r = w.editor((e) {
      e.unit = 'Tropfen';
      e.name = 'Lorazepam';
    });
    expect(r.$2.applied || r.$2.askWhy || r.$2.pended, isTrue);
    expect(w.st.unit, 'Tropfen');
    expect(w.st.name, 'Lorazepam');
  });

  test('T1 Datumsgrenzen: Jahreswechsel, Schaltjahr, Zeitumstellung', () {
    for (final start in [
      '2027-12-20T09:00:00',
      '2028-02-20T09:00:00',
      '2028-12-28T09:00:00',
      '2026-03-25T09:00:00',
      '2026-10-24T09:00:00'
    ]) {
      final w = Sim(start: start);
      w.setup(6, 10, 5);
      for (var d = 0; d < 70; d++) {
        final pl = w.st.plan[w.st.stage];
        if (pl > 0) {
          w.take(pl);
        } else {
          w.e.addIntake(0);
        }
        w.at(23, 59);
        w.day(d % 9 == 4 ? 2 : 1, 7);
        if (w.st.frz != null) w.fillGaps();
      }
      final S = w.st;
      expect(S.stageStart! <= w.today && S.stage >= 0 && S.stage < S.plan.length, isTrue,
          reason: 'Zustand gültig ab $start');
      // Kalender-Vorschau über mehrere Jahre blättern
      final pj = w.e.projMap(addD(w.today, 900));
      expect(pj.map.values.every((p) => p.v.isFinite), isTrue);
    }
  });

  test('I1 kaputte Sicherungen werden abgelehnt, Zustand bleibt gültig', () {
    final w = Sim();
    w.setup(10, 10, 14);
    w.take(10);
    final bad = <Object?>[
      null,
      '',
      'abc',
      <Object?>[],
      <String, Object?>{},
      {'plan': <Object?>[]},
      {
        'plan': [5, 0]
      },
      {'plan': 'x', 'log': {}},
      {
        'plan': [5, 0],
        'log': {},
        'stage': 9
      },
      {
        'plan': [5, 0],
        'log': {},
        'stage': -1,
        'stageStart': 'kaputt'
      },
    ];
    for (final b in bad) {
      final keep = w.e.exportJson();
      final ok = w.e.importJson(b);
      final s = w.st;
      expect(s.plan.isNotEmpty && s.stage >= 0 && s.stage < s.plan.length, isTrue, reason: '$b');
      if (!ok) expect(w.e.exportJson().toString(), keep.toString(), reason: '$b blieb unverändert');
    }
    // gültig, aber mit Fehlern: wird korrigiert
    expect(
        w.e.importJson({
          'plan': [5, 0],
          'log': {},
          'stage': 9
        }),
        isTrue);
    expect(w.st.stage, 0);
    expect(
        w.e.importJson({
          'plan': [5, 0],
          'log': {},
          'stage': -1,
          'stageStart': 'kaputt'
        }),
        isTrue);
    expect(w.st.stageStart, anyOf(isNull, isNotNull));
    w.e.refresh();
    expect(w.st.stageStart, isNotNull);
  });

  test('P2 Vorrat und Tabletten', () {
    final w = Sim();
    w.setup(10, 10, 14);
    w.e.saveTabs([5, 2], 1, null);
    w.e.setStock(20, 5);
    expect(w.st.stock!.mg, 100);
    w.e.setStock(10, 5, add: true);
    expect(w.st.stock!.mg, 150);
    expect(w.e.stockInfo(), isNotNull);
    // Unsinn in der Tablettenliste wird gefiltert
    w.e.saveTabs([-5, 0], 1, 0);
    expect(w.st.tabs!.str, isEmpty);
    expect(w.st.tabs!.liq, isNull);
  });

  test('N PIN: Hash unverändert, Regeln', () {
    final w = Sim();
    w.setup(10, 10, 14);
    expect(w.e.setPin('12', '12'), isNotNull);
    expect(w.e.setPin('1234', '4321'), isNotNull);
    expect(w.st.pin, isNull);
    expect(w.e.setPin('1234', '1234'), isNull);
    expect(w.st.pin, isNot('1234'));
    expect(w.e.checkPin('0000'), isFalse);
    expect(w.e.checkPin('1234'), isTrue);
    // Feste Referenzwerte des Hashes (dürfen sich nie ändern, sonst passen ältere Daten nicht)
    expect(Taper.hashPin('1234'), '7aeda952');
    expect(Taper.hashPin(''), 'f3f57ef6');
    expect(Taper.hashPin('äö9'), 'b5f5dc9b');
    w.e.clearPin();
    expect(w.st.pin, isNull);
  });

  test('O SOS zählt, "Kurz innehalten" bei Mehrnahme', () {
    final w = Sim();
    w.setup(10, 10, 14);
    w.e.sosDone();
    expect(w.st.sosN, 1);
    w.take(10);
    expect(w.e.addIntake(3), IntakeResult.needsPause);
    expect(w.st.log[w.today]!.dose, 10);
    expect(w.e.addIntake(3, force: true), IntakeResult.added);
    expect(w.st.log[w.today]!.r, 'lapse');
    // Zukunft und älter als 7 Tage werden nicht eingetragen
    expect(w.e.addIntake(1, k: addD(w.today, 1)), IntakeResult.ignored);
    expect(w.e.addIntake(1, k: addD(w.today, -8)), IntakeResult.ignored);
  });

  test('T2 lokale Uhr über Sommer-/Winterzeit: jeder Tag zählt genau einmal', () {
    // Läuft in jeder Zeitzone; mit TZ=Europe/Berlin liegen Umstellungen im Zeitraum.
    for (final start in [DateTime(2027, 3, 1, 9), DateTime(2026, 10, 10, 9), DateTime(2027, 10, 20, 9)]) {
      var now = start;
      final e = Taper(clock: () => now);
      expect(e.setup(name: 'D', unit: 'mg', dose: 10, step: 1, minStep: 0.25, days: 14, goal: 0), isNull);
      final first = e.today;
      for (var d = 0; d < 120; d++) {
        e.addIntake(e.st.plan[e.st.stage], force: true);
        final expectStage = (d ~/ 14) < e.st.plan.length - 1 ? d ~/ 14 : e.st.plan.length - 1;
        expect(e.st.stage, expectStage, reason: 'ab $start Tag $d');
        expect(e.today, addD(first, d));
        now = DateTime(now.year, now.month, now.day + 1, d.isEven ? 7 : 23);
        e.refresh();
      }
      expect(e.st.frz, isNull);
    }
  });

  test('Vorrat überzogen: bei 0 mg keine Warnung, sonst „reicht bis heute“ (19.11.)', () {
    final w = Sim(start: '2026-03-01T09:00:00');
    w.setup(2, 50, 3, 0.5); // 2 → 1 → 0 mg, je 3 Tage
    w.e.setStock(1, 1);
    w.at(10);
    w.take(2); // mehr genommen als gezählt
    expect(w.e.stockInfo()!.rem, -1);
    expect(w.e.stockInfo()!.days, 1, reason: 'heute schon genommen: Vorrat leer, aber nicht „nicht für heute“');
    for (var i = 0; i < 6; i++) {
      w.day();
      w.take(w.st.plan[w.st.stage]);
    }
    expect(w.st.plan[w.st.stage], 0, reason: 'Ziel erreicht');
    expect(w.e.stockInfo()!.days, double.infinity, reason: 'bei 0 mg reicht jeder Vorrat');
  });
}
