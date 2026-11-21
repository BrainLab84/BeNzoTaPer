// Plan berechnen und Tablettenkombinationen finden (reine Rechnung).
import 'meldung.dart';
import 'util.dart';

/// Plan von [start] bis [target] in Schritten von [step] (Rundung auf [minStep]).
/// Die Rundung läuft über den Gesamtverlauf, der Schritt wird im Mittel eingehalten.
List<double> makePlan(double start, double step, double minStep, double target) {
  final plan = <double>[start];
  var d = start;
  var n = 0;
  while (d > target + 1e-9 && n < 2000) {
    n++;
    var nx = jsRound((start - n * step) / minStep) * minStep;
    if (nx >= d - 1e-9) nx = d - minStep;
    if (nx <= target + 1e-9 || nx < minStep - 1e-9) nx = target;
    nx = round3(nx);
    plan.add(nx);
    d = nx;
  }
  return plan;
}

/// Obergrenzen gegen unsinnige Eingaben (z. B. 50 Mio. Tage ließen die Datumsrechnung
/// abstürzen). Großzügig – keine fachliche Vorgabe: höchstens 10 Jahre je Stufe, 100 Jahre insgesamt.
const maxStufenTage = 3650;
const maxPlanTage = 36500;

/// Fehlertext, wenn eine Stufe oder der ganze Plan zu lang ist, sonst `null`.
Meldung? planLaengeFehler(List<int> days) {
  for (var i = 0; i < days.length; i++) {
    if (days[i] > maxStufenTage) return Meldung(MeldungCode.stufeMaxTage, [i + 1, maxStufenTage]);
  }
  var sum = 0;
  for (final d in days) {
    sum += d;
  }
  if (sum > maxPlanTage) return const Meldung(MeldungCode.planZuLang);
  return null;
}

/// Ein Abschnitt beim Plan-Erstellen: „runter um [schritt] alle [tage] Tage bis [bis]“.
class Abschnitt {
  final double schritt;
  final int tage;
  final double bis;
  const Abschnitt(this.schritt, this.tage, this.bis);
}

/// Ergebnis von [planAusAbschnitten]: Stufen und Tage je Stufe, oder ein Fehlertext.
class AbschnittsPlan {
  final List<double> plan;
  final List<int> days;
  final Meldung? fehler;
  const AbschnittsPlan(this.plan, this.days, [this.fehler]);
}

/// Baut aus der aktuellen Dosis [start] und den [abschnitte]n einen Plan.
/// In jedem Abschnitt geht es um `schritt` runter, bis `bis` erreicht ist (der letzte Schritt kann
/// kleiner sein). Jede Stufe dauert die Tage ihres Abschnitts; die Stufe, mit der ein Abschnitt
/// endet, gehört schon zum nächsten (dort beginnt dessen Rhythmus).
AbschnittsPlan planAusAbschnitten(double start, List<Abschnitt> abschnitte) {
  if (!(start > 0)) return const AbschnittsPlan([], [], Meldung(MeldungCode.abschnittStartdosis));
  if (abschnitte.isEmpty) return const AbschnittsPlan([], [], Meldung(MeldungCode.abschnittKeiner));
  final plan = <double>[round3(start)];
  final days = <int>[];
  var cur = round3(start);
  for (var i = 0; i < abschnitte.length; i++) {
    final a = abschnitte[i];
    final nr = abschnitte.length > 1 ? i + 1 : 0;
    if (!(a.schritt > 0)) return AbschnittsPlan([], [], Meldung(MeldungCode.abschnittSchritt, [nr]));
    if (!(a.tage >= 1)) return AbschnittsPlan([], [], Meldung(MeldungCode.abschnittTage, [nr]));
    if (a.tage > maxStufenTage) return AbschnittsPlan([], [], Meldung(MeldungCode.abschnittMaxTage, [nr, maxStufenTage]));
    if (a.bis.isNaN) {
      return AbschnittsPlan([], [], Meldung(MeldungCode.abschnittBisFehlt, [nr]));
    }
    if (a.bis < 0) return AbschnittsPlan([], [], Meldung(MeldungCode.abschnittBisNegativ, [nr]));
    if (a.bis >= cur - 1e-9) {
      // Häufigster Fall: der vorige Abschnitt geht schon bis zum Ziel.
      if (i > 0 && cur <= 1e-9) {
        return AbschnittsPlan([], [], Meldung(MeldungCode.abschnittEndetBeiNull, [i]));
      }
      return AbschnittsPlan([], [],
          i == 0
              ? Meldung(MeldungCode.abschnittBisUeberStart, [nr, cur])
              : Meldung(MeldungCode.abschnittBisUeberVorigem, [nr, cur, i]));
    }
    // Die Stufe, mit der dieser Abschnitt beginnt, läuft in seinem Rhythmus.
    days.add(a.tage);
    while (cur - a.schritt > a.bis + 1e-9) {
      cur = round3(cur - a.schritt);
      plan.add(cur);
      days.add(a.tage);
      if (plan.length > 2000)
        return const AbschnittsPlan([], [], Meldung(MeldungCode.abschnittZuViele));
    }
    cur = round3(a.bis);
    plan.add(cur);
  }
  // Letzte Stufe: Rhythmus des letzten Abschnitts.
  days.add(abschnitte.last.tage);
  final lang = planLaengeFehler(days.take(days.length - 1).toList());
  if (lang != null) return AbschnittsPlan([], [], lang);
  return AbschnittsPlan(plan, days);
}

