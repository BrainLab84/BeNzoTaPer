// Vorratsrechnung, von Hand nachgerechnet: eigene Szenarien, Erwartungen aus der Spezifikation
// (Rechnung jeweils als Kommentar). Uhr = UTC.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

const ref = [
  [20, 2],
  [15, 14],
  [10, 21],
  [7.5, 21],
  [5, 21],
  [2.5, 21],
  [0, 21],
];

class W {
  DateTime jetzt;
  late final Taper t;
  final fehler = <String>[];
  W(String iso, List<List<num>> rows, {String? start}) : jetzt = DateTime.parse(iso) {
    t = Taper(clock: () => jetzt);
    neuerPlan(rows, start: start);
  }
  void neuerPlan(List<List<num>> rows, {String? start}) {
    final e = t.openEditor(neu: true)
      ..rows = [for (final r in rows) EditRow(r[0].toDouble(), r[1].toInt())]
      ..startDatum = start;
    final r = t.applyPlan(e);
    if (!r.applied) fehler.add('Plan nicht übernommen: ${r.err}');
  }

  void zu(String iso) {
    jetzt = DateTime.parse(iso);
    t.refresh();
  }

  IntakeResult ein(num mg, {String? tag, String? zeit, bool force = false}) =>
      t.addIntake(mg.toDouble(), t: zeit, k: tag, force: force);
  void zaehle(num n, num st, {bool add = false}) => t.setStock(n.toDouble(), st.toDouble(), add: add);
  StockInfo get si => t.stockInfo()!;
  String? get bis => si.days.isInfinite || si.days <= 0 ? null : addD(t.today, si.days.toInt() - 1);

  void soll(String was, Object? ist, Object? erwartet) {
    final ok = (ist is num && erwartet is num)
        ? (ist.isInfinite || erwartet.isInfinite ? ist == erwartet : (ist - erwartet).abs() < 1e-6)
        : ist == erwartet;
    if (!ok) fehler.add('[${t.today}] $was: erwartet $erwartet, ist $ist');
  }

  /// Vorrat prüfen: Rest, Reichweite (Tage), geschätzte Tage, „reicht bis“.
  void vorrat(String was, {num? rem, num? days, int? gesch, String? bis}) {
    final s = si;
    if (rem != null) soll('$was rem', s.rem, rem);
    if (days != null) soll('$was days', s.days, days);
    if (gesch != null) soll('$was geschaetzt', s.geschaetzt, gesch);
    if (bis != null) soll('$was bis', this.bis, bis);
  }

  void fertig() => expect(fehler, isEmpty, reason: fehler.join('\n'));
}

