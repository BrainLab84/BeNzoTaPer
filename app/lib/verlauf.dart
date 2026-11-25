// Reiter „Fortschritt“: wie weit man schon gekommen ist.
// Plan als gestrichelte Treppe, tatsächliche Einnahme als Welle (Durchschnitt der letzten 7 Tage),
// Tage über Plan als kleine Punkte. Keine Prozente. Daten aus dem Kern (`Taper.verlauf`).
import 'i18n/txt.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bericht.dart';
import 'logbuch.dart';
import 'bausteine.dart';
import 'plan_kopf.dart';

class VerlaufSeite extends StatelessWidget {
  const VerlaufSeite({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final ta = app.taper;
    final s = ta.s;
    if (s == null) {
      return OhnePlanHinweis(tr('Hier siehst du, wie weit du schon gekommen bist, sobald dein Plan angelegt ist.', 'Once your plan is set up, you can see here how far you have come.'),
          icon: Icons.insights_outlined);
    }
    final v = ta.verlauf();
    final today = ta.today;
    final heuteIdx = v.tage.indexWhere((x) => x.tag == today);
    final last = s.stage >= s.plan.length - 1;
    // Letzte Stufe erreicht = Ziel erreicht (auch wenn das Ziel nicht 0 mg ist).
    final ziel = last;
    final ende = ta.voraussichtlichesEnde();
    final geschafft = math.max(0, dBetween(ta.t0Of() ?? today, today));
    final hatWelle = v.tage.any((x) => x.schnitt7 != null);
    double? zuletzt;
    for (final x in v.tage) {
      if (x.schnitt7 != null) zuletzt = x.schnitt7;
    }

    Widget zahl(String gross, String klein) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(color: F.card2, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(gross, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 2),
              Text(klein, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: F.mu)),
            ]),
          ),
        );

    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      if (app.beispiel) const BeispielHinweis(),
      Karte(key: const Key('wegKarte'), children: [
        KartenTitel(tr('Dein Weg', 'Your journey'), icon: Icons.insights_outlined),
        Text(
          s.stage == 0
              ? tr('Start bei ${fz(s.plan.first)} ${s.unit}', 'Start at ${fz(s.plan.first)} ${s.unit}')
              : tr('Von ${fz(s.plan.first)} ${s.unit} auf ${fz(s.plan[s.stage])} ${s.unit}', 'From ${fz(s.plan.first)} ${s.unit} to ${fz(s.plan[s.stage])} ${s.unit}'),
          key: const Key('wegZeile'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final werte = [
            ('$geschafft', geschafft == 1 ? tr('Tag geschafft', 'day done') : tr('Tage geschafft', 'days done')),
            (tr('${s.stage + 1} von ${s.plan.length}', '${s.stage + 1} of ${s.plan.length}'), tr('Stufe', 'Step')),
            (ziel ? tr('Erreicht', 'Reached') : (ende != null ? datum(ende) : '–'), ziel ? tr('Ziel ${fz(s.plan.last)} ${s.unit}', 'Goal ${fz(s.plan.last)} ${s.unit}') : tr('Voraussichtlich\nbei ${fz(s.plan.last)} ${s.unit}', 'Expected\nat ${fz(s.plan.last)} ${s.unit}')),
          ];
          // Schmal oder große Schrift: als Liste untereinander statt drei enger Kästchen.
          if (c.maxWidth < MediaQuery.textScalerOf(context).scale(300)) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: F.card2, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                for (final (gross, klein) in werte)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Expanded(child: Text(klein, style: const TextStyle(color: F.mu))),
                      const SizedBox(width: 8),
                      Text(gross, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            );
          }
          return Row(children: [
            for (var i = 0; i < werte.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              zahl(werte[i].$1, werte[i].$2),
            ],
          ]);
        }),
      ]),
      Karte(key: const Key('diagramm'), children: [
        KartenTitel(tr('Verlauf', 'History'), hilfe: 'avg'),
        Semantics(
          label: tr('Diagramm: Plan als Treppe, Durchschnitt der letzten 7 Tage als Welle', 'Chart: plan as a staircase, 7-day average as a wave'),
          child: SizedBox(
            height: 340, // etwas größer als früher (260)
            child: CustomPaint(
                painter:
                    VerlaufMaler(v.tage, heuteIdx, schrift: Theme.of(context).textTheme.bodySmall ?? const TextStyle()),
                size: Size.infinite),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          const SizedBox(width: VerlaufMaler.achse),
          // Mit Jahr sind die Daten länger: bei schmalem Handy/großer Schrift verkleinern statt überlaufen.
          for (final (d, links) in [(v.start, true), (v.bis, false)])
            Expanded(
              child: Align(
                alignment: links ? Alignment.centerLeft : Alignment.centerRight,
                child: FittedBox(
                    fit: BoxFit.scaleDown, child: Text(datum(d), style: const TextStyle(fontSize: 12, color: F.mu))),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _legende(const _Strich(F.ac2, false),
              tr('Ø 7 Tage${zuletzt != null ? ' · zuletzt ${fz(round2(zuletzt))} ${s.unit}' : ''}', 'Avg. 7 days${zuletzt != null ? " · latest ${fz(round2(zuletzt))} ${s.unit}" : ""}')),
          _legende(const _Strich(F.mu, true), tr('Plan', 'Plan')),
          _legende(
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: F.bad, shape: BoxShape.circle)),
              tr('mehr genommen', 'took more')),
        ]),
        if (!hatWelle)
          Sub(tr('Trag deine Einnahmen ein – dann zeigt die Welle, was du tatsächlich genommen hast.', 'Log your intakes – then the wave shows what you actually took.'), oben: 10),
        if (s.frz != null) Sub(tr('Offene Tage – Anzeigen pausieren bis zum Nachtragen.', 'Open days – displays pause until filled in.'), oben: 10),
      ]),
      // Diagramm für den Arzt – teilen und lesen (nicht im Beispiel).
      if (!app.beispiel) Padding(padding: const EdgeInsets.only(top: 2), child: berichtKnoepfe(context, app)),
      // Verlaufsbericht (Logbuch) – eigene Karte, unabhängig vom Diagramm.
      if (!app.beispiel) Padding(padding: const EdgeInsets.only(top: 14), child: LogbuchKarte(app: app)),
    ]);
  }

  Widget _legende(Widget zeichen, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        zeichen,
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 12, color: F.mu))),
      ]);
}