/// Ein Teil der Kombination: [f] Tabletten (auch Bruchteile) der Stärke [s].
class ComboPart {
  final double s;
  final double f;
  const ComboPart(this.s, this.f);
}

class Combo {
  final bool exact;
  final List<ComboPart> parts;
  final double val;
  // nur wenn nicht exakt:
  final double? lo;
  final double? hi;
  final List<ComboPart> loParts;
  final List<ComboPart>? hiParts;
  const Combo.exact(this.parts, this.val)
      : exact = true,
        lo = null,
        hi = null,
        loParts = const [],
        hiParts = null;
  const Combo.inexact(this.lo, this.hi, this.loParts, this.hiParts)
      : exact = false,
        parts = const [],
        val = 0;
}

class _Piece {
  final double s;
  final double f;
  final int v;
  final int c;
  _Piece(this.s, this.f, this.v, this.c);
}

/// Kombination aus Tablettenstärken/Teilstücken für eine Dosis
/// (wenigste Stücke, ganze bevorzugt). `null`, wenn nichts passt.
Combo? combo(double dose, List<double> strs, double split) {
  strs = strs.where((x) => x > 0).toList();
  if (strs.isEmpty) return null;
  if (!(dose > 0)) return const Combo.exact([], 0);
  final n = (split > 0 ? jsRound(1 / split) : 1).toInt().clamp(1, 1 << 30);
  final pcs = <_Piece>[];
  for (final st in strs) {
    for (var k = 1; k <= n; k++) {
      pcs.add(_Piece(st, k / n, jsRound(st * k / n * 1000).toInt(), k == n ? 10 : 11));
    }
  }
  var u = 0;
  for (final p in pcs) {
    u = gcd(u, p.v);
  }
  if (u == 0) return null;
  final t = jsRound(dose * 1000).toInt();
  var maxPiece = 0;
  for (final p in pcs) {
    final x = p.v ~/ u;
    if (x > maxPiece) maxPiece = x;
  }
  final mx = (t / u).ceil() + maxPiece;
  if (mx > 20000) return null;
  final best = List<double>.filled(mx + 1, double.infinity)..[0] = 0;
  final ch = List<int>.filled(mx + 1, -1);
  for (var x = 1; x <= mx; x++) {
    for (var j = 0; j < pcs.length; j++) {
      final pu = pcs[j].v ~/ u;
      if (pu <= x && best[x - pu] + pcs[j].c < best[x]) {
        best[x] = best[x - pu] + pcs[j].c;
        ch[x] = j;
      }
    }
  }
  List<ComboPart> build(int x) {
    final g = <double, double>{};
    while (x > 0) {
      final p = pcs[ch[x]];
      g[p.s] = (g[p.s] ?? 0) + p.f;
      x -= p.v ~/ u;
    }
    final keys = g.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys.map((st) => ComboPart(st, round3(g[st]!))).toList();
  }

  if (t % u == 0 && best[t ~/ u].isFinite) {
    return Combo.exact(build(t ~/ u), dose);
  }
  var lo = t ~/ u;
  var hi = (t / u).ceil();
  while (lo > 0 && !best[lo].isFinite) {
    lo--;
  }
  while (hi <= mx && !best[hi].isFinite) {
    hi++;
  }
  return Combo.inexact(
    lo > 0 ? lo * u / 1000 : 0,
    hi <= mx ? hi * u / 1000 : null,
    lo > 0 ? build(lo) : const [],
    hi <= mx ? build(hi) : null,
  );
}

/// Bruchteil als Text: 0,5 -> "½", 1,25 -> "1¼".
String fracStr(double f) {
  final w = (f + 1e-9).floor();
  final r = jsRound((f - w) * 100) / 100;
  final m = {0.25: '¼', 0.5: '½', 0.75: '¾'};
  if (r < 1e-9) return '$w';
  if (m.containsKey(r)) return '${w > 0 ? w : ''}${m[r]}';
  return numStr(jsRound(f * 100) / 100).replaceAll('.', ',');
}

/// "1½ × 5 mg + 1 × 2 mg"
String partsStr(List<ComboPart> parts, String unit) =>
    parts.map((p) => '${fracStr(p.f)} × ${numStr(p.s).replaceAll('.', ',')} $unit').join(' + ');
