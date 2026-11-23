// QA-Audit: 150 zufällige, reproduzierbare Szenarien (fester Seed).
//
// Jedes Szenario mischt, was ein Mensch in der App tun kann: Plan anlegen (auch Grenzfälle: 1 Stufe,
// viele Stufen, krumme Dezimalwerte, Ziel ≠ 0), Einnahmen heute/nachträglich mit Uhrzeit, Einnahmen
// löschen, Tage vergessen, „Weiß ich nicht mehr“, Halten mit/ohne Ende, Weiter, Stufe kürzen/verlängern,
// Bedenkzeit übernehmen/verwerfen, neuen Plan schneller/langsamer, Vorrat zählen/nachkaufen, Tabletten,
// Notizen, gute Tage, Neustart der App (JSON hin und zurück), Sicherung laden, Uhrzeiten rund um
// Mitternacht, Monats-/Jahreswechsel, Schaltjahr.
//
// Nach JEDEM Schritt wird unabhängig nachgerechnet (nicht aus dem Kern abgeschrieben):
//  • Protokoll sauber: Dosis = Summe der Einnahmen, Ausrutscher-Markierung, nichts in der Zukunft,
//    keine leeren Tage, Einnahmen nach Uhrzeit sortiert, keine NaN.
//  • Zustand gültig: Stufe im Plan, Tage je Stufe ≥ 1, Halten-Felder zusammenpassend.
//  • Kalender-Prognose = unabhängig berechneter Plan pro Tag (auch nach Halte-Ende).
//  • Voraussichtliches Ende = erster Tag der letzten Stufe in dieser Prognose.
//  • Diagramm (Fortschritt): lückenlos, Vergangenheit = Protokoll, 7-Tage-Ø unabhängig, Zukunft = Prognose,
//    endet beim voraussichtlichen Ende.
//  • Vorrat: Rest = gezählt − Einnahmen danach; Reichweite = unabhängige Verbrauchsrechnung.
//  • Neustart: Zustand und alle abgeleiteten Werte vor/nach JSON-Rundreise identisch.
//  • refresh() ist idempotent (zweimal hintereinander ändert nichts).
import 'dart:convert';
import 'dart:math';

import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

/// JSON kanonisch (Schlüssel sortiert), damit Vergleiche nicht an der Reihenfolge hängen.
Object? canon(Object? x) {
  if (x is Map) {
    final ks = x.keys.map((k) => '$k').toList()..sort();
    return {for (final k in ks) k: canon(x[k])};
  }
  if (x is List) return x.map(canon).toList();
  return x;
}

String cj(Object? x) => jsonEncode(canon(jsonDecode(jsonEncode(x))));

class Audit {
  Audit(this.seed) : r = Random(seed);
  final int seed;
  final Random r;
  late DateTime jetzt;
  late Taper t;
  final log = <String>[];
  final zaehler = <String, int>{};
  int pruefungen = 0;

  TaperState get s => t.st;
  String get heute => t.today;

  void merke(String was) {
    log.add('$heute ${jetzt.hour}:${jetzt.minute.toString().padLeft(2, '0')}  $was');
    final k = was.split(' ').first;
    zaehler[k] = (zaehler[k] ?? 0) + 1;
  }

  Never fehler(String m) =>
      fail('Seed $seed, $heute: $m\nLetzte Schritte:\n${log.reversed.take(15).toList().reversed.join('\n')}');

  // ---------------------------------------------------------------- unabhängige Rechnung

  int need(int i) {
    final d = s.days;
    return (d != null && i < d.length && d[i] > 0) ? d[i] : s.target;
  }

