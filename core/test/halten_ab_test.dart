// „Dosis halten“ geht erst am letzten Tag einer Stufe; vorher rechnet nichts mit einem Halten.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  test('Halten erst am letzten Stufentag, dann N Tage mehr mit der alten Dosis', () {
    var jetzt = DateTime.parse('2026-11-22T10:00:00Z');
    final t = Taper(clock: () => jetzt);
    final e = t.openEditor(neu: true)
      ..rows = [EditRow(20, 14), EditRow(15, 14), EditRow(0, 14)];
    t.applyPlan(e);
    final ohne = t.reichweite(500);
    for (var d = 0; d < 14; d++) {
      jetzt = DateTime.parse('2026-11-22T10:00:00Z').add(Duration(days: d));
      t.refresh();
      expect(t.haltenAb, '2026-12-05');
      expect(t.haltenMoeglich, d == 13, reason: 'Tag $d');
      if (d < 13) expect(t.reichweite(500), ohne - d, reason: 'Vorrat unverändert vor dem Halten');
      t.addIntake(t.sollAm(t.today), t: '09:00');
    }
    expect(t.startHold(10), isTrue);
    expect(t.haltenMoeglich, isFalse);
    expect(t.st.holdUntil, '2026-12-15');
    expect(t.planAm('2026-12-15').plan, 20);
    expect(t.projMap('2027-01-20').map['2026-12-16']!.v, 15);
  });
}
