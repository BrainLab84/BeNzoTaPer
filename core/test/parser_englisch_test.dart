import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 20);
  List<(double, int, bool)> p(String t, {bool en = true}) =>
      [for (final r in parsePlanText(t, 14, now, en).rows) (r.dose, r.days, r.guess)];

  test('Englisch: Week 1–2 / Weeks 3 to 4', () {
    expect(p('Week 1-2: 10 mg\nWeek 3-4: 8 mg\nWeek 5: 6 mg'), [(10.0, 14, false), (8.0, 14, false), (6.0, 7, false)]);
    expect(p('Weeks 1 to 2: 10 mg\nWeeks 3 to 4: 5 mg').map((r) => r.$2), [14, 14]);
  });

  test('Englisch: Day 1–14 und „for 14 days“', () {
    expect(p('Day 1-14: 10 mg\nDay 15-28: 7.5 mg'), [(10.0, 14, false), (7.5, 14, false)]);
    expect(p('10 mg for 10 days\n5 mg for 5 days'), [(10.0, 10, false), (5.0, 5, false)]);
  });

  test('Englisch: Datum TT/MM (from 01/12) und mit Jahr', () {
    final r = parsePlanText('from 01/12: 10 mg\nfrom 15/12: 8 mg\nfrom 29/12: 6 mg', 14, now, true).rows;
    expect(r.map((x) => x.days), [14, 14, 14]);
    final r2 = parsePlanText('01/12/2026: 10 mg\n08/12/2026: 8 mg', 14, now, true).rows;
    expect(r2.first.days, 7);
  });

  test('Englisch: Einheiten und Stopp', () {
    expect(parsePlanText('Week 1: 2 drops', 14, now, true).unit, 'drops');
    expect(parsePlanText('Week 1: 2 drops', 14, now, false).unit, 'Tropfen');
    expect(parsePlanText('Week 1: 1 tablet', 14, now, true).unit, 'tab');
    expect(p('Week 1-2: 2 mg\nWeek 3: stop').last, (0.0, 7, false));
  });

  test('Brüche wie 1/2 Tablette bleiben Dosis, kein Datum', () {
    final r = parsePlanText('Week 1-2: 1/2 tablet', 14, now, true).rows;
    expect(r.single.dose, 0.5);
    expect(r.single.days, 14);
  });
}
