// Rechenkern von BeNzoTaPer: reine Dart-Logik, keine Oberfläche.
//
// Die Oberfläche ruft nur diese Klasse auf und zeigt das Ergebnis an.
import 'meldung.dart';
import 'plan_math.dart';
import 'plan_parser.dart';
import 'state.dart';
import 'util.dart';

typedef Clock = DateTime Function();

/// Ergebnis von [Taper.addIntake].
enum IntakeResult {
  /// Eingetragen.
  added,

  /// Nicht eingetragen (Zukunft oder mehr als 7 Tage zurück).
  ignored,

  /// Heute mehr als der Plan: erst "Kurz innehalten" zeigen,
  /// dann mit `force: true` erneut aufrufen.
  needsPause,
}

/// Ergebnis von [Taper.saveLeft].
enum LeftResult { invalid, unchanged, needsWhy, whyTooShort, pended, applied }

class WeekAvg {
  final double? avg;
  final int n;
  const WeekAvg(this.avg, this.n);
}

class StockInfo {
  final double rem;

  /// Tage, die der Vorrat noch reicht (inkl. heute). `double.infinity` = bis Planende.
  final double days;
  const StockInfo(this.rem, this.days);
}

class Proj {
  final double v;
  final bool ch; // neue Stufe beginnt
  const Proj(this.v, {this.ch = false});
}

class ProjMap {
  final Map<String, Proj> map;
  final String? end;
  const ProjMap(this.map, this.end);
}

/// Ein Tag im Fortschrittsdiagramm.
class VerlaufTag {
  final String tag;
  final double? plan;
  final double? schnitt7;
  final double? dosis;
  final bool zukunft;
  const VerlaufTag(this.tag, this.plan, this.schnitt7, this.dosis, this.zukunft);
}

class Verlauf {
  final List<VerlaufTag> tage;
  final String start;
  final String bis;
  const Verlauf(this.tage, this.start, this.bis);
}

class PlanForResult {
  final double plan;
  final int stage;
  const PlanForResult(this.plan, this.stage);
}

class WeekReview {
  final String sunday;
  final String from;
  final double? avg;
  final int n;
  final int ok;
  final int good;
  const WeekReview(this.sunday, this.from, this.avg, this.n, this.ok, this.good);
}

class EditRow {
  double? dose;
  int? days;
  bool guess;
  EditRow(this.dose, this.days, {this.guess = false});
}

/// Entwurf im Plan-Editor.
class PlanEdit {
  String name;
  String unit;
  List<EditRow> rows;
  int start;
  String conf;
  String why;
  bool askWhy;
  bool pendOk;
  Meldung? msg;
  Meldung? err;

  /// Startdatum (JJJJ-MM-TT) für einen neuen Plan, wenn es noch keinen gibt. Nur heute oder später;
  /// `null` oder älter = heute. Bei einem bestehenden Plan ohne Wirkung.
  String? startDatum;
  PlanEdit({
    required this.name,
    required this.unit,
    required this.rows,
    this.start = 0,
    this.conf = '',
    this.why = '',
    this.askWhy = false,
    this.pendOk = false,
    this.msg,
    this.err,
    this.startDatum,
  });
}

class ApplyResult {
  /// Fehler, sonst `null`.
  final Meldung? err;

  /// Der Editor muss nach einem Grund fragen (48 h Bedenkzeit).
  final bool askWhy;

  /// Änderung wurde vorgemerkt statt übernommen.
  final bool pended;

  /// Plan wurde übernommen.
  final bool applied;
  const ApplyResult({this.err, this.askWhy = false, this.pended = false, this.applied = false});
}

const int waitMs = 48 * 3600000;

class Taper {
  TaperState? s;
  final Clock clock;

  /// Wird nach jeder Änderung aufgerufen, damit die Oberfläche speichern kann.
  void Function(TaperState?)? onSave;

  Taper({this.s, Clock? clock, this.onSave}) : clock = clock ?? DateTime.now {
    if (s != null) {
      _migT0();
      autoAdvance();
    }
  }

  // ===== Zeit =====
  String get today => ymd(clock());
  int get nowMs => clock().millisecondsSinceEpoch;
  int daysAgo(String k) => dBetween(k, today);

  TaperState get st => s!;

  void save() => onSave?.call(s);

  /// Nach jeder Änderung: Stufe/Stillstand nachziehen .
  void _after() {
    save();
    autoAdvance();
    _expirePend();
  }

  /// Zum Aufrufen beim Öffnen der App und bei Tageswechsel.
  void refresh() {
    if (s == null) return;
    autoAdvance();
    _expirePend();
  }

  void _migT0() {
    final a = s;
    if (a == null) return;
    if (a.t0 == null) {
      ensureStart();
      final t = t0Of();
      if (t != null) a.t0 = t;
    }
    if (a.frzFloor == null) {
      ensureStart();
      a.frzFloor = a.stageStart ?? a.t0;
    }
  }

  // ===== Grundrechnung =====

  int need(int stage) {
    final d = st.days;
    return (d != null && stage < d.length && d[stage] > 0) ? d[stage] : st.target;
  }

  void ensureStart() {
    final a = s;
    if (a == null || a.stageStart != null) return;
    final ks = a.log.keys.where((k) => a.log[k]!.stage == a.stage).toList()..sort();
    a.stageStart = ks.isNotEmpty ? ks.first : (a.adv ?? today);
  }

  String get stageStart {
    ensureStart();
    return st.stageStart!;
  }