class _Strich extends StatelessWidget {
  const _Strich(this.farbe, this.gestrichelt);
  final Color farbe;
  final bool gestrichelt;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 3,
        child: gestrichelt
            ? Row(children: [
                Expanded(child: Container(color: farbe)),
                const SizedBox(width: 3),
                Expanded(child: Container(color: farbe)),
                const SizedBox(width: 3),
                Expanded(child: Container(color: farbe)),
              ])
            : DecoratedBox(decoration: BoxDecoration(color: farbe, borderRadius: BorderRadius.circular(2))),
      );
}

/// Farben des Diagramms: App (dunkler Grund) oder Papier (Arzt-Bericht, weißer Grund).
class MalerFarben {
  const MalerFarben({required this.line, required this.mu, required this.ac, required this.ac2, required this.bad});
  final Color line, mu, ac, ac2, bad;
  static const app = MalerFarben(line: F.line, mu: F.mu, ac: F.ac, ac2: F.ac2, bad: F.bad);
  static const papier = MalerFarben(
      line: Color(0xFFBFC5CF),
      mu: Color(0xFF4A5160),
      ac: Color(0xFF3E7A2E),
      ac2: Color(0xFF4E9A3A),
      bad: Color(0xFFD03A4A));
}

/// Zeichnet Treppe (Plan), Welle (7-Tage-Ø), Punkte (über Plan) und die Heute-Linie.
class VerlaufMaler extends CustomPainter {
  VerlaufMaler(this.tage, this.heuteIdx, {this.schrift = const TextStyle(), this.farben = MalerFarben.app});
  final List<VerlaufTag> tage;
  final int heuteIdx;
  final MalerFarben farben;

  /// Schrift der App (der Maler erbt sie nicht von selbst).
  final TextStyle schrift;

  /// Platz links für die mg-Beschriftung.
  static const achse = 30.0;

