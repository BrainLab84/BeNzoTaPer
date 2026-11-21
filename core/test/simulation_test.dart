// Simulation: viele zufällige Verläufe über Monate. Nach jedem Tag wird geprüft, ob sich der Plan
// richtig anpasst – unabhängig vom Code nachgerechnet, nicht aus dem Kern abgeschrieben:
//  • Halten verschiebt das Planende um genau die gehaltenen Tage.
//  • Vergessene Tage (?) und Ausrutscher verschieben den Plan nie.
//  • Stufe kürzen wirkt sofort, verlängern erst nach 48 h – dann um genau die Differenz.
//  • Neuer Plan: schneller sofort, langsamer erst nach 48 h; Ende passt zum neuen Plan.
//  • Prognose (Kalender), Diagramm (Fortschritt) und Planende stimmen überein.
//  • 7-Tage-Ø zählt nur eingetragene Tage; der laufende Tag zählt erst, wenn er voll ist.
//  • Vorrat: Rest = gezählt − Einnahmen danach.
import 'dart:math';

import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

class Sim {
  Sim(this.seed) : r = Random(seed);
  final int seed;
  final Random r;
  late DateTime jetzt;
  late Taper t;

  /// Erwartetes Planende (unabhängig mitgeführt).
  late String erwEnde;
  String? haltenSeit;
  bool neuSync = false;
  final protokoll = <String>[];
  int lastStage = 0;
  int pruefungen = 0;
  final zaehler = <String, int>{};

  String get heute => t.today;
  TaperState get s => t.st;

  void merke(String was) {
    protokoll.add('$heute: $was');
    zaehler[was.split(' ').first] = (zaehler[was.split(' ').first] ?? 0) + 1;
  }

  void fehler(String m) => fail('Seed $seed, $heute: $m\nLetzte Schritte:\n${protokoll.reversed.take(12).join('\n')}');

  /// Planende unabhängig nachgerechnet: Beginn der letzten Stufe.
  String ende(List<double> plan, List<int> days, int stage, String start) {
    var k = start;
    for (var i = stage; i < plan.length - 1; i++) {
      k = addD(k, days[i]);
    }
    return k;
  }

  List<int> tageListe() => [for (var i = 0; i < s.plan.length; i++) t.need(i)];

  void start() {
    jetzt = DateTime.utc(2026, 1, 5, 9);
    t = Taper(clock: () => jetzt);
    final dosis = [10.0, 20.0, 6.0, 30.0][r.nextInt(4)];
    final schritt = [0.5, 1.0, 2.0, 2.5][r.nextInt(4)];
    final tage = [7, 10, 14][r.nextInt(3)];
    expect(t.setup(dose: dosis, step: schritt, minStep: 0.5, days: tage, goal: 0), isNull);
    if (r.nextBool()) t.saveTabs([5, 2], 0.5, null);
    erwEnde = ende(s.plan, tageListe(), 0, heute);
    merke('Start $dosis mg, $schritt mg alle $tage Tage, ${s.plan.length} Stufen');
  }

  double get planHeute => s.plan[s.stage];