  /// Wievielter Tag der aktuellen Stufe (0 = erster Tag). Steht still bei Halten/Stillstand.
  int stageDay([String? todayKey]) {
    var t = todayKey ?? today;
    final a = st;
    if (a.hold && a.holdSince != null && a.holdSince! < t) t = a.holdSince!;
    if (a.frz != null && a.frz! < t) t = a.frz!;
    final d = dBetween(stageStart, t);
    return d < 0 ? 0 : d;
  }

  /// Der Plan beginnt erst an einem späteren Tag (Startdatum in der Zukunft).
  bool get vorStart {
    final a = s;
    final b = a?.t0;
    return a != null && b != null && b.compareTo(today) > 0;
  }

  /// Erster Tag des Protokolls.
  String? t0Of() {
    final a = st;
    if (a.t0 != null) return a.t0;
    final ks = a.log.keys.toList()..sort();
    final first = ks.isNotEmpty ? ks.first : null;
    final b = a.stageStart;
    if (first != null && (b == null || first < b)) return first;
    return b ?? first;
  }

  /// Tage ohne Eintrag (nicht "weiß ich nicht mehr"), vom Start bis gestern.
  List<String> openDays([String? todayKey]) {
    final t = todayKey ?? today;
    final out = <String>[];
    final t0 = t0Of();
    if (t0 == null) return out;
    var k = t0;
    var n = 0;
    while (k < t && n < 4000) {
      if (st.log[k] == null && !st.unk.contains(k)) out.add(k);
      k = addD(k, 1);
      n++;
    }
    return out;
  }

  /// Tage ohne Eintrag in den letzten 6 Tagen (zählt nicht mit).
  int qCount([String? todayKey]) {
    final t = todayKey ?? today;
    final t0 = t0Of();
    var c = 0;
    for (var i = 1; i <= 6; i++) {
      final k = addD(t, -i);
      if (t0 != null && k >= t0 && st.log[k] == null) c++;
    }
    return c;
  }

  String? firstFrz(String todayKey) {
    final a = st;
    if (a.hold) return null;
    final od = openDays(todayKey);
    if (od.isEmpty) return null;
    var f = od.first;
    final fl = a.frzFloor;
    if (fl != null && f < fl) f = fl;
    if (f > todayKey || (f == todayKey && !(od.first < f))) return null;
    if (a.stage >= a.plan.length - 1 && (!(a.plan[a.stage] > 0) || dBetween(stageStart, f) >= need(a.stage))) {
      return null;
    }
    return f;
  }

  /// Heutiger Eintrag, der noch unter Plan liegt (Tag läuft noch) – zählt nicht in Durchschnitte.
  bool partToday(String k, DayEntry? e) => k == today && e != null && e.plan != null && e.dose < e.plan! - 1e-9;

  void fixDay(DayEntry e) {
    e.dose = round3(e.it.fold<double>(0, (a, x) => a + x.v));
    e.plan ??= st.plan[st.stage];
    e.r = e.dose > e.plan! + 1e-9 ? 'lapse' : 'ok';
  }

  List<Intake> dayIt(DayEntry e) => e.it.isNotEmpty ? e.it : [Intake('', e.dose, 0)];

  /// Durchschnitt pro Tag der eingetragenen Tage, [weeks] Wochen rückwärts ab [end].
  List<WeekAvg> weekAvgs([DateTime? end, int weeks = 4]) {
    final endKey = ymd(end ?? clock());
    final out = <WeekAvg>[];
    for (var w = 0; w < weeks; w++) {
      var sum = 0.0;
      var n = 0;
      for (var i = 0; i < 7; i++) {
        final kk = addD(endKey, -(w * 7 + i));
        final e = st.log[kk];
        if (e != null && !partToday(kk, e)) {
          sum += e.dose;
          n++;
        }
      }
      out.add(WeekAvg(n > 0 ? sum / n : null, n));
    }
    return out;
  }

  /// Durchschnitt der eingetragenen Tage in den 7 Tagen bis [k] .
  /// Ein angefangener heutiger Tag zählt nicht mit, ein ? nie als 0 mg.
  double? avg7(String k) {
    var sum = 0.0;
    var n = 0;
    for (var i = 0; i < 7; i++) {
      final kk = addD(k, -i);
      final e = st.log[kk];
      if (e != null && !partToday(kk, e)) {
        sum += e.dose;
        n++;
      }
    }
    return n > 0 ? sum / n : null;
  }

  /// Daten fürs Fortschrittsdiagramm: vom ersten Tag bis zum Planende (bei Halten oder ohne Ende
  /// [ohneEnde] Tage über heute hinaus, bei offenen Tagen nur bis heute). Vergangene Tage: Plan des
  /// Tages und 7-Tage-Durchschnitt; kommende Tage: Plan laut Projektion.
  Verlauf verlauf({int ohneEnde = 30, int max = 2000}) {
    final a = st;
    final td = today;
    final start = t0Of() ?? td;
    String bis = td;
    var pj = const ProjMap({}, null);
    if (a.frz == null) {
      final ende = projMap(td).end;
      final last = a.stage >= a.plan.length - 1;
      final voraus = a.hold && a.holdUntil != null ? voraussichtlichesEnde() : null;
      if (last) {
        bis = td;
      } else if (ende != null && !a.hold) {
        bis = ende;
      } else if (voraus != null && voraus > td) {
        // Halten mit Enddatum: bis zum voraussichtlichen Ende
        bis = voraus;
      } else {
        bis = addD(td, ohneEnde);
      }
      if (bis.compareTo(td) > 0) pj = projMap(bis);
    }
    final tage = <VerlaufTag>[];
    var k = start.compareTo(td) <= 0 ? start : td;
    // Sehr lange Vorgeschichte: nur die letzten [max] Tage, damit heute immer im Bild ist.
    if (dBetween(k, td) >= max) k = addD(td, -(max - 1));
    while (k.compareTo(bis) <= 0 && tage.length < max) {
      if (k.compareTo(td) <= 0) {
        final e = a.log[k];
        final pl = e?.plan ?? (k == td ? a.plan[a.stage] : planFor(k).plan);
        tage.add(VerlaufTag(k, pl, avg7(k), e?.dose, false));
      } else {
        tage.add(VerlaufTag(k, pj.map[k]?.v, null, null, true));
      }
      k = addD(k, 1);
    }
    // start/bis = erster und letzter gezeichneter Tag (bei sehr langen Plänen gekürzt).
    return Verlauf(tage, tage.isEmpty ? start : tage.first.tag, tage.isEmpty ? bis : tage.last.tag);
  }

