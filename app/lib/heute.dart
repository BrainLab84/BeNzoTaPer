// Reiter „Heute“: Dosis-Karte, Vormerkung, Halten, Wochenstreifen, Wochen-Durchschnitt.
// (Vorrat, offene Tage, Vormerkung, neue Stufe, Dosis-Karte, Wochenstreifen, Nachsorge,
// Wochen-Durchschnitt, Heute eintragen, Tagebuch heute). Rechenregeln: nur aus dem Kern.
import 'i18n/txt.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'fortschritt.dart';
import 'kalender.dart';
import 'plan_kopf.dart';
import 'vorrat.dart';

class HeuteSeite extends StatefulWidget {
  const HeuteSeite({super.key, required this.app, required this.tagOeffnen, this.planEditor, this.vorratOeffnen});
  final AppState app;

  /// Plan-Reiter (mit dem Tablettenvorrat) öffnen.
  final VoidCallback? vorratOeffnen;

  /// Tag im Kalender öffnen (wechselt zum Kalender).
  final void Function(String tag) tagOeffnen;

  /// Öffnet den Plan-Editor mit einem Entwurf (vorgemerkte Planänderung). Fehlt noch → Hinweis.
  final void Function(PlanEdit e)? planEditor;
  @override
  State<HeuteSeite> createState() => _HeuteSeiteState();
}

class _HeuteSeiteState extends State<HeuteSeite> {
  // „Ändern“
  bool _aendern = false;
  bool _warumFragen = false;
  final _links = TextEditingController();
  final _warum = TextEditingController();
  bool _linksFehler = false;
  bool _warumFehler = false;

  // „Dosis halten“ (holdAsk)
  bool _halten = false;
  final _haltenTage = TextEditingController();
  bool _haltenFehler = false;

  // „Heute eintragen“

  AppState get app => widget.app;
  Taper get ta => app.taper;

