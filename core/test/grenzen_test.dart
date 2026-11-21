// Grenzwerte und Sonderfälle. Jeder Fall hier war entweder ein gefundener Fehler
// (Regressionstest) oder ein Grenzfall, der bisher nicht ausdrücklich geprüft wurde.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  late DateTime jetzt;
  Taper neu({String start = '2026-01-05'}) {
    jetzt = DateTime.parse('${start}T09:00:00Z');
    return Taper(clock: () => jetzt);
  }

  void tag(Taper t, [int n = 1]) {
    jetzt = jetzt.add(Duration(days: n));
    t.refresh();
  }

  group('Fehler 1: Halten mit Enddatum – Kalender/Diagramm laufen danach laut Plan weiter', () {
    test('Prognose: bis zum Halte-Ende gehaltene Dosis, danach nächste Stufe am richtigen Tag', () {
      final t = neu();
      t.setup(dose: 10, step: 1, minStep: 0.5, days: 7, goal: 0);
      for (var i = 0; i < 5; i++) {
        t.addIntake(10, force: true);
        tag(t);
      }
      // Stufentag 5 von 7, 3 Tage halten (bis 13.1.): danach noch 2 Tage 10 mg, ab 15.1. 9 mg.
      t.startHold(3);
      final pm = t.projMap('2026-01-20');
      expect([for (final k in ['2026-01-11', '2026-01-12', '2026-01-13', '2026-01-14']) pm.map[k]!.v],
          [10, 10, 10, 10]);
      expect(pm.map['2026-01-15']!.v, 9);
      expect(pm.map['2026-01-15']!.ch, isTrue, reason: 'Stufenwechsel-Markierung im Kalender');
      // So kommt es dann auch tatsächlich:
      for (var i = 0; i < 5; i++) {
        t.addIntake(t.st.plan[t.st.stage], force: true);
        tag(t);
      }
      expect(t.today, '2026-01-15');
      expect(t.st.plan[t.st.stage], 9);
    });

    test('Diagramm endet beim voraussichtlichen Ende statt 30 Tage flach', () {
      final t = neu();
      t.setup(dose: 10, step: 5, minStep: 0.5, days: 7, goal: 0); // 10 → 5 → 0
      t.startHold(5);
      final v = t.verlauf();
      expect(v.bis, t.voraussichtlichesEnde());
      expect(v.tage.last.plan, 0);
    });

    test('Ohne Enddatum bleibt alles gehalten (bis auf Weiteres)', () {
      final t = neu();
      t.setup(dose: 10, step: 1, minStep: 0.5, days: 7, goal: 0);
      t.startHold(null);
      final pm = t.projMap('2026-03-01');
      expect(pm.map.values.every((p) => p.v == 10), isTrue);
      expect(t.verlauf().bis, '2026-02-04', reason: 'heute + 30');
    });
  });

  group('Fehler 2: unsinnige Eingaben dürfen nicht abstürzen', () {
    test('Riesige Stufendauer wird abgelehnt statt die Datumsrechnung zu sprengen', () {
      for (final n in [3651, 50000000, 1000000000]) {
        final t = neu();
        final ed = t.openEditor(neu: true)..rows = [EditRow(10, n), EditRow(5, 14), EditRow(0, 14)];
        final r = t.applyPlan(ed);
        expect(r.applied, isFalse, reason: '$n Tage');
        expect(r.err?.code, MeldungCode.stufeMaxTage);
        expect(r.err?.werte[1], 3650);
        expect(t.s, isNull);
      }
    });

    test('3650 Tage je Stufe gehen, Gesamtlänge über 100 Jahre nicht', () {
      final t = neu();
      final ok = t.openEditor(neu: true)..rows = [EditRow(10, 3650), EditRow(0, 14)];
      expect(t.applyPlan(ok).applied, isTrue);
      expect(t.voraussichtlichesEnde(), addD('2026-01-05', 3650));
      final t2 = neu();
      final lang = t2.openEditor(neu: true)..rows = [for (var i = 0; i < 12; i++) EditRow(10.0 - i * 0.5, 3650)];
      expect(t2.applyPlan(lang).err?.code, MeldungCode.planZuLang);
    });

    test('Rechner und Abschnitte prüfen dieselben Grenzen', () {
      final t = neu();
      expect(t.setup(dose: 10, step: 1, minStep: .5, days: 5000, goal: 0), isNotNull);
      expect(t.setup(dose: double.infinity, step: 1, minStep: .5, days: 14, goal: 0), isNotNull);
      expect(planAusAbschnitten(10, [const Abschnitt(1, 4000, 0)]).fehler?.werte,
          [0, 3650]);
      expect(planAusAbschnitten(10, [const Abschnitt(0.01, 3650, 0)]).fehler, isNotNull,
          reason: '1000 Stufen × 10 Jahre');
      final e = t.openEditor(neu: true);
      t.editCalc(e, dose: 10, step: 1, minStep: .5, days: 5000, goal: 0);
      expect(e.err?.code, MeldungCode.stufeMaxTage);
    });

    test('Unendlich/NaN/negativ: Einnahme und Vorrat werden ignoriert', () {
      final t = neu();
      t.setup(dose: 10, step: 1, minStep: .5, days: 14, goal: 0);
      for (final v in [double.nan, double.infinity, -1.0]) {
        expect(t.addIntake(v, force: true), IntakeResult.ignored);
      }
      expect(t.st.log, isEmpty);
      t.setStock(double.infinity, 5);
      t.setStock(-3, 5);
      expect(t.st.stock, isNull);
      t.setStock(10, 5);
      t.setStock(double.nan, 5, add: true);
      expect(t.st.stock!.mg, 50);
    });

    test('Kaputte Uhrzeiten beim Nachtragen: kein Absturz, Zeitstempel nie in der Zukunft', () {
      final t = neu();
      t.setup(dose: 10, step: 1, minStep: .5, days: 14, goal: 0);
      tag(t, 2);
      for (final u in ['25:99', 'ab:cd', '7', ':', '23:59']) {
        expect(t.addIntake(1, t: u, k: '2026-01-06', force: true), IntakeResult.added);
        expect(t.addIntake(1, t: u, force: true), IntakeResult.added);
      }
      for (final e in t.st.log.values) {
        for (final x in e.it) {
          expect(x.ts, lessThanOrEqualTo(jetzt.millisecondsSinceEpoch));
        }
      }
    });
  });

  group('Fehler 3: Stillstand nach Stufenwechsel neu bewerten (Zustand vor/nach Neustart gleich)', () {
    test('Wechsel auf 0 mg bei offenen Tagen: refresh() danach ändert nichts mehr', () {
      final t = neu();
      final ed = t.openEditor(neu: true)..rows = [EditRow(10, 3), EditRow(0, 14)];
      t.applyPlan(ed);
      t.addIntake(10, force: true);
      tag(t, 5); // Tage 6.–9.1. vergessen
      final a = t.exportJson().toString();
      t.refresh();
      expect(t.exportJson().toString(), a, reason: 'idempotent');
    });
  });

  group('Fehler 4: Vorrat beim Halten auf überfälliger Stufe', () {
    test('Reichweite rechnet mit dem Stufenwechsel direkt am Halte-Ende', () {
      final t = neu();
      t.setup(dose: 10, step: 5, minStep: .5, days: 3, goal: 0); // 10 (3 T) → 5 (3 T) → 0
      tag(t, 3); // 3 Tage vergessen → Stillstand, Stufe bleibt 10 mg (überfällig)
      expect(t.st.stage, 0);
      t.startHold(2); // Halten löst den Stillstand; Stufentag 3 von 3
      // heute 10 + morgen 10 (gehalten), am Halte-Ende sofort 5 mg
      expect(t.reichweite(25), 3);
      expect(t.projMap(addD(t.today, 3)).map[addD(t.today, 2)]!.v, 5);
      expect(t.voraussichtlichesEnde(), addD(t.today, 5));
    });
  });

  group('Kalender: Monats-, Jahreswechsel, Schaltjahr, Zeitumstellung', () {
    test('Stufen über Jahreswechsel und 29.2. hinweg auf den Tag genau', () {
      final t = neu(start: '2027-12-20');
      t.setup(dose: 10, step: 5, minStep: .5, days: 7, goal: 0);
      expect(t.voraussichtlichesEnde(), '2028-01-03');
      final t2 = neu(start: '2028-02-25');
      t2.setup(dose: 10, step: 5, minStep: .5, days: 7, goal: 0);
      expect(t2.projMap('2028-03-04').map['2028-03-03']!.v, 5, reason: '25.2. + 7 Tage im Schaltjahr = 3.3.');
      expect(t2.projMap('2028-03-04').map['2028-03-02']!.v, 10);
    });

    test('Tage zählen über die Zeitumstellung (lokale Uhr) ohne Versatz', () {
      // 28./29.3.2026 und 24./25.10.2026: Tagesdifferenz bleibt ganzzahlig.
      expect(dBetween('2026-03-28', '2026-03-30'), 2);
      expect(dBetween('2026-10-24', '2026-10-26'), 2);
      expect(addD('2026-03-28', 1), '2026-03-29');
      expect(addD('2026-10-25', 1), '2026-10-26');
    });
  });

  group('Grenzfälle Plan', () {
    test('Plan mit einer einzigen Stufe: kein Ende, Diagramm bis heute, Vorrat bis Planende', () {
      final t = neu();
      t.applyPlan(t.openEditor(neu: true)..rows = [EditRow(5, 14)]);
      expect(t.voraussichtlichesEnde(), isNull);
      expect(t.verlauf().bis, t.today);
      t.setStock(10, 5);
      expect(t.stockInfo()!.days, 10);
    });

    test('Ziel ≠ 0 (z. B. 2,5 mg): Ende = Beginn der letzten Stufe', () {
      final t = neu();
      t.setup(dose: 5, step: 1.25, minStep: .25, days: 7, goal: 2.5);
      expect(t.st.plan, [5, 3.75, 2.5]);
      expect(t.voraussichtlichesEnde(), addD(t.today, 14));
    });

    test('Kleinste Dezimalschritte (0,125) bleiben exakt', () {
      final t = neu();
      t.setup(dose: 1, step: .125, minStep: .125, days: 3, goal: 0);
      expect(t.st.plan.length, 9);
      for (final p in t.st.plan) {
        expect((p * 1000).roundToDouble(), p * 1000, reason: 'keine Rundungsreste: $p');
      }
    });
  });
}