  /// Kleinste Teilung: aus den Tabletten, sonst die Einstellung.
  double minStep() {
    final t = st.tabs;
    if (t != null && t.str.isNotEmpty) {
      final n = (t.split > 0 ? jsRound(1 / t.split) : 1).toInt().clamp(1, 1 << 30);
      var u = 0;
      for (final x in t.str) {
        u = gcd(u, jsRound(x / n * 1000).toInt());
      }
      if (u > 0) return u / 1000;
    }
    final m = st.min;
    return (m != null && m != 0) ? m : 0.25;
  }

  /// Vorrat: Rest und Reichweite in Tagen (inkl. heute).
  StockInfo? stockInfo([DateTime? nowDt]) {
    final a = st;
    final sk = a.stock;
    if (sk == null) return null;
    var used = 0.0;
    a.log.forEach((k, e) {
      if (e.it.isNotEmpty) {
        for (final x in e.it) {
          if (x.ts > sk.ts) used += x.v;
        }
      } else if (k > sk.day) {
        used += e.dose;
      }
    });
    final rem = round3(sk.mg - used);
    return StockInfo(rem, reichweite(rem, nowDt));
  }

  /// Wie viele Tage (inkl. heute) reichen [mg] beim aktuellen Plan? Rechnet mit Stufenwechseln und
  /// Halten (dynamische Anpassung; Halten mit Enddatum endet dort, danach weiter laut Plan); der heute noch offene Rest der Tagesdosis geht zuerst ab.
  /// `0` = reicht nicht mehr für heute, `double.infinity` = bis zum Planende.
  double reichweite(double mg, [DateTime? nowDt]) {
    final a = st;
    final todayKey = ymd(nowDt ?? clock());
    // Plan beginnt erst später: bis dahin kein Verbrauch, danach wie ab dem ersten Plantag.
    final beginn = a.t0;
    if (beginn != null && todayKey.compareTo(beginn) < 0 && beginn == stageStart) {
      final ab = reichweite(mg, DateTime.parse('${beginn}T00:00:00Z'));
      return ab.isInfinite ? ab : ab + dBetween(todayKey, beginn);
    }
    var r = mg;
    var sg = a.stage;
    final te = a.log[todayKey];
    var left = need(sg) - stageDay(todayKey);
    var days = 0;
    final rest = a.plan[sg] - (te?.dose ?? 0);
    // „Reicht nicht für heute“ nur, wenn heute noch etwas offen ist. Ist heute schon alles genommen, zählt
    // ein überzogener Vorrat (mehr genommen als gezählt) als leer – sonst warnt die App auch bei 0 mg.
    if (rest > 0) {
      r -= rest;
      if (r < -1e-9) return 0;
    }
    // Halten mit Enddatum endet – danach geht der Plan weiter (wie [voraussichtlichesEnde]).
    // Ohne Enddatum: gehalten bis auf Weiteres. Während des Haltens steht der Stufentag still.
    var haltRest = a.hold ? (a.holdUntil != null ? dBetween(todayKey, a.holdUntil!) : 1 << 30) : 0;
    // Heute gehört immer zur laufenden Stufe. Beim Halten zählt heute nicht als Stufentag – dann kann die
    // nächste Stufe direkt am Halte-Ende beginnen (wie [endHold]/[autoAdvance]).
    if (haltRest <= 0 && left < 1) left = 1;
    days = 1;
    if (haltRest > 0) {
      haltRest--;
    } else {
      left--;
    }
    for (var i = 0; i < 3000; i++) {
      if (haltRest <= 0 && left <= 0 && sg < a.plan.length - 1) {
        sg++;
        left = need(sg);
      }
      final d = a.plan[sg];
      if (!(d > 0)) return double.infinity;
      if (r < d - 1e-9) break;
      r -= d;
      days++;
      if (haltRest > 0) {
        haltRest--;
      } else {
        left--;
      }
    }
    return days.toDouble();
  }

  /// Welche Stufe/Dosis für einen vergangenen Tag galt.
  PlanForResult planFor(String k) {
    final a = st;
    final ss = stageStart;
    if (k >= ss) return PlanForResult(a.plan[a.stage], a.stage);
    var sg = a.stage;
    var start = ss;
    while (sg > 0) {
      start = addD(start, -need(sg - 1));
      sg--;
      if (k >= start) break;
    }
    // Rückrechnung kennt keine früheren Halte-Phasen: mit echten Einträgen eingrenzen
    var lo = -1;
    var hi = a.stage;
    a.log.forEach((x, e) {
      final g = e.stage;
      if (g == null || !(g >= 0)) return;
      if (x < k && g > lo) lo = g;
      if (x > k && g < hi) hi = g;
    });
    final mn = hi < sg ? hi : sg;
    sg = (lo > mn ? lo : mn).clamp(0, a.plan.length - 1);
    return PlanForResult(a.plan[sg], sg);
  }

