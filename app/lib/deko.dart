// Look „Dämmerung“: Hintergrund-Verlauf, Blätter,
// Sonnenuntergang-Landschaft und Lavendel. Alles im Code gemalt – keine Bilddateien, bleibt auf jedem
// Bildschirm scharf.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hintergrund jeder Seite: Dämmerblau von oben nach unten, oben ein hängender Zweig.
/// Wird über das Seiten-Übergangs-Thema um jede Seite gelegt (siehe `main.dart`).
class Hintergrund extends StatelessWidget {
  const Hintergrund({super.key, required this.child, this.blaetter = true});
  final Widget child;
  final bool blaetter;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        key: const Key('hintergrund'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF314D76), Color(0xFF3F5E88), Color(0xFF55709C)],
            stops: [0, .5, 1],
          ),
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (blaetter)
            const IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _ObenMaler()))),
          child,
        ]),
      );
}

/// Zweig oben (Mitte rechts), dazu ein weiches Licht oben links.
class _ObenMaler extends CustomPainter {
  const _ObenMaler();
  @override
  void paint(Canvas c, Size s) {
    // Weiches Licht, damit der Verlauf nicht flach wirkt.
    c.drawCircle(
      Offset(s.width * .15, 30),
      s.width * .7,
      Paint()
        ..shader = RadialGradient(colors: [const Color(0x1AFFFFFF), const Color(0x00FFFFFF)])
            .createShader(Rect.fromCircle(center: Offset(s.width * .15, 30), radius: s.width * .7)),
    );
    final x = s.width * .66;
    // Stiel
    final stiel = Path()
      ..moveTo(x - 30, -6)
      ..quadraticBezierTo(x + 6, 4, x + 46, 22);
    c.drawPath(
        stiel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xCC8FA37A));
    const blaetter = [
      // dx, dy, Winkel, Länge, Breite
      (-26.0, -4.0, -2.2, 40.0, 17.0),
      (-12.0, 0.0, -2.75, 50.0, 20.0),
      (4.0, 4.0, 2.95, 54.0, 21.0),
      (20.0, 9.0, 2.45, 46.0, 19.0),
      (34.0, 15.0, 2.0, 40.0, 16.0),
      (44.0, 21.0, 1.35, 34.0, 14.0),
    ];
    for (final b in blaetter) {
      blatt(c, Offset(x + b.$1, b.$2), b.$3, b.$4, b.$5, deckkraft: .82);
    }
  }

  @override
  bool shouldRepaint(_ObenMaler old) => false;
}

/// Ein Blatt. [winkel] 0 = Spitze nach oben, positiv = im Uhrzeigersinn.
void blatt(Canvas c, Offset basis, double winkel, double laenge, double breite,
    {Color hell = const Color(0xFFDCE3B4),
    Color dunkel = const Color(0xFF93A877),
    double deckkraft = 1,
    bool schatten = true}) {
  c.save();
  c.translate(basis.dx, basis.dy);
  c.rotate(winkel);
  final p = Path()
    ..moveTo(0, 0)
    ..cubicTo(breite * .95, -laenge * .22, breite * .55, -laenge * .82, 0, -laenge)
    ..cubicTo(-breite * .55, -laenge * .82, -breite * .95, -laenge * .22, 0, 0)
    ..close();
  if (schatten) {
    c.drawPath(
        p.shift(const Offset(1.5, 2.5)),
        Paint()
          ..color = Color.fromRGBO(10, 20, 40, .22 * deckkraft)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }
  c.drawPath(
      p,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [dunkel.withValues(alpha: deckkraft), hell.withValues(alpha: deckkraft)],
        ).createShader(Rect.fromLTWH(-breite, -laenge, breite * 2, laenge)));
  final ader = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..color = dunkel.withValues(alpha: .7 * deckkraft)
    ..strokeWidth = math.max(.8, breite / 18);
  c.drawPath(
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(breite * .06, -laenge * .5, 0, -laenge * .9),
      ader);
  ader
    ..strokeWidth = math.max(.5, breite / 30)
    ..color = dunkel.withValues(alpha: .4 * deckkraft);
  for (var i = 1; i <= 3; i++) {
    final y = -laenge * (.2 + i * .17);
    final w = breite * (.42 - i * .07);
    c.drawLine(Offset(0, y), Offset(w, y - laenge * .1), ader);
    c.drawLine(Offset(0, y), Offset(-w, y - laenge * .1), ader);
  }
  c.restore();
}