  /// Plan-Dosis für einen künftigen Tag k (> heute). null bei offenen Tagen (außer [trotzOffen]: offene Tage
  /// verschieben den Plan nicht, der Vorrat rechnet darum mit der echten Planposition).
  double? soll(String k, {bool trotzOffen = false}) {
    if (s.frz != null && !trotzOffen) return null;
    final last = s.plan.length - 1;
    var sg = s.stage;
    var start = s.stageStart!;
    if (s.hold) {
      if (s.holdUntil == null || k.compareTo(s.holdUntil!) < 0) return s.plan[sg];
      start = addD(start, dBetween(s.holdSince!, s.holdUntil!));
      // Eine beim Halten schon abgelaufene Stufe endet frühestens am Halte-Ende.
      if (sg < last && addD(start, need(sg)).compareTo(s.holdUntil!) < 0) start = addD(s.holdUntil!, -need(sg));
    }
    while (sg < last && k.compareTo(addD(start, need(sg))) >= 0) {
      start = addD(start, need(sg));
      sg++;
    }
    return s.plan[sg];
  }

  /// Erster Tag der letzten Stufe (voraussichtlich), unabhängig.
  String? ende() {
    if (s.frz != null) return null;
    final last = s.plan.length - 1;
    if (last <= 0) return null;
    var k = s.stageStart!;
    if (s.hold) k = addD(k, max(0, dBetween(s.holdSince!, s.holdUntil ?? heute)));
    for (var i = s.stage; i < last; i++) {
      k = addD(k, need(i));
      if (i == s.stage && s.hold && k.compareTo(s.holdUntil ?? heute) < 0) k = s.holdUntil ?? heute;
    }
    if (s.hold && k.compareTo(s.holdUntil ?? heute) < 0) k = s.holdUntil ?? heute;
    return k;
  }

  double avg7(String k) {
    var sum = 0.0, n = 0;
    for (var i = 0; i < 7; i++) {
      final kk = addD(k, -i);
      final e = s.log[kk];
      if (e == null) continue;
      if (kk == heute && e.plan != null && e.dose < e.plan! - 1e-9) continue;
      sum += e.dose;
      n++;
    }
    return n == 0 ? double.nan : sum / n;
  }

  /// Gedächtnis: welche Dosis an einem Tag laut Plan galt – gemerkt, während der Tag lief (eigenes Modell).
  final gesehen = <String, double>{};

  /// Geplante Dosis eines vergangenen Tages ohne Eintrag (für den Vorrat): so, wie sie an dem Tag galt.
  double sollVergangen(String k) =>
      gesehen[k] ??
      (k.compareTo(s.stageStart!) < 0 ? t.planFor(k).plan : (s.hold ? s.plan[s.stage] : soll(k, trotzOffen: true)!));

  /// Reichweite unabhängig: heutiger Rest zuerst, dann Tag für Tag laut Prognose.
  double reichweite(double mg) {
    var rr = mg;
    final he = s.log[heute];
    final rest = (he?.plan ?? (s.hold ? s.plan[s.stage] : soll(heute, trotzOffen: true)!)) - (he?.dose ?? 0);
    if (rest > 0) {
      rr -= rest;
      if (rr < -1e-9) return 0;
    }
    var days = 1;
    var k = heute;
    for (var i = 0; i < 3000; i++) {
      k = addD(k, 1);
      final d = soll(k, trotzOffen: true)!;
      if (!(d > 0)) return double.infinity;
      if (rr < d - 1e-9) break;
      rr -= d;
      days++;
    }
    return days.toDouble();
  }

  // ---------------------------------------------------------------- Prüfungen

