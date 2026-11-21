// Reiter „Kalender“ und die Karte „Offene Tage“: Monatsansicht, Tag-Fenster, Nachtragen.
import 'i18n/txt.dart';
import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'deko.dart';
import 'lob.dart';
import 'eintragen.dart';
import 'fortschritt.dart';
import 'plan_kopf.dart';
import 'plan_reiter.dart';
import 'tag.dart';

/// Welcher Tag im Kalender geöffnet werden soll (aus Heute: Wochenstreifen, „Nachtragen“).
class TagWahl extends ChangeNotifier {
  String? tag;
  void waehle(String k) {
    tag = k;
    notifyListeners();
  }

  /// Einmal abholen (danach leer, damit ein neu aufgebauter Kalender ihn nicht erneut öffnet).
  String? abholen() {
    final t = tag;
    tag = null;
    return t;
  }
}

/// Karte „Offene Tage“, auf Heute und im Kalender.
class OffeneTageKarte extends StatefulWidget {
  const OffeneTageKarte({super.key, required this.app, required this.nachtragen});
  final AppState app;
  final void Function(String tag) nachtragen;
  @override
  State<OffeneTageKarte> createState() => _OffeneTageKarteState();
}

class _OffeneTageKarteState extends State<OffeneTageKarte> {
  bool _fragen = false; // Rückfrage „Weiß ich nicht mehr“ offen

  @override
  Widget build(BuildContext context) {
    final ta = widget.app.taper;
    final today = ta.today;
    final od = ta.openDays(today);
    final bk = od.where((k) => ta.daysAgo(k) <= 7).toList();
    final alt = od.where((k) => ta.daysAgo(k) > 7).toList();
    final titel = od.length == 1 && od[0] == addD(today, -1)
        ? tr('Gestern fehlt.', 'Yesterday is missing.')
        : (od.length == 1 ? tr('${datum(od[0])} fehlt.', '${datum(od[0])} is missing.') : tr('${od.length} Tage ohne Eintrag.', '${od.length} days without entry.'));
    final k = <Widget>[
      KartenTitel(tr('Offene Tage', 'Open days'), icon: Icons.warning_amber_rounded, hilfe: 'gap'),
      Text(titel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      Sub(
          tr('Die App rät nichts: Ohne Eintrag pausieren die Anzeigen. Trag nach, was du noch weißt, dann geht alles '
          'normal weiter. Am Plan ändert sich dadurch nichts.', 'The app does not guess: without an entry, the displays pause. Fill in what you still remember and everything continues normally. Your plan does not change because of this.'),
          oben: 6),
    ];
    if (bk.isNotEmpty) {
      k.add(const SizedBox(height: 12));
      k.add(hauptKnopf(tr('Nachtragen: ${datum(bk[0])}${bk.length > 1 ? ' (+${bk.length - 1} weitere)' : ''}', 'Add: ${datum(bk[0])}${bk.length > 1 ? " (+${bk.length - 1} more)" : ""}'),
          () => widget.nachtragen(bk[0]),
          icon: Icons.edit_outlined, key: const Key('nachtragenOffen')));
    }
    if (alt.isNotEmpty) {
      k.add(Sub(
          tr('${alt.length} ${alt.length == 1 ? 'Tag liegt' : 'Tage liegen'} mehr als 7 Tage zurück und lassen sich '
          'nicht mehr nachtragen.', '${alt.length} ${alt.length == 1 ? "day is" : "days are"} more than 7 days back and can no longer be added.'),
          oben: 12));
      k.add(const SizedBox(height: 8));
      if (_fragen) {
        k.add(Text(tr('Sicher? Diese Tage bleiben dauerhaft ein ?, die App läuft danach weiter.', 'Sure? These days will stay a ? permanently; the app carries on afterwards.')));
        k.add(const SizedBox(height: 8));
        k.add(Row(children: [
          Expanded(child: knopf(tr('Abbrechen', 'Cancel'), () => setState(() => _fragen = false))),
          const SizedBox(width: 8),
          Expanded(
            child: knopf(tr('Ja, weiß ich nicht mehr', 'Yes, I can’t remember'), () {
              ta.markUnk();
              setState(() => _fragen = false);
              widget.app.aenderung();
            }, hinten: F.warn, vorne: const Color(0xFF2A1D05), rand: F.warn),
          ),
        ]));
      } else {
        k.add(knopf(tr('Weiß ich nicht mehr', 'I can’t remember'), () => setState(() => _fragen = true)));
      }
    }
    return Karte(rand: F.warn, children: k);
  }
}

List<String> get _monate => monatsnamen();

String _p2(int n) => n < 10 ? '0$n' : '$n';

class KalenderSeite extends StatefulWidget {
  const KalenderSeite({super.key, required this.app, required this.wahl});
  final AppState app;
  final TagWahl wahl;
  @override
  State<KalenderSeite> createState() => _KalenderSeiteState();
}

class _KalenderSeiteState extends State<KalenderSeite> {
  late int _jahr;
  late int _monat; // 1..12
  late String _heute;

