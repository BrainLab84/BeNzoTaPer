// SOS (Welle aussitzen) und „Kurz innehalten“.
import 'i18n/txt.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';

/// Roter SOS-Knopf unten rechts (überall gleich).
/// SOS oben in der Mitte der Kopfzeile.
Widget sosKopfKnopf(BuildContext context, AppState app) => FilledButton.icon(
      key: const Key('sosKnopf'),
      style: FilledButton.styleFrom(
        backgroundColor: F.sos,
        foregroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const StadiumBorder(side: BorderSide(color: Color(0x40FFFFFF))),
        elevation: 2,
        shadowColor: const Color(0x55401020),
      ),
      icon: const Icon(Icons.support, size: 18),
      label: const Text('SOS', style: TextStyle(fontWeight: FontWeight.w700)),
      onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => SosSeite(app: app))),
    );

class SosSeite extends StatefulWidget {
  const SosSeite({super.key, required this.app, this.timerSofort = false, this.jetzt = DateTime.now});
  final AppState app;

  /// Aus „Kurz innehalten → Erst 15 Minuten warten“: Timer läuft sofort.
  final bool timerSofort;
  final DateTime Function() jetzt;
  @override
  State<SosSeite> createState() => _SosSeiteState();
}

class _SosSeiteState extends State<SosSeite> with SingleTickerProviderStateMixin {
  static const dauer = Duration(minutes: 15);
  late final AnimationController _atem = AnimationController(vsync: this, duration: const Duration(seconds: 10))
    ..repeat();
  DateTime? _ende;
  bool _geschafft = false;
  Timer? _takt;

  @override
  void initState() {
    super.initState();
    if (widget.timerSofort) _ende = widget.jetzt().add(dauer);
    _takt = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _tick() {
    if (_ende != null && !widget.jetzt().isBefore(_ende!)) {
      setState(() {
        _ende = null;
        _geschafft = true;
      });
    } else if (_ende != null) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _takt?.cancel();
    _atem.dispose();
    super.dispose();
  }

  String _rest() {
    final r = _ende!.difference(widget.jetzt());
    final ms = r.inMilliseconds < 0 ? 0 : r.inMilliseconds;
    final m = ms ~/ 60000, s = (ms % 60000) ~/ 1000;
    return '$m:${s < 10 ? '0' : ''}$s';
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final w = <Widget>[];
    w.add(Karte(rand: const Color(0x80FF9AA6), children: [
      const KartenTitel('SOS'),
      Text(tr('Das ist eine Welle. Sie geht vorbei – meist schneller, als es sich gerade anfühlt.', 'This is a wave. It passes – usually faster than it feels right now.'),
          style: TextStyle(fontSize: 17)),
      const SizedBox(height: 16),
      Center(child: _Atemkreis(_atem)),
      Sub(tr('4 Sekunden ein · 6 Sekunden aus', '4 seconds in · 6 seconds out'), mitte: true, oben: 8),
    ]));

    final timer = <Widget>[];
    if (_geschafft) {
      timer.add(Text.rich(
          TextSpan(
              children: [TextSpan(text: tr('15 Minuten geschafft ', '15 minutes done ')), ikon(Icons.check, groesse: 28, farbe: F.ok)]),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: F.ok)));
    } else if (_ende != null) {
      timer.add(Sub(tr('Noch durchhalten', 'Hold on a little longer'), mitte: true));
      timer.add(Text(_rest(),
          key: const Key('sosRest'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 46, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])));
      timer.add(Center(child: knopf(tr('Timer stoppen', 'Stop timer'), () => setState(() => _ende = null), breit: false)));
    } else {
      timer.add(hauptKnopf(
          tr('15 Minuten durchhalten', 'Hold on for 15 minutes'),
          () => setState(() {
                _ende = widget.jetzt().add(dauer);
                _geschafft = false;
              }),
          icon: Icons.timer_outlined));
      timer.add(Sub(tr('Nichts entscheiden, bis der Timer abgelaufen ist.', 'Decide nothing until the timer has run out.'), oben: 6));
    }
    w.add(Karte(children: timer));

    if (app.eingerichtet) {
      final ta = app.taper;
      final s = ta.st;
      final wk = ta.weekAvgs(null, 2);
      w.add(Karte(children: [
        KartenTitel(tr('Was du schon geschafft hast', 'What you have already achieved')),
        Text(
            tr('Stufe ${s.stage + 1} von ${s.plan.length} · heute ${fz(s.plan[s.stage])} statt ${fz(s.plan[0])} ${s.unit}', 'Step ${s.stage + 1} of ${s.plan.length} · today ${fz(s.plan[s.stage])} instead of ${fz(s.plan[0])} ${s.unit}')),
        if (wk[0].avg != null)
          Text(tr('Wochen-Ø ${fz(round1(wk[0].avg!))} ${s.unit}'
              '${wk[1].avg != null && wk[0].avg! < wk[1].avg! ? ' – unter der Vorwoche' : ''}', 'Weekly avg. ${fz(round1(wk[0].avg!))} ${s.unit}${wk[1].avg != null && wk[0].avg! < wk[1].avg! ? " – below last week" : ""}')),
        if (s.sosN > 0) Text(tr('${s.sosN} Welle${s.sosN == 1 ? '' : 'n'} schon ausgesessen', '${s.sosN} ${s.sosN == 1 ? "wave" : "waves"} already ridden out')),
      ]));
    }

