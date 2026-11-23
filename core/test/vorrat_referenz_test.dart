// Vorrat gegen einen eigenen, unabhängigen Referenzrechner: Langzeitsimulation, die den Kern (Taper)
// nach jedem Schritt mit dem Referenzrechner vergleicht (Rest, Reichweite, geschätzte Tage, Zeitstempel).
//
// Der Referenzrechner ist allein nach der Spezifikation geschrieben (nicht aus engine.dart):
//  - Planposition je Datum rein kalendarisch ab Starttag; Tage ohne Eintrag verschieben nichts.
//  - Halten [H, E): Stufentag steht still, danach geht es dort weiter, Rest verschiebt sich.
//  - Rest = gezählt − Einnahmen mit ts > Zähl-ts − geplante Dosis je vergangenem Tag ohne Eintrag
//    (ab max(Zähltag, Planstart) bis gestern).
//  - Reichweite inkl. heute: erst offener Rest von heute, dann Tag für Tag die volle Dosis.
//  - Einnahme heute mit der aktuellen Minute als Uhrzeit = genauer Zeitpunkt jetzt (sonst läge sie
//    rechnerisch vor einer Zählung in derselben Minute).
import 'dart:math';

import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

const int msDay = 86400000;
const double eps = 1e-6;

int dayIdx(DateTime t) => DateTime.utc(t.year, t.month, t.day).millisecondsSinceEpoch ~/ msDay;
String two(int n) => n.toString().padLeft(2, '0');
String keyOf(int d) {
  final x = DateTime.fromMillisecondsSinceEpoch(d * msDay, isUtc: true);
  return '${x.year}-${two(x.month)}-${two(x.day)}';
}

String hms(DateTime t) =>
    '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
String tsStr(int ms) {
  final x = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${keyOf(dayIdx(x))} ${hms(x)}';
}

// ===================== Referenzrechner =====================

class RIn {
  final int day;
  final double v;
  final int ts;
  RIn(this.day, this.v, this.ts);
  @override
  String toString() => '${keyOf(day)}:${v}mg@${tsStr(ts)}';
}

class RHold {
  final int h; // erster gehaltener Tag
  int? e; // erster nicht mehr gehaltener Tag (exklusiv); null = ohne Ende
  bool active;
  RHold(this.h, this.e, this.active);
}

class Ref {
  final int start;
  final List<double> doses;
  final List<int> durs;
  final holds = <RHold>[];
  final byDay = <int, List<RIn>>{};
  double? mg;
  int? cTs;
  int? cDay;
  Ref(this.start, this.doses, this.durs);

  bool get holding => holds.isNotEmpty && holds.last.active;

  void tick(int today) {
    if (holding) {
      final h = holds.last;
      if (h.e != null && today >= h.e!) h.active = false;
    }
  }

  /// Effektiver Plan-Tag (0 = erster Tag von Stufe 1) am Datum d (d >= start).
  int off(int d) {
    var held = 0;
    for (final h in holds) {
      final e = h.e ?? (1 << 40);
      if (d < h.h) break;
      if (d < e) return h.h - start - held; // im Halten: Stand vom ersten Halte-Tag
      held += e - h.h;
    }
    return d - start - held;
  }

  int stageAt(int d) {
    final o = off(d);
    var cum = 0;
    for (var i = 0; i < doses.length - 1; i++) {
      cum += durs[i];
      if (o < cum) return i;
    }
    return doses.length - 1;
  }

  double planned(int d) => d < start ? 0 : doses[stageAt(d)];
  bool hasEntry(int d) => (byDay[d] ?? const []).isNotEmpty;
  double takenOn(int d) => (byDay[d] ?? const <RIn>[]).fold(0.0, (a, x) => a + x.v);

  void add(RIn x) => (byDay[x.day] ??= []).add(x);

  (double, int)? rest(int today) {
    if (mg == null) return null;
    var r = mg!;
    for (final l in byDay.values) {
      for (final x in l) {
        if (x.ts > cTs!) r -= x.v;
      }
    }
    var g = 0;
    for (var d = max(cDay!, start); d < today; d++) {
      if (!hasEntry(d)) {
        r -= planned(d);
        g++;
      }
    }
    return (r, g);
  }