  @override
  void dispose() {
    for (final c in [_links, _warum, _haltenTage]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fertig() => app.aenderung();

  // ---------------------------------------------------------------- Aktionen

  void _aendernSchliessen() => setState(() {
        _aendern = false;
        _warumFragen = false;
        _linksFehler = false;
        _warumFehler = false;
        _warum.clear();
      });

  void _linksSpeichern() {
    final n = ganzZahl(_links.text);
    if (n == null || !(n >= 1 && n <= 365)) {
      setState(() => _linksFehler = true);
      return;
    }
    final r = ta.saveLeft(n, why: _warumFragen ? _warum.text : null);
    switch (r) {
      case LeftResult.invalid:
        setState(() => _linksFehler = true);
      case LeftResult.needsWhy:
        setState(() {
          _linksFehler = false;
          _warumFragen = true;
        });
      case LeftResult.whyTooShort:
        setState(() => _warumFehler = true);
      case LeftResult.unchanged:
      case LeftResult.pended:
      case LeftResult.applied:
        _aendernSchliessen();
        _fertig();
    }
  }

  void _haltenStarten({required bool offen}) {
    int? n;
    if (!offen) {
      n = ganzZahl(_haltenTage.text);
      if (n == null || !(n >= 1 && n <= 365)) {
        setState(() => _haltenFehler = true);
        return;
      }
    }
    ta.startHold(n);
    setState(() {
      _halten = false;
      _haltenFehler = false;
      _haltenTage.clear();
    });
    _fertig();
  }

  void _haltenUmschalten() {
    if (!ta.st.hold) {
      setState(() => _halten = true);
      return;
    }
    ta.stopHold();
    _fertig();
  }

  void _vormerkungUebernehmen() {
    final p = ta.st.pend;
    if (p == null) return;
    if (p.kind != 'left') {
      final ed = widget.planEditor;
      if (ed == null) {
        showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            content: Text(tr('Der Plan-Editor ist in dieser Testversion noch nicht eingebaut.', 'The plan editor is not included in this test version yet.')),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
        return;
      }
      final e = ta.usePend();
      if (e != null) ed(e);
      return;
    }
    ta.usePend();
    _fertig();
  }

  // ---------------------------------------------------------------- Aufbau

  @override
  Widget build(BuildContext context) {
    if (ta.s == null) {
      // Noch kein Plan: dieselbe Startkarte wie oben im Kalender.
      return OhnePlanHinweis(tr('Hier trägst du jeden Tag ein, was du genommen hast, sobald dein Plan angelegt ist.', 'Once your plan is set up, you log here every day what you took.'),
          icon: Icons.today_outlined);
    }
    final s = ta.st;
    final today = ta.today;
    final frozen = s.frz != null;
    final dose = s.plan[s.stage];
    final last = s.stage >= s.plan.length - 1;

    final w = <Widget>[];
    final si = ta.stockInfo();
    if (si != null && si.days <= 14)
      w.add(VorratWarnung(si: si, unit: s.unit, heute: today, oeffnen: widget.vorratOeffnen));
    if (frozen) w.add(OffeneTageKarte(app: app, nachtragen: widget.tagOeffnen));
    if (s.pend != null) w.add(_vormerkung());
    if (s.adv != null) {
      final d = dBetween(s.adv!, today);
      if (d >= 0 && d <= 1) {
        w.add(Karte(
          rand: F.acRand,
          children: [
            Text.rich(TextSpan(style: const TextStyle(fontSize: 16), children: [
              ikon(Icons.auto_awesome, farbe: F.ac2),
              TextSpan(
                  text: tr(' Neue Stufe ${s.adv == today ? 'ab heute' : 'seit gestern'}:', ' New step ${s.adv == today ? "from today" : "since yesterday"}:'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: tr(' ${fz(dose)} ${s.unit} pro Tag', ' ${fz(dose)} ${s.unit} per day')),
            ])),
          ],
        ));
      }
    }
    if (!frozen) w.add(_dosisKarte(today));
    w.add(_wochenstreifen(today));
    if (last && !(dose > 0)) w.add(_nachsorge(today));
    final wk = ta.weekAvgs(null, 4);
    w.add(_wochenschnitt(wk, today, frozen));
    // „Heute eintragen“ steht jetzt über dem Kalender, „Tagebuch heute“ im Reiter Fortschritt.
    if (app.beispiel) w.insert(0, const BeispielHinweis());
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: w);
  }

  // Vorgemerkte Änderung
  Widget _vormerkung() {
    final p = ta.st.pend!;
    final left = ta.pendLeftMs();
    final k = <Widget>[
      IconText(Icons.hourglass_empty, tr('Vorgemerkte Änderung', 'Scheduled change'), fett: true),
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(pendText(ta, p))),
      Sub(tr('Grund: ${p.why}', 'Reason: ${p.why}')),
    ];
    if (left > 0) {
      k.add(Sub(
          tr('Frühestens in ${(left / 3600000).ceil()} Stunden. Bis dahin gilt der bisherige Plan. „Dosis halten“ geht '
          'jederzeit sofort.', 'Earliest in ${(left / 3600000).ceil()} hours. Until then the current plan applies. “Hold dose” works immediately at any time.'),
          oben: 6));
      k.add(const SizedBox(height: 8));
      k.add(knopf(tr('Verwerfen', 'Discard'), () {
        ta.dropPend();
        _fertig();
      }));
    } else {
      k.add(Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(tr('Die Bedenkzeit ist vorbei. Willst du die Änderung immer noch?', 'The reflection period is over. Do you still want the change?'))));
      k.add(const SizedBox(height: 8));
      k.add(Row(children: [
        Expanded(child: hauptKnopf(tr('Übernehmen', 'Apply'), _vormerkungUebernehmen, blatt: false)),
        const SizedBox(width: 8),
        Expanded(
          child: knopf(tr('Verwerfen', 'Discard'), () {
            ta.dropPend();
            _fertig();
          }),
        ),
      ]));
    }
    return Karte(rand: F.ac, children: k);
  }