    const fett = TextStyle(fontWeight: FontWeight.w700);
    w.add(Karte(rand: const Color(0x66FF9AA6), children: [
      Text.rich(TextSpan(style: const TextStyle(fontSize: 14), children: Txt.en
          // Englisch: keine deutsche Hotline.
          ? const [
              TextSpan(text: 'Seizure, hallucinations, severe confusion: '),
              TextSpan(text: '112', style: fett),
              TextSpan(text: ' (Europe) or your local emergency number.'),
            ]
          : const [
              TextSpan(text: 'Krampfanfall, Halluzinationen, starke Verwirrung: '),
              TextSpan(text: '112', style: fett),
              TextSpan(text: '. Gedanken, dir etwas anzutun: Telefonseelsorge '),
              TextSpan(text: '0800 111 0 111', style: fett),
              TextSpan(text: ' (kostenlos, rund um die Uhr).'),
            ])),
    ]));

    w.add(Row(children: [
      Expanded(child: knopf(tr('Zurück', 'Back'), () => Navigator.pop(context))),
      const SizedBox(width: 10),
      Expanded(
        child: hauptKnopf(tr('Geschafft', 'Done'), nachIcon: Icons.check, blatt: false, () {
          if (app.eingerichtet) {
            app.taper.sosDone();
            app.aenderung();
          }
          Navigator.pop(context);
        }),
      ),
    ]));

    return Scaffold(
      appBar: AppBar(title: const Text('SOS')),
      body: ListView(padding: const EdgeInsets.all(16), children: w),
    );
  }
}

/// Atemkreis: 4 s größer werden (Einatmen), 6 s kleiner (Ausatmen).
class _Atemkreis extends AnimatedWidget {
  const _Atemkreis(Animation<double> a) : super(listenable: a);
  @override
  Widget build(BuildContext context) {
    final v = (listenable as Animation<double>).value;
    final ein = v < .4;
    final f = ein ? Curves.easeInOut.transform(v / .4) : 1 - Curves.easeInOut.transform((v - .4) / .6);
    final d = 90 + 70 * f;
    return SizedBox(
      width: 170,
      height: 170,
      child: Center(
        child: Container(
          width: d,
          height: d,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: F.acs2,
            border: Border.all(color: F.ac, width: 2),
          ),
          child: Text(ein ? tr('Einatmen', 'Breathe in') : tr('Ausatmen', 'Breathe out'), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

enum Innehalten { eintragen, warten, sos }

/// „Kurz innehalten“: heute mehr als geplant.
class InnehaltenSeite extends StatelessWidget {
  const InnehaltenSeite({super.key, required this.app, required this.menge});
  final AppState app;
  final double menge;
  @override
  Widget build(BuildContext context) {
    final ta = app.taper;
    final s = ta.st;
    final te = s.log[ta.today];
    final pl = te?.plan ?? s.plan[s.stage];
    final tot = round3((te?.dose ?? 0) + menge);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kurz innehalten', 'Pause for a moment'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Karte(rand: F.warn, children: [
          KartenTitel(tr('Kurz innehalten', 'Pause for a moment')),
          Text.rich(TextSpan(style: const TextStyle(fontSize: 16), children: [
            TextSpan(text: tr('Mit ', 'With ')),
            TextSpan(text: '${fz(menge)} ${s.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: tr(' wären es heute ${fz(tot)} statt ${fz(pl)} ${s.unit}.', ' it would be ${fz(tot)} today instead of ${fz(pl)} ${s.unit}.')),
          ])),
          const SizedBox(height: 12),
          hauptKnopf(tr('Erst 15 Minuten warten', 'Wait 15 minutes first'), () => Navigator.pop(context, Innehalten.warten),
              icon: Icons.timer_outlined),
          Sub(tr('Schon genommen? Dann einfach eintragen, der Kalender soll stimmen.', 'Already taken it? Then just log it, so the calendar is correct.'), oben: 14),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: knopf(tr('Eintragen', 'Log it'), () => Navigator.pop(context, Innehalten.eintragen))),
            const SizedBox(width: 10),
            Expanded(child: knopf(tr('Doch nicht', 'Never mind'), () => Navigator.pop(context))),
          ]),
        ]),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: F.sos,
        foregroundColor: Colors.white,
        label: const Text('SOS'),
        icon: const Icon(Icons.support),
        onPressed: () => Navigator.pop(context, Innehalten.sos),
      ),
    );
  }
}