  /// Runde Abstände für die Hilfslinien: höchstens 4 Abschnitte.
  static double schrittweite(double max) {
    for (final m in [1.0, 10.0, 100.0, 1000.0]) {
      for (final g in [0.25, 0.5, 1.0, 2.0, 2.5, 5.0]) {
        if (max / (g * m) <= 4) return g * m;
      }
    }
    return max;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = tage.length;
    if (n == 0) return;
    var maxY = 0.0;
    for (final t in tage) {
      for (final w in [t.plan, t.schnitt7, t.dosis]) {
        if (w != null && w > maxY) maxY = w;
      }
    }
    if (!(maxY > 0)) maxY = 1;
    final schritt = schrittweite(maxY);
    maxY *= 1.1;
    const pl = achse + 4, pr = 4.0, pt = 8.0, pb = 4.0;
    final b = size.width - pl - pr, h = size.height - pt - pb;
    double x(int i) => pl + (n == 1 ? b / 2 : i * b / (n - 1));
    double y(double v) => pt + (1 - v / maxY) * h;

    // Hilfslinien mit mg-Werten, Nulllinie kräftiger
    for (var k = 0; k * schritt <= maxY + 1e-9; k++) {
      final w = k * schritt, yy = y(w);
      canvas.drawLine(
          Offset(achse, yy), Offset(size.width, yy), Paint()..color = k == 0 ? farben.line : farben.line.withValues(alpha: .45));
      final tp = TextPainter(
        text: TextSpan(text: fz(w), style: schrift.copyWith(fontSize: 11, color: farben.mu)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(achse - 6 - tp.width, (yy - tp.height / 2).clamp(0, size.height - tp.height)));
    }

    // Heute
    if (heuteIdx >= 0) {
      _gestrichelt(
          canvas,
          Path()
            ..moveTo(x(heuteIdx), 0)
            ..lineTo(x(heuteIdx), size.height),
          Paint()
            ..color = farben.ac.withValues(alpha: .5)
            ..strokeWidth = 1,
          2,
          3);
    }

    // Plan als Treppe (gestrichelt): bis heute kräftig, danach blasser.
    Path treppe(Iterable<int> idx) {
      final p = Path();
      double? vorher;
      for (final i in idx) {
        final w = tage[i].plan;
        if (w == null) {
          vorher = null;
          continue;
        }
        if (vorher == null) {
          p.moveTo(x(i), y(w));
        } else {
          p
            ..lineTo(x(i), y(vorher))
            ..lineTo(x(i), y(w));
        }
        vorher = w;
      }
      return p;
    }

    final bisHeute = heuteIdx >= 0 ? heuteIdx : n - 1;
    final stift = Paint()
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _gestrichelt(canvas, treppe([for (var i = 0; i <= bisHeute; i++) i]), stift..color = farben.mu, 4, 3);
    if (bisHeute < n - 1) {
      _gestrichelt(
          canvas,
          treppe([for (var i = bisHeute; i < n; i++) i]),
          Paint()
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke
            ..color = farben.mu.withValues(alpha: .55),
          4,
          3);
    }

    // Welle: 7-Tage-Ø, weich verbunden, mit leichter Fläche darunter. Wo eine ganze Woche ohne
    // Eintrag ist (kein Ø), reißt die Welle ab – sie erfindet nichts dazwischen.
    final stuecke = <List<Offset>>[];
    var aktuell = <Offset>[];
    for (var i = 0; i < n; i++) {
      final w = tage[i].schnitt7;
      if (w != null) {
        aktuell.add(Offset(x(i), y(w)));
      } else if (aktuell.isNotEmpty && !tage[i].zukunft) {
        stuecke.add(aktuell);
        aktuell = <Offset>[];
      }
    }
    if (aktuell.isNotEmpty) stuecke.add(aktuell);
    for (final punkte in stuecke) {
      final welle = Path()..moveTo(punkte.first.dx, punkte.first.dy);
      for (var i = 1; i < punkte.length; i++) {
        final a = punkte[i - 1], c = punkte[i];
        final m = Offset((a.dx + c.dx) / 2, (a.dy + c.dy) / 2);
        welle.quadraticBezierTo(a.dx, a.dy, m.dx, m.dy);
      }
      welle.lineTo(punkte.last.dx, punkte.last.dy);
      final flaeche = Path.from(welle)
        ..lineTo(punkte.last.dx, y(0))
        ..lineTo(punkte.first.dx, y(0))
        ..close();
      canvas.drawPath(
          flaeche,
          Paint()
            ..shader = ui.Gradient.linear(
                Offset(0, pt), Offset(0, y(0)), [farben.ac2.withValues(alpha: .28), farben.ac2.withValues(alpha: 0)]));
      final stift2 = Paint()
        ..color = farben.ac2
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      if (punkte.length == 1) {
        canvas.drawCircle(punkte.first, 2, Paint()..color = farben.ac2);
      } else {
        canvas.drawPath(welle, stift2);
      }
    }
    if (stuecke.isNotEmpty) canvas.drawCircle(stuecke.last.last, 3.5, Paint()..color = farben.ac2);

    // Tage über Plan
    for (var i = 0; i < n; i++) {
      final t = tage[i];
      if (t.dosis != null && t.plan != null && t.dosis! > t.plan! + 1e-9) {
        canvas.drawCircle(Offset(x(i), y(t.dosis!)), 3, Paint()..color = farben.bad);
      }
    }
  }

  void _gestrichelt(Canvas c, Path p, Paint paint, double an, double aus) {
    paint.style = PaintingStyle.stroke;
    for (final m in p.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        c.drawPath(m.extractPath(d, math.min(d + an, m.length)), paint);
        d += an + aus;
      }
    }
  }

  @override
  bool shouldRepaint(VerlaufMaler old) => old.tage != tage || old.heuteIdx != heuteIdx || old.schrift != schrift || old.farben != farben;
}