  double reach(int today, double rem) {
    if (today >= start && planned(today) <= eps) return double.infinity;
    final open = planned(today) - takenOn(today);
    if (open > eps) {
      if (rem < open - eps) return 0;
      rem -= open;
    }
    var n = 1;
    for (var d = today + 1; n < 2000000; d++) {
      final p = planned(d);
      if (d >= start && p <= eps) return double.infinity;
      if (rem >= p - eps) {
        rem -= p;
        n++;
      } else {
        break;
      }
    }
    return n.toDouble();
  }
}

// ===================== Simulation =====================

class Ev {
  final String cat;
  final String msg;
  Ev(this.cat, this.msg);
}

final List<double> strengths = [0.5, 1, 2, 2.5, 5, 10];

class Sim {
  final int seed;
  final Random r;
  late DateTime jetzt;
  late Taper t;
  late Ref m;
  final hist = <String>[];
  final evs = <Ev>[];
  final counts = <String, int>{};
  int steps = 0;
  int simDays = 0;
  double? lastRemDiff;
  int? lastGDiff;
  bool lastPlanBad = false;
  bool lastHoldBad = false;
  double? lastDaysKey;
  int gap = 0;
  int plansRejected = 0;
  int holdRefused = 0;

  /// Modus B: Halten nur ohne offene Tage (frz == null) und nicht erneut während eines Haltens.
  final bool diszipliniert;

  /// Modus C: zusätzlich jeden Morgen alle offenen Tage nachtragen bzw. „weiß ich nicht mehr“ (kein frz über Tag).
  final bool sauber;
  int frzLag = 0;
  Sim(this.seed, {this.diszipliniert = false, this.sauber = false}) : r = Random(seed);

  int get T => dayIdx(jetzt);

  void log(String s) {
    hist.add('${keyOf(T)} ${hms(jetzt)} $s');
  }

  void ev(String cat, String msg) {
    counts[cat] = (counts[cat] ?? 0) + 1;
    if (evs.where((e) => e.cat == cat).length < 6) {
      final h = hist.length > 14 ? hist.sublist(hist.length - 14) : hist;
      evs.add(Ev(cat, 'seed=$seed $msg\n      ctx: ${ctx()}\n      verlauf:\n        ${h.join('\n        ')}'));
    }
  }

  String ctx() {
    final d = T;
    final hs = m.holds.map((h) => '[${keyOf(h.h)},${h.e == null ? '∞' : keyOf(h.e!)})${h.active ? '*' : ''}').join(' ');
    final s = t.s;
    return 'heute=${keyOf(d)} start=${keyOf(m.start)} plan=${m.doses}/${m.durs} '
        'refStufe=${d >= m.start ? m.stageAt(d) : '-'} engStufe=${s?.stage} engStageStart=${s?.stageStart} '
        'refHalten=$hs engHold=${s?.hold} since=${s?.holdSince} until=${s?.holdUntil} '
        'zählung=${m.mg}mg@${m.cTs == null ? '-' : tsStr(m.cTs!)} heuteGenommen=${m.takenOn(d)}';
  }

  void adv() {
    final p = r.nextDouble();
    Duration du;
    if (p < 0.03) {
      du = Duration.zero;
    } else if (p < 0.10) {
      du = Duration(milliseconds: 1 + r.nextInt(999));
    } else {
      du = Duration(minutes: 1 + r.nextInt(100), seconds: r.nextInt(60), milliseconds: r.nextInt(1000));
    }
    final n = jetzt.add(du);
    if (dayIdx(n) == T) jetzt = n;
  }

  // ---------- Plan ----------
  (List<double>, List<int>) randPlan() {
    final step = r.nextDouble() < 0.2 ? 0.25 : 0.5;
    while (true) {
      final n = 2 + r.nextInt(7);
      final startDose = (4 + r.nextInt(57)) * 0.5; // 2 .. 30
      final target = r.nextBool() ? 0.0 : (1 + r.nextInt(4)) * step;
      if (target >= startDose) continue;
      final cand = <double>[];
      for (var v = target + step; v < startDose - 1e-9; v += step) {
        cand.add(v);
      }
      if (cand.length < n - 2) continue;
      cand.shuffle(r);
      final mid = cand.take(n - 2).toList()..sort((a, b) => b.compareTo(a));
      final doses = [startDose, ...mid, target];
      final durs = [for (var i = 0; i < n; i++) r.nextDouble() < 0.15 ? 1 + r.nextInt(2) : 3 + r.nextInt(26)];
      return (doses, durs);
    }
  }