  // Dosis-Karte mit Tablettenkombination und Stufenbalken
  Widget _dosisKarte(String today) {
    final s = ta.st;
    final dose = s.plan[s.stage];
    final n = s.plan.length;
    final last = s.stage >= n - 1;
    final ndy = ta.need(s.stage);
    final sday = ta.stageDay(today);
    final nextIn = math.max(1, ndy - sday);
    final nextKey = addD(ta.stageStart, ndy);
    final finished = last && (!(dose > 0) || sday >= ndy);

    final k = <Widget>[
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(
          child: Text(tr('${s.name} · Stufe ${s.stage + 1} von $n', '${s.name} · Step ${s.stage + 1} of $n'),
              textAlign: TextAlign.center, style: const TextStyle(color: F.mu, fontSize: 14)),
        ),
        const HilfeKnopf('prog'),
      ]),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: fz(dose), style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w700, height: 1.05)),
          TextSpan(text: ' ${s.unit}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        key: const Key('dosis'),
        textAlign: TextAlign.center,
      ),
    ];
    final kombi = _kombi(dose);
    if (kombi != null) k.add(kombi);
    k.add(Fortschritt(taper: ta));

    if (finished) {
      k.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text.rich(
            TextSpan(children: [
              TextSpan(text: tr('Ziel erreicht ', 'Goal reached ')),
              ikon(Icons.auto_awesome, groesse: 20, farbe: F.ok),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: F.ok)),
      ));
    } else if (!last && s.hold) {
      // holdUntil = erster Tag mit der nächsten Dosis (so rechnen Kern, Kalender und Lob). Angezeigt wird der
      // letzte gehaltene Tag – vorher stand hier der Tag danach (Kalender zeigte an dem
      // Datum schon die nächste Stufe). Die Zahl „noch“ zählt heute mit.
      final bis = s.holdUntil == null ? null : addD(s.holdUntil!, -1);
      final rest = s.holdUntil == null ? 0 : dBetween(today, s.holdUntil!);
      k.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: IconText(
          Icons.pause,
          bis != null
              ? tr('Dosis wird voraussichtlich gehalten bis ${datum(bis)} (${tage(rest)} noch).', 'Dose is expected to be held until ${datum(bis)} (${tage(rest)} left).')
              : tr('Dosis wird gehalten – so lange du brauchst.', 'Dose is being held – as long as you need.'),
          farbe: F.warn,
          mitte: true,
        ),
      ));
      k.add(Sub(
          tr('${bis != null ? 'Danach geht es automatisch weiter. Bist du früher bereit, drück auf Weiter.' : 'Wenn du bereit bist, weiter abzudosieren, drück auf Weiter.'}'
          ' Der Plan verschiebt sich automatisch um die gehaltenen Tage nach hinten.', '${bis != null ? "After that it continues automatically. If you are ready earlier, tap Continue." : "When you are ready to keep tapering, tap Continue."} The plan shifts back automatically by the days held.'),
          oben: 4,
          mitte: true));
    } else if (!last && _aendern) {
      k.add(_aendernFormular());
    } else if (!last) {
      k.add(
          Sub(tr('Nächste Stufe ${nextIn == 1 ? 'morgen' : 'in $nextIn Tagen'} (${datum(nextKey)})', 'Next step ${nextIn == 1 ? "tomorrow" : "in $nextIn days"} (${datum(nextKey)})'), oben: 6, mitte: true));
    } else if (last && !finished) {
      k.add(Sub(tr('Letzte Stufe · Tag ${sday + 1} von $ndy', 'Last step · Day ${sday + 1} of $ndy'), oben: 8, mitte: true));
    }

    if (!last && _halten && !s.hold) {
      k.add(_haltenFormular());
    } else if (!last && !(_aendern && !s.hold)) {
      k.add(const SizedBox(height: 12));
      final aendern = knopf(tr('Ändern', 'Change'), () {
        _links.text = '$nextIn';
        setState(() => _aendern = true);
      }, icon: Icons.edit_outlined, key: const Key('aendern'));
      final halten = knopf(s.hold ? tr('Weiter abdosieren', 'Continue tapering') : tr('Dosis halten', 'Hold dose'), _haltenUmschalten,
          icon: s.hold ? Icons.play_arrow : Icons.pause, key: const Key('halten'));
      k.add(LayoutBuilder(
        builder: (context, c) => genugPlatz(context, c, 320) || s.hold
            ? Row(children: [
                if (!s.hold) ...[Expanded(child: aendern), const SizedBox(width: 8)],
                Expanded(child: halten),
                const HilfeKnopf('time'),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                aendern,
                const SizedBox(height: 8),
                Row(children: [Expanded(child: halten), const HilfeKnopf('time')]),
              ]),
      ));
    }
    return Karte(mitte: true, children: k);
  }

  Widget? _kombi(double dose) {
    final s = ta.st;
    final t = s.tabs;
    if (t == null || t.str.isEmpty || !(dose > 0)) return null;
    final cb = combo(dose, t.str, t.split);
    if (cb == null) return null;
    final liq = (t.liq != null && t.liq! > 0) ? tr('oder ${fz(jsRound(dose / t.liq! * 100) / 100)} ml Lösung', 'or ${fz(jsRound(dose / t.liq! * 100) / 100)} ml solution') : '';
    if (cb.exact) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(children: [
          IconText(Icons.medication_outlined, partsStr(cb.parts, s.unit), farbe: F.tx, gross: 15, mitte: true),
          if (liq.isNotEmpty) Sub(liq, mitte: true),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(children: [
        IconText(Icons.medication_outlined, tr('Mit deinen Tabletten nicht exakt machbar.', 'Can’t be dosed exactly with your tablets.'),
            farbe: F.warn, gross: 15, mitte: true),
        Sub(
            tr('Nächstmöglich: ${fz(cb.lo!)}${cb.hi != null ? ' oder ${fz(cb.hi!)}' : ''} ${s.unit}. Für so kleine '
            'Schritte geht z. B. eine Lösung.${liq.isNotEmpty ? ' · $liq' : ''}', 'Closest possible: ${fz(cb.lo!)}${cb.hi != null ? " or ${fz(cb.hi!)}" : ""} ${s.unit}. For such small steps, a solution works, for example.${liq.isNotEmpty ? " · $liq" : ""}'),
            mitte: true),
      ]),
    );
  }

  // Formular „Ändern“ mit Begründung
  Widget _aendernFormular() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Feldname(tr('In wie vielen Tagen soll die nächste Stufe beginnen?', 'In how many days should the next step start?'), oben: 0),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('linksTage'),
                controller: _links,
                keyboardType: TextInputType.number,
                decoration: feldStil(fehler: _linksFehler),
                onSubmitted: (_) => _linksSpeichern(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: hauptKnopf('OK', _linksSpeichern, key: const Key('linksOk'), blatt: false)),
            const SizedBox(width: 8),
            SizedBox(
              width: 50,
              child: IconButton(tooltip: tr('Abbrechen', 'Cancel'), icon: const Icon(Icons.close), onPressed: _aendernSchliessen),
            ),
          ]),
          Sub(tr('1 = morgen. Kalender und Enddatum passen sich an.', '1 = tomorrow. Calendar and end date adjust.'), oben: 4),
          if (_warumFragen) ...[
            const SizedBox(height: 10),
            IconText(Icons.hourglass_empty, tr('48 Stunden Bedenkzeit', '48-hour reflection period'), fett: true),
            Sub(tr('Das verlängert die Stufe. Die Änderung wird erst nach 48 Stunden wirksam. „Dosis halten“ geht '
                'sofort.', 'This extends the step. The change only takes effect after 48 hours. “Hold dose” works immediately.')),
            Feldname(tr('Warum?', 'Why?')),
            TextField(
              key: const Key('linksWarum'),
              controller: _warum,
              minLines: 2,
              maxLines: 4,
              decoration: feldStil(fehler: _warumFehler),
            ),
            const SizedBox(height: 8),
            hauptKnopf(tr('Vormerken', 'Schedule'), _linksSpeichern, key: const Key('vormerken')),
          ],
        ]),
      );

  // Formular „Dosis halten“
  Widget _haltenFormular() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Feldname(tr('Wie viele Tage willst du die Dosis halten?', 'How many days do you want to hold the dose?'), oben: 0),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('haltenTage'),
                controller: _haltenTage,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: feldStil(hinweis: tr('z. B. 7', 'e.g. 7'), fehler: _haltenFehler),
                onSubmitted: (_) => _haltenStarten(offen: false),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
                width: 96,
                child: hauptKnopf(tr('Halten', 'Hold'), () => _haltenStarten(offen: false), key: const Key('haltenStart'), blatt: false)),
          ]),
          Sub(tr('Danach geht es automatisch weiter. Die Stufe verlängert sich um die gehaltenen Tage.', 'After that it continues automatically. The step is extended by the days held.'), oben: 4),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: knopf(tr('Ohne Enddatum halten', 'Hold without end date'), () => _haltenStarten(offen: true))),
            const SizedBox(width: 8),
            Expanded(
              child: knopf(
                  tr('Abbrechen', 'Cancel'),
                  () => setState(() {
                        _halten = false;
                        _haltenFehler = false;
                      })),
            ),
          ]),
        ]),
      );

  // Wochenstreifen
  Widget _wochenstreifen(String today) {
    final s = ta.st;
    final t0 = ta.t0Of() ?? '9999';
    final nm = wochentageKurzSo();
    final zellen = <Widget>[];
    for (var i = 6; i >= 0; i--) {
      final k = addD(today, -i);
      final e = s.log[k];
      Widget g;
      var hinten = F.card2;
      var vorne = F.mu2;
      var rand = Colors.transparent;
      var deckkraft = 1.0;
      var tippbar = true;
      if (e != null) {
        final lapse = e.r == 'lapse';
        g = Icon(lapse ? Icons.close : Icons.check, size: 18, color: lapse ? F.bad : F.ok);
        hinten = lapse ? F.bads : F.oks;
        vorne = lapse ? F.bad : F.ok;
      } else if (k.compareTo(today) < 0 && k.compareTo(t0) >= 0) {
        final unbekannt = s.unk.contains(k);
        vorne = unbekannt ? F.mu2 : F.warn;
        if (!unbekannt) rand = F.warn;
        deckkraft = unbekannt ? .6 : 1;
        g = Text('?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.1, color: vorne));
      } else if (k.compareTo(t0) < 0) {
        g = const SizedBox(width: 18, height: 18);
        deckkraft = .25;
        tippbar = false;
      } else {
        g = const Opacity(opacity: .35, child: Icon(Icons.circle, size: 6, color: F.mu2));
        g = SizedBox(width: 18, height: 18, child: Center(child: g));
      }
      if (k == today) rand = F.ac;
      zellen.add(Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: i > 0 ? 5 : 0),
          child: Opacity(
            opacity: deckkraft,
            child: InkWell(
              key: Key('streifen-$k'),
              borderRadius: BorderRadius.circular(10),
              onTap: tippbar ? () => widget.tagOeffnen(k) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                    color: hinten, borderRadius: BorderRadius.circular(10), border: Border.all(color: rand)),
                child: Column(children: [
                  Text(nm[weekday0(k)],
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: vorne == F.mu2 ? F.mu2 : vorne)),
                  const SizedBox(height: 3),
                  SizedBox(height: 20, child: Center(child: g)),
                ]),
              ),
            ),
          ),
        ),
      ));
    }
    return Karte(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14), children: [Row(children: zellen)]);
  }

  // Nachsorge nach dem Ziel
  Widget _nachsorge(String today) {
    final s = ta.st;
    final d0 = dBetween(ta.stageStart, today) + 1;
    return Karte(
      rand: F.acRand,
      children: [
        KartenTitel(tr('Nachsorge', 'Aftercare'), icon: Icons.eco_outlined, farbe: F.ok),
        Text.rich(TextSpan(style: const TextStyle(fontSize: 18), children: [
          TextSpan(text: tr('Tag $d0', 'Day $d0'), style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: tr(' bei 0 ${s.unit}', ' at 0 ${s.unit}')),
        ])),
        Sub(
            tr('Nachwellen sind nach dem Absetzen nicht ungewöhnlich und klingen meist ab. Trag weiter ein, auch wenn du '
            'nichts genommen hast, dann bleibt auch ein Rückfall nachvollziehbar. Tagebuch, gute Tage und SOS bleiben '
            'für dich da.', 'Withdrawal waves after stopping are not unusual and usually fade. Keep logging even if you took nothing, so a relapse stays traceable. Diary, good days and SOS remain here for you.'),
            oben: 6),
      ],
    );
  }

  // Karte Wochen-Durchschnitt
  Widget _wochenschnitt(List<WeekAvg> wk, String today, bool frozen) {
    if (frozen) {
      return Opacity(
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
    return Karte(children: k);
  }
}
