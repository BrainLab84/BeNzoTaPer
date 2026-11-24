// Diagramm für den Arzt: nur das Verlaufs-Diagramm, immer der komplette
// Verlauf, als PDF zum Teilen – und zum Lesen direkt in der App. Knöpfe im Fortschritt unter dem Diagramm.
//
// Das ganze Blatt (Kopf, Diagramm, Datumsleiste, Legende) wird als Bild gezeichnet – derselbe Maler wie im
// Fortschritt, nur in Papier-Farben – und als einzige Seite (A4 quer) ins PDF gelegt. Lesen zeigt
// genau dieses Bild. Paket: pdf (Apache-2.0, reines Dart).
import 'i18n/txt.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'verlauf.dart';

/// Blattgröße (logisch, Seitenverhältnis A4 quer) und Bildschärfe.
const berichtBreite = 1123.0, berichtHoehe = 794.0, berichtSchaerfe = 2.0;

const _schwarz = Color(0xFF1F2430);

String berichtDateiname(DateTime jetzt) {
  final k = ymd(jetzt);
  return tr('Verlauf_$k.pdf', 'History_$k.pdf');
}

/// Zeichnet das Blatt auf [c] (Größe [berichtBreite] × [berichtHoehe]).
void berichtZeichnen(Canvas c, AppState app, {TextStyle schrift = const TextStyle()}) {
  final ta = app.taper;
  final s = ta.st;
  final v = ta.verlauf(max: 100000);
  final heute = ta.today;
  final heuteIdx = v.tage.indexWhere((x) => x.tag == heute);
  final mu = MalerFarben.papier.mu;

  void text(String t, Offset o, {double gr = 13, bool fett = false, Color? farbe, bool rechts = false, bool mitte = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: schrift.copyWith(
              fontSize: gr, fontWeight: fett ? FontWeight.w700 : FontWeight.w400, color: farbe ?? _schwarz)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(rechts ? o.dx - tp.width : (mitte ? o.dx - tp.width / 2 : o.dx), o.dy));
  }

  c.drawRect(const Rect.fromLTWH(0, 0, berichtBreite, berichtHoehe), Paint()..color = Colors.white);
  const rand = 40.0;
  text(tr('Verlauf · ${s.name}', 'History · ${s.name}'), const Offset(rand, 32), gr: 24, fett: true);
  final ende = ta.voraussichtlichesEnde();
  text(
      tr('Start ${datum(v.start)}  ·  heute ${datum(heute)}'
      '${ende != null && ende.compareTo(heute) > 0 ? '  ·  voraussichtlich bei ${fz(s.plan.last)} ${s.unit}: ${datum(ende)}' : ''}', 'Start ${datum(v.start)}  ·  today ${datum(heute)}${ende != null && ende.compareTo(heute) > 0 ? "  ·  expected at ${fz(s.plan.last)} ${s.unit}: ${datum(ende)}" : ""}'),
      const Offset(rand, 66),
      gr: 14,
      farbe: mu);

  // Diagramm
  const oben = 124.0, hoehe = 520.0;
  const flaeche = Rect.fromLTWH(rand, oben, berichtBreite - 2 * rand, hoehe);
  c.save();
  c.translate(flaeche.left, flaeche.top);
  VerlaufMaler(v.tage, heuteIdx, schrift: schrift.copyWith(fontSize: 12), farben: MalerFarben.papier)
      .paint(c, flaeche.size);
  c.restore();
  // Achsenbeschriftung mg
  text(s.unit, Offset(flaeche.left, oben - 20), gr: 12, farbe: mu);

  // Datumsleiste: Monatsanfänge (wie VerlaufMaler: links Achse + 4, rechts 4)
  final n = v.tage.length;
  const pl = VerlaufMaler.achse + 4, pr = 4.0;
  final b = flaeche.width - pl - pr;
  double x(int i) => flaeche.left + pl + (n <= 1 ? b / 2 : i * b / (n - 1));
  final monate = <int>[for (var i = 0; i < n; i++) if (v.tage[i].tag.endsWith('-01')) i];
  final jede = (monate.length / 12).ceil().clamp(1, 1000);
  final unten = oben + hoehe + 8;
  final strich = Paint()
    ..color = MalerFarben.papier.line
    ..strokeWidth = 1;
  for (var k = 0; k < monate.length; k += jede) {
    final i = monate[k];
    final p = v.tage[i].tag.split('-');
    c.drawLine(Offset(x(i), oben + hoehe - 4), Offset(x(i), oben + hoehe + 4), strich);
    text('${int.parse(p[1])}/${p[0].substring(2)}', Offset(x(i), unten), gr: 12, farbe: mu, mitte: true);
  }
  // Zweite Zeile: Start, Ende, „heute“ – ohne sich zu überdecken (Plan seit gestern oder
  // heute kurz vor dem Ende ließ „heute“ über Start/Ende liegen). Start steht ohnehin auch im Kopf.
  double breite(String t) => (TextPainter(
        text: TextSpan(text: t, style: schrift.copyWith(fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout())
          .width;
  final sT = datum(v.start), eT = datum(v.bis), hT = tr('heute ${datum(heute)}', 'today ${datum(heute)}');
  final sB = (x(0) - breite(sT) / 2, x(0) + breite(sT) / 2);
  final eB = (x(n - 1) - breite(eT), x(n - 1));
  final zeigeHeute = heuteIdx > 0 && heuteIdx < n - 1;
  final hB = zeigeHeute ? (x(heuteIdx) - breite(hT) / 2, x(heuteIdx) + breite(hT) / 2) : null;
  final platz = berichtDatumPlatz(sB, eB, hB);
  if (platz.start) text(sT, Offset(x(0), unten + 18), gr: 12, farbe: mu, mitte: true);
  if (n > 1 && platz.ende) text(eT, Offset(x(n - 1), unten + 18), gr: 12, farbe: mu, rechts: true);
  if (zeigeHeute) text(hT, Offset(x(heuteIdx), unten + 18), gr: 12, farbe: MalerFarben.papier.ac, mitte: true);

  // Legende
  var lx = rand;
  final ly = berichtHoehe - 52;
  void eintrag(void Function(Offset) zeichen, String t) {
    zeichen(Offset(lx, ly + 9));
    final tp = TextPainter(
      text: TextSpan(text: t, style: schrift.copyWith(fontSize: 13, color: _schwarz)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(lx + 30, ly));
    lx += 30 + tp.width + 28;
  }

  final f = MalerFarben.papier;
  eintrag(
      (o) => c.drawLine(o, o.translate(22, 0), Paint()
        ..color = f.ac2
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round),
      tr('Ø 7 Tage (tatsächlich genommen)', 'Avg. 7 days (actually taken)'));
  eintrag((o) {
    final p = Paint()
      ..color = f.mu
      ..strokeWidth = 1.5;
    for (var d = 0.0; d < 22; d += 7) {
      c.drawLine(o.translate(d, 0), o.translate(d + 4, 0), p);
    }
  }, tr('Plan (danach blasser: voraussichtlich)', 'Plan (fainter afterwards: expected)'));
  eintrag((o) => c.drawCircle(o.translate(11, 0), 4, Paint()..color = f.bad), tr('mehr genommen als geplant', 'taken more than planned'));
  eintrag((o) {
    final p = Paint()
      ..color = f.ac.withValues(alpha: .6)
      ..strokeWidth = 1.5;
    for (var d = -9.0; d < 9; d += 5) {
      c.drawLine(o.translate(11, d), o.translate(11, d + 2), p);
    }
  }, tr('heute', 'today'));
}

/// Haben Start- und End-Datum neben „heute“ Platz? Bereiche als (links, rechts); [luft] Mindestabstand.
/// „heute“ hat Vorrang; Start und Ende weichen. Überdecken sich Start und Ende (sehr kurzer Verlauf),
/// bleibt nur der Start.
({bool start, bool ende}) berichtDatumPlatz((double, double) start, (double, double) ende, (double, double)? heute,
    {double luft = 10}) {
  bool ueber((double, double) a, (double, double) b) => a.$1 < b.$2 + luft && b.$1 < a.$2 + luft;
  final s = heute == null || !ueber(start, heute);
  var e = heute == null || !ueber(ende, heute);
  if (s && e && ueber(start, ende)) e = false;
  return (start: s, ende: e);
}

/// Das Blatt als PNG.
Future<Uint8List> berichtBild(AppState app, {TextStyle schrift = const TextStyle()}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(berichtSchaerfe);
  berichtZeichnen(c, app, schrift: schrift);
  final bild = await rec
      .endRecording()
      .toImage((berichtBreite * berichtSchaerfe).round(), (berichtHoehe * berichtSchaerfe).round());
  final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();
  return daten!.buffer.asUint8List();
}

/// PDF mit einer Seite (A4 quer), darauf das Blatt.
Future<Uint8List> berichtPdf(Uint8List png, {String? titel}) {
  titel ??= tr('Verlauf', 'History');
  final doc = pw.Document(title: titel, creator: 'BeNzoTaPer');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(14),
    build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)),
  ));
  return doc.save();
}

