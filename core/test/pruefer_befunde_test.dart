// Befunde der unabhängigen Vorrat-Prüfungen als feste Regressionstests.
//
// Grundsatz: Eine Planänderung, ein Halten oder offene Tage ändern nie rückwirkend, mit welcher Dosis ein
// vergangener Tag ohne Eintrag im Vorrat geschätzt wird. Ab heute gilt die echte Planposition.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

late DateTime _jetzt;

Taper _neu(String start, {String uhr = '08:00:00'}) {
  _jetzt = DateTime.parse('${start}T${uhr}Z');
  return Taper(clock: () => _jetzt);
}

void _plan(Taper t, List<List<num>> rows, {String? start}) {
  final r = t.applyPlan(t.openEditor(neu: true)
    ..rows = [for (final x in rows) EditRow(x[0].toDouble(), x[1].toInt())]
    ..startDatum = start);
  expect(r.applied, isTrue);
}

void _tag(Taper t, [int n = 1]) {
  _jetzt = _jetzt.add(Duration(days: n));
  t.refresh();
}

void _min([int m = 1]) => _jetzt = _jetzt.add(Duration(minutes: m));

void _nimm(Taper t, double mg) {
  _min();
  t.addIntake(mg, force: true);
}

/// Alte Planänderung über den Editor (Weg alter Vormerkungen); bei Bedarf mit Begründung übernommen.
ApplyResult _aendern(Taper t, List<List<num>> rows, {int start = 0}) {
  final e = t.openEditor()
    ..rows = [for (final x in rows) EditRow(x[0].toDouble(), x[1].toInt())]
    ..start = start
    ..conf = 'ich bin mir sicher'
    ..pendOk = true;
  return t.applyPlan(e);
}

