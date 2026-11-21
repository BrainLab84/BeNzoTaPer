import 'dart:convert';

import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  test('Ein Abschnitt: 10 → 0 in 1-mg-Schritten alle 14 Tage', () {
    final r = planAusAbschnitten(10, const [Abschnitt(1, 14, 0)]);
    expect(r.fehler, isNull);
    expect(r.plan, [10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);
    expect(r.days, List.filled(11, 14));
  });

  test('Zwei Abschnitte: erst 2,5 mg, dann 1 mg langsamer', () {
    final r = planAusAbschnitten(20, const [Abschnitt(2.5, 14, 10), Abschnitt(1, 21, 0)]);
    expect(r.fehler, isNull);
    expect(r.plan, [20, 17.5, 15, 12.5, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);
    // 20 … 12,5 im ersten Rhythmus; ab 10 mg (Ende Abschnitt 1) gilt der zweite.
    expect(r.days, [14, 14, 14, 14, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21]);
    expect(r.plan.length, r.days.length);
  });

  test('Letzter Schritt kleiner, wenn es nicht aufgeht', () {
    final r = planAusAbschnitten(10, const [Abschnitt(3, 7, 0)]);
    expect(r.plan, [10, 7, 4, 1, 0]);
  });

  test('Krumme Zahlen ohne Rundungsfehler', () {
    final r = planAusAbschnitten(1, const [Abschnitt(0.1, 7, 0)]);
    expect(r.plan, [1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0]);
  });

  test('Ziel über 0 mg', () {
    final r = planAusAbschnitten(10, const [Abschnitt(2, 14, 5)]);
    expect(r.plan, [10, 8, 6, 5]);
  });

  test('Fehler werden verständlich gemeldet', () {
    Meldung? f(double start, List<Abschnitt> a) => planAusAbschnitten(start, a).fehler;
    expect(f(0, const [Abschnitt(1, 14, 0)]), const Meldung(MeldungCode.abschnittStartdosis));
    expect(f(10, const []), const Meldung(MeldungCode.abschnittKeiner));
    expect(f(10, const [Abschnitt(0, 14, 0)]), const Meldung(MeldungCode.abschnittSchritt, [0]));
    expect(f(10, const [Abschnitt(1, 0, 0)]), const Meldung(MeldungCode.abschnittTage, [0]));
    expect(f(10, const [Abschnitt(1, 14, 10)]), const Meldung(MeldungCode.abschnittBisUeberStart, [0, 10.0]));
    expect(f(10, const [Abschnitt(1, 14, 5), Abschnitt(1, 14, 6)]),
        const Meldung(MeldungCode.abschnittBisUeberVorigem, [2, 5.0, 1]));
    expect(f(10, const [Abschnitt(1, 14, 0), Abschnitt(1, 21, 0)]), const Meldung(MeldungCode.abschnittEndetBeiNull, [1]));
    expect(f(10, const [Abschnitt(1, 14, -1)]), const Meldung(MeldungCode.abschnittBisNegativ, [0]));
    expect(f(10, const [Abschnitt(1, 14, double.nan)]), const Meldung(MeldungCode.abschnittBisFehlt, [0]));
    expect(f(100, const [Abschnitt(0.01, 1, 0)]), const Meldung(MeldungCode.abschnittZuViele));
  });

  test('Plan aus Abschnitten lässt sich übernehmen (neuer Stand) und wieder laden', () {
    final t = Taper(clock: () => DateTime.utc(2026, 3, 10, 12));
    final r = planAusAbschnitten(20, const [Abschnitt(2.5, 14, 10), Abschnitt(1, 21, 0)]);
    final e = t.openEditor(neu: true)
      ..name = 'Diazepam'
      ..rows = [for (var i = 0; i < r.plan.length; i++) EditRow(r.plan[i], r.days[i])];
    expect(t.applyPlan(e).applied, isTrue);
    t.st.person = 'Alex';
    final j = jsonDecode(jsonEncode(t.exportJson()));
    expect(j['person'], 'Alex');
    final t2 = Taper(clock: () => DateTime.utc(2026, 3, 10, 12));
    expect(t2.importJson(j), isTrue);
    expect(t2.st.person, 'Alex');
    expect(t2.st.plan, r.plan);
    expect(t2.need(4), 21);
    // Ohne Namen kein Feld in der Sicherung (alte Sicherungen bleiben gleich).
    t.st.person = null;
    expect(t.exportJson()!.containsKey('person'), isFalse);
  });
}
