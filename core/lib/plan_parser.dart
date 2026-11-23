// Plan aus Text lesen ("Woche 1–2: 10 mg", "ab 01.12.: 8 mg", Tabellenzeilen ...).
// Das Einlesen von PDF/Word in Text passiert später in der Oberfläche.
import 'util.dart';

class ParsedRow {
  final double dose;
  final int days;
  final bool guess; // Dauer geschätzt
  const ParsedRow(this.dose, this.days, this.guess);
}

class ParsedPlan {
  final List<ParsedRow> rows;
  final String unit;

  /// Erstes erkanntes Datum (JJJJ-MM-TT) der ersten Stufe, sonst `null`.
  final String? startDatum;
  const ParsedPlan(this.rows, this.unit, [this.startDatum]);
}

const _num = r'(?:\d+\s*[½¼¾]|[½¼¾]|\d+\/\d+|\d+(?:[.,]\d+)?)';
const _units = r'(mg|mcg|µg|ug|ml|tropfen|drops?|gtt|tbl|tabl\w*|tabs?|pills?|caps?\w*)';
final _doseRe = RegExp('($_num)\\s*$_units\\b', caseSensitive: false);
final _segRe = RegExp('($_num)(?:\\s*$_units\\b)?', caseSensitive: false);
final _arrowRe = RegExp('→|->|=>|›');
final _arrowOrRe = RegExp('→|->|=>|›|>|;');
final _tod = RegExp(
    r'morgens|mittags|abends|nachts|vormittags|nachmittags|zur nacht|zum schlafen|\bfrüh\b|morning|evening|night|noon',
    caseSensitive: false);
final _stop =
    RegExp(r'absetzen|abgesetzt|stopp|beenden|beendet|keine einnahme|ohne medikament|\bende\b|\bstop\b|stopped|discontinue\w*|\bend\b|finished|no medication|\bnone\b', caseSensitive: false);
final _neg = RegExp(r'\bnicht\b|\bnie\b|niemals|\bkein\b|\bnot\b|\bnever\b|\bdon.t\b', caseSensitive: false);

double _numTok(String t) {
  t = t.trim();
  const fr = {'½': 0.5, '¼': 0.25, '¾': 0.75};
  var m = RegExp(r'^(\d+)\s*([½¼¾])$').firstMatch(t);
  if (m != null) return int.parse(m.group(1)!) + fr[m.group(2)!]!;
  if (fr.containsKey(t)) return fr[t]!;
  m = RegExp(r'^(\d+)\/(\d+)$').firstMatch(t);
  if (m != null) {
    final b = int.parse(m.group(2)!);
    return b != 0 ? int.parse(m.group(1)!) / b : double.nan;
  }
  return jsParseFloat(t.replaceAll(',', '.')) ?? double.nan;
}

String _unitName(String u, [bool en = false]) {
  u = u.toLowerCase();
  if (u == 'mg') return 'mg';
  if (u == 'mcg' || u == 'µg' || u == 'ug') return 'µg';
  if (u == 'ml') return 'ml';
  if (u == 'tropfen' || u == 'gtt' || u.startsWith('drop')) return en ? 'drops' : 'Tropfen';
  return en ? 'tab' : 'Tbl';
}

int _dayDiff(int a, int b) => ((b - a) / 86400000).round();

class _Dt {
  final int d;
  final int m;
  final int? y;
  const _Dt(this.d, this.m, this.y);
}

class _Mark {
  final String u;
  final int n;
  const _Mark(this.u, this.n);
}

class _Timing {
  int? days;
  _Mark? mark;
  _Dt? date;
  _Dt? date2;
}