  void pruefen() {
    pruefungen++;
    final last = s.plan.length - 1;
    // Zustand
    if (s.plan.isEmpty) fehler('Plan leer');
    if (s.stage < 0 || s.stage > last) fehler('Stufe ${s.stage} außerhalb 0..$last');
    for (var i = 0; i < s.plan.length; i++) {
      if (!(s.plan[i] >= 0) || !s.plan[i].isFinite) fehler('Plan[$i] = ${s.plan[i]}');
      if (need(i) < 1) fehler('Stufe $i: ${need(i)} Tage');
    }
    if (s.stageStart == null) fehler('stageStart fehlt');
    if (s.hold && s.holdSince == null) fehler('Halten ohne Beginn');
    if (!s.hold && (s.holdSince != null || s.holdUntil != null)) fehler('Halte-Reste ohne Halten');
    if (s.hold && s.holdUntil != null && s.holdUntil!.compareTo(heute) <= 0) fehler('Halten über das Ende hinaus');
    if (s.hold && s.frz != null) fehler('Offene Tage während des Haltens');
    if (s.frz != null && s.frz!.compareTo(heute) > 0) fehler('frz in der Zukunft');
    if (s.chg.length > 400) fehler('Änderungsprotokoll > 400');

    // Protokoll
    s.log.forEach((k, e) {
      if (!isDateKey(k)) fehler('Schlüssel $k');
      if (k.compareTo(heute) > 0) fehler('Eintrag in der Zukunft: $k');
      if (e.it.isEmpty) fehler('Leerer Tag $k (verwaist)');
      final sum = round3(e.it.fold<double>(0, (a, x) => a + x.v));
      if ((sum - e.dose).abs() > 1e-9) fehler('$k: Dosis ${e.dose} ≠ Summe $sum');
      if (!e.dose.isFinite) fehler('$k: Dosis ${e.dose}');
      final lapse = e.plan != null && e.dose > e.plan! + 1e-9;
      if ((e.r == 'lapse') != lapse) fehler('$k: Markierung ${e.r}, Dosis ${e.dose}, Plan ${e.plan}');
      for (var i = 1; i < e.it.length; i++) {
        if (e.it[i - 1].t.compareTo(e.it[i].t) > 0) fehler('$k: Einnahmen nicht nach Uhrzeit sortiert');
      }
      for (final x in e.it) {
        if (x.ts > t.nowMs) fehler('$k: Zeitstempel in der Zukunft');
      }
    });

    // Kalender-Prognose + voraussichtliches Ende
    final bis = addD(heute, 60);
    final pm = t.projMap(bis);
    if (s.frz != null) {
      if (pm.map.isNotEmpty) fehler('Prognose trotz offener Tage');
      if (t.voraussichtlichesEnde() != null) fehler('Ende trotz offener Tage');
    } else {
      for (var k = addD(heute, 1); k.compareTo(bis) <= 0; k = addD(k, 1)) {
        final ist = pm.map[k]?.v;
        if (ist != soll(k)) fehler('Kalender $k zeigt $ist, Plan sagt ${soll(k)}');
      }
      final e = ende();
      if (t.voraussichtlichesEnde() != e) fehler('Voraussichtlich ${t.voraussichtlichesEnde()} ≠ $e');
      if (!s.hold && t.planEndNow() != (last > 0 ? e : t.planEndNow())) fehler('planEndNow ≠ Ende');
      // Wechsel auf die letzte Stufe in der Prognose genau am Ende (wenn im Fenster)
      if (e != null &&
          s.stage < last &&
          e.compareTo(heute) > 0 &&
          e.compareTo(bis) <= 0 &&
          !(s.hold && s.holdUntil == null)) {
        if (soll(e) != s.plan[last] || soll(addD(e, -1)) == s.plan[last] && s.plan[last] != s.plan[last - 1]) {
          fehler('Ende $e passt nicht zum Stufenwechsel in der Prognose');
        }
      }
    }

    // Diagramm
    final v = t.verlauf(max: 100000);
    if (v.tage.isEmpty) fehler('Diagramm leer');
    for (var i = 1; i < v.tage.length; i++) {
      if (v.tage[i].tag != addD(v.tage[i - 1].tag, 1)) fehler('Diagramm-Lücke bei ${v.tage[i].tag}');
    }
    if (v.start != v.tage.first.tag || v.bis != v.tage.last.tag) fehler('Diagramm start/bis passt nicht');
    final hi = v.tage.indexWhere((x) => x.tag == heute);
    if (hi < 0) fehler('Heute fehlt im Diagramm');
    for (final x in v.tage) {
      if (!x.zukunft) {
        if (x.dosis != s.log[x.tag]?.dose) fehler('Diagramm ${x.tag}: Dosis ${x.dosis} ≠ ${s.log[x.tag]?.dose}');
        final a = avg7(x.tag);
        final b = x.schnitt7;
        if ((b == null) != a.isNaN || (b != null && (a - b).abs() > 1e-9)) fehler('Ø7 ${x.tag}: $b ≠ $a');
        if (s.log[x.tag]?.plan != null && x.plan != s.log[x.tag]!.plan) fehler('Diagramm ${x.tag}: Plan');
      } else if (x.plan != soll(x.tag)) {
        fehler('Diagramm-Zukunft ${x.tag}: ${x.plan} ≠ ${soll(x.tag)}');
      }
    }
    final e = ende();
    final String erwBis;
    if (s.frz != null || s.stage >= last) {
      erwBis = heute;
    } else if (s.hold && s.holdUntil == null) {
      erwBis = addD(heute, 30);
    } else {
      erwBis = (e != null && e.compareTo(heute) > 0) ? e : addD(heute, 30);
    }
    if (v.bis != erwBis) fehler('Diagramm endet ${v.bis}, erwartet $erwBis');

    // Vorrat
    final sk = s.stock;
    final si = t.stockInfo();
    if (sk == null) {
      if (si != null) fehler('Vorrat ohne Zählung');
    } else {
      var used = 0.0;
      s.log.forEach((k, e) {
        for (final x in e.it) {
          if (x.ts > sk.ts) used += x.v;
        }
      });
      // Tage ohne Eintrag seit dem Zähltag (ab Planstart, bis gestern): geplante Dosis.
      var ohne = 0;
      for (var k = sk.day.compareTo(s.t0!) > 0 ? sk.day : s.t0!; k.compareTo(heute) < 0; k = addD(k, 1)) {
        if (s.log[k] == null) {
          used += sollVergangen(k);
          ohne++;
        }
      }
      final rem = round3(sk.mg - used);
      if ((si!.rem - rem).abs() > 1e-6) {
        // Welche Tage ohne Eintrag anders geschätzt werden (eigenes Modell gegen Kern).
        final ab = [
          for (var k = sk.day.compareTo(s.t0!) > 0 ? sk.day : s.t0!; k.compareTo(heute) < 0; k = addD(k, 1))
            if (s.log[k] == null && (sollVergangen(k) - t.sollAm(k)).abs() > 1e-9)
              '$k: ${sollVergangen(k)} ≠ Kern ${t.sollAm(k)}'
        ];
        fehler('Vorrat-Rest ${si.rem} ≠ $rem  $ab');
      }
      if (si.geschaetzt != ohne) fehler('Vorrat: ${si.geschaetzt} geschätzte Tage ≠ $ohne');
      {
        final w = reichweite(si.rem);
        if (si.days != w) {
          fehler('Vorrat-Reichweite ${si.days} ≠ $w (Rest ${si.rem}, Stufe ${s.stage} ${s.plan}, '
              'Tag ${t.stageDay()}/${need(s.stage)}, Start ${s.stageStart}, Halten ${s.holdSince}–${s.holdUntil}, '
              'heute ${s.log[heute]?.dose})');
        }
      }
    }

    // Neustart: JSON hin und zurück → gleicher Zustand, gleiche Anzeigen
    final vorher = cj(t.exportJson());
    final t2 = Taper(s: TaperState.fromJson(jsonDecode(jsonEncode(t.exportJson()))), clock: () => jetzt);
    // Einzige bekannte Ausnahme (gewolltes Verhalten): frzFloor wird beim Laden nachgezogen, wenn er
    // fehlt (_migT0). Verhalten bleibt gleich – geprüft über frz/Stufentag/offene Tage unten.
    final j2 = t2.exportJson()!;
    if (s.frzFloor == null && j2['frzFloor'] == s.stageStart) j2['frzFloor'] = null;
    final nachher = cj(j2);
    if (vorher != nachher) fehler('Neustart ändert den Zustand:\n$vorher\n$nachher');
    if (t2.voraussichtlichesEnde() != t.voraussichtlichesEnde()) fehler('Neustart: anderes Ende');
    // Wirksamer Stillstand: vor dem Stufenbeginn ist gleichbedeutend mit dem Stufenbeginn (Stufentag 0,
    // kein Weiterschalten). frzFloor null vs. beim Laden nachgezogen ändert daher nichts am Verhalten.
    String? eff(String? x, String start) => x == null ? null : (x.compareTo(start) < 0 ? start : x);
    if (eff(t2.st.frz, t2.st.stageStart!) != eff(s.frz, s.stageStart!) ||
        eff(t2.firstFrz(heute), t2.st.stageStart!) != eff(t.firstFrz(heute), s.stageStart!)) {
      fehler(
          'Neustart: andere offene Tage/frz: frz ${s.frz}→${t2.st.frz}, first ${t.firstFrz(heute)}→${t2.firstFrz(heute)}, '
          'floor ${s.frzFloor}→${t2.st.frzFloor}, Stufe ${s.stage}/${s.plan.length}, Start ${s.stageStart}, '
          'offen ${t.openDays().where((k) => k.compareTo(addD(heute, -20)) > 0).toList()}');
    }
    if (t2.stageDay() != t.stageDay()) fehler('Neustart: anderer Stufentag');
    if (cj(t2.stockInfo()?.rem) != cj(t.stockInfo()?.rem) || t2.stockInfo()?.days != t.stockInfo()?.days) {
      fehler('Neustart: anderer Vorrat');
    }
    if (t2.openDays().join() != t.openDays().join()) fehler('Neustart: andere offene Tage');
    final v2 = t2.verlauf(max: 100000);
    if (v2.bis != v.bis || v2.tage.length != v.tage.length) fehler('Neustart: anderes Diagramm');
    // refresh idempotent
    t.refresh();
    if (cj(t.exportJson()) != vorher) fehler('refresh() ändert den Zustand ohne Grund');
  }

