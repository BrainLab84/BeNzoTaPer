// Reiter „Heute“ (Startreiter): Vorrat-Warnung, offene Tage, Vormerkung, neue Stufe, Lob,
// Heute eintragen, Dosis-Karte mit Halten, Wochenstreifen, Nachsorge, Tablettenvorrat.
// Rechenregeln: nur aus dem Kern.
import 'i18n/txt.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'fortschritt.dart';
import 'eintragen.dart';
import 'kalender.dart';
import 'lob.dart';
import 'plan_anpassen.dart';
import 'plan_kopf.dart';
import 'sicherung.dart';
import 'vorrat.dart';

class HeuteSeite extends StatefulWidget {
  const HeuteSeite({super.key, required this.app, required this.tagOeffnen, this.planEditor});
  final AppState app;

  /// Tag im Kalender öffnen (wechselt zum Kalender).
  final void Function(String tag) tagOeffnen;

  /// Öffnet den Plan-Editor mit einem Entwurf (vorgemerkte Planänderung). Fehlt noch → Hinweis.
  final void Function(PlanEdit e)? planEditor;
  @override
  State<HeuteSeite> createState() => _HeuteSeiteState();
}

class _HeuteSeiteState extends State<HeuteSeite> {

  // „Dosis halten“ (holdAsk)
  bool _halten = false;
  final _haltenTage = TextEditingController();
  bool _haltenFehler = false;

  // „Heute eintragen“

  AppState get app => widget.app;
  Taper get ta => app.taper;