_Timing _timingOf(String line) {
  final s = line.toLowerCase();
  final t = _Timing();
  RegExpMatch? m;
  int g(RegExpMatch m, int i) => int.parse(m.group(i)!);
  final rx = RegExp(r'(?:tag|tage|day|days)\s*(\d+)\s*(?:-|–|—|bis|to)\s*(?:tag\s*)?(\d+)');
  final rx2 = RegExp(r'(\d+)\.?\s*(?:-|–|—|bis)\s*(\d+)\.?\s*(tag|tage|tagen|day|days)\b');
  final rw = RegExp(r'(?:woche|wochen|week|weeks)\s*(\d+)\s*(?:-|–|—|bis|to)\s*(?:woche\s*)?(\d+)');
  final rw2 = RegExp(r'(\d+)\.?\s*(?:-|–|—|bis)\s*(\d+)\.?\s*(woche|wochen|week|weeks)\b');
  if ((m = rw.firstMatch(s)) != null && g(m!, 2) >= g(m, 1)) {
    t.days = (g(m, 2) - g(m, 1) + 1) * 7;
  } else if ((m = rw2.firstMatch(s)) != null && g(m!, 2) >= g(m, 1)) {
    t.days = (g(m, 2) - g(m, 1) + 1) * 7;
  } else if ((m = rx.firstMatch(s)) != null && g(m!, 2) >= g(m, 1)) {
    t.days = g(m, 2) - g(m, 1) + 1;
  } else if ((m = rx2.firstMatch(s)) != null && g(m!, 2) >= g(m, 1)) {
    t.days = g(m, 2) - g(m, 1) + 1;
  } else if ((m = RegExp(r'(\d+)\s*(?:wochen|woche|weeks|week)\b').firstMatch(s)) != null) {
    t.days = g(m!, 1) * 7;
  } else if ((m = RegExp(r'(\d+)\s*(?:tagen|tage|tag|days|day)\b').firstMatch(s)) != null) {
    t.days = g(m!, 1);
  }
  // Datum
  final ds = <_Dt>[];
  for (final dm in RegExp(r'(\d{1,2})\.\s?(\d{1,2})\.(?:\s?(\d{4}|\d{2}))?(?!\d)').allMatches(s)) {
    final mo = g(dm, 2), dd = g(dm, 1);
    if (mo >= 1 && mo <= 12 && dd >= 1 && dd <= 31) {
      int? y;
      final ys = dm.group(3);
      if (ys != null) y = ys.length == 2 ? 2000 + int.parse(ys) : int.parse(ys);
      ds.add(_Dt(dd, mo, y));
    }
  }
  for (final dm in RegExp(r'(?:(?:from|on|until|till|to|ab|bis|starting)\s+)(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?(?![\d/])(?!\s*(?:mg|mcg|µg|ug|ml|tropfen|drops?|gtt|tbl|tab|pill|cap))|(?<![\d/])(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})(?!\d)')
      .allMatches(s)) {
    final dd = int.parse(dm.group(1) ?? dm.group(4)!), mo = int.parse(dm.group(2) ?? dm.group(5)!);
    final ys = dm.group(3) ?? dm.group(6);
    if (mo >= 1 && mo <= 12 && dd >= 1 && dd <= 31) {
      ds.add(_Dt(dd, mo, ys == null ? null : (ys.length == 2 ? 2000 + int.parse(ys) : int.parse(ys))));
    }
  }
  if (ds.isNotEmpty) {
    t.date = ds[0];
    if (ds.length >= 2 && t.days == null) t.date2 = ds[1];
  }
  if (t.days == null && t.date == null) {
    if ((m = RegExp(r'(woche|wochen|week|weeks)\s*(\d+)').firstMatch(s)) != null) {
      t.mark = _Mark('w', g(m!, 2));
    } else if ((m = RegExp(r'(?:^|[^a-zäöü])(tag|tage|day)\s*(\d+)').firstMatch(s)) != null) {
      t.mark = _Mark('d', g(m!, 2));
    } else if ((m = RegExp(r'(\d+)\.\s*(woche|week)').firstMatch(s)) != null) {
      t.mark = _Mark('w', g(m!, 1));
    } else if ((m = RegExp(r'(\d+)\.\s*tag').firstMatch(s)) != null) {
      t.mark = _Mark('d', g(m!, 1));
    }
  }
  return t;
}

class _Row {
  double dose;
  int? days;
  _Timing t;
  bool timed;
  int? ts;
  _Row(this.dose, this.days, this.t, this.timed);
}

class _Ms {
  final double v;
  final String u;
  const _Ms(this.v, this.u);
}