  /// Prognose für die Zukunft (Kalender): Dosis pro Tag bis [untilKey] und Enddatum.
  ProjMap projMap(String untilKey) {
    final a = st;
    if (a.frz != null) return const ProjMap({}, null);
    final map = <String, Proj>{};
    var sg = a.stage;
    final last = a.plan.length - 1;
    var start = stageStart;
    String? end;
    if (!a.hold) {
      var st2 = start;
      var s2 = sg;
      while (s2 < last) {
        st2 = addD(st2, need(s2));
        s2++;
      }
      end = (s2 == last && last > 0) ? st2 : null;
      if (last == 0) end = null;
    }
    // Halten mit Enddatum: bis dahin die gehaltene Dosis, danach läuft die Stufe weiter –
    // um die Halte-Tage verschoben, genau wie [endHold], [voraussichtlichesEnde] und [reichweite].
    // Ohne Enddatum: gehalten bis auf Weiteres.
    final weiterAb = a.hold ? a.holdUntil : null;
    if (weiterAb != null && a.holdSince != null) {
      final d = dBetween(a.holdSince!, weiterAb);
      start = addD(start, d < 0 ? 0 : d);
    }
    var k = addD(today, 1);
    var n = 0;
    while (k <= untilKey && n < 4000) {
      if (!a.hold || (weiterAb != null && k >= weiterAb)) {
        while (sg < last && k >= addD(start, need(sg))) {
          start = addD(start, need(sg));
          sg++;
          if (k == start) map[k] = Proj(a.plan[sg], ch: true);
        }
      }
      if (k.compareTo(stageStart) >= 0) map[k] ??= Proj(a.plan[sg]);
      k = addD(k, 1);
      n++;
    }
    return ProjMap(map, end);
  }

  // ===== Protokoll =====

  void logChg(String t) {
    final a = st;
    a.chg.add(Chg(nowMs, today, t));
    if (a.chg.length > 400) a.chg = a.chg.sublist(a.chg.length - 400);
  }

  String nowHM() {
    final d = clock();
    final h = d.hour, m = d.minute;
    return '${h < 10 ? '0' : ''}$h:${m < 10 ? '0' : ''}$m';
  }