  void tagAblauf() {
    final x = r.nextDouble();
    final frei = s.frz == null;
    // Plan-Aktionen (selten)
    if (!s.hold && r.nextDouble() < .03) {
      final n = r.nextDouble() < .3 ? null : 1 + r.nextInt(20);
      expect(t.startHold(n), isTrue);
      haltenSeit = heute;
      merke('Halten ${n ?? 'ohne Ende'}');
    } else if (s.hold && r.nextDouble() < .1) {
      final seit = s.holdSince!;
      t.stopHold();
      // Der Plan verschiebt sich um genau die gehaltenen Tage.
      if (!neuSync) erwEnde = addD(erwEnde, dBetween(seit, heute));
      merke('Halten beendet nach ${dBetween(seit, heute)} Tagen');
    } else if (!s.hold && frei && s.stage < s.plan.length - 1 && r.nextDouble() < .03) {
      _stufeAendern();
    } else if (r.nextDouble() < .012) {
      _neuerPlan();
    }
    // Vormerkung nach 48 h übernehmen
    final p = s.pend;
    if (p != null) {
      if (t.pendLeftMs() > 0) {
        // vor Ablauf darf die Oberfläche „Übernehmen“ nicht zeigen – Engine liefert die Restzeit
        if (t.pendLeftMs() > waitMs) fehler('Bedenkzeit länger als 48 h');
      } else if (r.nextDouble() < .5) {
        _vormerkungUebernehmen();
      } else if (r.nextDouble() < .1) {
        t.dropPend();
        merke('Vormerkung verworfen');
      }
    }

    // Einnahme
    if (x < .07) {
      merke('vergessen');
    } else if (x < .12) {
      final v = planHeute + [0.5, 1, 2, 5][r.nextInt(4)];
      t.addIntake(v, force: true);
      merke('Ausrutscher $v');
    } else if (x < .16) {
      final h = (planHeute / 2 * 4).round() / 4;
      if (h > 0) t.addIntake(h, force: true);
      if (r.nextBool() && planHeute - h > 0) t.addIntake(planHeute - h, force: true);
      merke('aufgeteilt');
    } else if (x < .18 && planHeute > 0.5) {
      t.addIntake(planHeute - 0.5, force: true);
      merke('weniger');
    } else {
      t.addIntake(planHeute, force: true);
    }

    // Vergessene Tage nachtragen (bis 7 Tage zurück) oder „weiß ich nicht mehr“
    final offen = t.openDays();
    if (offen.isNotEmpty && r.nextDouble() < .5) {
      for (final k in offen) {
        if (t.daysAgo(k) <= 7 && r.nextDouble() < .8) {
          final pf = t.planFor(k).plan;
          t.addIntake(pf, k: k, force: true);
          merke('nachgetragen $k');
        }
      }
    }
    if (t.openDays().any((k) => t.daysAgo(k) > 7) && r.nextDouble() < .5) {
      t.markUnk();
      merke('weiß-nicht-mehr');
    }
    pruefen();
  }

  void _stufeAendern() {
    final alt = t.need(s.stage);
    final tag = t.stageDay();
    final n = 1 + r.nextInt(alt + 10);
    final nd = tag + n;
    final res = t.saveLeft(n, why: 'Simulation');
    if (nd == alt) {
      expect(res, LeftResult.unchanged);
    } else if (nd < alt) {
      if (res != LeftResult.applied) fehler('kürzer muss sofort gelten: $res');
      erwEnde = addD(erwEnde, nd - alt);
      merke('Stufe kürzer $alt→$nd');
    } else {
      if (res != LeftResult.pended) fehler('länger nur mit Bedenkzeit: $res');
      if (t.need(s.stage) != alt) fehler('länger darf nicht sofort gelten');
      merke('Stufe länger vorgemerkt $alt→$nd');
    }
  }

  void _neuerPlan() {
    final e = t.openEditor(neu: true);
    final langsamer = r.nextBool();
    // Mal ab der heutigen Dosis (Stufenbeginn bleibt), mal gleich eine Stufe tiefer (Neustart heute).
    final d = planHeute > 1 && r.nextBool() ? planHeute - 0.5 : (planHeute > 0 ? planHeute : 1.0);
    final schritt = langsamer ? 0.5 : 1.0;
    final tage = langsamer ? 21 : 7;
    t.editCalc(e, dose: d, step: schritt, minStep: 0.5, days: tage, goal: 0);
    e.conf = 'Ich bin mir sicher';
    final neu = [for (final x in e.rows) x.dose!];
    final neuTage = [for (final x in e.rows) x.days!];
    final keep = (neu.first - planHeute).abs() < 1e-9;
    final vorher = List<double>.from(s.plan);
    // Unabhängig: Ist der neue Plan langsamer? (Dosis rauf, höheres Ziel oder späteres Ende)
    final altEnde = ende(s.plan, tageListe(), s.stage, t.stageStart);
    final neuStart = keep ? t.stageStart : heute;
    final neuEnde = ende(neu, neuTage, 0, neuStart);
    final langsam = neu.first > planHeute + 1e-9 || neu.last > s.plan.last + 1e-9 || neuEnde.compareTo(altEnde) > 0;
    final res = t.applyPlan(e);
    if (res.askWhy) {
      if (!langsam) fehler('schnellerer Plan darf keine Bedenkzeit brauchen');
      e.why = 'Simulation langsamer';
      final r2 = t.applyPlan(e);
      if (!r2.pended) fehler('langsamer muss vorgemerkt werden');
      if (!_gleich(s.plan, vorher)) fehler('vorgemerkter Plan darf noch nicht gelten');
      merke('Plan langsamer vorgemerkt');
      return;
    }
    if (langsam) fehler('langsamer Plan ohne 48 h Bedenkzeit übernommen');
    if (!res.applied) fehler('Plan nicht übernommen: ${res.err}');
    if (!_gleich(s.plan, neu)) fehler('neuer Plan nicht übernommen');
    erwEnde = neuEnde;
    lastStage = s.stage; // neuer Plan fängt bei Stufe 1 an
    merke('Plan neu (schneller) ${s.plan.length} Stufen, keep=$keep');
  }

