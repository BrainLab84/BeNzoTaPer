// „Plan anpassen“ (aus der Dosis-Karte in Heute): ab heute alles änderbar – Dosis und Tage jeder Stufe,
// Stufen dazu oder weg. Gilt sofort; Verlauf, Einnahmen und Vorrat bleiben. Geht die Anpassung höher oder
// macht sie den Plan länger, kommt vorher ein ruhiges „Kurz innehalten“. Vorschau live aus dem Kern.
import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'i18n/meldungen.dart';
import 'i18n/txt.dart';
import 'plan_reiter.dart';

class _Zeile {
  _Zeile(double? dosis, int? tage)
      : dosis = TextEditingController(text: dosis == null ? '' : fz(dosis)),
        tage = TextEditingController(text: tage == null ? '' : '$tage');
  final TextEditingController dosis, tage;
  void dispose() {
    dosis.dispose();
    tage.dispose();
  }
}

class PlanAnpassenSeite extends StatefulWidget {
  const PlanAnpassenSeite({super.key, required this.app});
  final AppState app;
  @override
  State<PlanAnpassenSeite> createState() => _PlanAnpassenSeiteState();
}

class _PlanAnpassenSeiteState extends State<PlanAnpassenSeite> {
  final _zeilen = <_Zeile>[];
  String? _fehler;

  AppState get app => widget.app;
  Taper get ta => app.taper;

  @override
  void initState() {
    super.initState();
    for (final r in ta.anpassenVorlage()) {
      _zeilen.add(_Zeile(r.dose, r.days));
    }
  }

  @override
  void dispose() {
    for (final z in _zeilen) {
      z.dispose();
    }
    super.dispose();
  }

  List<EditRow> get _rows => [
        for (var i = 0; i < _zeilen.length; i++)
          EditRow(zahl(_zeilen[i].dosis.text),
              (i == _zeilen.length - 1 && _zeilen.length > 1) ? null : ganzZahl(_zeilen[i].tage.text)),
      ];