  // ---------------------------------------------------------------- Aktionen

  int nextIn() => max(1, need(s.stage) - t.stageDay());

  void tag([int n = 1]) {
    // Die übersprungenen Tage laufen mit dem jetzigen Plan (offene Tage verschieben ihn nicht).
    for (var i = 0; i < n; i++) {
      final k = addD(heute, i);
      gesehen[k] = soll(k, trotzOffen: true)!;
    }
    final h = [0, 1, 7, 9, 12, 18, 23][r.nextInt(7)];
    final m = h == 23 ? 59 : (h == 0 ? 1 : r.nextInt(60));
    jetzt = DateTime.utc(jetzt.year, jetzt.month, jetzt.day + n, h, m);
    t.refresh();
    merke('Tag +$n');
  }

  void zeit() {
    final h = jetzt.hour + 1 + r.nextInt(5);
    if (h > 23) return;
    jetzt = DateTime.utc(jetzt.year, jetzt.month, jetzt.day, h, r.nextInt(60));
    t.refresh();
  }

  String? uhr() => r.nextInt(3) == 0
      ? null
      : '${r.nextInt(24).toString().padLeft(2, '0')}:${r.nextInt(60).toString().padLeft(2, '0')}';

  double menge() {
    final p = s.plan[s.stage];
    switch (r.nextInt(6)) {
      case 0:
        return round3(p / 2);
      case 1:
        return round3(p + [0.25, 0.5, 1, 2.5][r.nextInt(4)]);
      case 2:
        return 0;
      default:
        return p;
    }
  }