/// Text in Stufen umwandeln. [now] liefert das Jahr für Daten ohne Jahreszahl.
ParsedPlan parsePlanText(String text, [int defDays = 14, DateTime? now, bool englisch = false]) {
  if (defDays <= 0) defDays = 14;
  final lines = text
      .replaceAll('\r', '')
      .split('\n')
      .map((x) => x.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((x) => x.isNotEmpty);
  final rows = <_Row>[];
  final uc = <String, int>{};
  for (final line in lines) {
    var ms = <_Ms>[
      for (final m in _doseRe.allMatches(line)) _Ms(_numTok(m.group(1)!), _unitName(m.group(2)!, englisch)),
    ];
    if (_arrowRe.hasMatch(line)) {
      final nn = <double>[];
      String? uu;
      for (final sg in line.split(_arrowRe)) {
        final q = _segRe.firstMatch(sg);
        if (q != null) {
          nn.add(_numTok(q.group(1)!));
          if (q.group(2) != null) uu = _unitName(q.group(2)!, englisch);
        }
      }
      if (nn.length >= 2 && uu != null) ms = nn.map((v) => _Ms(v, uu!)).toList();
    }
    ms = ms.where((x) => x.v.isFinite).toList();
    final t = _timingOf(line);
    final hasT = t.days != null || t.date != null || t.mark != null;
    List<double> doses;
    if (ms.isNotEmpty) {
      for (final x in ms) {
        uc[x.u] = (uc[x.u] ?? 0) + 1;
      }
      if (ms.length > 1 && _tod.hasMatch(line)) {
        doses = [ms.fold<double>(0, (a, x) => a + x.v)];
      } else if (ms.length > 1 && (_arrowOrRe.hasMatch(line) || ms.length >= 3)) {
        doses = ms.map((x) => x.v).toList();
      } else {
        doses = [ms[0].v];
      }
    } else if (_stop.hasMatch(line) && !_neg.hasMatch(line) && hasT) {
      doses = [0];
    } else {
      continue;
    }
    for (var i = 0; i < doses.length; i++) {
      final later = doses.length > 1 && i > 0;
      rows.add(_Row(round3(doses[i]), t.days, later ? (_Timing()..days = t.days) : t, hasT));
    }
  }
  final nt = rows.where((r) => r.timed).length;
  final work = nt >= 2 ? rows.where((r) => r.timed).toList() : rows;
  // Dauer aus Startmarken / Datum ableiten
  final base = (now ?? DateTime.now()).year;
  int? prev;
  for (final r in work) {
    final dt = r.t.date;
    if (dt != null) {
      final y = dt.y ?? base;
      var ts = DateTime.utc(y, dt.m, dt.d).millisecondsSinceEpoch;
      if (prev != null && ts < prev && dt.y == null) {
        ts = DateTime.utc(y + 1, dt.m, dt.d).millisecondsSinceEpoch;
      }
      r.ts = ts;
      prev = ts;
      final d2 = r.t.date2;
      if (d2 != null && r.days == null) {
        var ts2 = DateTime.utc(d2.y ?? y, d2.m, d2.d).millisecondsSinceEpoch;
        if (ts2 < ts) ts2 = DateTime.utc((d2.y ?? y) + 1, d2.m, d2.d).millisecondsSinceEpoch;
        r.days = _dayDiff(ts, ts2) + 1;
      }
    }
  }
  for (var i = 0; i < work.length; i++) {
    final r = work[i];
    if (r.days != null) continue;
    final mk = r.t.mark;
    if (mk != null) {
      for (var j = i + 1; j < work.length; j++) {
        final n = work[j].t.mark;
        if (n != null && n.u == mk.u && n.n > mk.n) {
          r.days = (n.n - mk.n) * (n.u == 'w' ? 7 : 1);
          break;
        }
      }
      if (r.days == null && mk.u == 'w') r.days = 7;
    } else if (r.ts != null) {
      for (var j = i + 1; j < work.length; j++) {
        final tj = work[j].ts;
        if (tj != null && tj > r.ts!) {
          r.days = _dayDiff(r.ts!, tj);
          break;
        }
      }
    }
  }
  final out = <_Out>[];
  for (final r in work) {
    final g = r.days == null || r.days! < 1;
    final dy = g ? defDays : r.days!;
    if (out.isNotEmpty && (out.last.dose - r.dose).abs() < 1e-9) {
      out.last.days += dy;
      out.last.guess = out.last.guess || g;
    } else {
      out.add(_Out(r.dose, dy, g));
    }
  }
  var unit = 'mg';
  var best = 0;
  uc.forEach((k, v) {
    if (v > best) {
      best = v;
      unit = k;
    }
  });
  final ts0 = work.isNotEmpty ? work.first.ts : null;
  final start = ts0 == null ? null : ymd(DateTime.fromMillisecondsSinceEpoch(ts0, isUtc: true));
  return ParsedPlan(out.map((o) => ParsedRow(o.dose, o.days, o.guess)).toList(), unit, start);
}

class _Out {
  double dose;
  int days;
  bool guess;
  _Out(this.dose, this.days, this.guess);
}