  void _vormerkungUebernehmen() {
    final p = s.pend!;
    if (p.kind == 'left') {
      final alt = t.need(s.stage);
      final gleicheStufe = p.stage == s.stage;
      t.usePend();
      if (gleicheStufe && p.nd! > alt) {
        if (t.need(s.stage) != p.nd) fehler('Verlängerung nicht übernommen');
        erwEnde = addD(erwEnde, p.nd! - alt);
      }
      merke('Verlängerung übernommen');
    } else {
      final e = t.usePend()!;
      e.conf = 'Ich bin mir sicher';
      final res = t.applyPlan(e);
      if (!res.applied) fehler('vorgemerkter Plan nicht übernommen: ${res.err}');
      merke('Plan-Vormerkung übernommen');
      neuSync = true;
    }
  }

  static bool _gleich(List<double> a, List<double> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) (a[i] - b[i]).abs() < 1e-9].every((x) => x);

  void naechsterTag() {
    jetzt = jetzt.add(const Duration(days: 1));
    final warHalten = s.hold;
    final seit = s.holdSince;
    final bis = s.holdUntil;
    t.refresh();
    if (warHalten && !s.hold) {
      // automatisch beendet
      if (!neuSync) erwEnde = addD(erwEnde, dBetween(seit!, bis!));
      merke('Halten automatisch beendet');
    }
  }

  /// Prüft alle Regeln für den aktuellen Tag.
  void pruefen() {
    pruefungen++;
    final a = s;
    if (neuSync && !a.hold) {
      erwEnde = t.planEndNow()!;
      neuSync = false;
      lastStage = a.stage;
    }
    if (a.stage < lastStage && !neuSync) fehler('Stufe ging zurück: $lastStage → ${a.stage}');
    lastStage = a.stage;

    // 1) Planende: dynamisch angepasst, aber nur durch Halten/Ändern/neuen Plan
    // 1a) Beim Halten: voraussichtlich = Ende vor dem Halten + Halte-Tage (bis Enddatum bzw. bis heute)
    if (a.hold && !neuSync && a.frz == null && a.plan.length > 1) {
      final d = dBetween(a.holdSince!, a.holdUntil ?? heute);
      var soll = addD(erwEnde, d < 0 ? 0 : d);
      // Frühestens am Halte-Ende bzw. heute (Halten auf einer überfälligen Stufe)
      final frueh = a.holdUntil ?? heute;
      if (soll.compareTo(frueh) < 0) soll = frueh;
      if (t.voraussichtlichesEnde() != soll) fehler('Halten: voraussichtlich ${t.voraussichtlichesEnde()} ≠ $soll');
    }
    if (!a.hold && !neuSync) {
      final ist = t.planEndNow();
      if (ist != erwEnde) fehler('Planende $ist, erwartet $erwEnde');
      final unabh = ende(a.plan, tageListe(), a.stage, t.stageStart);
      if (unabh != ist) fehler('Planende unabhängig $unabh ≠ $ist');
      if (a.frz == null && t.voraussichtlichesEnde() != (a.plan.length > 1 ? ist : null)) {
        fehler('Voraussichtlich ${t.voraussichtlichesEnde()} ≠ Planende $ist');
      }
      if (a.frz == null) {
        final pm = t.projMap(heute);
        if (pm.end != (a.plan.length > 1 ? ist : null)) fehler('Kalender-Ende ${pm.end} ≠ $ist');
      }
    }

    // 2) Stufe passt zum Datum (ohne Halten und ohne offene Tage)
    if (!a.hold && a.frz == null && a.stage < a.plan.length - 1) {
      final d = dBetween(t.stageStart, heute);
      if (d < 0 || d >= t.need(a.stage)) fehler('Stufe ${a.stage} überfällig/zu früh: Tag $d von ${t.need(a.stage)}');
    }

    // 2b) Offene Tage: Die Stufe bleibt beim ersten offenen Tag stehen (Anzeigen pausieren),
    //     läuft also nicht still weiter.
    if (!a.hold && a.frz != null && a.stage < a.plan.length - 1) {
      final d = dBetween(t.stageStart, a.frz!);
      if (d < 0 || d >= t.need(a.stage)) fehler('Offene Tage: Stufe ${a.stage} passt nicht zum Stand ${a.frz}');
    }

    // 3) Diagramm (Fortschritt) = Protokoll + Prognose
    final v = t.verlauf();
    if (!v.tage.any((x) => x.tag == heute)) fehler('Heute fehlt im Diagramm');
    for (var i = 1; i < v.tage.length; i++) {
      if (v.tage[i].tag != addD(v.tage[i - 1].tag, 1)) fehler('Diagramm-Tage nicht lückenlos');
    }
    if (v.start != v.tage.first.tag || v.bis != v.tage.last.tag) fehler('Diagramm-Grenzen falsch');
    final pm = t.projMap(v.bis);
    for (final x in v.tage) {
      if (!x.zukunft) {
        if (x.tag.compareTo(heute) > 0) fehler('Vergangenheit nach heute');
        final e = a.log[x.tag];
        if (e != null) {
          if (x.dosis != e.dose) fehler('Diagramm-Dosis ${x.tag}');
          if (x.plan != e.plan) fehler('Diagramm-Plan ${x.tag}');
        } else if (x.dosis != null) {
          fehler('? als Dosis gezeichnet');
        }
        // 7-Tage-Ø unabhängig: nur eingetragene, laufender Tag erst wenn voll
        var sum = 0.0, n = 0;
        for (var j = 0; j < 7; j++) {
          final k = addD(x.tag, -j);
          final e2 = a.log[k];
          if (e2 == null) continue;
          if (k == heute && e2.dose < (e2.plan ?? 0) - 1e-9) continue;
          sum += e2.dose;
          n++;
        }
        final erw = n > 0 ? sum / n : null;
        if (erw == null ? x.schnitt7 != null : (x.schnitt7 == null || (x.schnitt7! - erw).abs() > 1e-9)) {
          fehler('7-Tage-Ø ${x.tag}: ${x.schnitt7} ≠ $erw');
        }
      } else {
        if (x.plan != pm.map[x.tag]?.v) fehler('Diagramm-Zukunft ${x.tag} ≠ Kalender');
      }
    }
    if (a.frz != null && v.tage.any((x) => x.zukunft)) fehler('offene Tage: keine Zukunft zeichnen');
    if (!a.hold && a.frz == null && a.stage < a.plan.length - 1) {
      if (v.bis != t.planEndNow()) fehler('Diagramm endet ${v.bis}, Plan ${t.planEndNow()}');
      if (v.tage.last.plan != a.plan.last) fehler('Diagramm endet nicht beim Ziel');
    }
    if (a.hold && a.frz == null) {
      // Bis zum Halte-Ende die gehaltene Dosis (danach laut Plan – oben gegen den Kalender geprüft)
      for (final x in v.tage.where((x) => x.zukunft && (a.holdUntil == null || x.tag.compareTo(a.holdUntil!) < 0))) {
        if (x.plan != a.plan[a.stage]) fehler('Halten: Zukunft muss die gehaltene Dosis sein');
      }
    }

    // 4) Prognose unabhängig: Stufenwechsel genau an den Stufengrenzen
    if (!a.hold && a.frz == null) {
      var st = a.stage;
      var beginn = t.stageStart;
      var k = addD(heute, 1);
      final pm60 = t.projMap(addD(heute, 60)).map;
      for (var i = 0; i < 60; i++) {
        while (st < a.plan.length - 1 && dBetween(beginn, k) >= t.need(st)) {
          beginn = addD(beginn, t.need(st));
          st++;
        }
        final p = pm60[k];
        if (p == null || (p.v - a.plan[st]).abs() > 1e-9) fehler('Prognose $k: ${p?.v} ≠ ${a.plan[st]}');
        if (p!.ch != (k == beginn && st > a.stage)) fehler('Stufenwechsel-Markierung $k');
        k = addD(k, 1);
      }
    }

    // 5) Vorrat
    final sk = a.stock;
    if (sk != null) {
      var used = 0.0;
      a.log.forEach((k, e) {
        if (e.it.isNotEmpty) {
          for (final i in e.it) {
            if (i.ts > sk.ts) used += i.v;
          }
        } else if (k.compareTo(sk.day) > 0) {
          used += e.dose;
        }
      });
      final si = t.stockInfo()!;
      if ((si.rem - (sk.mg - used)).abs() > 1e-6) fehler('Vorrat-Rest ${si.rem} ≠ ${sk.mg - used}');
    }
  }
}

