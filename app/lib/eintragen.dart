// „Heute eintragen“ steht direkt über dem Kalender: „Dosis genommen“ und eine abweichende Dosis sofort sichtbar.
import 'i18n/txt.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'deko.dart';
import 'tag.dart';

class HeuteEintragen extends StatefulWidget {
  const HeuteEintragen({super.key, required this.app});
  final AppState app;
  @override
  State<HeuteEintragen> createState() => _HeuteEintragenState();
}

class _HeuteEintragenState extends State<HeuteEintragen> {
  final _menge = TextEditingController();
  String? _zeit; // null = aktuelle Uhrzeit
  bool _mengeFehler = false;

  AppState get app => widget.app;
  Taper get ta => app.taper;

  @override
  void dispose() {
    _menge.dispose();
    super.dispose();
  }

  void _fertig() => app.aenderung();

  Future<void> _einzeln() async {
    final v = zahl(_menge.text);
    if (v == null || !(v >= 0)) {
      setState(() => _mengeFehler = true);
      return;
    }
    setState(() => _mengeFehler = false);
    if (await einnahmeEintragen(context, app, v, t: _zeit ?? ta.nowHM())) {
      _menge.clear();
      if (mounted) setState(() => _zeit = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ta.today;
    final wk = ta.weekAvgs(null, 4);
    final s = ta.st;
    final dose = s.plan[s.stage];
    final last = s.stage >= s.plan.length - 1;
    final te = s.log[today];
    final ndy = ta.need(s.stage);
    final nextIn = math.max(1, ndy - ta.stageDay(today));
    final k = <Widget>[KartenTitel(tr('Heute eintragen', 'Log today'))];
    final tk = te?.dose ?? 0;
    // Planwert des Tages, sonst die aktuelle Dosis (0 zählt als „kein Plan“).
    final soll = (te?.plan != null && te!.plan != 0) ? te.plan! : dose;
    if (te != null) {
      final its = ta.dayIt(te);
      for (var i = 0; i < its.length; i++) {
        k.add(EinnahmeZeile(
          zeit: its[i].t,
          menge: '${fz(its[i].v)} ${s.unit}',
          loeschen: () {
            ta.delIntake(i);
            _fertig();
          },
        ));
      }
      if (te.r == 'lapse') {
        final tmD = (!last && !s.hold && nextIn == 1) ? s.plan[s.stage + 1] : dose;
        final tmT = tmD != dose ? tr('Morgen beginnt die neue Stufe: ${fz(tmD)}', 'Tomorrow the new step begins: ${fz(tmD)}') : tr('Morgen gilt wieder ${fz(tmD)}', 'Tomorrow ${fz(tmD)} applies again');
        k.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2, right: 6), child: Icon(Icons.close, size: 19)),
            Flexible(
              child: Text.rich(TextSpan(style: const TextStyle(fontSize: 17), children: [
                TextSpan(text: '${fz(te.dose)} ${s.unit}', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: tr(' genommen statt ${fz(soll)}.', ' taken instead of ${fz(soll)}.')),
              ])),
            ),
          ]),
        ));
        final a0 = wk[0].avg, a1 = wk[1].avg;
        if (a0 != null && a1 != null && a0 < a1) {
          k.add(Sub(
              tr('Wochen-Ø trotzdem unter der Vorwoche (${fz(round1(a0))} statt ${fz(round1(a1))} ${s.unit}). $tmT ${s.unit}.', 'Weekly avg. still below last week (${fz(round1(a0))} instead of ${fz(round1(a1))} ${s.unit}). $tmT ${s.unit}.'),
              oben: 6));
        } else {
          k.add(Sub(tr('$tmT ${s.unit}. Ein Tag ändert den Wochen-Ø nur wenig.', '$tmT ${s.unit}. One day changes the weekly avg. only slightly.'), oben: 6));
        }
      } else if (tk >= soll - 1e-9) {
        k.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: IconText(Icons.check,
              tk < 1e-9 && !(soll > 0) ? tr('Heute nichts genommen – im Plan.', 'Nothing taken today – on plan.') : tr('Tagesdosis komplett – im Plan.', 'Full daily dose – on plan.'),
              farbe: F.ok, gross: 17),
        ));
      } else {
        k.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: IconText(Icons.check, tr('bisher ${fz(tk)} von ${fz(soll)} ${s.unit}', 'so far ${fz(tk)} of ${fz(soll)} ${s.unit}'), farbe: F.ok),
        ));
      }
      if (tk < soll - 1e-9) {
        final rest = round3(soll - tk);
        k.add(const SizedBox(height: 10));
        k.add(hauptKnopf(tr('Rest genommen (${fz(rest)} ${s.unit})', 'Remainder taken (${fz(rest)} ${s.unit})'), () => einnahmeEintragen(context, app, rest),
            icon: Icons.check, key: const Key('rest')));
      }
    } else {
      k.add(hauptKnopf(dose > 0 ? tr('${fz(dose)} ${s.unit} wie geplant genommen', '${fz(dose)} ${s.unit} taken as planned') : tr('Heute nichts genommen', 'Nothing taken today'),
          () => einnahmeEintragen(context, app, dose),
          icon: Icons.check, key: const Key('wieGeplant')));
    }
    final min = (s.min != null && s.min != 0) ? s.min! : 0.25;
    k.add(Feldname(tr('${te != null ? 'Weitere Einnahme' : 'Oder einzelne Einnahme'} (${s.unit} · Uhrzeit)', '${te != null ? "Another intake" : "Or a single intake"} (${s.unit} · time)')));
    final menge = TextField(
      key: const Key('menge'),
      controller: _menge,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: feldStil(hinweis: tr('z. B. ', 'e.g. ') + fz(dose > 0 ? dose / 2 : min), fehler: _mengeFehler),
    );
    final zeit = UhrzeitFeld(wert: _zeit ?? ta.nowHM(), geaendert: (z) => setState(() => _zeit = z));
    final plus = SizedBox(width: 64, child: knopf('+', _einzeln, key: const Key('plus')));
    k.add(LayoutBuilder(
      builder: (context, c) => genugPlatz(context, c, 300)
          ? Row(children: [
              Expanded(child: menge),
              const SizedBox(width: 8),
              SizedBox(width: 108, child: zeit),
              const SizedBox(width: 8),
              plus,
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              menge,
              const SizedBox(height: 8),
              Row(children: [Expanded(child: zeit), const SizedBox(width: 8), plus]),
            ]),
    ));
    k.add(const SizedBox(height: 12));
    k.add(guterTagKnopf(app, today, heute: true));
    k.add(const SizedBox(height: 26)); // Platz für den Lavendel unten links
    return Karte(
        key: const Key('heuteEintragen'),
        hintergrund: const CustomPaint(painter: LavendelEckeMaler()),
        children: k);
  }
}