  Future<void> _speichern() async {
    final rows = _rows;
    final p = ta.anpassenPruefen(rows);
    if (p.err != null) {
      setState(() => _fehler = meldungText(p.err!));
      return;
    }
    if (p.bremst) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          key: const Key('anpInnehalten'),
          title: Text(tr('Kurz innehalten', 'Pause for a moment')),
          content: Text(tr(
              'Dein angepasster Plan geht höher oder dauert länger. Das ist in Ordnung, wenn es gerade nötig ist. '
                  'Passt es so?',
              'Your adjusted plan goes higher or takes longer. That is okay if you need it right now. Is it right like this?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Zurück', 'Back'))),
            FilledButton(
                key: const Key('anpJa'), onPressed: () => Navigator.pop(c, true), child: Text(tr('Ja, anpassen', 'Yes, adjust'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final r = ta.planAnpassen(rows);
    if (r.err != null) {
      setState(() => _fehler = meldungText(r.err!));
      return;
    }
    app.aenderung();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    messenger.showSnackBar(SnackBar(content: Text(tr('Plan angepasst.', 'Plan adjusted.'))));
  }

  String _reicht(StockInfo? si, String heute) {
    if (si == null) return '';
    if (si.days < 1) return tr('reicht nicht mehr für heute', 'not enough for today');
    if (!si.days.isFinite) return tr('reicht bis zum Ende des Plans', 'lasts until the end of the plan');
    final d = si.days.toInt();
    return tr('reicht ca. ${tage(d)} (bis ${datum(addD(heute, d - 1))})', 'lasts approx. ${tage(d)} (until ${datum(addD(heute, d - 1))})');
  }

  Widget _vorschau() {
    final s = ta.st;
    final p = ta.anpassenPruefen(_rows);
    final k = <Widget>[KartenTitel(tr('So sieht es dann aus', 'This is how it will look'), icon: Icons.visibility_outlined)];
    if (p.err != null) {
      k.add(Sub(meldungText(p.err!)));
    } else {
      final neu = Taper(s: p.neu, clock: ta.clock);
      final endeAlt = ta.voraussichtlichesEnde(), endeNeu = neu.voraussichtlichesEnde();
      if (endeNeu != null) {
        k.add(Text(voraussichtlichText(p.neu!, endeNeu), key: const Key('anpEnde'), style: const TextStyle(fontWeight: FontWeight.w700)));
        if (endeAlt != null && endeAlt != endeNeu) {
          k.add(Sub(tr('bisher ${datum(endeAlt)}', 'before ${datum(endeAlt)}')));
        }
      }
      if (s.stock != null) {
        final alt = ta.stockInfo(), jetzt = neu.stockInfo();
        k.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(tr('Vorrat ${_reicht(jetzt, ta.today)}', 'Supply ${_reicht(jetzt, ta.today)}'),
              key: const Key('anpVorrat'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ));
        if (alt != null && jetzt != null && alt.days != jetzt.days) k.add(Sub(tr('bisher ${_reicht(alt, ta.today)}', 'before ${_reicht(alt, ta.today)}')));
      }
    }
    return Karte(key: const Key('anpVorschau'), rand: F.acRand, children: k);
  }

  @override
  Widget build(BuildContext context) {
    final s = ta.st;
    final w = <Widget>[
      Sub(tr('Ab heute. Bisherige Tage, Einnahmen und Vorrat bleiben.', 'From today. Past days, intakes and supply are kept.')),
      if (s.hold)
        Sub(tr('Das Halten endet, ab heute gilt der angepasste Plan.', 'The hold ends; the adjusted plan applies from today.'), oben: 4),
      const SizedBox(height: 12),
    ];
    final n = _zeilen.length;
    for (var i = 0; i < n; i++) {
      final z = _zeilen[i];
      final ziel = i == n - 1 && n > 1;
      final titel = i == 0 ? tr('Jetzt', 'Now') : (ziel ? tr('Ziel', 'Goal') : tr('Danach', 'Then'));
      w.add(Karte(
        farbe: F.card2.withValues(alpha: .5),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
        children: [
          Row(children: [
            Expanded(child: Text(titel, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (i > 0 && !ziel)
              IconButton(
                key: Key('anpWeg$i'),
                tooltip: tr('Stufe entfernen', 'Remove step'),
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _zeilen.removeAt(i).dispose()),
              ),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Feldname(tr('Dosis (${s.unit})', 'Dose (${s.unit})'), oben: 6),
                TextField(
                  key: Key('anpDosis$i'),
                  controller: z.dosis,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: feldStil(),
                  onChanged: (_) => setState(() => _fehler = null),
                ),
              ]),
            ),
            if (!ziel) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Feldname(i == 0 ? tr('Tage ab heute', 'Days from today') : tr('Tage', 'Days'), oben: 6),
                  TextField(
                    key: Key('anpTage$i'),
                    controller: z.tage,
                    keyboardType: TextInputType.number,
                    decoration: feldStil(),
                    onChanged: (_) => setState(() => _fehler = null),
                  ),
                ]),
              ),
            ],
          ]),
        ],
      ));
      w.add(const SizedBox(height: 10));
    }
    w.add(knopf(tr('Stufe dazu', 'Add step'), () {
      setState(() => _zeilen.insert(n > 1 ? n - 1 : n, _Zeile(null, 14)));
    }, icon: Icons.add, key: const Key('anpPlus')));
    w.add(const SizedBox(height: 14));
    w.add(_vorschau());
    if (_fehler != null) {
      w.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_fehler!, key: const Key('anpFehler'), style: const TextStyle(color: F.bad))));
    }
    w.add(const SizedBox(height: 16));
    w.add(Row(children: [
      Expanded(child: knopf(tr('Abbrechen', 'Cancel'), () => Navigator.pop(context, false))),
      const SizedBox(width: 10),
      Expanded(flex: 2, child: hauptKnopf(tr('Anpassen', 'Adjust'), _speichern, key: const Key('anpSpeichern'), blatt: false)),
    ]));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Plan anpassen', 'Adjust plan'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: w),
    );
  }
}