  void schritt() {
    final last = s.plan.length - 1;
    final w = r.nextInt(100);
    if (w < 30) {
      // heute eintragen (wie geplant oder abweichend)
      final v = menge();
      final res = t.addIntake(v, t: uhr(), force: true);
      merke('Einnahme $v → $res');
    } else if (w < 38) {
      // nachtragen bis 7 Tage zurück
      final k = addD(heute, -(1 + r.nextInt(9)));
      final v = round3(t.planFor(k).plan * [1.0, 0.5, 1.25][r.nextInt(3)]);
      final res = t.addIntake(v, t: uhr(), k: k, force: true);
      merke('Nachtragen $k $v → $res');
    } else if (w < 43) {
      // Einnahme löschen (heute oder im Tag-Fenster bis 7 Tage zurück)
      final ks = s.log.keys.where((k) => t.daysAgo(k) <= 7).toList()..sort();
      if (ks.isEmpty) return;
      final k = ks[r.nextInt(ks.length)];
      final n = t.dayIt(s.log[k]!).length;
      t.delIntake(r.nextInt(n), k);
      merke('Löschen $k');
    } else if (w < 46) {
      zeit();
    } else if (w < 50) {
      // Lücken schließen: bis 7 Tage nachtragen, ältere „Weiß ich nicht mehr“
      for (final k in t.openDays()) {
        if (t.daysAgo(k) <= 7) t.addIntake(t.planFor(k).plan, k: k, force: true);
      }
      if (t.openDays().any((k) => t.daysAgo(k) > 7)) {
        t.markUnk();
        merke('WeißNicht');
      }
      merke('Lücken');
    } else if (w < 60) {
      // Wie in der App: Halten gibt es nur auf der Dosis-Karte (nicht bei offenen Tagen, nicht auf der letzten Stufe).
      if (!s.hold && s.stage < last && s.frz == null) {
        final n = r.nextInt(3) == 0 ? null : 1 + r.nextInt(20);
        t.startHold(n);
        merke('Halten ${n ?? 'offen'}');
      } else if (s.hold && r.nextBool()) {
        t.stopHold();
        merke('Weiter');
      }
    } else if (w < 66) {
      if (!s.hold && s.stage < last && s.frz == null) {
        final ni = nextIn();
        if (r.nextBool() && ni > 1) {
          final res = t.saveLeft(1 + r.nextInt(ni - 1));
          merke('Kürzer → $res');
        } else {
          final res = t.saveLeft(ni + 1 + r.nextInt(10), why: 'zu schnell');
          merke('Länger → $res');
        }
      }
    } else if (w < 69) {
      if (s.pend != null) {
        if (t.pendLeftMs() <= 0 && r.nextBool()) {
          final ed = t.usePend();
          if (ed != null) {
            final res = t.applyPlan(ed..conf = 'Ich bin mir sicher');
            merke('Vormerkung Plan → ${res.applied}');
          } else {
            merke('Vormerkung Stufe übernommen');
          }
        } else if (r.nextInt(3) == 0) {
          t.dropPend();
          merke('Vormerkung verworfen');
        }
      }
    } else if (w < 72) {
      neuerPlan();
    } else if (w < 75) {
      final anz = [0.5, 10.0, 28.0, 100.0, 3.0][r.nextInt(5)];
      final st = [1.0, 2.0, 5.0, 10.0, 0.5][r.nextInt(5)];
      final add = r.nextBool();
      t.setStock(anz, st, add: add);
      merke('Vorrat ${anz * st}${add ? ' dazu' : ''}');
    } else if (w < 76) {
      t.saveTabs(<double>[5, 2, 1].sublist(r.nextInt(3)), [1.0, 0.5, 0.25][r.nextInt(3)], r.nextBool() ? 1 : null);
      merke('Tabletten');
    } else if (w < 78) {
      final k = addD(heute, -r.nextInt(5));
      if (r.nextBool()) {
        t.toggleGood(k);
      } else {
        t.saveNote(k, Note(sym: r.nextInt(6), text: r.nextBool() ? 'Kaffee' : ''));
      }
      merke('Notiz/gut $k');
    } else if (w < 82) {
      // Neustart der App
      t = Taper(s: TaperState.fromJson(jsonDecode(jsonEncode(t.exportJson()))), clock: () => jetzt);
      merke('Neustart');
    } else if (w < 84) {
      // Sicherung laden (eigene Sicherung)
      final j = jsonDecode(jsonEncode(t.exportJson()));
      expect(t.importJson(j), isTrue);
      merke('SicherungLaden');
    } else if (w < 95) {
      tag();
    } else {
      // Tage vergessen
      tag(2 + r.nextInt(r.nextInt(4) == 0 ? 12 : 4));
    }
  }

