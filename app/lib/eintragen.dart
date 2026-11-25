// „Heute eintragen“ (Reiter Heute): „Dosis genommen“ und eine abweichende Dosis sofort sichtbar.
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
  AppState get app => widget.app;
  Taper get ta => app.taper;

  void _fertig() => app.aenderung();

  /// „Einnahme“: Menge eingeben, OK – die Uhrzeit ist der Moment des Eintragens.
  Future<void> _einnahme() async {
    final s = ta.st;
    final v = await showDialog<double>(context: context, builder: (_) => _MengeDialog(unit: s.unit));
    if (v == null || !mounted) return;
    await einnahmeEintragen(context, app, v, t: ta.nowHM());
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
              tr('Wochen-Ø trotzdem unter der Vorwoche (${fz(round2(a0))} statt ${fz(round2(a1))} ${s.unit}). $tmT ${s.unit}.', 'Weekly avg. still below last week (${fz(round2(a0))} instead of ${fz(round2(a1))} ${s.unit}). $tmT ${s.unit}.'),
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
    }
    k.add(const SizedBox(height: 12));
    k.add(hauptKnopf(tr('Einnahme', 'Intake'), _einnahme, icon: Icons.add, key: const Key('einnahme')));
    // Nach dem Ziel (0 mg): „nichts genommen“ mit einem Tipp, damit auch ein Rückfall nachvollziehbar bleibt.
    if (te == null && !(dose > 0)) {
      k.add(const SizedBox(height: 8));
      k.add(knopf(tr('Heute nichts genommen', 'Nothing taken today'), () => einnahmeEintragen(context, app, 0, t: ta.nowHM()),
          icon: Icons.check, key: const Key('nichts')));
    }
    k.add(const SizedBox(height: 12));
    k.add(guterTagKnopf(app, today, heute: true));
    k.add(const SizedBox(height: 26)); // Platz für den Lavendel unten links
    return Karte(
        key: const Key('heuteEintragen'),
        hintergrund: const CustomPaint(painter: LavendelEckeMaler()),
        children: k);
  }
}

/// Fenster „Einnahme“: nur die Menge. Gibt die Menge zurück oder `null` (Abbrechen).
class _MengeDialog extends StatefulWidget {
  const _MengeDialog({required this.unit});
  final String unit;
  @override
  State<_MengeDialog> createState() => _MengeDialogState();
}

class _MengeDialogState extends State<_MengeDialog> {
  final _menge = TextEditingController();
  bool _fehler = false;

  @override
  void dispose() {
    _menge.dispose();
    super.dispose();
  }

  void _ok() {
    final v = zahl(_menge.text);
    if (v == null || !(v >= 0) || !v.isFinite) {
      setState(() => _fehler = true);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('einnahmeDialog'),
        title: Text(tr('Einnahme', 'Intake')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const Key('menge'),
            controller: _menge,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: feldStil(hinweis: tr('Menge in ${widget.unit}', 'Amount in ${widget.unit}'), fehler: _fehler),
            onSubmitted: (_) => _ok(),
          ),
          Sub(tr('Die Uhrzeit wird automatisch gespeichert.', 'The time is saved automatically.'), oben: 8),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(key: const Key('plus'), onPressed: _ok, child: const Text('OK')),
        ],
      );
}