/// Bauen und teilen. Fehler → kurze Meldung.
Future<void> berichtTeilen(BuildContext context, AppState app) async {
  final bote = ScaffoldMessenger.of(context);
  final schrift = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
  try {
    final png = await berichtBild(app, schrift: schrift);
    final pdf = await berichtPdf(png, titel: tr('Verlauf ${app.taper.st.name}', 'History ${app.taper.st.name}'));
    await app.dateien.teilenBytes(berichtDateiname(app.taper.clock()), pdf, 'application/pdf');
  } catch (_) {
    bote.showSnackBar(SnackBar(content: Text(tr('Das PDF konnte nicht erstellt werden.', 'The PDF could not be created.'))));
  }
}

/// „Lesen“: das Blatt in der App (zoombar), unten Teilen.
class BerichtSeite extends StatefulWidget {
  const BerichtSeite({super.key, required this.app});
  final AppState app;

  @override
  State<BerichtSeite> createState() => _BerichtSeiteState();
}

class _BerichtSeiteState extends State<BerichtSeite> {
  Future<Uint8List>? _bild;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bild ??= berichtBild(widget.app, schrift: Theme.of(context).textTheme.bodyMedium ?? const TextStyle());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Diagramm für den Arzt', 'Chart for the doctor'))),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: FutureBuilder<Uint8List>(
                future: _bild,
                builder: (context, snap) {
                  if (snap.hasError) return Center(child: Text(tr('Das Blatt konnte nicht erstellt werden.', 'The sheet could not be created.')));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  return InteractiveViewer(
                    key: const Key('berichtBlatt'),
                    maxScale: 6,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(snap.data!, gaplessPlayback: true),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Sub(tr('Mit zwei Fingern vergrößern. Handy quer drehen zeigt es größer.', 'Zoom with two fingers. Turning the phone sideways shows it larger.'), mitte: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: knopf(tr('Als PDF teilen', 'Share as PDF'), () => berichtTeilen(context, widget.app),
                  icon: Icons.share_outlined, key: const Key('berichtTeilenSeite')),
            ),
          ]),
        ),
      );
}

/// Die zwei Knöpfe unter dem Diagramm im Fortschritt.
Widget berichtKnoepfe(BuildContext context, AppState app) => LayoutBuilder(builder: (context, c) {
      final teilen = knopf(tr('Diagramm als PDF teilen', 'Share chart as PDF'), () => berichtTeilen(context, app),
          icon: Icons.picture_as_pdf_outlined, key: const Key('berichtTeilen'));
      final lesen = knopf(tr('Lesen', 'Read'), () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => BerichtSeite(app: app)));
      }, icon: Icons.visibility_outlined, key: const Key('berichtLesen'));
      if (c.maxWidth < MediaQuery.textScalerOf(context).scale(310)) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          teilen,
          const SizedBox(height: 8),
          lesen,
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 3, child: teilen),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: lesen),
        ]),
      );
    });