  void neuerPlan() {
    final ed = t.openEditor();
    final art = r.nextInt(5);
    if (art == 0) {
      // schneller: Tage der Stufen kürzen
      for (final row in ed.rows) {
        row.days = max(1, (row.days ?? 14) - 3);
      }
    } else if (art == 1) {
      // langsamer: Tage verlängern
      for (final row in ed.rows) {
        row.days = (row.days ?? 14) + 4;
      }
    } else if (art == 2) {
      t.editCalc(ed,
          dose: s.plan[s.stage], step: [0.5, 1.0, 0.25][r.nextInt(3)], minStep: 0.25, days: 3 + r.nextInt(12), goal: 0);
    } else if (art == 3) {
      // andere Startstufe
      ed.start = r.nextInt(ed.rows.length);
    } else {
      // Dosis der aktuellen Stufe ändern
      ed.rows[min(ed.start, ed.rows.length - 1)].dose = round3(s.plan[s.stage] * [0.9, 1.1][r.nextInt(2)]);
    }
    ed.conf = 'Ich bin mir sicher';
    var res = t.applyPlan(ed);
    if (res.askWhy) {
      ed.why = 'brauche mehr Zeit';
      res = t.applyPlan(ed);
    }
    merke('Plan art$art → applied ${res.applied} pended ${res.pended} err ${res.err}');
  }

