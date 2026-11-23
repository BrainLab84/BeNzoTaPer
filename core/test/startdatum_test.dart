// Startdatum beim ersten Plan: heute oder später. Vor dem Start keine Dosis, keine offenen Tage,
// keine Einnahme, kein Verbrauch.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

void main() {
  late DateTime jetzt;
  Taper neu([String heute = '2026-11-22']) {
    jetzt = DateTime.parse('${heute}T09:00:00Z');
    return Taper(clock: () => jetzt);
  }

  void tag(Taper t, [int n = 1]) {
    jetzt = jetzt.add(Duration(days: n));
    t.refresh();
  }

  // Referenzplan aus Doc 29: Diazepam 20 → 0 mg.
  List<EditRow> referenz() => [
        EditRow(20, 2),
        EditRow(15, 14),
        EditRow(10, 21),
        EditRow(7.5, 21),
        EditRow(5, 21),
        EditRow(2.5, 21),
        EditRow(0, 21),
      ];

  Taper mitStart(String? start, {String heute = '2026-11-22'}) {
    final t = neu(heute);
    final e = t.openEditor(neu: true)
      ..rows = referenz()
      ..startDatum = start;
    expect(t.applyPlan(e).applied, isTrue);
    return t;
  }

  test('Ohne Startdatum: Start heute wie bisher', () {
    final t = mitStart(null);
    expect(t.st.t0, '2026-11-22');
    expect(t.st.stageStart, '2026-11-22');
    expect(t.vorStart, isFalse);
  });

  test('Startdatum in der Vergangenheit wird zu heute', () {
    final t = mitStart('2026-11-01');
    expect(t.st.t0, '2026-11-22');
    expect(t.vorStart, isFalse);
  });

  test('Start in 5 Tagen: vorher nichts offen, nichts eintragbar, Kalender leer bis zum Start', () {
    final t = mitStart('2026-11-27');
    expect(t.st.t0, '2026-11-27');
    expect(t.st.stageStart, '2026-11-27');
    expect(t.vorStart, isTrue);
    expect(t.addIntake(20), IntakeResult.ignored);
    expect(t.st.log, isEmpty);
    final pm = t.projMap('2026-11-30').map;
    expect(pm.containsKey('2026-11-23'), isFalse);
    expect(pm.containsKey('2026-11-26'), isFalse);
    expect(pm['2026-11-27']!.v, 20, reason: 'erster Plantag');
    expect(pm['2026-11-29']!.v, 15);
    // Voraussichtlich bei 0 mg: wie Referenz A, um 5 Tage später (02.03. → 07.03.2027).
    expect(t.voraussichtlichesEnde(), '2027-03-07');

    for (var i = 0; i < 4; i++) {
      tag(t);
      expect(t.openDays(), isEmpty, reason: 'vor dem Start keine ?-Tage (${t.today})');
      expect(t.st.frz, isNull);
      expect(t.st.stage, 0);
    }
    tag(t); // 27.11.: Start
    expect(t.vorStart, isFalse);
    expect(t.stageDay(), 0);
    expect(t.addIntake(20), IntakeResult.added);
    tag(t);
    expect(t.openDays(), isEmpty);
    tag(t); // 29.11.: zweite Stufe
    expect(t.openDays(), ['2026-11-28'], reason: 'ab Start zählen fehlende Tage');
  });

  test('Vorrat vor dem Start: kein Verbrauch, Reichweite = Vorlauf + Referenz A (42 Tage)', () {
    final t = mitStart('2026-11-27');
    t.setStock(50, 10);
    final si = t.stockInfo()!;
    expect(si.rem, 500);
    // Referenz A: 500 mg reichen ab Start ca. 42 Tage; dazu 5 Vorlauftage ohne Verbrauch.
    expect(si.days, 47);
    tag(t, 2);
    expect(t.stockInfo()!.days, 45, reason: 'jeder Vorlauftag zieht nur einen Tag ab');
    expect(t.stockInfo()!.rem, 500);
    tag(t, 3); // Start
    expect(t.stockInfo()!.days, 42, reason: 'wie Referenz A am ersten Plantag');
  });

  test('Import: erkanntes Datum wird Vorschlag, wenn es nicht in der Vergangenheit liegt', () {
    final t = neu();
    final e = t.openEditor(neu: true);
    t.editParse(e, 'ab 01.12.2026 20 mg\nab 15.12.2026 15 mg\nab 05.01.2027 10 mg');
    expect(e.startDatum, '2026-12-01');
    final alt = t.openEditor(neu: true);
    t.editParse(alt, 'ab 01.11.2026 20 mg\nab 15.11.2026 15 mg\nab 30.11.2026 10 mg');
    expect(alt.startDatum, isNull, reason: 'Vergangenheit: kein Vorschlag, Start heute');
  });

  test('Bestehender Plan: Startdatum ohne Wirkung', () {
    final t = mitStart(null);
    final e = t.openEditor(neu: true)
      ..rows = referenz()
      ..startDatum = '2026-12-10'
      ..conf = 'Ich bin mir sicher';
    expect(t.applyPlan(e).applied, isTrue);
    expect(t.st.t0, '2026-11-22');
    expect(t.vorStart, isFalse);
  });
}
