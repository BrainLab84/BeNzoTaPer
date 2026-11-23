// Karte „Wochen-Durchschnitt“ (steht im Kalender). Rechnet nur mit eingetragenen Tagen (Kern).
import 'i18n/txt.dart';

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';

class WochenschnittKarte extends StatelessWidget {
  const WochenschnittKarte({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final ta = app.taper;
    return _wochenschnitt(ta, ta.weekAvgs(null, 4), ta.today, ta.st.frz != null);
  }

  Widget _wochenschnitt(Taper ta, List<WeekAvg> wk, String today, bool frozen) {
    if (frozen) {
      return Opacity(
        key: const Key('wochenKarte'),
        opacity: .45,
        child: Karte(children: [
          KartenTitel(tr('Auswertung pausiert', 'Evaluation paused')),
          Sub(tr('Wochen-Ø und Kurve warten, bis die offenen Tage nachgetragen sind. Ein ? ist nie 0 mg.', 'Weekly avg. and curve wait until the open days are filled in. A ? is never 0 mg.')),
        ]),
      );
    }
    final s = ta.st;
    final cur = wk[0].avg;
    final k = <Widget>[KartenTitel(tr('Wochen-Durchschnitt', 'Weekly average'), hilfe: 'avg')];
    if (cur == null) {
      k.add(Sub(tr('Noch keine Einträge in den letzten 7 Tagen.', 'No entries in the last 7 days yet.')));
    } else {
      // Wrap statt Row: bei großer Schrift auf schmalen Handys rutscht „mg / Tag“ in die nächste Zeile.
      k.add(Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
        Text('Ø ${fz(round1(cur))}',
            key: const Key('wochenschnitt'), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
        Padding(padding: const EdgeInsets.only(bottom: 7), child: Text(tr('${s.unit} / Tag', '${s.unit} / day'))),
      ]));
      final vor = wk[1].avg;
      if (vor != null) {
        final df = cur - vor;
        k.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              tr('${df < 0 ? '↓ ' : df > 0 ? '↑ ' : '→ '}${fz(round1(df.abs()))} ${s.unit} zur Vorwoche', '${df < 0 ? "↓ " : df > 0 ? "↑ " : "→ "}${fz(round1(df.abs()))} ${s.unit} vs. last week'),
              style: TextStyle(fontWeight: FontWeight.w700, color: df < 0 ? F.ok : F.mu)),
        ));
      }
      final namen = [tr('Diese Woche', 'This week'), tr('Vorwoche', 'Last week'), tr('vor 2 Wo.', '2 wks ago'), tr('vor 3 Wo.', '3 wks ago')];
      final mx = s.plan[0] != 0 ? s.plan[0] : 1.0;
      k.add(const SizedBox(height: 10));
      for (var i = 0; i < wk.length && i < 4; i++) {
        final a = wk[i].avg;
        final anteil = a == null ? 0.0 : (a / mx).clamp(0.0, 1.0);
        k.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            SizedBox(width: 88, child: Text(namen[i], style: const TextStyle(color: F.mu, fontSize: 13))),
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(color: F.card2, borderRadius: BorderRadius.circular(6)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: anteil,
                  child: Container(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6), gradient: const LinearGradient(colors: [F.pri, F.ac])),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(a == null ? '–' : fz(round1(a)),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
        ));
      }
      final qc = ta.qCount(today);
      k.add(Text.rich(TextSpan(style: const TextStyle(color: F.mu, fontSize: 14), children: [
        TextSpan(text: tr('Ø der eingetragenen Tage', 'Avg. of the logged days')),
        if (qc > 0) ...[
          const TextSpan(text: ' · '),
          TextSpan(text: tr('${tage(qc)} ohne Eintrag', '${tage(qc)} without entry'), style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: tr(' (zählt nicht mit).', ' (not counted).')),
        ] else ...[
          TextSpan(text: tr('. So siehst du den Trend auch nach einem ', '. This way you also see the trend after a ')),
          ikon(Icons.close, groesse: 14),
          TextSpan(text: tr('-Tag.', '-day.')),
        ],
      ])));
    }
    return Karte(key: const Key('wochenKarte'), children: k);
  }
}