  @override
  void initState() {
    super.initState();
    _heute = widget.app.taper.today;
    _aufHeute();
    final t = widget.wahl.abholen();
    if (t != null) _spaeterOeffnen(t);
    widget.wahl.addListener(_gewaehlt);
  }

  @override
  void dispose() {
    widget.wahl.removeListener(_gewaehlt);
    super.dispose();
  }

  void _gewaehlt() {
    final t = widget.wahl.abholen();
    if (t != null) _spaeterOeffnen(t);
  }

  void _aufHeute() {
    final p = _heute.split('-');
    _jahr = int.parse(p[0]);
    _monat = int.parse(p[1]);
  }

  /// Nach dem Aufbau öffnen (aus Heute: Wochenstreifen, „Nachtragen“).
  void _spaeterOeffnen(String k) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _oeffnen(k);
      });

  /// Tag antippen: Fenster von unten mit Einnahmen, Nachtragen und Notizen.
  void _oeffnen(String k) => tagFensterOeffnen(context, widget.app, k);

  void _blaettern(int d) => setState(() {
        if (d == 0) {
          _aufHeute();
          return;
        }
        var m = _monat + d, y = _jahr;
        if (m < 1) {
          m = 12;
          y--;
        } else if (m > 12) {
          m = 1;
          y++;
        }
        _monat = m;
        _jahr = y;
      });

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final ta = app.taper;
    final s = ta.s;
    final today = ta.today;
    // Tageswechsel bei offener App.
    if (today != _heute) {
      final alt = _heute.split('-');
      final zeigteAlt = int.parse(alt[0]) == _jahr && int.parse(alt[1]) == _monat;
      _heute = today;
      if (zeigteAlt) _aufHeute();
    }
    if (s == null) {
      // Noch kein Plan: Startkarte und ein leerer Kalender zum Umschauen.
      return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [PlanKopf(app: app), _kalender(today)]);
    }
    final frozen = s.frz != null;
    final lob = lobHeute(app);
    // Reihenfolge von oben nach unten:
    // (Startkarte) → Kalender → Einnehmen → Verlauf (Stufenbalken) → Notizen für heute.
    final w = <Widget>[
      if (app.beispiel) PlanKopf(app: app),
      if (s.person != null) Begruessung(name: s.person!),
      // Dezent über dem Kalender: wann der Plan gestartet/zuletzt geändert wurde.
      Padding(
        key: const Key('kalPlanDatum'),
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text(planDatumZeile(ta), style: const TextStyle(color: F.mu, fontSize: 12.5)),
      ),
      _kalender(today),
      if (app.beispiel) const BeispielHinweis(),
      // Bei offenen Tagen erst nachtragen sonst „Dosis genommen“ / abweichende Dosis.
      if (frozen) OffeneTageKarte(app: app, nachtragen: _oeffnen),
      // Lob beim Halten: über „Heute eintragen“, den ganzen Lob-Tag, mit X weg.
      if (!frozen && lob != null) LobKarte(app: app, text: lob.text, schluessel: lob.schluessel),
      if (!frozen) HeuteEintragen(key: ValueKey('eintragen-$today'), app: app),
      // Verlauf: Stufenbalken. Bei offenen Tagen ausgegraut („Anzeigen pausieren“).
      if (s.plan.length >= 2)
        Opacity(
          opacity: frozen ? .4 : 1,
          // Stufen vor einem Sonnenuntergang mit Lavendel.
          child: Karte(
            key: const Key('kalenderFortschritt'),
            padding: const EdgeInsets.fromLTRB(4, 34, 4, 12),
            hintergrund: const CustomPaint(painter: LandschaftMaler()),
            children: [Fortschritt(taper: ta)],
          ),
        ),
      // „Notizen für heute“ (Befinden-Text, Links, Smileys, Notiz). Bei offenen Tagen ausgeblendet.
      if (!frozen)
        Karte(key: const Key('tagebuchHeute'), children: [
          Text(tr('Notizen für heute', 'Notes for today'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          TagInhalt(key: ValueKey('heute-$today'), app: app, tag: today),
        ]),
      // Hinweis als eigener Block unter „Notiz speichern“.
      if (!frozen)
        Padding(
          key: const Key('notizenHinweis'),
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline, size: 16, color: F.mu)),
            const SizedBox(width: 8),
            Expanded(child: Text(notizenHinweis, style: const TextStyle(color: F.mu, fontSize: 13.5))),
          ]),
        ),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: w);
  }

  Widget _kalender(String today) {
    final ta = widget.app.taper;
    final s = ta.s;
    final y = _jahr, m = _monat;
    final dim = DateTime.utc(y, m + 1, 0).day;
    final erster = '$y-${_p2(m)}-01';
    final off = (weekday0(erster) + 6) % 7;
    final t0c = s == null ? '9999' : (ta.t0Of() ?? '9999');
    final pj = s == null ? const ProjMap({}, null) : ta.projMap('$y-${_p2(m)}-${_p2(dim)}');
    final tp = today.split('-');
    final istAktuell = int.parse(tp[0]) == y && int.parse(tp[1]) == m;

    final zellen = <Widget>[
      for (final wd in wochentageKurz())
        Center(
          child: Text(wd,
              style: const TextStyle(fontSize: 11, color: F.mu2, fontWeight: FontWeight.w600, letterSpacing: .4)),
        ),
      for (var i = 0; i < off; i++) const SizedBox.shrink(),
      for (var dn = 1; dn <= dim; dn++) _zelle('$y-${_p2(m)}-${_p2(dn)}', dn, today, t0c, pj),
    ];

    final k = <Widget>[
      Row(children: [
        _pfeil('‹', () => _blaettern(-1), tr('Voriger Monat', 'Previous month')),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text('${_monate[m - 1]} $y',
                  key: const Key('monat'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            const HilfeKnopf('cal'),
          ]),
        ),
        _pfeil('›', () => _blaettern(1), tr('Nächster Monat', 'Next month')),
      ]),
      const SizedBox(height: 12),
      // Feste Zellgröße: Schrift im Raster höchstens leicht vergrößern, sonst überdecken sich die Zahlen.
      MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: GridView.count(
          crossAxisCount: 7,
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: zellen,
        ),
      ),
    ];
    if (!istAktuell) {
      k.add(const SizedBox(height: 10));
      k.add(knopf(tr('Zurück zu heute', 'Back to today'), () => _blaettern(0), key: const Key('zurueckHeute')));
    }
    if (s == null) {
      // ohne Plan keine Statuszeile
    } else if (s.frz != null) {
      k.add(Padding(
          padding: EdgeInsets.only(top: 6),
          child: IconText(Icons.warning_amber_rounded, tr('Offene Tage – Anzeigen pausieren bis zum Nachtragen.', 'Open days – displays pause until filled in.'),
              farbe: F.warn)));
    } else if (ta.voraussichtlichesEnde() case final ende?) {
      // wie auf der Plan-Karte, immer „voraussichtlich“, rückt beim Halten mit.
      k.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text.rich(TextSpan(children: [
          ikon(Icons.flag, farbe: F.mu),
          TextSpan(text: tr(' Voraussichtlich bei ${fz(s.plan.last)} ${s.unit}: ', ' Expected at ${fz(s.plan.last)} ${s.unit}: ')),
          TextSpan(text: datum(ende), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (s.hold) TextSpan(text: tr(' (Dosis wird gehalten)', ' (dose is being held)')),
        ])),
      ));
    }
    return Karte(children: k);
  }

  Widget _pfeil(String z, VoidCallback onTap, String tip) => Tooltip(
        message: tip,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            backgroundColor: F.card2,
            foregroundColor: F.tx,
            side: const BorderSide(color: F.line2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(z, style: const TextStyle(fontSize: 18, height: 1)),
        ),
      );

  // Eine Tageszelle.
  Widget _zelle(String k, int dn, String today, String t0c, ProjMap pj) {
    final s = widget.app.taper.s;
    final e = s?.log[k];
    var hinten = F.card2;
    Color vorne = F.mu;
    Border? rand;
    var deckkraft = 1.0;
    Widget? mitte;
    Color? punkt;
    var neueStufe = false;

    if (k.compareTo(today) <= 0) {
      if (e != null) {
        final lapse = e.r == 'lapse';
        hinten = lapse ? F.bads : F.oks;
        vorne = lapse ? F.bad : F.ok;
        mitte = lapse
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.close, size: 15, color: vorne),
                Text(fz(e.dose), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: vorne)),
              ])
            : Icon(Icons.check, size: 19, color: vorne);
      } else if (k.compareTo(today) < 0 && s != null) {
        deckkraft = .4;
        if (k.compareTo(t0c) >= 0) {
          if (!s.unk.contains(k)) {
            deckkraft = 1;
            vorne = F.warn;
            rand = Border.all(color: F.warn);
          }
          mitte = Text('?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1, color: vorne));
        }
      }
      if (k == today) rand = Border.all(color: F.ac, width: 2);
      if (s != null && s.notes.containsKey(k)) punkt = e == null ? F.ac : (e.r == 'lapse' ? F.bad : F.ok);
    } else {
      hinten = Colors.transparent;
      rand = Border.all(color: F.line);
      final p = pj.map[k];
      if (p != null) {
        if (p.ch) {
          neueStufe = true;
          rand = Border.all(color: F.acs2);
        }
        mitte = Text(fz(p.v), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: F.mu));
      }
    }
    final gut = s?.good.contains(k) ?? false;

    return Opacity(
      opacity: deckkraft,
      child: InkWell(
        key: Key('tag-$k'),
        borderRadius: BorderRadius.circular(10),
        onTap: s == null ? null : () => _oeffnen(k),
        child: Container(
          decoration: BoxDecoration(
            color: hinten,
            borderRadius: BorderRadius.circular(10),
            border: rand,
          ),
          foregroundDecoration: gut
              ? BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: F.gold, width: 1.5))
              : null,
          child: Stack(children: [
            Positioned(
              top: 3,
              left: 5,
              child: Opacity(
                opacity: .7,
                child: Text('$dn', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: vorne)),
              ),
            ),
            // Inhalt unterhalb der Tageszahl; in kleinen Zellen (schmale Handys) wird er verkleinert,
            // statt die Zahl zu überdecken.
            if (mitte != null)
              Positioned.fill(
                top: 11,
                bottom: 2,
                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: mitte)),
              ),
            if (gut) const Positioned(top: 3, right: 4, child: Icon(Icons.wb_sunny_outlined, size: 11, color: F.gold)),
            if (punkt != null)
              Positioned(
                bottom: 4,
                right: 5,
                child: Container(width: 5, height: 5, decoration: BoxDecoration(color: punkt, shape: BoxShape.circle)),
              ),
            if (neueStufe)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FractionallySizedBox(
                  widthFactor: .56,
                  child: Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      color: F.ac,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Hinweis unter „Notiz speichern“.
String get notizenHinweis => tr('Du kannst jederzeit nachtragen, falls du etwas vergessen hast. '
    'Tipp auf einen Tag im Kalender, um seine Notizen zu sehen.', 'You can add entries at any time if you forgot something. Tap a day in the calendar to see its notes.');

/// Fenster von unten für einen Tag: Einnahmen (nachtragen bis 7 Tage zurück), guter Tag, Befinden, Notiz.
/// Baut sich bei jeder Änderung neu auf. Nach unten wischen oder ✕ schließt.
Future<void> tagFensterOeffnen(BuildContext context, AppState app, String tag) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: F.card,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        minChildSize: .4,
        maxChildSize: .95,
        builder: (c, sc) => ListenableBuilder(
          listenable: app,
          builder: (c, _) {
            final today = app.taper.today;
            final kopf = tag == today ? null : '${datum(tag)}${tag.compareTo(today) > 0 ? ' · Zukunft' : ''}';
            return ListView(
              key: const Key('tagFenster'),
              controller: sc,
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.viewInsetsOf(c).bottom),
              children: [
                Row(children: [
                  Expanded(
                    child: kopf == null
                        ? Text(tr('Notizen für heute', 'Notes for today'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))
                        : IconText(Icons.sticky_note_2_outlined, kopf, fett: true),
                  ),
                  IconButton(
                    tooltip: tr('Schließen', 'Close'),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(c).pop(),
                  ),
                ]),
                const SizedBox(height: 4),
                TagInhalt(key: ValueKey('fenster-$tag'), app: app, tag: tag, kurz: true),
              ],
            );
          },
        ),
      ),
    );