  bool newPlan() {
    for (var tries = 0; tries < 20; tries++) {
      final (doses, durs) = randPlan();
      final startOff = r.nextDouble() < 0.7 ? 0 : 1 + r.nextInt(10);
      final startK = keyOf(T + startOff);
      final ed = t.openEditor(neu: true)
        ..rows = [for (var i = 0; i < doses.length; i++) EditRow(doses[i], durs[i])]
        ..startDatum = startK;
      final res = t.applyPlan(ed);
      if (!res.applied) {
        plansRejected++;
        continue;
      }
      m = Ref(T + startOff, doses, durs);
      log('Plan $doses / $durs Start $startK');
      return true;
    }
    return false;
  }

  // ---------- Aktionen ----------
  double vary(double p) {
    final x = r.nextDouble();
    final d = [0.25, 0.5, 1.0, 2.0][r.nextInt(4)];
    if (x < 0.75) return p;
    if (x < 0.87) return p + d;
    if (x < 0.95) return max(0, p - d);
    return 0;
  }

  void intake(double v, {String? tt, int? back, required int refTs, String label = 'Einnahme'}) {
    final d = T - (back ?? 0);
    final k = keyOf(d);
    final res = t.addIntake(v, t: tt, k: back == null ? null : k, force: true);
    final allowed = (back ?? 0) <= 7 && T >= m.start; // vor Planstart: Kern nimmt nichts an (beobachtet)
    log('$label ${v}mg tag=$k t=${tt ?? '-'} -> $res');
    if (res == IntakeResult.added) {
      if (!allowed) ev('addIntake angenommen obwohl >7 Tage', 'tag=$k');
      final it = t.st.log[k]?.it ?? const <Intake>[];
      var ts = refTs;
      if (!it.any((x) => x.ts == refTs && (x.v - v).abs() < eps)) {
        final sameMin = back == null && tt != null && tt == '${two(jetzt.hour)}:${two(jetzt.minute)}';
        ev(sameMin ? 'Zeitstempel[heute, aktuelle Minute]' : 'Zeitstempel',
            'erwartet ts=${tsStr(refTs)} v=$v; Kern: ${it.map((x) => '${x.v}@${x.ts == 0 ? 0 : tsStr(x.ts)}(${x.t})').toList()}');
        // Modell an den Kern angleichen, damit die Abweichung nicht weiterläuft
        final known = (m.byDay[d] ?? []).map((y) => y.ts).toSet();
        final cand = it.where((x) => (x.v - v).abs() < eps && !known.contains(x.ts)).toList();
        if (cand.isNotEmpty) ts = cand.last.ts;
      }
      m.add(RIn(d, v, ts));
    } else if (allowed) {
      ev('addIntake abgelehnt', 'tag=$k v=$v t=$tt res=$res');
    }
  }

  /// Zeitpunkt einer Einnahme heute mit Uhrzeit [mins]: die aktuelle Minute heißt „jetzt“.
  int tsHeute(int mins) =>
      mins == jetzt.hour * 60 + jetzt.minute ? jetzt.millisecondsSinceEpoch : T * msDay + mins * 60000;

  void actMain() {
    final p = m.planned(T);
    final v = vary(p);
    if (r.nextDouble() < 0.15) {
      // mit Uhrzeit (heute, nicht in der Zukunft)
      final mins = r.nextInt(jetzt.hour * 60 + jetzt.minute + 1);
      final tt = '${two(mins ~/ 60)}:${two(mins % 60)}';
      intake(v, tt: tt, refTs: tsHeute(mins), label: 'Einnahme(Uhrzeit)');
    } else {
      intake(v, refTs: jetzt.millisecondsSinceEpoch);
    }
  }

  void actExtra() {
    final v = [0.25, 0.5, 1.0, 2.0, 5.0][r.nextInt(5)];
    if (r.nextBool()) {
      intake(v, refTs: jetzt.millisecondsSinceEpoch, label: 'Zusatz');
    } else {
      final mins = jetzt.hour * 60 + jetzt.minute;
      intake(v, tt: '${two(mins ~/ 60)}:${two(mins % 60)}', refTs: tsHeute(mins), label: 'Zusatz(gleiche Minute)');
    }
  }