void main() {
  test('Offener Tag: Eintrag heute bekommt die echte Planposition, Reichweite stimmt', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 2],
      [5, 40],
      [0, 14]
    ]);
    t.setStock(20, 5); // 100 mg
    _nimm(t, 10); // 05.01.
    _tag(t, 2); // 06.01. vergessen, heute 07.01. = Stufe 2 (5 mg)
    _nimm(t, 5);
    expect(t.st.log[t.today]!.plan, 5);
    final si = t.stockInfo()!; // 100 − 10 − 10 (06.01. geschätzt) − 5
    expect(si.rem, 75);
    expect(si.days, 16);
  });

  test('Offene Tage, dann „weiß ich nicht mehr“: Rest bleibt, Schätzung mit der damaligen Stufe', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 2],
      [5, 3],
      [2, 3],
      [0, 14]
    ]);
    t.setStock(50, 5); // 250 mg
    for (final d in [10, null, 5, null, 5, 2, 2, 2, 0, 0, 0]) {
      if (d != null) _nimm(t, d.toDouble());
      _tag(t);
    }
    final vor = t.stockInfo()!; // 250 − 26 − 10 (06.01.) − 5 (08.01.)
    expect(vor.rem, 209);
    t.markUnk();
    expect(t.stockInfo()!.rem, 209);
    expect(t.sollAm('2026-01-08'), 5);
  });

  test('Tag ohne Eintrag beim Halten am Stufenanfang: nach dem Halten unverändert geschätzt', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 3],
      [5, 40],
      [0, 14]
    ]);
    t.setStock(20, 5); // 100 mg
    for (var d = 0; d < 3; d++) {
      _nimm(t, 10);
      _tag(t);
    }
    expect(t.startHold(2), isTrue); // 08.01. = erster Tag 5 mg, heute nichts eingetragen
    _tag(t); // 09.01.
    _nimm(t, 5);
    expect(t.stockInfo()!.rem, 60); // 100 − 30 − 5 (08.01. geschätzt) − 5
    _tag(t); // 10.01.: Halten endet
    expect(t.st.hold, isFalse);
    expect(t.stockInfo()!.rem, 60);
    expect(t.sollAm('2026-01-08'), 5);
  });

  test('Halten auf der Zielstufe mit Tagen ohne Eintrag: Schätzung bleibt über das Halte-Ende', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 2],
      [1, 3]
    ]); // Ziel 1 mg läuft offen weiter
    t.setStock(10, 10); // 100 mg
    for (var d = 0; d < 2; d++) {
      _nimm(t, 10);
      _tag(t);
    }
    _tag(t, 14); // 07.–20.01. nichts eingetragen; heute 21.01.
    expect(t.startHold(3), isFalse, reason: 'bei offenen Tagen erst eintragen');
    t.markUnk(); // 07.–13.01.: weiß ich nicht mehr
    for (var k = '2026-01-14'; k.compareTo('2026-01-20') <= 0; k = addD(k, 1)) {
      t.addIntake(1, k: k, force: true);
    }
    expect(t.st.frz, isNull);
    expect(t.startHold(3), isTrue);
    for (var d = 0; d < 3; d++) {
      _nimm(t, 1);
      _tag(t);
    } // 24.01.: Halten endet
    expect(t.st.hold, isFalse);
    final si = t.stockInfo()!; // 100 − 20 − 7 geschätzt − 7 nachgetragen − 3
    expect(si.rem, 63);
    expect(si.geschaetzt, 7);
    expect(t.sollAm('2026-01-07'), 1);
  });

  test('Planänderung schätzt vergangene Tage nicht rückwirkend mit dem neuen Plan', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 20],
      [5, 20],
      [0, 14]
    ]);
    t.setStock(10, 10); // 100 mg
    _nimm(t, 10);
    _tag(t, 3); // 06.–07.01. ohne Eintrag (je 10 mg geschätzt)
    _nimm(t, 10);
    final vor = t.stockInfo()!;
    expect(vor.rem, 60);
    final r = _aendern(t, [
      [8, 10],
      [4, 10],
      [0, 14]
    ]);
    expect(r.applied, isTrue);
    expect(t.sollAm('2026-01-06'), 10);
    expect(t.stockInfo()!.rem, 60);
  });

  test('Planänderung bei offenen Tagen über einen Stufenwechsel: die Vergangenheit bleibt', () {
    // Plan 10×5, 8×5, 6×20. Ab 08.01. nichts eingetragen (Stufe 2 ab 10.01.), heute 14.01.
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 5],
      [8, 5],
      [6, 20],
      [0, 14]
    ]);
    t.setStock(100, 5); // 500 mg
    for (var d = 0; d < 3; d++) {
      _nimm(t, 10);
      _tag(t);
    }
    _tag(t, 6); // 08.–13.01. offen, heute 14.01.
    expect(t.st.frz, isNotNull);
    final vor = t.stockInfo()!; // 500 − 30 − 10 − 10 − 8×4
    expect(vor.rem, 418);
    expect(vor.geschaetzt, 6);
    // Gleiche Dosis wie die (stehende) Stufe 1, Stufe 1 jetzt 20 Tage lang
    expect(
        _aendern(t, [
          [10, 20],
          [8, 5],
          [6, 20],
          [0, 14]
        ]).applied,
        isTrue);
    expect(t.stockInfo()!.rem, 418);
    for (final (k, mg) in [('2026-01-09', 10.0), ('2026-01-10', 8.0), ('2026-01-13', 8.0)]) {
      expect(t.sollAm(k), mg, reason: k);
    }
  });

  test('Stufe verlängern (alte Vormerkung) ändert vergangene Tage nicht', () {
    final t = _neu('2026-03-01');
    _plan(t, [
      [10, 10],
      [8, 10],
      [6, 10],
      [0, 14]
    ]);
    t.setStock(100, 5); // 500 mg
    expect(t.saveLeft(15, why: 'zu schnell'), LeftResult.pended);
    _tag(t, 26); // 01.–26.03. ohne Eintrag, heute 27.03.
    final vor = t.stockInfo()!; // 10×10 + 8×10 + 6×6
    expect(vor.rem, 284);
    t.usePend();
    expect(t.stockInfo()!.rem, 284);
    expect(t.sollAm('2026-03-12'), 8);
    expect(t.sollAm('2026-03-25'), 6);
  });

  test('„Kurz innehalten“ prüft bei offenen Tagen gegen die echte Dosis', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 2],
      [5, 40],
      [0, 14]
    ]);
    _nimm(t, 10);
    _tag(t, 2); // 07.01.: Plan 5 mg, 06.01. offen
    expect(t.addIntake(8), IntakeResult.needsPause);
  });

  test('Reichweite über 3000 Tage wird nicht abgeschnitten', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [1, 1],
      [0.25, 14]
    ]);
    t.setStock(1000, 1);
    expect(t.stockInfo()!.days, 3997); // heute 1 mg offen → 999 / 0,25 = 3996 → 3997
  });

  test('Halten bei offenen Tagen geht erst nach dem Eintragen – dann mit der echten Stufe', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 2],
      [5, 40],
      [0, 14]
    ]);
    t.setStock(20, 5); // 100 mg
    _nimm(t, 10);
    _tag(t, 2); // 07.01.: Plan 5 mg, 06.01. offen
    expect(t.startHold(null), isFalse);
    expect(t.st.hold, isFalse);
    t.addIntake(10, k: '2026-01-06', force: true);
    expect(t.startHold(null), isTrue);
    expect(t.st.plan[t.st.stage], 5);
    expect(t.stockInfo()!.days, 16); // 80 mg: heute 5 offen → 75 / 5 = 15 → 16
  });

  test('Erneut „Halten“ während eines Haltens wird abgelehnt (gehaltene Tage bleiben)', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 4],
      [5, 4],
      [0, 14]
    ]);
    _nimm(t, 10);
    _tag(t); // 06.01.
    expect(t.startHold(null), isTrue);
    for (var d = 0; d < 2; d++) {
      _nimm(t, 10);
      _tag(t);
    } // 08.01.
    expect(t.startHold(2), isFalse);
    expect(t.st.holdSince, '2026-01-06');
    expect(t.st.holdUntil, isNull);
    _nimm(t, 10);
    t.stopHold(); // 06.–07.01. gehalten → 08.01. Tag 2, 09.01. Tag 3, 10.01. Tag 4, ab 11.01. 5 mg
    _tag(t, 2);
    expect(t.sollAm(t.today), 10);
    _tag(t);
    expect(t.sollAm(t.today), 5);
  });

  test('Halten vor dem Planstart wird abgelehnt, der Start bleibt', () {
    final t = _neu('2026-01-05');
    _plan(
        t,
        [
          [10, 3],
          [5, 3],
          [0, 14]
        ],
        start: '2026-01-10');
    expect(t.startHold(3), isFalse);
    _tag(t, 5); // 10.01. Planstart
    for (var i = 0; i < 3; i++) {
      _nimm(t, 10);
      _tag(t);
    } // 13.01.: laut Plan erster Tag 5 mg
    expect(t.st.t0, '2026-01-10');
    expect(t.sollAm(t.today), 5);
  });

  test('Grenze 12:00: Nachtrag ohne Uhrzeit am Zähltag', () {
    for (final (uhr, soll) in [('12:00:00', 100.0), ('11:59:59.999', 90.0)]) {
      final t = _neu('2026-01-05', uhr: uhr);
      _plan(t, [
        [10, 5],
        [0, 14]
      ]);
      t.setStock(10, 10); // 100 mg
      _tag(t); // 06.01.
      t.addIntake(10, k: '2026-01-05', force: true); // ohne Uhrzeit = 12:00
      expect(t.stockInfo()!.rem, soll, reason: uhr);
    }
  });

  test('Nachkauf bei überzogenem Rest: addiert auf den negativen Rest, Vorschau = Ergebnis', () {
    final t = _neu('2026-01-05');
    _plan(t, [
      [10, 50],
      [0, 14]
    ]);
    t.setStock(1, 10); // 10 mg
    _nimm(t, 10);
    _nimm(t, 20); // 20 mg zu viel → Rest −20
    final vor = t.stockInfo()!;
    expect(vor.rem, -20);
    final vorschau = t.reichweite(vor.rem + 100);
    t.setStock(10, 10, add: true);
    final nach = t.stockInfo()!;
    expect(nach.rem, 80);
    expect(nach.days, 9);
    expect(vorschau, nach.days);
  });

  test('Plan während des Haltens schneller gemacht: die Stufe endet frühestens am Halte-Ende', () {
    // Plan 10×10, 8×10, 6×10. Ab 05.01. gehalten (Stufentag 5), am 08.01. Stufe 1 auf 3 Tage gekürzt.
    final t = _neu('2026-01-01');
    _plan(t, [
      [10, 10],
      [8, 10],
      [6, 10],
      [0, 14]
    ]);
    t.setStock(100, 5); // 500 mg
    for (var d = 0; d < 4; d++) {
      _nimm(t, 10);
      _tag(t);
    }
    expect(t.startHold(5), isTrue); // gehalten 05.–09.01., ab 10.01. weiter
    for (var d = 0; d < 3; d++) {
      _nimm(t, 10);
      _tag(t);
    } // 08.01.
    expect(
        _aendern(t, [
          [10, 3],
          [8, 10],
          [6, 10],
          [0, 14]
        ]).applied,
        isTrue);
    // Kein Sprung über mehrere Stufen: nach dem Halten direkt Stufe 2, danach 10 Tage 6 mg.
    expect(t.voraussichtlichesEnde(), '2026-01-30');
    _nimm(t, 10);
    _tag(t);
    _nimm(t, 10);
    _tag(t); // 10.01.: Halten zu Ende
    expect(t.st.hold, isFalse);
    expect(t.st.stage, 1);
    expect(t.st.stageStart, '2026-01-10');
    expect(t.sollAm(t.today), 8);
    expect(t.sollAm('2026-01-09'), 10);
    expect(t.voraussichtlichesEnde(), '2026-01-30');
  });
}