/// Ein Lavendelzweig: Stiel, Blüten an der oberen Hälfte, zwei schmale Blätter unten.
void lavendel(Canvas c, Offset basis, double hoehe, double neigung, {double deckkraft = 1}) {
  final spitze = basis + Offset(math.sin(neigung) * hoehe, -math.cos(neigung) * hoehe);
  final mitte = Offset.lerp(basis, spitze, .5)! + Offset(hoehe * .05, 0);
  Offset punkt(double t) {
    // quadratische Kurve basis → mitte → spitze
    final a = Offset.lerp(basis, mitte, t)!;
    final b = Offset.lerp(mitte, spitze, t)!;
    return Offset.lerp(a, b, t)!;
  }

  c.drawPath(
      Path()
        ..moveTo(basis.dx, basis.dy)
        ..quadraticBezierTo(mitte.dx, mitte.dy, spitze.dx, spitze.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, hoehe / 60)
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(118, 136, 120, .9 * deckkraft));
  // schmale Blätter am Fuß
  blatt(c, punkt(.12), neigung - .55, hoehe * .26, hoehe * .05,
      hell: const Color(0xFFB9C7A2), dunkel: const Color(0xFF7D9172), deckkraft: .85 * deckkraft, schatten: false);
  blatt(c, punkt(.2), neigung + .5, hoehe * .22, hoehe * .045,
      hell: const Color(0xFFB9C7A2), dunkel: const Color(0xFF7D9172), deckkraft: .85 * deckkraft, schatten: false);
  const n = 11;
  for (var i = 0; i < n; i++) {
    final t = .42 + .58 * i / (n - 1);
    final p = punkt(t);
    final gr = 1 - .55 * i / (n - 1);
    final farbe = Color.lerp(const Color(0xFF7562B8), const Color(0xFFC3B2F0), i / (n - 1))!;
    for (final seite in [-1.0, 1.0]) {
      if (i == n - 1 && seite > 0) continue;
      c.save();
      c.translate(p.dx + seite * 2.6 * gr, p.dy);
      c.rotate(neigung + seite * .45);
      final r = Rect.fromCenter(center: Offset.zero, width: 4.6 * gr + 1.2, height: 7.5 * gr + 2);
      c.drawOval(r, Paint()..color = farbe.withValues(alpha: .95 * deckkraft));
      c.drawOval(
          Rect.fromCenter(center: Offset(-.6, -1.2 * gr), width: r.width * .45, height: r.height * .4),
          Paint()..color = Color.fromRGBO(240, 230, 255, .45 * deckkraft));
      c.restore();
    }
  }
}

/// Glatte Bergkette über die ganze Breite: [hoehen] = Gipfelhöhen (Anteil der Höhe), gleichmäßig verteilt.
Path _berge(Size s, double basis, List<double> hoehen) {
  final p = Path()..moveTo(0, s.height);
  final pts = [
    for (var i = 0; i < hoehen.length; i++) Offset(s.width * i / (hoehen.length - 1), s.height * (basis - hoehen[i]))
  ];
  p.lineTo(pts.first.dx, pts.first.dy);
  for (var i = 0; i < pts.length - 1; i++) {
    final m = Offset.lerp(pts[i], pts[i + 1], .5)!;
    p.quadraticBezierTo(pts[i].dx, pts[i].dy, m.dx, m.dy);
  }
  p
    ..lineTo(pts.last.dx, pts.last.dy)
    ..lineTo(s.width, s.height)
    ..close();
  return p;
}