  void start() {
    final y = [2026, 2027, 2028][r.nextInt(3)]; // 2028 = Schaltjahr
    final mo = [1, 2, 3, 10, 12][r.nextInt(5)];
    final d = mo == 2 ? 20 + r.nextInt(9) : 1 + r.nextInt(28);
    jetzt = DateTime.utc(y, mo, d, 9);
    t = Taper(clock: () => jetzt);
    gesehen.clear();
    final art = r.nextInt(10);
    if (art < 5) {
      final dose = [10.0, 20.0, 6.0, 30.0, 2.5][r.nextInt(5)];
      final step = [0.5, 1.0, 2.0, 2.5, 0.125][r.nextInt(5)];
      final goal = r.nextInt(4) == 0 ? round3(dose / 2) : 0.0;
      final err =
          t.setup(dose: dose, step: step, minStep: step < 0.25 ? 0.125 : 0.25, days: 3 + r.nextInt(12), goal: goal);
      if (err != null) fehler('setup: $err');
      merke('Setup $dose step $step goal $goal');
    } else {
      // Import/Abtippen: frei gewählte Stufen (1 Stufe, viele Stufen, krumme Tage)
      final n = [1, 2, 3, 8, 40][r.nextInt(5)];
      final rows = <EditRow>[];
      var d = [10.0, 7.5, 1.0][r.nextInt(3)];
      for (var i = 0; i < n; i++) {
        rows.add(EditRow(round3(i == n - 1 && n > 1 ? 0 : d), 1 + r.nextInt(21)));
        d = round3(max(0, d - d / n));
      }
      final ed = t.openEditor(neu: true)..rows = rows;
      final res = t.applyPlan(ed);
      if (!res.applied) fehler('Import: ${res.err}');
      merke('Import $n Stufen');
    }
    if (r.nextBool()) t.saveTabs([5, 2], 0.5, null);
  }

  void lauf(int schritte) {
    start();
    pruefen();
    for (var i = 0; i < schritte; i++) {
      try {
        schritt();
      } on TestFailure {
        rethrow;
      } catch (e, st) {
        fehler('Ausnahme: $e\n$st');
      }
      pruefen();
    }
  }
}

void main() {
  test('Audit: 150 Szenarien, nach jedem Schritt alles unabhängig nachgerechnet', () {
    var pruef = 0;
    final gesamt = <String, int>{};
    for (var seed = 1; seed <= 150; seed++) {
      final a = Audit(seed)..lauf(80 + (seed % 5) * 40);
      pruef += a.pruefungen;
      a.zaehler.forEach((k, v) => gesamt[k] = (gesamt[k] ?? 0) + v);
    }
    print('Audit: $pruef Zustände geprüft · Aktionen: $gesamt');
    for (final w in [
      'Einnahme',
      'Nachtragen',
      'Löschen',
      'WeißNicht',
      'Lücken',
      'Halten',
      'Weiter',
      'Kürzer',
      'Länger',
      'Vormerkung',
      'Plan',
      'Vorrat',
      'Neustart',
      'SicherungLaden',
      'Tag',
      'Import',
      'Setup'
    ]) {
      expect(gesamt[w] ?? 0, greaterThan(0), reason: '„$w“ kam nie vor');
    }
  });
}