  void actBackfill({int? backFix}) {
    int back;
    if (backFix != null) {
      back = backFix;
    } else {
      final x = r.nextDouble();
      back = x < 0.07 ? 8 : 1 + r.nextInt(7);
    }
    final d = T - back;
    final v = vary(m.planned(d));
    if (r.nextBool()) {
      final mins = r.nextInt(24 * 60);
      intake(v,
          tt: '${two(mins ~/ 60)}:${two(mins % 60)}',
          back: back,
          refTs: d * msDay + mins * 60000,
          label: 'Nachtrag(Uhrzeit)');
    } else {
      intake(v, back: back, refTs: d * msDay + 12 * 3600000, label: 'Nachtrag(ohne Uhrzeit)');
    }
  }

  void actDelete() {
    final back = r.nextInt(8);
    final d = T - back;
    final k = keyOf(d);
    final it = t.st.log[k]?.it;
    if (it == null || it.isEmpty) return;
    final i = r.nextInt(it.length);
    final x = it[i];
    final v = x.v, ts = x.ts;
    t.delIntake(i, k);
    log('Löschen tag=$k i=$i (${v}mg@${ts == 0 ? 0 : tsStr(ts)})');
    final l = m.byDay[d] ?? [];
    var j = l.indexWhere((y) => y.ts == ts && (y.v - v).abs() < eps);
    if (j < 0) {
      ev('Löschen-Zuordnung', 'Kern-Eintrag ${v}@$ts nicht im Modell: $l');
      j = l.indexWhere((y) => (y.v - v).abs() < eps);
    }
    if (j >= 0) l.removeAt(j);
  }

  void actCount({bool add = false}) {
    if (!add && r.nextDouble() < 0.25 && jetzt.hour < 12) {
      jetzt = DateTime.utc(jetzt.year, jetzt.month, jetzt.day, 12); // Grenze: genau 12:00:00.000
    }
    final n = (r.nextInt(120)).toDouble() + (r.nextDouble() < 0.2 ? 0.5 : 0);
    final s = strengths[r.nextInt(strengths.length)];
    t.setStock(n, s, add: add);
    if (add && m.mg != null) {
      m.mg = m.mg! + n * s;
    } else {
      m.mg = n * s;
      m.cTs = jetzt.millisecondsSinceEpoch;
      m.cDay = T;
    }
    log('${add ? 'Nachkauf' : 'Zählen'} $n×$s=${n * s}mg');
  }

  void actHold() {
    if (T < m.start) return; // vor Planstart: eigener Kurztest
    if (diszipliniert && (t.st.frz != null || m.holding)) return;
    final n = r.nextDouble() < 0.3 ? null : 1 + r.nextInt(20);
    final wasHolding = m.holding;
    final frzOpen = t.st.frz != null;
    final res = t.startHold(n);
    log('Halten(${n ?? 'ohne Ende'}) -> $res${frzOpen ? ' [frz offen]' : ''}${wasHolding ? ' [erneut]' : ''}');
    if (!res) {
      holdRefused++;
      return;
    }
    if (wasHolding) {
      // Referenz: das laufende Halten endet heute, ein neues beginnt heute (gehaltene Tage bleiben verschoben)
      m.holds.last
        ..e = T
        ..active = false;
      ev('Halten erneut während Halten', 'n=$n');
    }
    if (frzOpen) ev('Halten bei offenem Tag (frz)', 'n=$n kernStufe=${t.st.stage} refStufe=${m.stageAt(T)}');
    m.holds.add(RHold(T, n == null ? null : T + n, true));
  }

  void actStopHold() {
    t.stopHold();
    log('Halten beenden');
    if (m.holding) {
      m.holds.last
        ..e = T
        ..active = false;
    }
  }

  void actRestart() {
    t.wipe();
    log('wipe()');
    lastRemDiff = null;
    lastGDiff = null;
    lastDaysKey = null;
    adv();
    newPlan();
    if (r.nextDouble() < 0.8) {
      adv();
      actCount();
    }
  }

