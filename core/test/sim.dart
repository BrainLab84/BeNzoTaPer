// Test-Hilfe: Taper mit steuerbarer Uhr .
import 'package:tapering_core/tapering_core.dart';

class Sim {
  DateTime now;
  late Taper e;

  Sim({String start = '2026-11-16T09:00:00', TaperState? state})
      : now = DateTime.parse(start.endsWith('Z') ? start : '${start}Z') {
    e = Taper(s: state, clock: () => now);
  }

  String get today => ymd(now);
  TaperState get st => e.s!;

  /// Ein Tag (oder [n]) weiter, auf [h] Uhr.
  void day([int n = 1, int h = 9]) {
    now = DateTime.utc(now.year, now.month, now.day + n, h);
    e.refresh();
  }

  void at(int h, [int m = 0]) => now = DateTime.utc(now.year, now.month, now.day, h, m);

  /// Einnahme ohne "Kurz innehalten".
  IntakeResult take(double v, [String? t, String? k]) =>
      e.addIntake(v, t: (t == null || t.isEmpty) ? null : t, k: (k == null || k.isEmpty) ? null : k, force: true);

  void setup(double dose, [double pct = 10, int t = 14, double min = 0.25, double tg = 0]) {
    final err =
        e.setup(name: 'Diazepam', unit: 'mg', dose: dose, step: dose * pct / 100, minStep: min, days: t, goal: tg);
    if (err != null) throw StateError(err.toString());
  }

  /// Enddatum laut Plan; `null` bei Halten oder Stillstand.
  String? endCalc() {
    e.ensureStart();
    if (st.hold || st.frz != null) return null;
    return Taper.planEnd(st.plan, st.days, st.stage, st.stageStart!, st.target);
  }

  /// Enddatum wie im Kalender angezeigt.
  String? endShown() => e.projMap(today).end;

  /// Editor öffnen, ändern, übernehmen. [conf] = "Ich bin mir sicher" eintippen.
  (PlanEdit, ApplyResult) editor(void Function(PlanEdit) fn, {bool conf = true}) {
    final ed = e.openEditor();
    fn(ed);
    if (conf) ed.conf = 'Ich bin mir sicher';
    return (ed, e.applyPlan(ed));
  }

  /// Alle offenen Tage innerhalb von 7 Tagen nachtragen, ältere als "weiß ich nicht".
  void fillGaps() {
    for (final k in e.openDays()) {
      if (e.daysAgo(k) <= 7) take(e.planFor(k).plan, '', k);
    }
    if (st.frz != null) e.markUnk();
  }
}

String endOrNull(String? s) => s ?? 'null';