  /// Einnahme eintragen. [k] = Tag (Standard heute, nachtragen bis 7 Tage zurück).
  /// [force]: "Kurz innehalten" wurde schon gezeigt/übersprungen.
  IntakeResult addIntake(double v, {String? t, String? k, bool force = false}) {
    final a = st;
    final td = today;
    k ??= td;
    if (k > td || (k < td && daysAgo(k) > 7)) return IntakeResult.ignored;
    if (vorStart) return IntakeResult.ignored; // Plan beginnt erst später: noch nichts einzutragen
    if (!(v >= 0) || !v.isFinite) return IntakeResult.ignored; // Oberfläche prüft schon; doppelt hält besser
    if (k == td && !force) {
      final pe0 = a.log[k];
      final pl0 = (pe0 != null && pe0.plan != null) ? pe0.plan! : a.plan[a.stage];
      if ((pe0?.dose ?? 0) + v > pl0 + 1e-9) return IntakeResult.needsPause;
    }
    var e = a.log[k];
    if (e == null) {
      final pf = k == td ? PlanForResult(a.plan[a.stage], a.stage) : planFor(k);
      e = a.log[k] = DayEntry(plan: pf.plan, stage: pf.stage);
    }
    if (e.it.isEmpty) {
      e.it = (e.dose > 0 || e.r != null) ? [Intake('', e.dose, 0)] : [];
    }
    final p = k.split('-');
    final hm = ((t == null || t.isEmpty) ? '12:00' : t).split(':');
    final hh = jsParseInt(hm[0]) ?? 12;
    final mi = hm.length > 1 ? (jsParseInt(hm[1]) ?? 0) : 0;
    final noT = t == null || t.isEmpty;
    final zoneUtc = clock().isUtc;
    var ts = (k == td && noT)
        ? nowMs
        : (zoneUtc
                ? DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]), hh, mi)
                : DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]), hh, mi))
            .millisecondsSinceEpoch;
    if (ts > nowMs) ts = nowMs;
    e.it.add(Intake(noT ? (k == td ? nowHM() : '') : t, round3(v), ts));
    _stableSortByTime(e.it);
    if (k < td) logChg('Nachgetragen (${lbl(k)}, ${fmt(v)} ${a.unit})');
    fixDay(e);
    _after();
    return IntakeResult.added;
  }

  static void _stableSortByTime(List<Intake> l) {
    final idx = {for (var i = 0; i < l.length; i++) l[i]: i};
    l.sort((x, y) {
      final c = x.t.compareTo(y.t);
      return c != 0 ? c : idx[x]!.compareTo(idx[y]!);
    });
  }

  /// Einnahme [i] des Tages [k] (Standard heute) löschen.
  void delIntake(int i, [String? k]) {
    final a = st;
    k ??= today;
    final e = a.log[k];
    if (e == null) return;
    e.it = dayIt(e).toList();
    if (i >= 0 && i < e.it.length) {
      final rm = e.it[i];
      logChg('Einnahme gelöscht (${lbl(k)}, ${fmt(rm.v)} ${a.unit})');
      e.it.removeAt(i);
    }
    if (e.it.isEmpty) {
      a.log.remove(k);
    } else {
      fixDay(e);
    }
    _after();
  }

  void toggleGood(String k) {
    if (!st.good.remove(k)) st.good.add(k);
    _after();
  }

  /// Notiz zum Tag speichern (leer = löschen).
  void saveNote(String k, Note n) {
    if (n.isEmpty) {
      st.notes.remove(k);
    } else {
      st.notes[k] = Note(sx: List.of(n.sx), sym: n.sym, text: n.text.trim());
    }
    _after();
  }

  /// "Weiß ich nicht mehr": offene Tage über 7 Tage zurück bleiben dauerhaft ein "?".
  void markUnk() {
    final td = today;
    var n = 0;
    for (final k in openDays(td)) {
      if (daysAgo(k) > 7) {
        st.unk.add(k);
        n++;
      }
    }
    if (n > 0) logChg('$n ${n == 1 ? 'Tag' : 'Tage'} ohne Angabe belassen (weiß ich nicht mehr)');
    _after();
  }

  // ===== Stufen, Halten, Stillstand =====

  /// Offene Tage: Anzeigen pausieren (frz) bis nachgetragen. Am Plan wird dabei nichts verschoben.
  void settle() {
    final a = st;
    final t = today;
    var ch = false;
    if (a.hold) {
      if (a.frz != null) {
        a.frz = null;
        ch = true;
      }
    } else {
      final f = firstFrz(t);
      if (a.frz != null) {
        if (f == null) {
          a.frz = null;
          ch = true;
        }
      } else if (f != null) {
        a.frz = f;
        ch = true;
      }
    }
    if (ch) save();
  }

  /// Stufenwechsel und Ende von "Halten" nachziehen.
  void autoAdvance() {
    final a = s;
    if (a == null) return;
    ensureStart();
    final tH = today;
    if (a.hold && a.holdUntil != null && tH >= a.holdUntil!) {
      endHold(a.holdUntil!, 'Halten nach Plan beendet (${dmy(a.holdUntil!)})');
      save();
    }
    settle();
    final t0 = today;
    final t = (a.frz != null && a.frz! < t0) ? a.frz! : t0;
    var ch = false;
    while (!a.hold && a.stage < a.plan.length - 1 && t >= addD(a.stageStart!, need(a.stage))) {
      a.stageStart = addD(a.stageStart!, need(a.stage));
      a.stage++;
      a.adv = a.stageStart;
      ch = true;
    }
    // Nach einem Stufenwechsel offene Tage neu bewerten (z. B. letzte Stufe 0 mg: nichts mehr zu pausieren).
    // Sonst ändert erst der nächste refresh() den Zustand (Zustand vor/nach Neustart gleich).
    if (ch) settle();
    if (ch) save();
  }

  /// Dosis halten für [days] Tage (`null` = ohne Enddatum). Gibt `false` bei ungültiger Zahl.
  bool startHold(int? days) {
    final a = st;
    final t = today;
    ensureStart();
    if (days != null && !(days >= 1 && days <= 365)) return false;
    a.hold = true;
    a.holdSince = t;
    a.frz = null;
    a.holdUntil = days != null ? addD(t, days) : null;
    logChg('Stufe ${a.stage + 1} gehalten' +
        (days != null ? ' für $days${days == 1 ? ' Tag' : ' Tage'} (bis ${dmy(a.holdUntil!)})' : ' ohne Enddatum'));
    _after();
    return true;
  }

  /// "Weiter abdosieren": Halten jetzt beenden.
  void stopHold() {
    if (!st.hold) return;
    endHold(today, 'Halten beendet, weiter abdosiert');
    _after();
  }

  /// Der Plan verschiebt sich um die gehaltenen Tage.
  void endHold(String t, String msg) {
    final a = st;
    logChg(msg);
    if (a.holdSince != null) {
      final d = dBetween(a.holdSince!, t);
      a.stageStart = addD(stageStart, d < 0 ? 0 : d);
    }
    a.hold = false;
    a.holdSince = null;
    a.holdUntil = null;
    a.frzFloor = t;
    a.frz = openDays(t).isNotEmpty ? t : null;
  }

  // ===== Bedenkzeit und Planänderungen =====

  static String planEnd(List<double> plan, List<int>? days, int stage, String start, int tg) {
    var k = start;
    for (var i = stage; i < plan.length - 1; i++) {
      k = addD(k, (days != null && i < days.length && days[i] > 0) ? days[i] : tg);
    }
    return k;
  }

  /// Enddatum laut Plan (`null` bei Halten).
  /// Voraussichtlich beim Ziel ab.
  /// Ohne Halten = Planende. Beim Halten mit Enddatum: um die Halte-Tage bis dahin verschoben. Beim Halten
  /// ohne Enddatum: so, als ginge es jetzt weiter – rückt also jeden gehaltenen Tag um einen Tag mit.
  /// Rechnet genau wie [endHold]. `null` bei offenen Tagen.
  String? voraussichtlichesEnde() {
    final a = st;
    if (a.frz != null) return null;
    final last = a.plan.length - 1;
    if (last <= 0) return null;
    var k = stageStart;
    if (a.hold && a.holdSince != null) {
      final d = dBetween(a.holdSince!, a.holdUntil ?? today);
      k = addD(k, d < 0 ? 0 : d);
    }
    for (var i = a.stage; i < last; i++) {
      k = addD(k, need(i));
    }
    // Beim Halten kann es frühestens am Halte-Ende (bzw. ab heute) weitergehen.
    if (a.hold) {
      final frueh = a.holdUntil ?? today;
      if (k < frueh) k = frueh;
    }
    return k;
  }

  String? planEndNow() {
    ensureStart();
    final a = st;
    return a.hold ? null : planEnd(a.plan, a.days, a.stage, a.stageStart!, a.target);
  }

  bool isSlower(PlanOverride o) {
    final a = st;
    ensureStart();
    final sg = o.stage < o.plan.length - 1 ? o.stage : o.plan.length - 1;
    final keep = (o.plan[sg] - a.plan[a.stage]).abs() < 1e-9;
    if (o.plan[sg] > a.plan[a.stage] + 1e-9) return true;
    if (o.plan.last > a.plan.last + 1e-9) return true;
    final oe = planEnd(a.plan, a.days, a.stage, a.stageStart!, a.target);
    final ne = planEnd(o.plan, o.days, sg, keep ? a.stageStart! : today, a.target);
    return ne > oe;
  }

  String planSum(List<double> plan, List<int>? days, int sg) {
    var t = 0;
    for (var i = sg; i < plan.length; i++) {
      t += (days != null && i < days.length && days[i] > 0) ? days[i] : st.target;
    }
    return '${fmt(plan[sg])} ${st.unit} jetzt · ${plan.length - sg} Stufen · ca. $t Tage';
  }

  void _setPend(Pend p) {
    p.at = nowMs;
    p.base = st.stage;
    st.pend = p;
    logChg('Vorgemerkt (48 h): ${p.txt} · Grund: ${p.why}');
  }

  void dropPend() {
    final p = st.pend;
    if (p != null) logChg('Verworfen: ${p.txt}');
    st.pend = null;
    _after();
  }

  /// Läuft die Bedenkzeit noch? Verbleibende Millisekunden (<= 0 = vorbei).
  int pendLeftMs() => st.pend == null ? 0 : st.pend!.at + waitMs - nowMs;

  void _expirePend() {
    final a = s;
    if (a == null) return;
    final p = a.pend;
    if (p != null && p.kind == 'left' && p.stage != a.stage) {
      logChg('Vormerkung verfallen (Stufe hat gewechselt): ${p.txt}');
      a.pend = null;
      save();
    }
  }

  /// Vorgemerkte Änderung übernehmen. Bei "left" sofort, bei "plan" kommt ein
  /// Editor-Entwurf zurück, den die Oberfläche zeigt und mit [applyPlan] bestätigt.
  PlanEdit? usePend() {
    final a = st;
    final p = a.pend;
    if (p == null) return null;
    if (p.kind == 'left') {
      ensureStart();
      final nd = (p.nd != null && p.nd! > 0) ? p.nd! : dBetween(a.stageStart!, p.next!);
      if (p.stage == a.stage && nd > need(a.stage)) {
        a.days ??= a.plan.map((_) => a.target).toList();
        a.days![a.stage] = nd;
        logChg('Übernommen: ${p.txt}');
      }
      a.pend = null;
      _after();
      return null;
    }
    final o = p.o!;
    final e = openEditor();
    e.rows = [for (var i = 0; i < o.plan.length; i++) EditRow(o.plan[i], o.days[i])];
    e.name = o.name;
    e.unit = o.unit;
    e.start = (o.stage + (a.stage - p.base)).clamp(0, o.plan.length - 1);
    e.pendOk = true;
    e.msg = const Meldung(MeldungCode.vorgemerktPruefen);
    return e;
  }

  /// Aktuelle Stufe ändern: in [n] Tagen beginnt die nächste Stufe (1 = morgen).
  /// Kürzer = sofort, länger = 48 h Bedenkzeit mit Begründung [why].
  LeftResult saveLeft(int n, {String? why}) {
    final a = st;
    if (!(n >= 1 && n <= 365)) return LeftResult.invalid;
    final nd = stageDay() + n;
    final nk = addD(stageStart, nd);
    if (nd == need(a.stage)) return LeftResult.unchanged;
    if (nd > need(a.stage)) {
      if (why == null) return LeftResult.needsWhy;
      final w = why.trim();
      if (w.length < 3) return LeftResult.whyTooShort;
      _setPend(Pend(
        kind: 'left',
        stage: a.stage,
        nd: nd,
        next: nk,
        why: w,
        txt: 'Stufe ${a.stage + 1} verlängern, nächste Stufe ab ${dmy(nk)}',
      ));
      _after();
      return LeftResult.pended;
    }
    a.days ??= a.plan.map((_) => a.target).toList();
    a.days![a.stage] = nd;
    logChg('Nächste Stufe vorgezogen auf ${dmy(nk)}');
    _after();
    return LeftResult.applied;
  }

  // ===== Einrichten und Plan-Editor =====

  /// Erste Einrichtung per Rechner. Gibt einen Fehler zurück, sonst `null`.
  Meldung? setup({
    String name = '',
    String unit = '',
    required double dose,
    required double step,
    required double minStep,
    required int days,
    required double goal,
  }) {
    if (!(dose > 0)) return const Meldung(MeldungCode.setupDosis);
    if (!(step > 0)) return const Meldung(MeldungCode.setupSchritt);
    if (!(minStep > 0) || !(days >= 3) || !(goal >= 0) || goal >= dose) {
      return const Meldung(MeldungCode.setupWerteZiel);
    }
    if (!dose.isFinite || days > maxStufenTage) return const Meldung(MeldungCode.werteKurz);
    final td = today;
    final plan = makePlan(dose, step, minStep, goal);
    final lang = planLaengeFehler([for (var i = 0; i < plan.length - 1; i++) days]);
    if (lang != null) return lang;
    s = TaperState(
      name: name.isEmpty ? 'Medikament' : name,
      unit: unit.isEmpty ? 'mg' : unit,
      step: step,
      min: minStep,
      target: days,
      plan: plan,
      stage: 0,
      stageStart: td,
      t0: td,
      days: plan.map((_) => days).toList(),
    );
    _after();
    return null;
  }

  /// Editor öffnen: [neu] = leer starten, sonst mit dem laufenden Plan.
  PlanEdit openEditor({bool neu = false}) {
    final a = s;
    final rows =
        (a != null && !neu) ? [for (var i = 0; i < a.plan.length; i++) EditRow(a.plan[i], need(i))] : <EditRow>[];
    return PlanEdit(
      name: a?.name ?? 'Diazepam',
      unit: a?.unit ?? 'mg',
      rows: rows,
      start: (a != null && !neu) ? a.stage : 0,
    );
  }

  /// Rechner im Editor ("Neuen Plan berechnen").
  void editCalc(PlanEdit e,
      {required double dose, required double step, required double minStep, required int days, required double goal}) {
    if (!(dose > 0) || !(step > 0) || !(minStep > 0) || !(days >= 1) || !(goal >= 0) || goal >= dose) {
      e.err = const Meldung(MeldungCode.editWerteZiel);
      e.msg = null;
      return;
    }
    final plan = makePlan(dose, step, minStep, goal);
    final lang = !dose.isFinite
        ? const Meldung(MeldungCode.werteKurz)
        : planLaengeFehler([for (var i = 0; i < plan.length - 1; i++) days]);
    if (lang != null) {
      e.err = lang;
      e.msg = null;
      return;
    }
    e.rows = plan.map((x) => EditRow(x, days)).toList();
    e.start = 0;
    e.err = null;
    e.msg = Meldung(MeldungCode.stufenBerechnet, [e.rows.length]);
  }

  /// Text auslesen (eingefügt, aus Datei oder abgetippt).
  void editParse(PlanEdit e, String text, {bool englisch = false}) {
    final r = parsePlanText(text, 14, clock(), englisch);
    if (r.rows.isEmpty) {
      e.err = const Meldung(MeldungCode.keineDosierungen);
      e.msg = null;
      return;
    }
    e.rows = r.rows.map((x) => EditRow(x.dose, x.days, guess: x.guess)).toList();
    e.unit = r.unit;
    e.start = 0;
    // Erkanntes Datum nur als Vorschlag und nur, wenn es nicht in der Vergangenheit liegt.
    final sd = r.startDatum;
    e.startDatum = (sd != null && sd.compareTo(today) >= 0) ? sd : null;
    e.err = null;
    final g = r.rows.where((x) => x.guess).length;
    e.msg = Meldung(MeldungCode.schritteErkannt, [r.rows.length, g]);
  }

  static final _ws = RegExp(r'\s+');

  /// Bestätigungssatz beim Ändern eines bestehenden Plans (Deutsch oder Englisch).
  static const _sicherSatz = {'ich bin mir sicher', 'i am sure'};

  /// Plan übernehmen. Bei bestehendem Plan: "Ich bin mir sicher" nötig; Dosis rauf
  /// oder langsamer wird 48 h vorgemerkt (mit Grund).
  ApplyResult applyPlan(PlanEdit e) {
    final a = s;
    e.msg = null;
    final rows = e.rows;
    ApplyResult fail(Meldung m) {
      e.err = m;
      return ApplyResult(err: m);
    }

    if (rows.isEmpty) return fail(const Meldung(MeldungCode.keineSchritte));
    if (a != null && !_sicherSatz.contains(e.conf.trim().toLowerCase().replaceAll(_ws, ' '))) {
      return fail(const Meldung(MeldungCode.sicherTippen));
    }
    for (var i = 0; i < rows.length; i++) {
      final d = rows[i].dose;
      if (!(d != null && d >= 0 && d.isFinite)) return fail(Meldung(MeldungCode.stufeDosisFehlt, [i + 1]));
      final n = rows[i].days;
      if (!(n != null && n >= 1)) return fail(Meldung(MeldungCode.stufeTageFehlen, [i + 1]));
    }
    // Die letzte Stufe läuft offen weiter, ihre Tage zählen nicht zur Länge.
    final lang = planLaengeFehler([for (var i = 0; i < rows.length - 1; i++) rows[i].days!]);
    if (lang != null) return fail(lang);
    if (rows.last.days! > maxStufenTage) return fail(Meldung(MeldungCode.stufeMaxTage, [rows.length, maxStufenTage]));
    final plan = rows.map((r) => r.dose!).toList();
    final days = rows.map((r) => r.days!).toList();
    final sg = e.start < rows.length - 1 ? e.start : rows.length - 1;
    final name = e.name.trim().isEmpty ? 'Medikament' : e.name.trim();
    final unit = e.unit.trim().isEmpty ? 'mg' : e.unit.trim();
    final td = today;

    var same0 = false;
    if (a != null) {
      final o = PlanOverride(plan, days, sg, name, unit);
      if (!e.pendOk && isSlower(o)) {
        if (!e.askWhy) {
          e.askWhy = true;
          e.err = null;
          return const ApplyResult(askWhy: true);
        }
        final w = e.why.trim();
        if (w.length < 3) return fail(const Meldung(MeldungCode.begruenden));
        _setPend(Pend(
          kind: 'plan',
          o: o,
          why: w,
          txt: 'Plan ändern: ${planSum(a.plan, a.days, a.stage)} → ${planSum(plan, days, sg)}',
        ));
        _after();
        return const ApplyResult(pended: true);
      }
      same0 =
          _listEq(plan, a.plan) && _listEq(days, [for (var i = 0; i < a.plan.length; i++) need(i)]) && sg == a.stage;
      if (!same0 || e.pendOk) {
        logChg((e.pendOk ? 'Vorgemerkte Änderung übernommen: ' : 'Plan geändert: ') +
            '${planSum(a.plan, a.days, a.stage)} → ${planSum(plan, days, sg)}');
      }
      if (e.pendOk) a.pend = null;
    }
    if (a == null) {
      final sd = e.startDatum;
      final beginn = (sd != null && isDateKey(sd) && sd.compareTo(td) > 0) ? sd : td;
      s = TaperState(
        name: name,
        unit: unit,
        target: 14,
        plan: plan,
        days: days,
        stage: sg,
        stageStart: beginn,
        t0: beginn,
      );
    } else {
      final same = _listEq(plan, a.plan) && sg == a.stage;
      final keep = (plan[sg] - a.plan[a.stage]).abs() < 1e-9;
      final old = a.stage;
      if (!same) {
        for (final en in a.log.values) {
          en.stage = (keep && en.stage == old) ? sg : -1;
        }
      }
      a.name = name;
      a.unit = unit;
      a.plan = plan;
      a.days = days;
      a.stage = sg;
      if (!same) a.adv = null;
      if (!same && !keep) {
        a.stageStart = td;
        a.frz = null;
        a.frzFloor = a.stageStart;
        if (a.hold) a.holdSince = a.stageStart;
      }
      if (!same0 && !e.pendOk && a.pend != null && a.pend!.kind == 'plan') {
        logChg('Vormerkung verworfen, weil der Plan inzwischen geändert wurde');
        a.pend = null;
      }
    }
    e.err = null;
    _after();
    return const ApplyResult(applied: true);
  }

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ===== Tabletten und Vorrat =====

  void saveTabs(List<double> str, double split, double? liq) {
    st.tabs = Tabs(
      str: str.where((x) => x > 0).toList(),
      split: split,
      liq: (liq != null && liq > 0) ? liq : null,
    );
    _after();
  }

  /// Vorrat setzen (gezählt) oder mit [add] einen Nachkauf dazurechnen.
  /// [count] Tabletten à [strength].
  void setStock(double count, double strength, {bool add = false}) {
    final mg = count * strength;
    if (!(mg >= 0) || !mg.isFinite) return; // ungültig: nichts ändern
    if (add && st.stock != null) {
      st.stock!.mg += mg;
    } else {
      st.stock = Stock(mg, nowMs, today);
    }
    _after();
  }

  // ===== SOS, Wochenrückblick =====

  /// "Geschafft": eine Welle ausgesessen.
  void sosDone() {
    st.sosN++;
    _after();
  }

  /// Ruhiger Wochenrückblick (Sonntag + Montag), `null` wenn nichts anzuzeigen ist.
  WeekReview? weekReview() {
    final td = today;
    final dow = weekday0(td);
    if (dow != 0 && dow != 1) return null;
    final sun = dow == 0 ? td : addD(td, -1);
    if (st.wkSeen == sun) return null;
    var dose = 0.0;
    var n = 0, ok = 0, gd = 0;
    for (var i = 0; i < 7; i++) {
      final k = addD(sun, -i);
      final e = st.log[k];
      if (e != null && !partToday(k, e)) {
        dose += e.dose;
        n++;
        if (e.r != 'lapse') ok++;
      }
      if (st.good.contains(k)) gd++;
    }
    if (n == 0 && gd == 0) return null;
    return WeekReview(sun, addD(sun, -6), n > 0 ? dose / n : null, n, ok, gd);
  }

  void markWeekSeen(String sunday) {
    st.wkSeen = sunday;
    _after();
  }

  // ===== PIN-Sperre =====

  /// FNV-1a-Hash, unverändert, damit ältere Daten passen.
  static String hashPin(String p) {
    var h = 2166136261;
    for (final c in 'tb!$p'.codeUnits) {
      h ^= c;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  bool checkPin(String v) => st.pin != null && hashPin(v) == st.pin;

  /// PIN setzen. Gibt einen Fehler zurück, sonst `null`.
  Meldung? setPin(String a, String b) {
    if (!RegExp(r'^\d{4,8}$').hasMatch(a)) return const Meldung(MeldungCode.pinZiffern);
    if (a != b) return const Meldung(MeldungCode.pinUngleich);
    st.pin = hashPin(a);
    _after();
    return null;
  }

  void clearPin() {
    st.pin = null;
    _after();
  }

  // ===== Sichern / Laden / Löschen =====

  /// Sicherung laden. `false`, wenn der Inhalt nicht passt (alter Stand bleibt).
  bool importJson(Object? json) {
    final o = TaperState.fromJson(json);
    if (o == null) return false;
    s = o;
    o.frz = null;
    _migT0();
    _after();
    return true;
  }

  Map<String, dynamic>? exportJson() => s?.toJson();

  /// Alles löschen.
  void wipe() {
    s = null;
    save();
  }
}
