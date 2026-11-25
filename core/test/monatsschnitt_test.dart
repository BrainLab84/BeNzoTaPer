// Monats-Ø (Kalendermonat) und Rundung auf 2 Nachkommastellen.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  late DateTime jetzt;
  Taper neu() {
    jetzt = DateTime.parse('2026-11-29T09:00:00Z');
    final t = Taper(clock: () => jetzt);
    final e = t.openEditor(neu: true)..rows = [EditRow(1, 30), EditRow(0.99, 30), EditRow(0, 14)];
    expect(t.applyPlan(e).applied, isTrue);
    return t;
  }

  void tag(Taper t) {
    jetzt = jetzt.add(const Duration(days: 1));
    t.refresh();
  }

  test('Monats-Ø zählt nur abgeschlossene Tage des Kalendermonats, Vormonat getrennt', () {
    final t = neu();
    t.addIntake(1, force: true); // 29.11.
    tag(t);
    t.addIntake(0.98, force: true); // 30.11. weniger als geplant
    tag(t); // 1.12.
    expect(t.monatsSchnitt().avg, isNull, reason: 'Dezember noch ohne abgeschlossenen Tag');
    expect(t.monatsSchnitt(null, 1).avg, closeTo(0.99, 1e-9));
    expect(t.monatsSchnitt(null, 1).n, 2);
    t.addIntake(1, force: true);
    expect(t.monatsSchnitt().avg, 1);
  });

  test('round2 macht 0,01-Schritte sichtbar', () {
    expect(round2(0.994), 0.99);
    expect(round2(0.995), 1.0);
    expect(fmt(round2(9.876)), '9,88');
    expect(round2(-0.004), 0);
  });
}
