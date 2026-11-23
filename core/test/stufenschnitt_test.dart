// Live-Ø seit Stufenbeginn.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  late DateTime jetzt;
  Taper neu() {
    jetzt = DateTime.parse('2026-11-22T09:00:00Z');
    final t = Taper(clock: () => jetzt);
    final e = t.openEditor(neu: true)..rows = [EditRow(20, 14), EditRow(15, 14), EditRow(0, 14)];
    expect(t.applyPlan(e).applied, isTrue);
    return t;
  }

  void tag(Taper t) {
    jetzt = jetzt.add(const Duration(days: 1));
    t.refresh();
  }

  test('Beispiel des Nutzers: 20 mg, dann 25 mg → Ø 22,5 sofort', () {
    final t = neu();
    expect(t.stufenSchnitt().avg, isNull);
    t.addIntake(20, force: true);
    expect(t.stufenSchnitt().avg, 20);
    tag(t);
    t.addIntake(25, force: true);
    expect(t.stufenSchnitt().avg, 22.5, reason: 'über Plan zählt sofort');
    expect(t.stufenSchnitt().n, 2);
  });

  test('Heute angefangen (unter Plan) zählt erst, wenn komplett; gestern weniger zählt', () {
    final t = neu();
    t.addIntake(15, force: true); // weniger als geplant, Tag läuft noch
    expect(t.stufenSchnitt().avg, isNull);
    tag(t); // gestern ist abgeschlossen: 15 zählt
    expect(t.stufenSchnitt().avg, 15);
    t.addIntake(10, force: true);
    expect(t.stufenSchnitt().avg, 15, reason: 'heute erst 10 von 20');
    t.addIntake(10, force: true);
    expect(t.stufenSchnitt().avg, 17.5);
  });

  test('Fehlende Tage zählen nicht; Halten verliert keine Tage; neue Stufe beginnt neu', () {
    final t = neu();
    t.addIntake(20, force: true);
    tag(t);
    tag(t); // gestern ohne Eintrag
    t.addIntake(22, force: true);
    expect(t.stufenSchnitt().avg, 21, reason: 'der Tag ohne Eintrag zählt nicht');
    t.addIntake(20, k: addD(t.today, -1)); // nachgetragen
    expect(t.stufenSchnitt().n, 3);
    t.startHold(2);
    tag(t);
    t.addIntake(20, force: true);
    tag(t);
    t.addIntake(20, force: true);
    expect(t.stufenSchnitt().n, 5, reason: 'Haltetage gehören zur Stufe');
    for (var i = 0; i < 20 && t.st.stage == 0; i++) {
      tag(t);
      t.addIntake(t.st.plan[t.st.stage], force: true);
    }
    expect(t.st.stage, 1);
    expect(t.stufenSchnitt().avg, 15, reason: 'neue Stufe, neuer Ø');
  });
}