void main() {
  // ---------------------------------------------------------------------------------------------
  test('S01 Referenz A ohne Halten', () {
    // 500: 2×20=40 →460; 14×15=210 →250; 21×10=210 →40; 7,5: 5 Tage=37,5 →2,5. 2+14+21+5 = 42 Tage.
    // bis 22.11.+41 = 02.01.2027. 0 mg ab 22.11.+100 = 02.03.2027.
    final w = W('2026-11-22T09:00:00Z', ref);
    w.zaehle(50, 10);
    w.vorrat('A', rem: 500, days: 42, gesch: 0, bis: '2027-01-02');
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2027-03-02');
    w.fertig();
  });

  test('S02 Referenz B mit Halten 20 Tage', () {
    // 20 Halte-Tage×20 = 400 →100; danach Stufe 0 noch 2 Tage×20 = 40 →60; 4×15 = 60 →0. 20+2+4 = 26.
    // bis 22.11.+25 = 17.12. Ende 02.03.+20 = 22.03.2027.
    final w = W('2026-11-22T09:00:00Z', ref);
    w.zaehle(50, 10);
    w.t.startHold(20);
    w.vorrat('B', rem: 500, days: 26, bis: '2026-12-17');
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2027-03-22');
    // Reihenfolge andersherum: erst Halten, dann zählen
    final v = W('2026-11-22T09:00:00Z', ref);
    v.t.startHold(20);
    v.zaehle(50, 10);
    v.vorrat('B2', rem: 500, days: 26, bis: '2026-12-17');
    w.fehler.addAll(v.fehler);
    w.fertig();
  });

  test('S03 mehrere Dosisänderungen, Grenzen exakt', () {
    // Plan 12×3, 9×4, 6×5, 3×6, 0. Summe = 36+36+30+18 = 120.
    // 117: 36→81, 36→45, 30→15, 3×5=15→0 ⇒ 3+4+5+5 = 17 Tage, bis 08.12.
    // 114: →78 →42 →12, 3×4 → 0 ⇒ 16 Tage, bis 07.12.  120: ganzer Plan gedeckt ⇒ ∞.
    // Ende: 22.11.+18 = 10.12.
    final w = W('2026-11-22T09:00:00Z', [
      [12, 3],
      [9, 4],
      [6, 5],
      [3, 6],
      [0, 1]
    ]);
    w.zaehle(39, 3);
    w.vorrat('117', rem: 117, days: 17, bis: '2026-12-08');
    w.zaehle(38, 3);
    w.vorrat('114', rem: 114, days: 16, bis: '2026-12-07');
    w.zaehle(40, 3);
    w.vorrat('120', rem: 120, days: double.infinity);
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2026-12-10');
    w.fertig();
  });

  test('S04 offene Tage ohne Eintrag', () {
    // Plan 10×5, 8×5, 6×5, 0. Zählen 22.11. 100. Bis 25.11. nichts eingetragen:
    // offen 22,23,24 je 10 ⇒ rem 70, geschätzt 3. Heute 25.11. = Stufe 0 Tag 3:
    // heute 10 →60, 26.11. 10 →50, 27.11.–01.12. 5×8 →10, 02.12. 6 →4, dann 6>4. ⇒ 8 Tage, bis 02.12.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 5],
      [8, 5],
      [6, 5],
      [0, 1]
    ]);
    w.zaehle(10, 10);
    w.zu('2026-11-25T09:00:00Z');
    w.vorrat('Lücke', rem: 70, days: 8, gesch: 3, bis: '2026-12-02');
    w.fertig();
  });

  test('S05 Stufenwechsel mitten in Lücke, Nachtragen mit/ohne Uhrzeit', () {
    // Plan 10×5, 8×5, 6×5, 0. 22.11. 09:00 zählen 100, 09:01 10 genommen.
    // 29.11.: offen 23–26 (Stufe 0, 4×10 = 40) und 27, 28 (Stufe 1, 2×8 = 16) ⇒ 56; rem 100−10−56 = 34, geschätzt 6.
    // Heute 29.11. = Stufe 1 Tag 2: 8 →26, 30.11./01.12. 16 →10, 02.12. (Stufe 2) 6 →4 ⇒ 4 Tage, bis 02.12.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 5],
      [8, 5],
      [6, 5],
      [0, 1]
    ]);
    w.zaehle(10, 10);
    w.zu('2026-11-22T09:01:00Z');
    w.ein(10);
    w.zu('2026-11-29T09:00:00Z');
    w.vorrat('vor Nachtrag', rem: 34, days: 4, gesch: 6, bis: '2026-12-02');
    // 23.11. mit 10 um 08:00 nachtragen: ersetzt Schätzung 10 durch 10 ⇒ rem 34, geschätzt 5.
    w.soll('Nachtrag 23.', w.ein(10, tag: '2026-11-23', zeit: '08:00'), IntakeResult.added);
    w.vorrat('Nachtrag 23.', rem: 34, days: 4, gesch: 5);
    // 27.11. (Stufe 1, Plan 8) mit 6 ohne Uhrzeit ⇒ +2 ⇒ rem 36, geschätzt 4.
    // 36−8 = 28; 30.11./01.12. 16 →12; 02.12./03.12. je 6 →0 ⇒ 5 Tage, bis 03.12.
    w.ein(6, tag: '2026-11-27');
    w.vorrat('Nachtrag 27.', rem: 36, days: 5, gesch: 4, bis: '2026-12-03');
    w.fertig();
  });

  test('S06 „weiß ich nicht mehr“ zählt wie offen', () {
    // Plan 10×30, 5×10, 0. 22.11. zählen 300, 10 genommen. 03.12.: offen 23.11.–02.12. = 10 Tage×10 ⇒ rem 190.
    // Heute 03.12. = Stufe 0 Tag 11, Stufe 0 bis 21.12.: noch 19 Tage×10 = 190 → genau 0 ⇒ 19, bis 21.12.
    // markUnk: Tage > 7 zurück (23., 24., 25.11.) ⇒ ändert am Vorrat nichts.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 30],
      [5, 10],
      [0, 1]
    ]);
    w.zaehle(30, 10);
    w.zu('2026-11-22T09:01:00Z');
    w.ein(10);
    w.zu('2026-12-03T09:00:00Z');
    w.vorrat('vor markUnk', rem: 190, days: 19, gesch: 10, bis: '2026-12-21');
    w.t.markUnk();
    w.soll('unk', w.t.st.unk.length, 3);
    w.vorrat('nach markUnk', rem: 190, days: 19, gesch: 10, bis: '2026-12-21');
    w.fertig();
  });

  test('S07 Nachtrag am Zähltag ohne Uhrzeit, gezählt um 08:00 ⇒ abgezogen', () {
    // Plan 10×10, 5×10, 0. 22.11. 10 genommen. 23.11. 08:00 zählen 50. 24.11.: 23. offen ⇒ rem 40, geschätzt 1.
    // Nachtrag 23. 10 ohne Uhrzeit = 12:00 > 08:00 ⇒ abgezogen ⇒ rem 40, geschätzt 0.
    // Heute 24.11. 10 →30, 25./26./27. →0 ⇒ 4 Tage, bis 27.11.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 10],
      [5, 10],
      [0, 1]
    ]);
    w.ein(10);
    w.zu('2026-11-23T08:00:00Z');
    w.zaehle(5, 10);
    w.zu('2026-11-24T09:00:00Z');
    w.vorrat('vor', rem: 40, days: 4, gesch: 1, bis: '2026-11-27');
    w.ein(10, tag: '2026-11-23');
    w.vorrat('nach', rem: 40, days: 4, gesch: 0, bis: '2026-11-27');
    w.fertig();
  });

  test('S08 Nachtrag am Zähltag, gezählt um 14:00 ⇒ 12:00 liegt davor', () {
    // Wie S07, aber gezählt um 14:00. 24.11.: rem 40, geschätzt 1.
    // Nachtrag 23. 10 ohne Uhrzeit (12:00 < 14:00) ⇒ nicht abgezogen, Schätzung entfällt ⇒ rem 50, geschätzt 0.
    // 50−10 = 40 → 4 weitere ⇒ 5 Tage, bis 28.11.
    // Nachtrag 23. 2,5 um 15:00 (nach dem Zählen) ⇒ rem 47,5; 37,5 → 3 weitere ⇒ 4 Tage, bis 27.11.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 10],
      [5, 10],
      [0, 1]
    ]);
    w.ein(10);
    w.zu('2026-11-23T14:00:00Z');
    w.zaehle(5, 10);
    w.zu('2026-11-24T09:00:00Z');
    w.vorrat('vor', rem: 40, gesch: 1);
    w.ein(10, tag: '2026-11-23');
    w.vorrat('12:00', rem: 50, days: 5, gesch: 0, bis: '2026-11-28');
    w.ein(2.5, tag: '2026-11-23', zeit: '15:00');
    w.vorrat('15:00', rem: 47.5, days: 4, gesch: 0, bis: '2026-11-27');
    w.fertig();
  });

  test('S09 Zusatzdosen und Löschen', () {
    // Plan 10×10, 5×10, 0. Zählen 100. 09:05 5, 13:00 5, 20:00 2,5 (erst Innehalten, dann force).
    // rem 87,5; heute über Plan ⇒ kein Rest. 1 + 8×10 (→7,5) ⇒ 9 Tage, bis 30.11.
    // Löschen 2,5 ⇒ rem 90 ⇒ 1 + 9×10 (Stufe 0 bis 01.12.) → 0, 02.12. 5 > 0 ⇒ 10 Tage, bis 01.12.
    // Löschen 5 ⇒ rem 95, heute 5 offen →90 ⇒ 10 Tage, bis 01.12.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 10],
      [5, 10],
      [0, 1]
    ]);
    w.zaehle(10, 10);
    w.zu('2026-11-22T09:05:00Z');
    w.ein(5);
    w.zu('2026-11-22T13:00:00Z');
    w.ein(5);
    w.zu('2026-11-22T20:00:00Z');
    w.soll('Innehalten', w.ein(2.5), IntakeResult.needsPause);
    w.vorrat('nach Innehalten', rem: 90);
    w.soll('force', w.ein(2.5, force: true), IntakeResult.added);
    w.vorrat('3 Einnahmen', rem: 87.5, days: 9, bis: '2026-11-30');
    w.t.delIntake(2);
    w.vorrat('2,5 gelöscht', rem: 90, days: 10, bis: '2026-12-01');
    w.t.delIntake(0);
    w.vorrat('5 gelöscht', rem: 95, days: 10, bis: '2026-12-01');
    w.fertig();
  });

  test('S10 mehrfach aufstocken am selben Tag, dann neu zählen', () {
    // Plan 5×20, 0. 09:00 zählen 15, 09:30 5 genommen, 10:00 +10, 11:00 +10 ⇒ 35−5 = 30.
    // heute erledigt ⇒ 1 + 6 ⇒ 7 Tage, bis 28.11.
    // 12:00 neu zählen 20 (Einnahme 09:30 liegt davor) ⇒ rem 20 ⇒ 1 + 4 = 5, bis 26.11.
    // 13:00 +5 ⇒ 25 ⇒ 6, bis 27.11. Nächster Tag ohne Eintrag: 25 − 5 = 20 → 4 ⇒ 5, bis 27.11.
    final w = W('2026-11-22T09:00:00Z', [
      [5, 20],
      [0, 1]
    ]);
    w.zaehle(3, 5);
    w.zu('2026-11-22T09:30:00Z');
    w.ein(5);
    w.zu('2026-11-22T10:00:00Z');
    w.zaehle(2, 5, add: true);
    w.zu('2026-11-22T11:00:00Z');
    w.zaehle(1, 10, add: true);
    w.vorrat('2× aufgestockt', rem: 30, days: 7, bis: '2026-11-28');
    w.zu('2026-11-22T12:00:00Z');
    w.zaehle(4, 5);
    w.vorrat('neu gezählt', rem: 20, days: 5, bis: '2026-11-26');
    w.zu('2026-11-22T13:00:00Z');
    w.zaehle(1, 5, add: true);
    w.vorrat('+5', rem: 25, days: 6, bis: '2026-11-27');
    w.zu('2026-11-23T09:00:00Z');
    w.vorrat('Folgetag', rem: 25, days: 5, gesch: 0, bis: '2026-11-27');
    w.fertig();
  });

  test('S11 fast leer, dann aufstocken', () {
    // Plan 10×10, 5×10, 0. Zählen 10, 10 genommen ⇒ rem 0, heute erledigt ⇒ 1 Tag (bis heute).
    // 23.11.: rem 0, heute 10 offen ⇒ 0. +20 (Zählzeitpunkt bleibt) ⇒ rem 20 ⇒ 2 Tage, bis 24.11.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 10],
      [5, 10],
      [0, 1]
    ]);
    w.zaehle(1, 10);
    w.zu('2026-11-22T09:01:00Z');
    w.ein(10);
    w.vorrat('leer, heute erledigt', rem: 0, days: 1, bis: '2026-11-22');
    w.zu('2026-11-23T09:00:00Z');
    w.vorrat('leer', rem: 0, days: 0, gesch: 0);
    w.zaehle(2, 10, add: true);
    w.vorrat('aufgestockt', rem: 20, days: 2, bis: '2026-11-24');
    w.fertig();
  });

  test('S12 Vorrat kleiner als Tagesdosis, Grenzen', () {
    // Plan 10×10, 5×10, 0. 5 < 10 ⇒ 0. 5 genommen ⇒ rem 0, Rest heute 5 ⇒ 0. +5 ⇒ Rest heute 5 = 5 ⇒ 1.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 10],
      [5, 10],
      [0, 1]
    ]);
    w.zaehle(1, 5);
    w.vorrat('5 mg', rem: 5, days: 0);
    w.soll('reichweite(9,999)', w.t.reichweite(9.999), 0);
    w.soll('reichweite(10)', w.t.reichweite(10), 1);
    w.soll('reichweite(19,999)', w.t.reichweite(19.999), 1);
    w.soll('reichweite(20)', w.t.reichweite(20), 2);
    w.zu('2026-11-22T09:01:00Z');
    w.ein(5);
    w.vorrat('5 genommen', rem: 0, days: 0);
    w.zaehle(1, 5, add: true);
    w.vorrat('+5', rem: 5, days: 1, bis: '2026-11-22');
    // Mit 5 genommen ist heute noch 5 offen.
    w.soll('reichweite(4,999)', w.t.reichweite(4.999), 0);
    w.soll('reichweite(14,999)', w.t.reichweite(14.999), 1);
    w.soll('reichweite(15)', w.t.reichweite(15), 2);
    w.fertig();
  });

  test('S13 sehr großer Vorrat und Plansumme exakt', () {
    // Referenzplan Summe 40+210+210+157,5+105+52,5 = 775 ⇒ 775 ⇒ ∞; 772,5 ⇒ letzter 2,5-Tag fehlt:
    // 2+14+21+21+21+20 = 99 Tage, bis 22.11.+98 = 28.02.2027.
    final w = W('2026-11-22T09:00:00Z', ref);
    w.zaehle(1000, 100);
    w.vorrat('100 g', days: double.infinity);
    w.zaehle(310, 2.5);
    w.vorrat('775', rem: 775, days: double.infinity);
    w.zaehle(309, 2.5);
    w.vorrat('772,5', rem: 772.5, days: 99, bis: '2027-02-28');
    w.fertig();
  });

  test('S14 Halten ohne Enddatum, dann vorzeitig weiter', () {
    // Referenz. Halten ohne Ende in Stufe 0 (20 mg): 500/20 = 25 Tage, bis 16.12.
    // 4 Tage je 20 genommen (22.–25.) ⇒ 25.11.: rem 420, heute erledigt ⇒ 1 + 21 = 22, bis 16.12.
    // 26.11.: (noch Halten) 420/20 = 21, bis 16.12. stopHold ⇒ Plan um 4 Tage verschoben, Stufe 0 läuft ab Tag 0:
    // 26./27. 40 →380, 14×15 →170, 17×10 →0 ⇒ 2+14+17 = 33, bis 28.12. Ende 02.03.+4 = 06.03.2027.
    final w = W('2026-11-22T08:00:00Z', ref);
    w.zaehle(50, 10);
    w.t.startHold(null);
    w.vorrat('Start', rem: 500, days: 25, bis: '2026-12-16');
    for (final d in ['22', '23', '24', '25']) {
      w.zu('2026-11-${d}T09:00:00Z');
      w.ein(20);
    }
    w.vorrat('25.11.', rem: 420, days: 22, gesch: 0, bis: '2026-12-16');
    w.zu('2026-11-26T09:00:00Z');
    w.vorrat('26.11. gehalten', rem: 420, days: 21, bis: '2026-12-16');
    w.t.stopHold();
    w.vorrat('weiter', rem: 420, days: 33, gesch: 0, bis: '2026-12-28');
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2027-03-06');
    w.fertig();
  });

  test('S15 Halten mit Ende mitten in der Stufe, über Monatsgrenze, konsistent über die Zeit', () {
    // Plan 10×10, 8×10, 6×10, 0. 22.–25. je 10 (Stufentag 0–3). 26.11. 08:00 zählen 200, Halten 7 (bis 03.12.).
    // 26.11.–02.12. 7×10 →130, ab 03.12. Stufe 0 Tag 4–9: 6×10 →70, ab 09.12. 8×8 →6 ⇒ 7+6+8 = 21, bis 16.12.
    // Ende: 22.11.+30 = 22.12. +7 = 29.12.
    // Nach 7 Tagen planmäßig (03.12.): rem 130, Halten vorbei ⇒ 6+8 = 14, bis 16.12. (gleiches Datum).
    final w = W('2026-11-22T09:00:00Z', [
      [10, 10],
      [8, 10],
      [6, 10],
      [0, 1]
    ]);
    for (final d in ['22', '23', '24', '25']) {
      w.zu('2026-11-${d}T09:00:00Z');
      w.ein(10);
    }
    w.zu('2026-11-26T08:00:00Z');
    w.zaehle(20, 10);
    w.t.startHold(7);
    w.vorrat('Haltebeginn', rem: 200, days: 21, gesch: 0, bis: '2026-12-16');
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2026-12-29');
    for (final d in [
      '2026-11-26',
      '2026-11-27',
      '2026-11-28',
      '2026-11-29',
      '2026-11-30',
      '2026-12-01',
      '2026-12-02'
    ]) {
      w.zu('${d}T09:00:00Z');
      w.ein(10);
    }
    w.vorrat('02.12.', rem: 130, days: 15, bis: '2026-12-16');
    w.zu('2026-12-03T09:00:00Z');
    w.soll('Halten beendet', w.t.st.hold, false);
    w.vorrat('03.12.', rem: 130, days: 14, gesch: 0, bis: '2026-12-16');
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2026-12-29');
    w.fertig();
  });

  test('S16 Halten kurz und vorzeitig beendet, Jahresende; Halten gleich wieder beendet', () {
    // Referenz. 22./23. 20, 24.11. (Stufe 1 Tag 0) 15, 25.11. Halten 10, 25./26. je 15, 27.11. stopHold (2 Tage verschoben).
    // rem 500−85 = 415. 27.11. = Stufe 1 Tag 1: 13×15 = 195 →220, 21×10 →10, 1×7,5 →2,5 ⇒ 35, bis 31.12.2026.
    // Ende 02.03.+2 = 04.03.2027.
    final w = W('2026-11-22T08:00:00Z', ref);
    w.zaehle(50, 10);
    w.zu('2026-11-22T09:00:00Z');
    w.ein(20);
    w.zu('2026-11-23T09:00:00Z');
    w.ein(20);
    w.zu('2026-11-24T09:00:00Z');
    w.ein(15);
    w.zu('2026-11-25T08:30:00Z');
    w.t.startHold(10);
    w.zu('2026-11-25T09:00:00Z');
    w.ein(15);
    w.zu('2026-11-26T09:00:00Z');
    w.ein(15);
    w.zu('2026-11-27T09:00:00Z');
    w.t.stopHold();
    w.vorrat('nach stopHold', rem: 415, days: 35, gesch: 0, bis: '2026-12-31');
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2027-03-04');
    // Halten am selben Tag an und aus ⇒ wie Referenz A.
    final v = W('2026-11-22T09:00:00Z', ref);
    v.zaehle(50, 10);
    v.t.startHold(10);
    v.t.stopHold();
    v.vorrat('an/aus', rem: 500, days: 42, bis: '2027-01-02');
    v.soll('Ende', v.t.voraussichtlichesEnde(), '2027-03-02');
    w.fehler.addAll(v.fehler);
    w.fertig();
  });

  test('S17 Startdatum in der Zukunft', () {
    // Referenz, Start 25.11., heute 22.11.: Vorlauf 22.–24. = 3 + 42 = 45, bis 22.11.+44 = 05.01.2027.
    // Einnahme vor Start: ignoriert. Ende 25.11.+100 = 05.03.2027.
    // 23.11.: 2 + 42 = 44, bis 05.01. 27.11. ohne Einträge: offen 25./26. je 20 ⇒ rem 460, geschätzt 2;
    // heute Stufe 1 Tag 0: 14×15 →250, 21×10 →40, 5×7,5 →2,5 ⇒ 40, bis 05.01.2027.
    final w = W('2026-11-22T09:00:00Z', ref, start: '2026-11-25');
    w.zaehle(50, 10);
    w.soll('Einnahme vor Start', w.ein(10), IntakeResult.ignored);
    w.vorrat('22.11.', rem: 500, days: 45, gesch: 0, bis: '2027-01-05');
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2027-03-05');
    w.zu('2026-11-23T09:00:00Z');
    w.soll('Nachtrag vor Start', w.ein(10, tag: '2026-11-22'), IntakeResult.ignored);
    w.vorrat('23.11.', rem: 500, days: 44, gesch: 0, bis: '2027-01-05');
    w.zu('2026-11-27T09:00:00Z');
    w.vorrat('27.11.', rem: 460, days: 40, gesch: 2, bis: '2027-01-05');
    w.fertig();
  });

  test('S18 Startdatum in der Zukunft mit kleinem Vorrat, Monatsgrenze', () {
    // Start 25.11.: 30 mg ⇒ Starttag 20 →10 ⇒ 1 ⇒ 3+1 = 4, bis 25.11.; 10 mg ⇒ 3+0 = 3, bis 24.11.; 40 ⇒ 3+2 = 5.
    final w = W('2026-11-22T09:00:00Z', ref, start: '2026-11-25');
    w.zaehle(3, 10);
    w.vorrat('30', days: 4, bis: '2026-11-25');
    w.zaehle(1, 10);
    w.vorrat('10', days: 3, bis: '2026-11-24');
    w.zaehle(4, 10);
    w.vorrat('40', days: 5, bis: '2026-11-26');
    // Start 01.12.: Vorlauf 22.–30.11. = 9; 40 mg ⇒ 2 ⇒ 11, bis 02.12.
    final v = W('2026-11-22T09:00:00Z', ref, start: '2026-12-01');
    v.zaehle(4, 10);
    v.vorrat('Start 01.12.', rem: 40, days: 11, bis: '2026-12-02');
    w.fehler.addAll(v.fehler);
    w.fertig();
  });

  test('S19 Plan erreicht 0 mg', () {
    // Plan 5×3, 2,5×3, 0. Summe 22,5 ⇒ 22,5 ⇒ ∞. 20 ⇒ 15 →5, 2×2,5 →0 ⇒ 5 Tage, bis 26.11.
    // Mit 22,5 planmäßig bis 27.11.: rem 0, heute erledigt, morgen 0 mg ⇒ ∞. 28.11. (0-mg-Stufe): ∞.
    final w = W('2026-11-22T08:00:00Z', [
      [5, 3],
      [2.5, 3],
      [0, 1]
    ]);
    w.zaehle(8, 2.5);
    w.vorrat('20', rem: 20, days: 5, bis: '2026-11-26');
    w.zaehle(9, 2.5);
    w.vorrat('22,5', rem: 22.5, days: double.infinity);
    final dosen = {'22': 5, '23': 5, '24': 5, '25': 2.5, '26': 2.5, '27': 2.5};
    dosen.forEach((d, mg) {
      w.zu('2026-11-${d}T09:00:00Z');
      w.ein(mg);
    });
    w.vorrat('27.11.', rem: 0, days: double.infinity, gesch: 0);
    w.zu('2026-11-28T09:00:00Z');
    w.vorrat('28.11.', rem: 0, days: double.infinity, gesch: 0);
    w.fertig();
  });

  test('S20 Teildosen 7,5 und 2,5', () {
    // Plan 7,5×4, 2,5×4, 0. 17,5 ⇒ 7,5 →10, 7,5 →2,5 ⇒ 2, bis 23.11.
    // 5 + 2,5 genommen ⇒ rem 10, heute erledigt ⇒ 1 + 1 ⇒ 2, bis 23.11.
    // +20 ⇒ 30: 3×7,5 →7,5, 3×2,5 →0 ⇒ 1+3+3 = 7, bis 28.11. +2,5 ⇒ 32,5 = Rest des Plans ⇒ ∞.
    final w = W('2026-11-22T09:00:00Z', [
      [7.5, 4],
      [2.5, 4],
      [0, 1]
    ]);
    w.zaehle(7, 2.5);
    w.vorrat('17,5', rem: 17.5, days: 2, bis: '2026-11-23');
    w.zu('2026-11-22T09:01:00Z');
    w.ein(5);
    w.zu('2026-11-22T15:00:00Z');
    w.ein(2.5);
    w.vorrat('genommen', rem: 10, days: 2, bis: '2026-11-23');
    w.zaehle(8, 2.5, add: true);
    w.vorrat('+20', rem: 30, days: 7, bis: '2026-11-28');
    w.zaehle(1, 2.5, add: true);
    w.vorrat('+2,5', rem: 32.5, days: double.infinity);
    w.fertig();
  });

  test('S21 Reihenfolge-Unabhängigkeit: gleiche Endlage ⇒ gleiche Zahlen', () {
    // Plan 10×10, 5×20, 0. Endlage 23.11. 12:00: 150 mg gesamt, 22. und 23. je 10 genommen ⇒ rem 130.
    // 23.11. Tag 1, erledigt ⇒ 1 + 8×10 →50 + 10×5 →0 ⇒ 19, bis 11.12. Wochen-Ø 10 (n 2).
    const p = [
      [10, 10],
      [5, 20],
      [0, 1]
    ];
    // A: zählen, nehmen, nehmen, aufstocken
    final a = W('2026-11-22T08:00:00Z', p);
    a.zaehle(10, 10);
    a.zu('2026-11-22T09:00:00Z');
    a.ein(10);
    a.zu('2026-11-23T09:00:00Z');
    a.ein(10);
    a.zu('2026-11-23T10:00:00Z');
    a.zaehle(5, 10, add: true);
    // B: gleich aufstocken
    final b = W('2026-11-22T08:00:00Z', p);
    b.zaehle(10, 10);
    b.zu('2026-11-22T08:30:00Z');
    b.zaehle(5, 10, add: true);
    b.zu('2026-11-22T09:00:00Z');
    b.ein(10);
    b.zu('2026-11-23T09:00:00Z');
    b.ein(10);
    // C: 22. vergessen, am 23. nachgetragen
    final c = W('2026-11-22T08:00:00Z', p);
    c.zaehle(10, 10);
    c.zu('2026-11-23T09:00:00Z');
    c.ein(10, tag: '2026-11-22', zeit: '09:00');
    c.ein(10);
    c.zu('2026-11-23T10:00:00Z');
    c.zaehle(5, 10, add: true);
    // D: gleich 150 gezählt
    final d = W('2026-11-22T08:00:00Z', p);
    d.zaehle(15, 10);
    d.zu('2026-11-22T09:00:00Z');
    d.ein(10);
    d.zu('2026-11-23T09:00:00Z');
    d.ein(10);
    final alle = {'A': a, 'B': b, 'C': c, 'D': d};
    final f = <String>[];
    alle.forEach((n, w) {
      w.zu('2026-11-23T12:00:00Z');
      w.vorrat(n, rem: 130, days: 19, gesch: 0, bis: '2026-12-11');
      w.soll('$n Wochen-Ø', w.t.weekAvgs()[0].avg, 10);
      w.soll('$n Wochen-n', w.t.weekAvgs()[0].n, 2);
      w.soll('$n Stufen-Ø', w.t.stufenSchnitt().avg, 10);
      // Sichern und wieder laden ⇒ gleich
      final x = Taper(clock: () => w.jetzt);
      x.importJson(w.t.exportJson());
      final s2 = x.stockInfo()!;
      w.soll('$n Import rem', s2.rem, 130);
      w.soll('$n Import days', s2.days, 19);
      f.addAll(w.fehler);
    });
    expect(f, isEmpty, reason: f.join('\n'));
  });

  test('S22 Rest genau gleich Tagesdosis, Gleitkomma', () {
    // Plan 0,7×10, 0,35×10, 0. 1,4 ⇒ 0,7 →0,7 →0 ⇒ 2, bis 23.11.
    // Einnahmen 0,1 + 0,2 + 0,4 = 0,7 ⇒ rem 0,7, heute erledigt ⇒ 1 + 1 ⇒ 2, bis 23.11.
    final w = W('2026-11-22T09:00:00Z', [
      [0.7, 10],
      [0.35, 10],
      [0, 1]
    ]);
    w.zaehle(2, 0.7);
    w.vorrat('1,4', rem: 1.4, days: 2, bis: '2026-11-23');
    w.zu('2026-11-22T09:01:00Z');
    w.ein(0.1);
    w.zu('2026-11-22T09:02:00Z');
    w.ein(0.2);
    w.zu('2026-11-22T09:03:00Z');
    w.ein(0.4);
    w.vorrat('0,7 genommen', rem: 0.7, days: 2, bis: '2026-11-23');
    // Ganzzahlig: 10 = Tagesdosis 10 ⇒ 1, 9,99 ⇒ 0.
    final v = W('2026-11-22T09:00:00Z', [
      [10, 10],
      [0, 1]
    ]);
    v.zaehle(1, 10);
    v.vorrat('10', days: 1, bis: '2026-11-22');
    v.zaehle(1, 9.99);
    v.vorrat('9,99', days: 0);
    w.fehler.addAll(v.fehler);
    w.fertig();
  });

  test('S23 Jahresgrenze mit Lücke und Schaltjahr', () {
    // Plan 4×5, 2×5, 0 ab 29.12.2026. 28 ⇒ 5×4 →8, 4×2 →0 ⇒ 9, bis 06.01.2027. Ende 29.12.+10 = 08.01.2027.
    // 02.01.2027 ohne Einträge: offen 29.,30.,31.12.,01.01. 4×4 ⇒ rem 12, geschätzt 4; heute Tag 4: 4 →8, 4×2 ⇒ 5, bis 06.01.
    final w = W('2026-12-29T09:00:00Z', [
      [4, 5],
      [2, 5],
      [0, 1]
    ]);
    w.zaehle(7, 4);
    w.vorrat('29.12.', rem: 28, days: 9, bis: '2027-01-06');
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2027-01-08');
    w.zu('2027-01-02T09:00:00Z');
    w.vorrat('02.01.', rem: 12, days: 5, gesch: 4, bis: '2027-01-06');
    // Schaltjahr: ab 26.02.2028 Plan 6×3, 3×4, 0; 27 ⇒ 18 →9, 3×3 →0 ⇒ 6, bis 02.03.2028. Ende 26.02.+7 = 04.03.2028.
    final v = W('2028-02-26T09:00:00Z', [
      [6, 3],
      [3, 4],
      [0, 1]
    ]);
    v.zaehle(9, 3);
    v.vorrat('Schaltjahr', rem: 27, days: 6, bis: '2028-03-02');
    v.soll('Ende', v.t.voraussichtlichesEnde(), '2028-03-04');
    w.fehler.addAll(v.fehler);
    w.fertig();
  });

  test('S24 wipe() + neuer Plan = wie frisch', () {
    // Unordentlicher Zustand am 22./23.11., dann am 24.11. alles löschen und Referenz neu anlegen.
    // Wie frisch am 24.11.: 42 Tage, bis 04.01.2027, Ende 24.11.+100 = 04.03.2027.
    // 26.11. ohne Einträge: offen 24./25. je 20 ⇒ rem 460, geschätzt 2; heute Stufe 1 Tag 0 ⇒ 14+21+5 = 40, bis 04.01.2027.
    final w = W('2026-11-22T08:00:00Z', [
      [10, 3],
      [5, 3],
      [0, 1]
    ]);
    w.zaehle(7, 10);
    w.zu('2026-11-22T09:00:00Z');
    w.ein(12, force: true);
    w.t.startHold(5);
    w.zu('2026-11-23T09:00:00Z');
    w.ein(3);
    w.zu('2026-11-24T09:00:00Z');
    w.t.wipe();
    w.soll('wipe', w.t.s, null);
    w.neuerPlan(ref);
    w.zaehle(50, 10);
    final f = W('2026-11-24T09:00:00Z', ref);
    f.zaehle(50, 10);
    for (final x in [w, f]) {
      x.vorrat('24.11.', rem: 500, days: 42, gesch: 0, bis: '2027-01-04');
      x.soll('Ende', x.t.voraussichtlichesEnde(), '2027-03-04');
      x.soll('Wochen-n', x.t.weekAvgs()[0].n, 0);
      x.soll('Stufen-Ø', x.t.stufenSchnitt().avg, null);
      x.soll('Halten', x.t.st.hold, false);
      x.zu('2026-11-26T09:00:00Z');
      x.vorrat('26.11.', rem: 460, days: 40, gesch: 2, bis: '2027-01-04');
    }
    w.fehler.addAll(f.fehler);
    w.fertig();
  });

  test('S25 Wochen-Ø und Live-Ø (heute erst bei komplett/über Plan, Lücken nie 0)', () {
    // Plan 10×14, 5×14, 0. 22.: 15, 23.: 12, 24.: –, 25.: 8, 26.: 5 (angefangen).
    // 26.11.: Ø (15+12+8)/3 = 11,667, n 3. +5 ⇒ 10 = Plan ⇒ (15+12+8+10)/4 = 11,25, n 4. +1 ⇒ 11 ⇒ 46/4 = 11,5.
    // 27.: –, 28.: 9. 29.11. (nichts): Woche 23.–29. ⇒ (12+8+11+9)/4 = 10, n 4; Stufe ⇒ (15+12+8+11+9)/5 = 11, n 5.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 14],
      [5, 14],
      [0, 1]
    ]);
    w.ein(15, force: true);
    w.zu('2026-11-23T09:00:00Z');
    w.ein(12, force: true);
    w.zu('2026-11-25T09:00:00Z');
    w.ein(8);
    w.zu('2026-11-26T09:00:00Z');
    w.ein(5);
    w.soll('Woche angefangen', w.t.weekAvgs()[0].avg, 35 / 3);
    w.soll('Woche angefangen n', w.t.weekAvgs()[0].n, 3);
    w.soll('Stufe angefangen', w.t.stufenSchnitt().avg, 35 / 3);
    w.soll('Stufe angefangen n', w.t.stufenSchnitt().n, 3);
    w.zu('2026-11-26T10:00:00Z');
    w.ein(5);
    w.soll('Woche komplett', w.t.weekAvgs()[0].avg, 11.25);
    w.soll('Stufe komplett', w.t.stufenSchnitt().avg, 11.25);
    w.zu('2026-11-26T11:00:00Z');
    w.ein(1, force: true);
    w.soll('Woche über Plan', w.t.weekAvgs()[0].avg, 11.5);
    w.soll('Woche über Plan n', w.t.weekAvgs()[0].n, 4);
    w.zu('2026-11-28T09:00:00Z');
    w.ein(9);
    w.zu('2026-11-29T09:00:00Z');
    w.soll('Woche 29.', w.t.weekAvgs()[0].avg, 10);
    w.soll('Woche 29. n', w.t.weekAvgs()[0].n, 4);
    w.soll('Stufe 29.', w.t.stufenSchnitt().avg, 11);
    w.soll('Stufe 29. n', w.t.stufenSchnitt().n, 5);
    // Stufenwechsel: Plan 10×3, 5×3, 0. 22.–24. je 10, 25.11. (Stufe 1) 4 angefangen ⇒ Stufe-Ø leer, Woche 10 (n 3).
    // 26.11.: 25. zählt ⇒ Stufe 4 (n 1), Woche (30+4)/4 = 8,5.
    final v = W('2026-11-22T09:00:00Z', [
      [10, 3],
      [5, 3],
      [0, 1]
    ]);
    for (final d in ['22', '23', '24']) {
      v.zu('2026-11-${d}T09:00:00Z');
      v.ein(10);
    }
    v.zu('2026-11-25T09:00:00Z');
    v.ein(4);
    v.soll('Stufe 1 angefangen', v.t.stufenSchnitt().avg, null);
    v.soll('Stufe 1 angefangen n', v.t.stufenSchnitt().n, 0);
    v.soll('Woche', v.t.weekAvgs()[0].avg, 10);
    v.zu('2026-11-26T09:00:00Z');
    v.soll('Stufe 1 26.', v.t.stufenSchnitt().avg, 4);
    v.soll('Stufe 1 26. n', v.t.stufenSchnitt().n, 1);
    v.soll('Woche 26.', v.t.weekAvgs()[0].avg, 8.5);
    w.fehler.addAll(v.fehler);
    w.fertig();
  });

  test('S26 Stufenwechsel in der Lücke, heute angefangen', () {
    // Plan 10×3, 6×10, 3×10, 0. 22.11. 08:00 zählen 100, 09:00 10.
    // 26.11.: offen 23./24. (10) und 25. (Stufe 1: 6) ⇒ 26 ⇒ rem 64, geschätzt 3. Heute Stufe 1 Tag 1:
    // 6 →58, 27.11.–04.12. 8×6 →10, 3×3 →1 ⇒ 1+8+3 = 12, bis 07.12.
    // Heute 3 genommen ⇒ rem 61, Rest heute 6−3 = 3 →58 ⇒ wieder 12, bis 07.12.
    // Lücke nachgetragen (23./24. 10, 25. 6) ⇒ rem 61, geschätzt 0 ⇒ 12, bis 07.12.
    final w = W('2026-11-22T08:00:00Z', [
      [10, 3],
      [6, 10],
      [3, 10],
      [0, 1]
    ]);
    w.zaehle(10, 10);
    w.zu('2026-11-22T09:00:00Z');
    w.ein(10);
    w.zu('2026-11-26T09:00:00Z');
    w.vorrat('Lücke', rem: 64, days: 12, gesch: 3, bis: '2026-12-07');
    w.zu('2026-11-26T09:01:00Z');
    w.ein(3);
    w.vorrat('heute 3', rem: 61, days: 12, gesch: 3, bis: '2026-12-07');
    w.ein(10, tag: '2026-11-23', zeit: '09:00');
    w.ein(10, tag: '2026-11-24', zeit: '09:00');
    w.ein(6, tag: '2026-11-25', zeit: '09:00');
    w.vorrat('nachgetragen', rem: 61, days: 12, gesch: 0, bis: '2026-12-07');
    // Diagnose: Stufe nach dem Nachtragen und Plan im heutigen Eintrag
    w.soll('Stufe nach Nachtrag', w.t.st.stage, 1);
    w.soll('Plan im heutigen Eintrag', w.t.st.log['2026-11-26']?.plan, 6);
    // Heute geplant 6, 3 genommen: weitere 3,5 wären mehr als geplant ⇒ „Kurz innehalten“.
    w.soll('Innehalten bei 6,5 > 6', w.ein(3.5), IntakeResult.needsPause);
    // Gleiche Endlage, andere Reihenfolge: erst nachtragen, dann heute 3 ⇒ muss dieselben Zahlen geben (12).
    final v = W('2026-11-22T08:00:00Z', [
      [10, 3],
      [6, 10],
      [3, 10],
      [0, 1]
    ]);
    v.zaehle(10, 10);
    v.zu('2026-11-22T09:00:00Z');
    v.ein(10);
    v.zu('2026-11-26T09:00:00Z');
    v.ein(10, tag: '2026-11-23', zeit: '09:00');
    v.ein(10, tag: '2026-11-24', zeit: '09:00');
    v.ein(6, tag: '2026-11-25', zeit: '09:00');
    v.zu('2026-11-26T09:01:00Z');
    v.ein(3);
    v.vorrat('andere Reihenfolge', rem: 61, days: 12, gesch: 0, bis: '2026-12-07');
    w.fehler.addAll(v.fehler);
    w.fertig();
  });

  test('S27 Zähltag: Einnahme vor/nach dem Zählen, Nachtrag heute mit Uhrzeit', () {
    // Plan 10×10, 5×10, 0. 08:00 5, 12:00 zählen 50, 18:00 5 ⇒ rem 45; heute erledigt ⇒ 1 + 4 = 5, bis 26.11.
    // 20:00 Nachtrag 2 um 11:00 (vor dem Zählen) ⇒ rem 45. 1 um 13:00 (danach) ⇒ rem 44 ⇒ 5, bis 26.11.
    // 23.11.: rem 44, geschätzt 0, heute 10 →34 → 3 ⇒ 4, bis 26.11.
    final w = W('2026-11-22T08:00:00Z', [
      [10, 10],
      [5, 10],
      [0, 1]
    ]);
    w.ein(5);
    w.zu('2026-11-22T12:00:00Z');
    w.zaehle(5, 10);
    w.zu('2026-11-22T18:00:00Z');
    w.ein(5);
    w.vorrat('18:00', rem: 45, days: 5, bis: '2026-11-26');
    w.zu('2026-11-22T20:00:00Z');
    w.ein(2, zeit: '11:00', force: true);
    w.vorrat('11:00 nachgetragen', rem: 45, days: 5, bis: '2026-11-26');
    w.ein(1, zeit: '13:00', force: true);
    w.vorrat('13:00 nachgetragen', rem: 44, days: 5, bis: '2026-11-26');
    w.zu('2026-11-23T09:00:00Z');
    w.vorrat('23.11.', rem: 44, days: 4, gesch: 0, bis: '2026-11-26');
    w.fertig();
  });

  test('S28 Tage vor dem Zähltag nicht geschätzt; neu zählen; Zähltag selbst offen', () {
    // Plan 10×30, 0. Nichts eingetragen. 25.11. zählen 100 ⇒ rem 100, geschätzt 0 ⇒ 10, bis 04.12.
    // 27.11.: offen 25./26. ⇒ rem 80, geschätzt 2 ⇒ 8, bis 04.12.
    // neu zählen 70 (27.11. 09:00) ⇒ rem 70, geschätzt 0 ⇒ 7, bis 03.12.
    // 28.11.: Zähltag 27. offen ⇒ 10 ⇒ rem 60, geschätzt 1 ⇒ 6, bis 03.12.
    // 27. nachgetragen 10 um 08:00 (vor dem Zählen) ⇒ rem 70, geschätzt 0 ⇒ 7, bis 04.12.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 30],
      [0, 1]
    ]);
    w.zu('2026-11-25T09:00:00Z');
    w.zaehle(10, 10);
    w.vorrat('25.11.', rem: 100, days: 10, gesch: 0, bis: '2026-12-04');
    w.zu('2026-11-27T09:00:00Z');
    w.vorrat('27.11.', rem: 80, days: 8, gesch: 2, bis: '2026-12-04');
    w.zaehle(7, 10);
    w.vorrat('neu', rem: 70, days: 7, gesch: 0, bis: '2026-12-03');
    w.zu('2026-11-28T09:00:00Z');
    w.vorrat('28.11.', rem: 60, days: 6, gesch: 1, bis: '2026-12-03');
    w.ein(10, tag: '2026-11-27', zeit: '08:00');
    w.vorrat('Nachtrag', rem: 70, days: 7, gesch: 0, bis: '2026-12-04');
    w.fertig();
  });

  test('S29 Halten mit Ende in Stufe 1, Haltetage ohne Eintrag', () {
    // Plan 10×3, 5×60, 0. 22.–24. je 10. 25.11. (Stufe 1 Tag 0) 08:00 zählen 200, Halten 6 (bis 01.12.), danach nichts eingetragen.
    // Gehalten wird 5. 200/5 = 40 Tage (6 Halte + 34 Stufe 1, Stufe 1 hat 60), bis 25.11.+39 = 03.01.2027.
    // 28.11.: offen 25.–27. je 5 ⇒ rem 185, geschätzt 3 ⇒ 37, bis 03.01.2027.
    // 02.12.: Halten zu Ende; offen 25.11.–01.12. = 7 Tage je 5 (6 gehalten + 01.12. Stufe 1 Tag 0) ⇒ rem 165,
    // geschätzt 7 ⇒ 33, bis 03.01.2027.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 3],
      [5, 60],
      [0, 1]
    ]);
    for (final d in ['22', '23', '24']) {
      w.zu('2026-11-${d}T09:00:00Z');
      w.ein(10);
    }
    w.zu('2026-11-25T08:00:00Z');
    w.zaehle(20, 10);
    w.t.startHold(6);
    w.vorrat('Haltebeginn', rem: 200, days: 40, gesch: 0, bis: '2027-01-03');
    w.zu('2026-11-28T09:00:00Z');
    w.vorrat('28.11.', rem: 185, days: 37, gesch: 3, bis: '2027-01-03');
    // 30.11. (noch gehalten): offen 25.–29. = 5×5 ⇒ rem 175, 35 Tage.
    w.zu('2026-11-30T09:00:00Z');
    w.vorrat('30.11.', rem: 175, days: 35, gesch: 5, bis: '2027-01-03');
    // 01.12. Halten endet: offen 25.–30. = 6×5 ⇒ rem 170, 34 Tage.
    w.zu('2026-12-01T09:00:00Z');
    w.vorrat('01.12.', rem: 170, days: 34, gesch: 6, bis: '2027-01-03');
    w.zu('2026-12-02T09:00:00Z');
    w.soll('Halten beendet', w.t.st.hold, false);
    w.vorrat('02.12.', rem: 165, days: 33, gesch: 7, bis: '2027-01-03');
    w.fertig();
  });

  test('S30 Halten ohne Ende in Stufe 1 mit Lücke, dann weiter', () {
    // Referenz. 22./23. 20, 24.–29. je 15 (Stufe 1 Tag 0–5). 30.11. (Tag 6) 08:00 zählen 300, Halten ohne Ende (15).
    // 300/15 = 20, bis 19.12. 03.12. nichts eingetragen: offen 30.11.–02.12. 3×15 ⇒ rem 255, geschätzt 3 ⇒ 17, bis 19.12.
    // stopHold am 03.12. (3 Tage verschoben, Stufe 1 ab Tag 6): 8×15 = 120 →135, 13×10 →5 ⇒ 21, bis 23.12.; rem bleibt 255.
    final w = W('2026-11-22T09:00:00Z', ref);
    final dosen = {'22': 20, '23': 20, '24': 15, '25': 15, '26': 15, '27': 15, '28': 15, '29': 15};
    dosen.forEach((d, mg) {
      w.zu('2026-11-${d}T09:00:00Z');
      w.ein(mg);
    });
    w.zu('2026-11-30T08:00:00Z');
    w.zaehle(30, 10);
    w.t.startHold(null);
    w.vorrat('Haltebeginn', rem: 300, days: 20, gesch: 0, bis: '2026-12-19');
    w.zu('2026-12-03T09:00:00Z');
    w.vorrat('03.12.', rem: 255, days: 17, gesch: 3, bis: '2026-12-19');
    w.t.stopHold();
    w.vorrat('weiter', rem: 255, days: 21, gesch: 3, bis: '2026-12-23');
    w.fertig();
  });

  test('S31 reichweite(mg) direkt am Referenzplan', () {
    // 22.11., nichts genommen: 0/19,99 ⇒ 0; 20/39,99 ⇒ 1; 40 ⇒ 2; 54,99 ⇒ 2 (40+15=55); 55 ⇒ 3;
    // 774,99 ⇒ 99; 775 ⇒ ∞.
    final w = W('2026-11-22T09:00:00Z', ref);
    final f = {0.0: 0, 19.99: 0, 20.0: 1, 39.99: 1, 40.0: 2, 54.99: 2, 55.0: 3, 774.99: 99};
    f.forEach((mg, d) => w.soll('reichweite($mg)', w.t.reichweite(mg), d));
    w.soll('reichweite(775)', w.t.reichweite(775), double.infinity);
    w.fertig();
  });

  test('S32 Nachtrag löschen ⇒ Tag wieder geschätzt', () {
    // Plan 10×10, 8×10, 0. 22.11. 08:00 zählen 100. 23.11.: 22. mit 6 (09:00) nachgetragen ⇒ rem 94, geschätzt 0.
    // Heute Tag 1: 10 →84, 8×10 →4 ⇒ 9, bis 01.12.
    // Nachtrag löschen ⇒ 22. offen ⇒ 10 ⇒ rem 90, geschätzt 1: 10 →80, 8×10 →0, 02.12. Stufe 1: 8 > 0 ⇒ 9, bis 01.12.
    final w = W('2026-11-22T08:00:00Z', [
      [10, 10],
      [8, 10],
      [0, 1]
    ]);
    w.zaehle(10, 10);
    w.zu('2026-11-23T09:00:00Z');
    w.ein(6, tag: '2026-11-22', zeit: '09:00');
    w.vorrat('Nachtrag', rem: 94, days: 9, gesch: 0, bis: '2026-12-01');
    w.t.delIntake(0, '2026-11-22');
    w.vorrat('gelöscht', rem: 90, days: 9, gesch: 1, bis: '2026-12-01');
    w.fertig();
  });

  test('S33 Lücke über Stufenwechsel, nachtragen, dann Halten ohne Ende', () {
    // Plan 10×3, 6×10, 0. 22.11. 08:00 zählen 100, 09:00 10. 26.11.: offen 23./24. (10) und 25. (Stufe 1: 6) ⇒ rem 64.
    // Heute echte Position Stufe 1 (6). Halten erst nach dem Nachtragen (10, 10, 6 wie geplant ⇒ Rest gleich).
    // Halten ohne Ende ⇒ 6 gehalten: 6 →58, 9×6 →4 ⇒ 10 Tage, bis 05.12.
    final w = W('2026-11-22T08:00:00Z', [
      [10, 3],
      [6, 10],
      [0, 1]
    ]);
    w.zaehle(10, 10);
    w.zu('2026-11-22T09:00:00Z');
    w.ein(10);
    w.zu('2026-11-26T09:00:00Z');
    w.vorrat('vor Halten', rem: 64, gesch: 3);
    // Bei offenen Tagen geht Halten erst nach dem Eintragen („weiß ich nicht mehr“ erst nach 7 Tagen).
    w.soll('Halten bei offenen Tagen', w.t.startHold(null), false);
    w.ein(10, tag: '2026-11-23');
    w.ein(10, tag: '2026-11-24');
    w.ein(6, tag: '2026-11-25');
    w.vorrat('nachgetragen', rem: 64, gesch: 0);
    w.soll('Halten', w.t.startHold(null), true);
    w.vorrat('Halten', rem: 64, days: 10, gesch: 0, bis: '2026-12-05');
    w.fertig();
  });

  test('S34 Planänderung (schneller) bei laufendem Plan', () {
    // Plan 10×10, 5×10, 0. 22.11. 08:00 zählen 140, 22./23. je 10 ⇒ rem 120.
    // 24.11.: alter Plan: 8×10 (24.11.–01.12.) →40, 8×5 →0 ⇒ 16, bis 09.12.
    // Neuer Plan 10×10, 5×5, 0 (gleiche Stufe/Dosis, Stufenbeginn bleibt): 8×10 →40, 5×5 →15, dann 0 ⇒ ∞.
    final w = W('2026-11-22T08:00:00Z', [
      [10, 10],
      [5, 10],
      [0, 1]
    ]);
    w.zaehle(14, 10);
    w.zu('2026-11-22T09:00:00Z');
    w.ein(10);
    w.zu('2026-11-23T09:00:00Z');
    w.ein(10);
    w.zu('2026-11-24T09:00:00Z');
    w.vorrat('alter Plan', rem: 120, days: 16, gesch: 0, bis: '2026-12-09');
    final e = w.t.openEditor()
      ..rows = [EditRow(10, 10), EditRow(5, 5), EditRow(0, 1)]
      ..conf = 'Ich bin mir sicher';
    final r = w.t.applyPlan(e);
    w.soll('übernommen', r.applied, true);
    w.vorrat('neuer Plan', rem: 120, days: double.infinity, gesch: 0);
    w.soll('Ende', w.t.voraussichtlichesEnde(), '2026-12-07');
    w.fertig();
  });

  test('S35 Halten in Stufe 1 ohne Einträge, vorzeitig beendet', () {
    // Plan 10×3, 5×60, 0. 22.–24. je 10. 25.11. 08:00 zählen 200, Halten 10 Tage. Nichts eingetragen.
    // 28.11. 09:00 stopHold: offen 25.–27. (gehalten, 5) ⇒ rem 185, geschätzt 3. Stufe 1 läuft ab Tag 0 weiter:
    // 185/5 = 37 Tage (Stufe 1 hat 60), bis 28.11.+36 = 03.01.2027.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 3],
      [5, 60],
      [0, 1]
    ]);
    for (final d in ['22', '23', '24']) {
      w.zu('2026-11-${d}T09:00:00Z');
      w.ein(10);
    }
    w.zu('2026-11-25T08:00:00Z');
    w.zaehle(20, 10);
    w.t.startHold(10);
    w.zu('2026-11-28T09:00:00Z');
    w.vorrat('vor stopHold', rem: 185, days: 37, gesch: 3);
    w.t.stopHold();
    w.vorrat('nach stopHold', rem: 185, days: 37, gesch: 3, bis: '2027-01-03');
    w.fertig();
  });

  test('S36 Wochen-Ø: heutiger kompletter Tag nach Lücke über Stufenwechsel', () {
    // Plan 10×3, 6×10, 0. 22.11. 10; 23.–25. offen; 26.11. (echte Stufe 1, Plan 6) 6 genommen = komplett.
    // Wochen-Ø 20.–26.11.: (10+6)/2 = 8, n 2.
    final w = W('2026-11-22T09:00:00Z', [
      [10, 3],
      [6, 10],
      [0, 1]
    ]);
    w.ein(10);
    w.zu('2026-11-26T09:00:00Z');
    w.ein(6);
    w.soll('Wochen-Ø', w.t.weekAvgs()[0].avg, 8);
    w.soll('Wochen-n', w.t.weekAvgs()[0].n, 2);
    w.fertig();
  });

  test('S37 sehr großer Vorrat, Plan endet nicht bei 0 bzw. Halten ohne Ende', () {
    // Plan 5×3, 2,5 (offen, > 0). 10000 mg: 3×5 = 15 → 9985 / 2,5 = 3994 ⇒ 3+3994 = 3997 Tage.
    // Halten ohne Ende bei 5: 10000/5 = 2000 Tage (Kontrolle unterhalb einer evtl. Schleifengrenze).
    final w = W('2026-11-22T09:00:00Z', [
      [5, 3],
      [2.5, 1]
    ]);
    w.zaehle(1000, 10);
    w.vorrat('Erhaltungsdosis', rem: 10000, days: 3997);
    final v = W('2026-11-22T09:00:00Z', [
      [5, 3],
      [0, 1]
    ]);
    v.t.startHold(null);
    v.zaehle(1000, 10);
    v.vorrat('Halten 2000', days: 2000);
    v.zaehle(2000, 10);
    v.vorrat('Halten 4000', days: 4000);
    w.fehler.addAll(v.fehler);
    w.fertig();
  });

  test('R1 Reproduktion Halte-Tage nach Halte-Ende', () {
    var jetzt = DateTime.parse('2026-11-22T09:00:00Z');
    final t = Taper(clock: () => jetzt);
    t.applyPlan(t.openEditor(neu: true)..rows = [EditRow(10, 3), EditRow(5, 60), EditRow(0, 1)]);
    for (var i = 0; i < 3; i++) {
      t.addIntake(10); // 22.–24.11. Stufe 0
      jetzt = jetzt.add(const Duration(days: 1));
      t.refresh();
    }
    t.setStock(20, 10); // 25.11. 09:00, Stufe 1 (5 mg)
    t.startHold(6); // bis 01.12.
    jetzt = DateTime.parse('2026-12-02T09:00:00Z');
    t.refresh();
    expect(t.stockInfo()!.rem, 165); // 7 offene Tage × 5
  });

  test('R2 Reproduktion heutiger Eintrag mit eingefrorener Stufe', () {
    var jetzt = DateTime.parse('2026-11-22T08:00:00Z');
    final t = Taper(clock: () => jetzt);
    t.applyPlan(t.openEditor(neu: true)..rows = [EditRow(10, 3), EditRow(6, 10), EditRow(3, 10), EditRow(0, 1)]);
    t.setStock(10, 10);
    jetzt = DateTime.parse('2026-11-26T09:00:00Z'); // 23.–25. offen, heute echte Stufe 1 (6 mg)
    t.refresh();
    t.addIntake(3);
    expect(t.stockInfo()!.days, 12); // Rest heute 6−3 = 3
  });
}