  // ---------- Vergleich ----------
  void check(String act) {
    steps++;
    final d = T;
    m.tick(d);
    if (t.s == null) return;
    // Plan heute
    if (d >= m.start) {
      final eng = t.st.plan[t.planPos(keyOf(d)).$1];
      final ref = m.planned(d);
      final bad = (eng - ref).abs() > eps;
      if (bad && !lastPlanBad) {
        ev('Planposition heute (planPos)${t.st.hold ? '[Halten]' : ''}',
            'nach "$act": ref=$ref (Stufe ${m.stageAt(d)}) kern=$eng (planPos ${t.planPos(keyOf(d))}, st.stage ${t.st.stage})');
      }
      lastPlanBad = bad;
      if ((t.st.plan[t.st.stage] - ref).abs() > eps) frzLag++;
    }
    final hb = t.st.hold != m.holding;
    if (hb && !lastHoldBad) ev('Halte-Status', 'nach "$act": ref=${m.holding} kern=${t.st.hold}');
    lastHoldBad = hb;

    final si = t.stockInfo();
    final rr = m.rest(d);
    if (rr == null) {
      if (si != null) ev('stockInfo ohne Vorrat', 'nach "$act"');
      return;
    }
    if (si == null) {
      ev('stockInfo fehlt', 'nach "$act"');
      return;
    }
    final rd = si.rem - rr.$1;
    if ((lastRemDiff == null && rd.abs() > eps) || (lastRemDiff != null && (rd - lastRemDiff!).abs() > eps)) {
      // Diagnose: geplante Dosis der geschätzten Tage
      final sollDiff = <String>[];
      for (var x = max(m.cDay!, m.start); x < d; x++) {
        final a = t.sollAm(keyOf(x));
        final b = m.planned(x);
        if ((a - b).abs() > eps) sollDiff.add('${keyOf(x)}: kern=$a ref=$b');
      }
      ev(
          'Rest${lastPlanBad ? '[PlanposAbw]' : ''}',
          'nach "$act": ref=${rr.$1} kern=${si.rem} (Diff ${rd.toStringAsFixed(3)}, vorher ${lastRemDiff?.toStringAsFixed(3)}) '
              'g ref=${rr.$2} kern=${si.geschaetzt}; sollAm-Abweichungen: ${sollDiff.take(8).toList()}${sollDiff.length > 8 ? '…(${sollDiff.length})' : ''}');
    }
    lastRemDiff = rd;
    final gd = si.geschaetzt - rr.$2;
    if ((lastGDiff == null && gd != 0) || (lastGDiff != null && gd != lastGDiff)) {
      ev('geschaetzt', 'nach "$act": ref=${rr.$2} kern=${si.geschaetzt}');
    }
    lastGDiff = gd;
    // Reichweite: mit dem Rest des Kerns gerechnet (trennt Reichweite-Logik vom Rest)
    final refDays = m.reach(d, si.rem);
    final same = (refDays.isInfinite && si.days.isInfinite) || (refDays - si.days).abs() < eps;
    if (!same) {
      final key = si.days - refDays;
      if (lastDaysKey == null || key != lastDaysKey) {
        final te = t.st.log[keyOf(d)];
        final flags = [
          if (lastPlanBad) 'PlanposAbw',
          if (te?.plan != null && (te!.plan! - m.planned(d)).abs() > eps) 'TagesplanVeraltet',
          if (d < m.start) 'vorStart',
          if (m.holding) (m.holds.last.e == null ? 'HaltenOhneEnde' : 'HaltenMitEnde'),
          if (si.rem < 0) 'RestNegativ',
          if (m.takenOn(d) >= m.planned(d) - eps) 'heuteVoll',
          if (refDays.isInfinite || si.days.isInfinite) 'unendlich',
          if (refDays.isFinite && refDays > 3000) 'über3000',
        ];
        ev('Reichweite[${flags.join(',')}]', 'nach "$act": rem=${si.rem} ref=$refDays kern=${si.days}');
      }
      lastDaysKey = key;
    } else {
      lastDaysKey = null;
    }
  }

  void step(String label, void Function() f) {
    adv();
    f();
    check(label);
  }

