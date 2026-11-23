// Reiter „Plan“: Plan-Karte (Zusammenfassung, Neuen Plan erstellen / importieren),
// Tablettenvorrat und alle Stufen. Ohne Plan: dieselbe Startkarte wie im Kalender.
import 'i18n/txt.dart';
import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'plan_kopf.dart';

class PlanReiter extends StatelessWidget {
  const PlanReiter({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final s = app.taper.s;
    if (s == null) {
      return OhnePlanHinweis(tr('Hier stehen deine Stufen, sobald dein Plan angelegt ist.', 'Your steps appear here once your plan is set up.'),
          icon: Icons.route_outlined);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      if (app.beispiel) const BeispielHinweis(),
      _planKarte(context),
      _stufen(),
    ]);
  }

  Widget _planKarte(BuildContext context) {
    final ta = app.taper;
    final s = ta.st;
    // immer „voraussichtlich“ (nichts steht fest), rückt beim Halten mit.
    final ende = ta.voraussichtlichesEnde();
    final String status;
    if (s.frz != null) {
      status = tr('Offene Tage – Anzeigen pausieren bis zum Nachtragen.', 'Open days – displays pause until filled in.');
    } else if (ende != null) {
      status = voraussichtlichText(s, ende);
    } else {
      status = '';
    }
    return Karte(
      key: const Key('planKarte'),
      rand: F.acRand,
      children: [
        KartenTitel(tr('Dein Plan', 'Your plan'), icon: Icons.route_outlined, hilfe: 'plan'),
        Text('${s.name} · ${fz(s.plan.first)} → ${fz(s.plan.last)} ${s.unit}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        Sub(tr('Stufe ${s.stage + 1} von ${s.plan.length} · jetzt ${fz(s.plan[s.stage])} ${s.unit}', 'Step ${s.stage + 1} of ${s.plan.length} · now ${fz(s.plan[s.stage])} ${s.unit}'), oben: 4),
        // wann der Plan gestartet bzw. zuletzt geändert wurde.
        Sub(planDatumZeile(ta), key: const Key('planDatum'), oben: 2),
        if (status.isNotEmpty) Sub(status, oben: 2),
        // Neuer Plan oder Import gibt es nur ohne eigenen Plan; geändert wird mit „Plan anpassen“ (Heute).
        if (!app.beispiel)
          Sub(tr('Ganz neu anfangen? Erst sichern, dann Mehr → Zurücksetzen.',
                  'Start completely over? Back up first, then More → Reset.'),
              key: const Key('neuAnfangen'), oben: 10),
      ],
    );
  }

  // Karte „Stufen“ (Stufenliste).

  Widget _stufen() {
    final ta = app.taper;
    final s = ta.st;
    final zeilen = <Widget>[];
    for (var i = 0; i < s.plan.length; i++) {
      final p = s.plan[i];
      final cb = (s.tabs != null && s.tabs!.str.isNotEmpty && p > 0) ? combo(p, s.tabs!.str, s.tabs!.split) : null;
      final fertig = i < s.stage;
      final jetzt = i == s.stage;
      final farbe = jetzt ? F.ac2 : (fertig ? F.mu2 : F.tx);
      zeilen.add(Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: F.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: tr('Stufe ${i + 1}${jetzt ? ' · jetzt' : ''}', 'Step ${i + 1}${jetzt ? " · now" : ""}'),
                    style: TextStyle(color: farbe, fontWeight: jetzt ? FontWeight.w700 : FontWeight.w400)),
                TextSpan(text: tr(' · ${ta.need(i)} Tage', ' · ${ta.need(i)} days'), style: const TextStyle(color: F.mu, fontSize: 13)),
              ])),
              if (cb != null)
                cb.exact
                    ? Text(partsStr(cb.parts, s.unit), style: const TextStyle(color: F.mu, fontSize: 12))
                    : Text.rich(TextSpan(style: const TextStyle(color: F.mu, fontSize: 12), children: [
                        ikon(Icons.warning_amber_rounded, groesse: 12, farbe: F.warn),
                        TextSpan(text: tr(' nicht exakt teilbar', ' not exactly divisible')),
                      ])),
            ]),
          ),
          Text('${fz(p)} ${s.unit}',
              style: TextStyle(
                color: farbe,
                fontWeight: jetzt ? FontWeight.w700 : FontWeight.w400,
                decoration: fertig ? TextDecoration.lineThrough : null,
              )),
        ]),
      ));
    }
    return Karte(key: const Key('stufen'), children: [
      KartenTitel(tr('Stufen', 'Steps')),
      ...zeilen,
      Sub(
          tr('Jede Stufe läuft ihre Tage ab Beginn, dann geht es automatisch weiter. Mit „Dosis halten“ kannst du den '
          'Plan jederzeit anhalten.', 'Each step runs its days from its start, then it continues automatically. With “Hold dose” you can pause the plan at any time.'),
          oben: 8),
    ]);
  }
}

/// Protokolleinträge, die den Plan selbst ändern (neuer Plan, Stufe vorgezogen, übernommene Vormerkung).
const _planAenderung = [
  'Plan geändert:',
  'Plan angepasst:',
  'Vorgemerkte Änderung übernommen:',
  'Übernommen:',
  'Nächste Stufe vorgezogen'
];

/// „Plan gestartet am T.M.JJJJ“, bei Änderungen dazu „· geändert am T.M.JJJJ“ (letzte Änderung).
String planDatumZeile(Taper ta) {
  final s = ta.st;
  final start = s.t0 ?? ta.t0Of() ?? ta.today;
  String? geaendert;
  for (final c in s.chg.reversed) {
    if (_planAenderung.any(c.t.startsWith)) {
      geaendert = c.d;
      break;
    }
  }
  if (ta.vorStart) return tr('Plan startet am ${datum(start)}', 'Plan starts on ${datum(start)}');
  return tr('Plan gestartet am ${datum(start)}${geaendert != null ? ' · geändert am ${datum(geaendert)}' : ''}', 'Plan started on ${datum(start)}${geaendert != null ? " · changed on ${datum(geaendert)}" : ""}');
}

/// Zeile „Voraussichtlich bei 0 mg: T.M.JJJJ“.
String voraussichtlichText(TaperState s, String ende) =>
    tr('Voraussichtlich bei ${fz(s.plan.last)} ${s.unit}: ${datum(ende)}${s.hold ? ' (Dosis wird gehalten)' : ''}', 'Expected at ${fz(s.plan.last)} ${s.unit}: ${datum(ende)}${s.hold ? " (dose is being held)" : ""}');