/// Sonnenuntergang über Bergen, unten weich ins Kartenblau; rechts Lavendel.
/// Hintergrund der Stufen-Karte (Kalender).
class LandschaftMaler extends CustomPainter {
  const LandschaftMaler();
  @override
  void paint(Canvas c, Size s) {
    final h = s.height, w = s.width;
    final rect = Offset.zero & s;
    // Himmel
    c.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5B6E9F), Color(0xFF8380B0), Color(0xFFC796B4), Color(0xFFF0BCA4)],
            stops: [0, .22, .4, .5],
          ).createShader(rect));
    // Sonne mit Schein
    final sonne = Offset(w * .26, h * .42);
    final r = math.min(h * .12, 26.0);
    c.drawCircle(
        sonne,
        r * 4,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xB3FFE2B0), Color(0x00FFC9A0)])
              .createShader(Rect.fromCircle(center: sonne, radius: r * 4)));
    c.drawCircle(
        sonne,
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF6CF), Color(0xFFFFDC9A)],
          ).createShader(Rect.fromCircle(center: sonne, radius: r)));
    // Wolkenschleier
    c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(w * .1, h * .3, w * .45, h * .035), const Radius.circular(20)),
        Paint()
          ..color = const Color(0x33FFD6C8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    // Berge, hinten nach vorne
    void kette(double basis, List<double> hoehen, Color oben, Color unten) {
      final p = _berge(s, basis, hoehen);
      c.drawPath(
          p,
          Paint()
            ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [oben, unten])
                .createShader(Rect.fromLTWH(0, h * (basis - .16), w, h * .5)));
    }

    kette(.5, [.02, .06, .1, .05, .03, .08, .11, .07, .04, .06], const Color(0xFFAE93BD), const Color(0xFF9D8DBC));
    // Dunst
    c.drawRect(
        Rect.fromLTWH(0, h * .46, w, h * .12),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00FFFFFF), Color(0x26FFFFFF), Color(0x00FFFFFF)],
          ).createShader(Rect.fromLTWH(0, h * .46, w, h * .12)));
    kette(.58, [.06, .09, .05, .02, .04, .08, .05, .03, .06, .1, .07], const Color(0xFF8584B3),
        const Color(0xFF7479A9));
    kette(.65, [.08, .05, .03, .02, .03, .02, .04, .03, .05, .06, .04, .07], const Color(0xFF5F769F),
        const Color(0xFF55709A));
    // Baumreihe links
    final baeume = Path();
    for (var i = 0; i < 18; i++) {
      final x = w * (.01 + i * .018);
      final hb = h * (.035 + (i * 37 % 7) / 160);
      final y = h * (.62 - (i % 5) * .004);
      baeume
        ..moveTo(x - 3.5, y + 4)
        ..lineTo(x, y - hb)
        ..lineTo(x + 3.5, y + 4)
        ..close();
    }
    c.drawPath(baeume, Paint()..color = const Color(0xCC4E6890));
    // Unten weich ins Kartenblau (dort stehen Punkte und mg-Angaben)
    final unten = Rect.fromLTWH(0, h * .6, w, h * .4);
    c.drawRect(
        unten,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x0052709A), Color(0xF052709A), Color(0xFF4C6893)],
            stops: [0, .35, 1],
          ).createShader(unten));
    // Lavendel rechts
    c.drawCircle(
        Offset(w - 18, h * .5),
        h * .45,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0x26E9B6D2), Color(0x00E9B6D2)])
              .createShader(Rect.fromCircle(center: Offset(w - 18, h * .5), radius: h * .45)));
    lavendel(c, Offset(w - 22, h * 1.02), h * .62, -.2, deckkraft: .9);
    lavendel(c, Offset(w - 16, h * 1.02), h * .78, .02);
    lavendel(c, Offset(w - 10, h * 1.02), h * .55, .22, deckkraft: .85);
  }

  @override
  bool shouldRepaint(LandschaftMaler old) => false;
}

/// Lavendel und Blätter in einer Kartenecke unten links, mit rosa Schein (Karte „Heute eintragen“).
class LavendelEckeMaler extends CustomPainter {
  const LavendelEckeMaler();
  @override
  void paint(Canvas c, Size s) {
    final b = Offset(18, s.height + 6);
    c.drawCircle(
        b + const Offset(10, -30),
        90,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0x40F0B0C4), Color(0x00F0B0C4)])
              .createShader(Rect.fromCircle(center: b + const Offset(10, -30), radius: 90)));
    lavendel(c, b, 78, .32, deckkraft: .9);
    lavendel(c, b + const Offset(-8, 0), 92, .1);
    lavendel(c, b + const Offset(-14, 0), 64, -.15, deckkraft: .85);
    blatt(c, b + const Offset(8, -14), 1.05, 52, 16, deckkraft: .9);
    blatt(c, b + const Offset(24, -22), 1.35, 44, 14, deckkraft: .85);
    blatt(c, b + const Offset(42, -30), 1.0, 34, 12, deckkraft: .8);
  }

  @override
  bool shouldRepaint(LavendelEckeMaler old) => false;
}

/// Kleiner Blattzweig (im grünen Hauptknopf rechts).
class BlattZweigMaler extends CustomPainter {
  const BlattZweigMaler();
  @override
  void paint(Canvas c, Size s) {
    final b = Offset(s.width * .55, s.height * .95);
    const hell = Color(0xFFE6F2C4), dunkel = Color(0xFF7FAE62);
    blatt(c, b, -.55, s.height * .62, s.height * .26, hell: hell, dunkel: dunkel, deckkraft: .85, schatten: false);
    blatt(c, b, .15, s.height * .8, s.height * .3, hell: hell, dunkel: dunkel, deckkraft: .9, schatten: false);
    blatt(c, b, .85, s.height * .6, s.height * .24, hell: hell, dunkel: dunkel, deckkraft: .8, schatten: false);
  }

  @override
  bool shouldRepaint(BlattZweigMaler old) => false;
}

/// Blattzweig rechts im grünen Hauptknopf (der Knopf hält rechts Platz dafür frei).
class KnopfBlattMaler extends CustomPainter {
  const KnopfBlattMaler();
  @override
  void paint(Canvas c, Size s) {
    final h = math.min(s.height - 10, 40.0);
    c.save();
    c.translate(s.width - 12 - h * .8, (s.height - h) / 2);
    const BlattZweigMaler().paint(c, Size(h * .8, h));
    c.restore();
  }

  @override
  bool shouldRepaint(KnopfBlattMaler old) => false;
}