  void run(DateTime begin, int days) {
    jetzt = begin;
    t = Taper(clock: () => jetzt);
    if (!newPlan()) throw StateError('kein Plan');
    check('Plan');
    if (r.nextDouble() < 0.85) step('Zählen', actCount);
    for (var day = 0; day < days; day++) {
      if (day > 0) {
        jetzt = DateTime.utc(jetzt.year, jetzt.month, jetzt.day + 1, 6, r.nextInt(180), r.nextInt(60), r.nextInt(1000));
        if (r.nextDouble() < 0.02) jetzt = DateTime.utc(jetzt.year, jetzt.month, jetzt.day, 0, 0, 0, 0);
        t.refresh();
        log('--- Tag weiter, refresh');
        check('refresh');
        if (sauber && T >= m.start) {
          for (var b = 7; b >= 1; b--) {
            if (T - b >= m.start && !m.hasEntry(T - b) && (t.st.log[keyOf(T - b)] == null)) {
              step('Nachtrag (sauber)', () => actBackfill(backFix: b));
            }
          }
          if (t.st.frz != null)
            step('markUnk (sauber)', () {
              t.markUnk();
              log('markUnk');
            });
        }
      }
      simDays++;
      if (gap > 0) {
        gap--;
        if (gap == 0) {
          // nach der Lücke oft nachtragen
          for (var b = 1; b <= 7; b++) {
            if (!m.hasEntry(T - b) && r.nextDouble() < 0.4) step('Nachtrag nach Lücke', () => actBackfill(backFix: b));
          }
        }
        continue;
      }
      final acts = <(String, void Function())>[];
      if (r.nextDouble() < 0.93) acts.add(('Einnahme', actMain));
      if (r.nextDouble() < 0.08) acts.add(('Zusatz', actExtra));
      if (r.nextDouble() < 0.15) acts.add(('Nachtrag', actBackfill));
      if (r.nextDouble() < 0.05) acts.add(('Löschen', actDelete));
      if (r.nextDouble() < (m.mg == null ? 0.3 : 0.03)) acts.add(('Zählen', actCount));
      if (r.nextDouble() < 0.03) acts.add(('Nachkauf', () => actCount(add: true)));
      if (r.nextDouble() < 0.025) acts.add(('Halten', actHold));
      if (m.holding && r.nextDouble() < (m.holds.last.e == null ? 0.06 : 0.02))
        acts.add(('Halten beenden', actStopHold));
      if (r.nextDouble() < 0.03) {
        acts.add((
          'markUnk',
          () {
            t.markUnk();
            log('markUnk');
          }
        ));
      }
      if (r.nextDouble() < 0.004) acts.add(('Neustart', actRestart));
      acts.shuffle(r);
      for (final (l, f) in acts) {
        step(l, f);
      }
      if (r.nextDouble() < 0.03) {
        gap = 1 + r.nextInt(12);
        log('Lücke $gap Tage');
      }
    }
  }
}

void main() {
  for (final modus in ['A', 'B', 'C']) {
    test('Vorrat gegen Referenzrechner, Modus $modus (24 Verläufe, 200–400 Tage)', () {
      final seeds = [for (var i = 1; i <= 24; i++) i * 7919 + 13];
      final all = <Ev>[];
      var steps = 0, frzLag = 0;
      for (final seed in seeds) {
        final sim = Sim(seed, diszipliniert: modus != 'A', sauber: modus == 'C');
        final r = Random(seed * 31);
        final begin = DateTime.utc(2025 + r.nextInt(4), 1 + r.nextInt(12), 1 + r.nextInt(28), 7, r.nextInt(60));
        final n = 200 + r.nextInt(201);
        try {
          sim.run(begin, n);
        } catch (e, st) {
          all.add(Ev('Ausnahme', 'seed=$seed $e\n$st\n${sim.hist.reversed.take(10).join('\n')}'));
        }
        steps += sim.steps;
        frzLag += sim.frzLag;
        all.addAll(sim.evs);
      }
      expect(steps, greaterThan(10000));
      // Modus A/B: viele Prüfungen bei stehender Anzeige (offene Tage) – genau die schwierigen Fälle.
      if (modus != 'C') expect(frzLag, greaterThan(1000));
      expect(all, isEmpty, reason: all.take(3).map((e) => '### ${e.cat}\n  ${e.msg}').join('\n\n'));
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
