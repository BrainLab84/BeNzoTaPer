// Lange Zufallsverläufe mit täglichen Invarianten (entspricht tests/longsim.js).
// Unabhängig von den Referenzdaten: prüft, dass sich der Kern in sich stimmig verhält.
import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';
import 'dart:convert';
import 'golden_test.dart' show diff;
import 'sim.dart';

Object? jsonDecodeRound(Object? o) => jsonDecode(jsonEncode(o));

class Rng {
  int seed;
  Rng(this.seed);
  double call() {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    return seed / 4294967296;
  }
}

int dB(String a, String b) => dBetween(a, b);

void runSeed(int seed, int days, String profile, List<String> bad) {
  final r = Rng(seed);
  void flag(String what, [Object? info = '']) {
    if (bad.length < 40) bad.add('seed $seed: $what $info');
  }

  final w = Sim(start: '2026-11-16T07:00:00');
  final cfg = [
    [10.0, 10.0, 14],
    [20.0, 5.0, 21],
    [6.0, 10.0, 10],
    [30.0, 8.0, 14],
    [2.0, 10.0, 28],
    [15.0, 10.0, 7]
  ][seed % 6];
  w.setup(cfg[0] as double, cfg[1] as double, cfg[2] as int);
  w.st.tabs = Tabs(str: [5, 2, 1], split: 0.5);
  w.st.stock = Stock(400, w.now.millisecondsSinceEpoch, w.today);
  var stockIn = 400.0;
  final stockTs = w.st.stock!.ts;
  final stockTag = w.st.stock!.day;
  var lastEnd = w.planEndNowOrNull();
  String? refEnd, pauseFrom, prevHU;
  var wasPaused = false;
  double? prevAvg;

  for (var d = 0; d < days; d++) {
    final today = w.today;
    var edited = false;
    final e = w.e;
    var S = w.st;
    if (S.frz != null) {
      for (final k in e.openDays(today)) {
        if (dB(k, today) <= 7 && r.call() < 0.85) {
          final pp = e.planFor(k).plan;
          w.take(r.call() < 0.85 ? pp : pp + 1, '', k);
        }
      }
      if (w.st.frz != null && e.openDays(today).any((k) => e.daysAgo(k) > 7) && r.call() < 0.7) e.markUnk();
      if (w.st.frz != null) {
        for (final k in e.openDays(today)) {
          if (dB(k, today) <= 7) w.take(e.planFor(k).plan, '', k);
        }
      }
      if (w.st.frz != null && e.openDays(today).isNotEmpty) e.markUnk();
      if (w.st.frz != null) flag('Stillstand lässt sich nicht lösen', today);
    }
    S = w.st;
    final pl = S.plan[S.stage];
    final x = r.call();
    if (profile == 'brav') {
      if (pl > 0) {
        w.at(8);
        w.take(pl / 2, '08:00');
        w.at(20);
        w.take(pl / 2, '20:00');
      } else {
        e.addIntake(0);
      }
    } else if (x < 0.04) {
      // vergessen
    } else if (x < 0.10 && pl > 0) {
      w.at(9);
      e.addIntake(pl);
      w.at(21);
      if (e.addIntake(pl * 0.2 > 0.5 ? pl * 0.2 : 0.5, t: '21:00') != IntakeResult.needsPause) {
        flag('Pause-Dialog fehlt', today);
      } else {
        e.addIntake(pl * 0.2 > 0.5 ? pl * 0.2 : 0.5, t: '21:00', force: true);
      }
    } else if (x < 0.13 && pl > 0) {
      w.at(9);
      w.take(pl / 2, '09:00');
    } else if (pl > 0 && r.call() < 0.5) {
      w.at(8);
      w.take(pl / 2, '08:00');
      w.at(20);
      final te = w.st.log[today]!;
      e.addIntake(round3((te.plan ?? pl) - te.dose));
    } else if (pl > 0) {
      w.take(pl);
    } else {
      e.addIntake(0);
    }
    if (profile != 'brav') {
      if (r.call() < 0.2) e.saveNote(today, Note(sym: 1 + (r.call() * 5).floor()));
      if (r.call() < 0.06) e.toggleGood(today);
      S = w.st;
      final lastS = S.stage >= S.plan.length - 1;
      if (!lastS && !S.hold && S.frz == null && r.call() < 0.012) {
        e.startHold(r.call() < 0.6 ? 2 + (r.call() * 12).floor() : null);
      } else if (S.hold && S.holdUntil == null && r.call() < 0.12) {
        e.stopHold();
      } else if (S.hold && S.holdUntil != null && r.call() < 0.03) {
        e.stopHold();
      }
      S = w.st;
      if (!lastS && !S.hold && S.frz == null && S.pend == null && r.call() < 0.01) {
        final left = e.need(S.stage) - e.stageDay();
        final n = r.call() < 0.5 ? (left - 3 > 1 ? left - 3 : 1) : left + 5;
        if (e.saveLeft(n) == LeftResult.needsWhy) e.saveLeft(n, why: 'Grund');
        edited = true;
      }
      if (w.st.pend != null && w.now.millisecondsSinceEpoch - w.st.pend!.at > waitMs) {
        if (r.call() < 0.7) {
          final ed = e.usePend();
          if (ed != null) {
            ed.conf = 'Ich bin mir sicher';
            e.applyPlan(ed);
          }
        } else {
          e.dropPend();
        }
        edited = true;
      }
      S = w.st;
      if (!lastS && !S.hold && r.call() < 0.006) {
        final ed = e.openEditor();
        final n = ed.rows.length;
        final i = S.stage + 1 + (r.call() * (n - S.stage - 1 > 1 ? n - S.stage - 1 : 1)).floor();
        if (i < n)
          ed.rows[i].days =
              ((ed.rows[i].days! + (r.call() < 0.5 ? -3 : 4)) > 1) ? ed.rows[i].days! + (r.call() < 0.5 ? -3 : 4) : 1;
        ed.conf = 'Ich bin mir sicher';
        final res = e.applyPlan(ed);
        if (res.askWhy) {
          ed.why = 'weil';
          e.applyPlan(ed);
        }
        edited = true;
      }
      if (r.call() < 0.01) {
        final dump = e.exportJson()!;
        if (!e.importJson(dump)) flag('Import der eigenen Sicherung schlägt fehl');
        // frzFloor wird beim Laden aufgefüllt (gewolltes Verhalten), sonst bleibt alles gleich
        final a = jsonDecodeRound(dump) as Map, b = jsonDecodeRound(e.exportJson()) as Map;
        a.remove('frzFloor');
        b.remove('frzFloor');
        final dd = diff(a, b);
        if (dd != null) flag('Import verändert Daten', dd);
      }
    }
    final si = e.stockInfo();
    if (si != null && si.days <= 7 && si.days.isFinite) {
      w.st.stock!.mg += 150;
      stockIn += 150;
    }
    // ===== Invarianten =====
    S = w.st;
    if (!(S.stage >= 0 && S.stage < S.plan.length)) flag('Stufe außerhalb Plan', S.stage);
    if (S.stageStart! > today) flag('Stufenbeginn in Zukunft', '${S.stageStart} > $today');
    if (S.days != null && S.days!.length != S.plan.length) flag('days ≠ plan');
    if (!S.hold && S.frz == null && S.stage < S.plan.length - 1 && e.stageDay() >= e.need(S.stage)) {
      flag('Stufe überfällig', today);
    }
    if (S.hold && S.frz != null) flag('hold und frz gleichzeitig');
    if (S.hold && S.holdUntil != null && S.holdUntil! <= today) flag('Halten über Enddatum hinaus', S.holdUntil);
    S.log.forEach((k, en) {
      if (en.it.isNotEmpty) {
        final sum = round3(en.it.fold(0.0, (a, x) => a + x.v));
        if ((sum - en.dose).abs() > 1e-9) flag('Tagessumme falsch', k);
      }
      if ((en.dose > en.plan! + 1e-9) != (en.r == 'lapse')) flag('✓/✗ falsch', k);
    });
    // Wochen-Ø unabhängig nachrechnen
    {
      var sum = 0.0;
      var n = 0;
      for (var i = 0; i < 7; i++) {
        final k = addD(today, -i);
        final en = S.log[k];
        if (en == null) continue;
        if (k == today && en.dose < en.plan! - 1e-9) continue;
        sum += en.dose;
        n++;
      }
      final a = e.weekAvgs(w.now, 1)[0].avg;
      final ex = n > 0 ? sum / n : null;
      if (!((a == null && ex == null) || (a != null && ex != null && (a - ex).abs() < 1e-9))) {
        flag('Wochen-Ø falsch', '$a vs $ex');
      }
      if (profile == 'brav' && prevAvg != null && ex != null && ex > prevAvg + 1e-9 && !edited) {
        flag('Wochen-Ø steigt trotz Planeinnahme', '$prevAvg→$ex');
      }
      prevAvg = ex;
    }
    // Vorrat unabhängig
    if (S.stock != null) {
      var used = 0.0;
      for (final en in S.log.values) {
        for (final x in en.it) {
          if (x.ts > stockTs) used += x.v;
        }
      }
      // Tage ohne Eintrag seit dem Zähltag (ab Planstart, bis gestern) unabhängig nachzählen: die werden mit der
      // geplanten Dosis abgezogen. Ohne solche Tage gilt Rest = gezählt − eingetragen exakt.
      var ohne = 0;
      final t0 = S.t0 ?? today;
      for (var k = stockTag.compareTo(t0) > 0 ? stockTag : t0; k.compareTo(today) < 0; k = addD(k, 1)) {
        if (S.log[k] == null) ohne++;
      }
      final info = e.stockInfo()!;
      final rem = info.rem;
      if (info.geschaetzt != ohne) flag('Vorrat: geschätzte Tage', '${info.geschaetzt} vs $ohne');
      if (ohne == 0 && (rem - (stockIn - used)).abs() > 1e-6) flag('Vorrat falsch', '$rem vs ${stockIn - used}');
      if (rem > stockIn - used + 1e-6) flag('Vorrat zu hoch', '$rem vs ${stockIn - used}');
    }
    // Enddatum-Konsistenz
    final paused = S.hold;
    final endNow = w.planEndNowOrNull();
    if (!paused && S.frz == null && S.stage < S.plan.length - 1) {
      final shown = w.endShown();
      if (shown != endNow) flag('Angezeigtes Enddatum ≠ berechnet', '$shown vs $endNow');
    }
    if (paused && !wasPaused) {
      refEnd = lastEnd;
      pauseFrom = S.holdSince;
    }
    if (!paused && wasPaused && !edited && refEnd != null && pauseFrom != null) {
      final res = (prevHU != null && prevHU <= today) ? prevHU : today;
      final exp = addD(refEnd, dB(pauseFrom, res));
      if (endNow != exp && S.stage < S.plan.length - 1) {
        flag('Verschiebung nach Pause falsch', 'Tag $d erwartet $exp, ist $endNow (Pause ab $pauseFrom bis $res)');
      }
    }
    if (!paused &&
        !wasPaused &&
        !edited &&
        lastEnd != null &&
        endNow != null &&
        endNow != lastEnd &&
        S.stage < S.plan.length - 1) {
      flag('Enddatum ändert sich ohne Grund', '$lastEnd→$endNow $today');
    }
    if (paused && edited) {
      refEnd = null;
      pauseFrom = null;
    }
    if (!paused) lastEnd = endNow;
    wasPaused = paused;
    prevHU = S.hold ? S.holdUntil : null;
    if (edited) lastEnd = endNow;
    // Kalender-Zukunft unabhängig projizieren
    if (!paused && S.frz == null) {
      var s = S.stage;
      var st = S.stageStart!;
      final lastI = S.plan.length - 1;
      int need(int i) => S.days != null && S.days![i] > 0 ? S.days![i] : S.target;
      final pj = e.projMap(addD(today, 60));
      for (var i = 1; i <= 60; i++) {
        final k = addD(today, i);
        while (s < lastI && k >= addD(st, need(s))) {
          st = addD(st, need(s));
          s++;
        }
        if (pj.map[k]!.v != S.plan[s]) {
          flag('Kalender-Zukunft falsch', '$k zeigt ${pj.map[k]!.v} statt ${S.plan[s]}');
          break;
        }
      }
    }
    // Wochenstreifen = Log
    S.log.forEach((k, en) {
      if (en.r != 'lapse' && en.r != 'ok') flag('Eintrag ohne ✓/✗', k);
    });
    if (profile != 'brav' && r.call() < 0.005) {
      final gap = 5 + (r.call() * 40).floor();
      w.at(23, 59);
      w.day(gap, 7);
      d += gap - 1;
      continue;
    }
    w.at(23, 59);
    w.day(1, 7);
  }
}

extension on Sim {
  String? planEndNowOrNull() {
    e.ensureStart();
    return st.hold ? null : Taper.planEnd(st.plan, st.days, st.stage, st.stageStart!, st.target);
  }
}

void main() {
  test('Langsimulation: 10 Verläufe à 400 Tage, Invarianten halten', () {
    final bad = <String>[];
    for (final seed in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]) {
      runSeed(seed, 400, seed <= 2 ? 'brav' : 'mix', bad);
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