  /// Vorrat-Karte unten auf Heute; die Warnung oben scrollt dorthin.
  final _vorratKey = GlobalKey();
  void _zumVorrat() {
    final c = _vorratKey.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    for (final c in [_haltenTage]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fertig() => app.aenderung();

  // ---------------------------------------------------------------- Aktionen

  void _haltenStarten({required bool offen}) {
    int? n;
    if (!offen) {
      n = ganzZahl(_haltenTage.text);
      if (n == null || !(n >= 1 && n <= 365)) {
        setState(() => _haltenFehler = true);
        return;
      }
    }
    if (!ta.haltenMoeglich) return;
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
      if (ta.haltenMoeglich) setState(() => _halten = true);
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
            content: Text(tr('Die Änderung kann hier nicht geöffnet werden.', 'The change cannot be opened here.')),
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
      // Noch kein Plan: Startkarte.
      return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [PlanKopf(app: app)]);
    }
    final s = ta.st;
    final today = ta.today;
    final frozen = s.frz != null;
    final dose = s.plan[s.stage];
    final last = s.stage >= s.plan.length - 1;

    final w = <Widget>[];
    if (app.sicherungErinnern) w.add(_sicherungBanner());
    final si = ta.stockInfo();
    if (si != null && si.days <= 14)
      w.add(VorratWarnung(si: si, unit: s.unit, heute: today, oeffnen: _zumVorrat));
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
    // Plan beginnt erst später: nur eine ruhige Karte mit Starttag und Startdosis, dazu der Vorrat.
    if (ta.vorStart) {
      w.add(_vorStartKarte());
      w.add(VorratKarte(key: _vorratKey, app: app, gross: true));
      if (s.person != null) w.insert(0, Begruessung(name: s.person!));
      return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: w);
    }
    // Reihenfolge: Lob → Heute eintragen → Stufen-Karte → Wochenstreifen → Vorrat.
    final lob = frozen ? null : lobHeute(app);
    if (lob != null) w.add(LobKarte(app: app, text: lob.text, schluessel: lob.schluessel));
    if (!frozen) w.add(HeuteEintragen(key: ValueKey('eintragen-$today'), app: app));
    if (!frozen) w.add(_dosisKarte(today));
    w.add(_wochenstreifen(today));
    if (last && !(dose > 0)) w.add(_nachsorge(today));
    w.add(VorratKarte(key: _vorratKey, app: app, gross: true));
    if (app.beispiel) w.insertAll(0, [PlanKopf(app: app), const BeispielHinweis()]);
    if (s.person != null && !app.beispiel) w.insert(0, Begruessung(name: s.person!));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: w);
  }

  // Dezente Erinnerung zum Sichern (alle 14 Tage, nur bei Änderungen).
  Widget _sicherungBanner() => Karte(
        key: const Key('sicherungBanner'),
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        children: [
          Row(children: [
            const Icon(Icons.save_outlined, color: F.mu, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Seit einer Weile nicht gesichert.', 'Not backed up for a while.'),
                  style: const TextStyle(color: F.mu, fontSize: 14)),
            ),
            TextButton(
              key: const Key('sicherungBannerSichern'),
              onPressed: () => Navigator.of(context)
                  .push<bool>(MaterialPageRoute(builder: (_) => SicherungSpeichernSeite(app: app, dateien: app.dateien))),
              child: Text(tr('Sichern', 'Back up')),
            ),
            IconButton(
              key: const Key('sicherungBannerWeg'),
              tooltip: tr('Später', 'Later'),
              icon: const Icon(Icons.close, size: 18, color: F.mu),
              onPressed: app.sicherungErinnerungWeg,
            ),
          ]),
        ],
      );

  // Vor dem Start: Starttag und Startdosis, nichts zum Eintragen.
  Widget _vorStartKarte() {
    final s = ta.st;
    return Karte(key: const Key('vorStart'), rand: F.acRand, mitte: true, children: [
      const Icon(Icons.event_outlined, color: F.ac2, size: 30),
      const SizedBox(height: 8),
      Text(tr('Plan startet am ${datum(s.t0!)}', 'Plan starts on ${datum(s.t0!)}'),
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      Sub(tr('Startdosis: ${fz(s.plan[s.stage])} ${s.unit} pro Tag', 'Starting dose: ${fz(s.plan[s.stage])} ${s.unit} per day'),
          oben: 6, mitte: true),
    ]);
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
          tr('Frühestens in ${stunden((left / 3600000).ceil())}. Bis dahin gilt der bisherige Plan. „Dosis halten“ geht '
          'jederzeit sofort.', 'Earliest in ${stundenEn((left / 3600000).ceil())}. Until then the current plan applies. “Hold dose” works immediately at any time.'),
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
      // Halten beginnt am letzten Stufentag: letzter Haltetag = [holdUntil], die nächste Stufe beginnt am
      // Tag danach. Die Zahl „noch“ zählt die Tage nach heute.
      final bis = ta.haltBis;
      final rest = s.holdUntil == null ? 0 : dBetween(today, s.holdUntil!);
      k.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: IconText(
          Icons.pause,
          bis != null
              ? tr('Dosis wird voraussichtlich gehalten bis ${datum(bis)} (noch ${tage(rest)}).', 'Dose is expected to be held until ${datum(bis)} (${tage(rest)} left).')
              : tr('Dosis wird gehalten – so lange du brauchst.', 'Dose is being held – as long as you need.'),
          farbe: F.warn,
          mitte: true,
        ),
      ));
      k.add(Sub(
          tr('${bis != null ? 'Danach geht es automatisch weiter. Bist du früher bereit, drück auf „Weiter abdosieren“.' : 'Wenn du bereit bist, drück auf „Weiter abdosieren“.'}'
          ' Der Plan verschiebt sich automatisch um die gehaltenen Tage nach hinten.', '${bis != null ? "After that it continues automatically. If you are ready earlier, tap “Continue tapering”." : "When you are ready, tap “Continue tapering”."} The plan shifts back automatically by the days held.'),
          oben: 4,
          mitte: true));
    } else if (!last) {
      k.add(
          Sub(tr('Nächste Stufe ${nextIn == 1 ? 'morgen' : 'in $nextIn Tagen'} (${datum(nextKey)})', 'Next step ${nextIn == 1 ? "tomorrow" : "in $nextIn days"} (${datum(nextKey)})'), oben: 6, mitte: true));
    } else if (last && !finished) {
      k.add(Sub(tr('Letzte Stufe · Tag ${sday + 1} von $ndy', 'Last step · Day ${sday + 1} of $ndy'), oben: 8, mitte: true));
    }

    if (!last && _halten && !s.hold) {
      k.add(_haltenFormular());
    } else if (!finished) {
      // „Plan anpassen“: ab heute alles änderbar, gilt sofort (auch beim Halten und in der letzten Stufe).
      k.add(const SizedBox(height: 12));
      final anpassen = knopf(tr('Plan anpassen', 'Adjust plan'), () {
        Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PlanAnpassenSeite(app: app)));
      }, icon: Icons.tune, key: const Key('anpassen'));
      final halten = last
          ? null
          : knopf(s.hold ? tr('Weiter abdosieren', 'Continue tapering') : tr('Dosis halten', 'Hold dose'),
              (s.hold || ta.haltenMoeglich) ? _haltenUmschalten : null,
              icon: s.hold ? Icons.play_arrow : Icons.pause, key: const Key('halten'));
      if (!last && !s.hold) {
        final ab = ta.haltenAb;
        k.add(Sub(
            ta.haltenMoeglich
                ? tr('Beginnt morgen die nächste Stufe und du bist noch nicht bereit? Dann kannst du hier die Dosis halten.',
                    'Next step starts tomorrow and you are not ready yet? Then you can hold the dose here.')
                : tr('Wenn die nächste Stufe beginnt und du noch nicht bereit bist, kannst du die Dosis halten – ab ${datum(ab!)} möglich.',
                    'If the next step begins and you are not ready yet, you can hold the dose – possible from ${datum(ab)}.'),
            oben: 0,
            mitte: true));
        k.add(const SizedBox(height: 8));
      }
      k.add(LayoutBuilder(
        builder: (context, c) => halten == null
            ? Row(children: [Expanded(child: anpassen), const HilfeKnopf('time')])
            : genugPlatz(context, c, 320)
                ? Row(children: [
                    Expanded(child: anpassen),
                    const SizedBox(width: 8),
                    Expanded(child: halten),
                    const HilfeKnopf('time'),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    anpassen,
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
            'nichts genommen hast, dann bleibt auch ein Rückfall nachvollziehbar. Notizen, gute Tage und SOS bleiben '
            'für dich da.', 'Withdrawal waves after stopping are not unusual and usually fade. Keep logging even if you took nothing, so a relapse stays traceable. Notes, good days and SOS remain here for you.'),
            oben: 6),
      ],
    );
  }
}

String stunden(int n) => '$n ${n == 1 ? 'Stunde' : 'Stunden'}';
String stundenEn(int n) => '$n ${n == 1 ? 'hour' : 'hours'}';
