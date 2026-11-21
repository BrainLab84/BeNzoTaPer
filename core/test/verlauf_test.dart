import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  late DateTime jetzt;
  Taper neu() {
    jetzt = DateTime.utc(2026, 3, 1, 12);
    final t = Taper(clock: () => jetzt);
    t.setup(dose: 10, step: 1, minStep: 0.5, days: 7, goal: 0);
    return t;
  }

  void tag(Taper t, double v) {
    t.addIntake(v, force: true);
    jetzt = jetzt.add(const Duration(days: 1));
    t.refresh();
  }

  test('Frischer Plan: Zukunft bis Planende, Treppe laut Plan', () {
    final t = neu();
    final v = t.verlauf();
    expect(v.start, '2026-03-01');
    expect(v.bis, '2026-05-10'); // 10 Stufen à 7 Tage
    expect(v.tage.first.zukunft, isFalse);
    expect(v.tage.first.plan, 10);
    expect(v.tage.first.schnitt7, isNull);
    expect(v.tage[7].plan, 9);
    expect(v.tage.last.plan, 0);
    expect(v.tage.length, 71);
  });

  test('Welle: 7-Tage-Ø mit Ausrutscher, ? zählt nie als 0', () {
    final t = neu();
    for (var i = 0; i < 6; i++) {
      tag(t, i == 3 ? 12 : 10);
    }
    // Tag 7 ohne Eintrag lassen, dann weiter.
    jetzt = jetzt.add(const Duration(days: 1));
    t.addIntake(10, k: '2026-03-07');
    t.addIntake(9, force: true);
    t.refresh();
    final v = t.verlauf();
    final m4 = v.tage.firstWhere((x) => x.tag == '2026-03-04');
    expect(m4.dosis, 12);
    expect(m4.schnitt7, closeTo((10 + 10 + 10 + 12) / 4, 1e-9));
    final heute = v.tage.firstWhere((x) => x.tag == '2026-03-08');
    expect(heute.plan, 9);
    expect(heute.schnitt7, closeTo((10 * 5 + 12 + 9) / 7, 1e-9));
  });

  test('Angefangener Tag drückt den Durchschnitt nicht', () {
    final t = neu();
    tag(t, 10);
    t.addIntake(5, force: true);
    final v = t.verlauf();
    expect(v.tage.last.zukunft, isTrue);
    final heute = v.tage.firstWhere((x) => x.tag == '2026-03-02');
    expect(heute.schnitt7, 10);
  });

  test('Halten: 30 Tage Ausblick mit gleicher Dosis; offene Tage: nur bis heute', () {
    final t = neu();
    tag(t, 10);
    t.startHold(null);
    var v = t.verlauf();
    expect(v.bis, '2026-04-01');
    expect(v.tage.where((x) => x.zukunft).every((x) => x.plan == 10), isTrue);
    t.stopHold();
    jetzt = jetzt.add(const Duration(days: 3));
    t.refresh();
    expect(t.st.frz, isNotNull);
    v = t.verlauf();
    expect(v.bis, t.today);
    expect(v.tage.any((x) => x.zukunft), isFalse);
  });

  test('Letzte Stufe: bis heute', () {
    final t = Taper(clock: () => DateTime.utc(2026, 3, 1, 12));
    t.setup(dose: 1, step: 1, minStep: 0.5, days: 3, goal: 0);
    t.st.stage = 1;
    final v = t.verlauf();
    expect(v.bis, t.today);
  });
}