void main() {
  test('Simulation: 60 Verläufe × 300 Tage – Plan passt sich richtig an', () {
    final gesamt = <String, int>{};
    var tage = 0;
    for (var seed = 1; seed <= 60; seed++) {
      final sim = Sim(seed)..start();
      // Vorrat setzen, damit auch der mitläuft
      if (sim.s.tabs != null) {
        sim.t.setStock(40, sim.s.tabs!.str.first);
      }
      for (var d = 0; d < 300; d++) {
        sim.tagAblauf();
        sim.naechsterTag();
        sim.pruefen();
        tage++;
        if (sim.s.stage >= sim.s.plan.length - 1 && !(sim.s.plan.last > 0) && d > 120) break;
      }
      sim.zaehler.forEach((k, v) => gesamt[k] = (gesamt[k] ?? 0) + v);
    }
    // Abdeckung: alle Ereignisse kamen wirklich vor
    for (final w in [
      'Halten',
      'vergessen',
      'Ausrutscher',
      'nachgetragen',
      'weiß-nicht-mehr',
      'Stufe',
      'Plan',
      'Verlängerung',
      'aufgeteilt',
    ]) {
      expect(gesamt[w] ?? 0, greaterThan(0), reason: 'Ereignis „$w“ kam in der Simulation nie vor');
    }
    print('Simuliert: $tage Tage, Ereignisse: $gesamt');
  });

  test('Halten: Ende verschiebt sich um genau die gehaltenen Tage (fest, ohne Zufall)', () {
    var jetzt = DateTime.utc(2026, 1, 5, 9);
    final t = Taper(clock: () => jetzt);
    t.setup(dose: 10, step: 1, minStep: 0.5, days: 7, goal: 0);
    final e0 = t.planEndNow()!;
    void tag() {
      t.addIntake(t.st.plan[t.st.stage], force: true);
      jetzt = jetzt.add(const Duration(days: 1));
      t.refresh();
    }

    for (var i = 0; i < 10; i++) {
      tag();
    }
    t.startHold(5);
    for (var i = 0; i < 5; i++) {
      expect(t.planEndNow(), isNull);
      expect(t.voraussichtlichesEnde(), addD(e0, 5), reason: 'mit Enddatum steht das Ende gleich fest');
      tag();
    }
    expect(t.st.hold, isFalse);
    expect(t.planEndNow(), addD(e0, 5));
    t.startHold(null);
    for (var i = 0; i < 9; i++) {
      expect(t.voraussichtlichesEnde(), addD(e0, 5 + i), reason: 'ohne Enddatum rückt es täglich mit');
      tag();
    }
    expect(t.voraussichtlichesEnde(), addD(e0, 14));
    t.stopHold();
    expect(t.planEndNow(), addD(e0, 14));
    // Vergessene Tage: kein Verschieben
    jetzt = jetzt.add(const Duration(days: 3));
    t.refresh();
    expect(t.st.frz, isNotNull);
    expect(t.planEndNow(), addD(e0, 14));
    for (final k in t.openDays()) {
      t.addIntake(t.planFor(k).plan, k: k, force: true);
    }
    t.refresh();
    expect(t.st.frz, isNull);
    expect(t.planEndNow(), addD(e0, 14));
  });

  test('Vorrat beim Halten mit Enddatum: danach weiter laut Plan', () {
    var jetzt = DateTime.utc(2026, 1, 5, 9);
    final t = Taper(clock: () => jetzt);
    t.setup(dose: 10, step: 1, minStep: 0.5, days: 7, goal: 0);
    for (var i = 0; i < 3; i++) {
      t.addIntake(10, force: true);
      jetzt = jetzt.add(const Duration(days: 1));
      t.refresh();
    }
    expect(t.stageDay(), 3);
    t.startHold(5);
    // 5 Halte-Tage à 10 + 4 Resttage Stufe 1 à 10 = 90, 7 × 9 = 63 → 153, dann 5 × 8 = 40 → 193
    expect(t.reichweite(200), 21);
    t.stopHold();
    t.startHold(null);
    expect(t.reichweite(200), 20, reason: 'ohne Enddatum: bis auf Weiteres gehalten');
  });
}
