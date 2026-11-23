// Ein Tag: Einnahmen (nachtragen bis 7 Tage zurück), guter Tag, Befinden, Notiz.
// Wird im Kalender gezeigt: „Tagebuch heute“ unter dem Monat und im Tag-Fenster (Tag antippen).
import 'i18n/txt.dart';
import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'sos.dart';

/// Einnahme eintragen. Liegt sie heute über dem Plan, kommt erst „Kurz innehalten“.
/// Gibt `true` zurück, wenn eingetragen wurde.
Future<bool> einnahmeEintragen(BuildContext context, AppState app, double v, {String? t, String? k}) async {
  final tag = k ?? app.taper.today;
  final vorherDrueber = app.taper.st.log[tag]?.r == 'lapse';
  final r = app.taper.addIntake(v, t: t, k: k);
  if (r != IntakeResult.needsPause) {
    app.aenderung();
    if (r == IntakeResult.added && context.mounted) await _mehrAlsGeplant(context, app, tag, vorherDrueber);
    return r == IntakeResult.added;
  }
  final wahl = await Navigator.of(context)
      .push<Innehalten>(MaterialPageRoute(builder: (_) => InnehaltenSeite(app: app, menge: v)));
  if (wahl == Innehalten.eintragen) {
    app.taper.addIntake(v, t: t, k: k, force: true);
    app.aenderung();
    if (context.mounted) await _mehrAlsGeplant(context, app, tag, vorherDrueber);
    return true;
  }
  if ((wahl == Innehalten.warten || wahl == Innehalten.sos) && context.mounted) {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => SosSeite(app: app, timerSofort: wahl == Innehalten.warten)));
  }
  return false;
}

/// Nach dem Speichern: Rutscht der Tag dadurch über den Plan, einmal ein kurzes Fenster mit OK.
Future<void> _mehrAlsGeplant(BuildContext context, AppState app, String tag, bool vorherDrueber) async {
  if (vorherDrueber || app.taper.st.log[tag]?.r != 'lapse') return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      key: const Key('mehrAlsGeplant'),
      content: Text(tr(
          'Mehr als geplant – das kommt vor. Ein einzelner Tag macht nicht den ganzen Plan kaputt. Der Wochen-Ø zeigt: '
              'Über die Woche fällt er oft weniger ins Gewicht, als es sich gerade anfühlt.',
          "More than planned – that happens. One day doesn't undo the whole plan. The weekly average shows that over a "
              'week it often weighs less than it feels right now.')),
      actions: [FilledButton(key: const Key('mehrAlsGeplantOk'), onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );
}

/// Eine Zeile „Uhrzeit · Menge · ✕“ .
class EinnahmeZeile extends StatelessWidget {
  const EinnahmeZeile({super.key, required this.zeit, required this.menge, this.loeschen});
  final String zeit;
  final String menge;
  final VoidCallback? loeschen;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: F.line))),
        child: Row(children: [
          SizedBox(width: 56, child: Text(zeit.isEmpty ? '–' : zeit, style: const TextStyle(color: F.mu))),
          Expanded(child: Text(menge, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (loeschen != null)
            IconButton(
              tooltip: tr('Einnahme löschen', 'Delete intake'),
              style: IconButton.styleFrom(backgroundColor: F.bads, foregroundColor: const Color(0xFFF0A7A4)),
              icon: const Icon(Icons.close, size: 18),
              onPressed: loeschen,
            ),
        ]),
      );
}

/// Uhrzeit-Auswahl „HH:MM“. [wert] leer = keine Uhrzeit (nur bei [leerErlaubt]).
class UhrzeitFeld extends StatelessWidget {
  const UhrzeitFeld({super.key, required this.wert, required this.geaendert, this.leerErlaubt = false});
  final String wert;
  final ValueChanged<String> geaendert;
  final bool leerErlaubt;

  Future<void> _waehlen(BuildContext context) async {
    final p = wert.split(':');
    final init = wert.isEmpty
        ? TimeOfDay.now()
        : TimeOfDay(hour: int.tryParse(p[0]) ?? 12, minute: int.tryParse(p.length > 1 ? p[1] : '') ?? 0);
    final t = await showTimePicker(
      context: context,
      initialTime: init,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
    );
    if (t != null) geaendert('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _waehlen(context),
        child: InputDecorator(
          decoration: feldStil().copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
          child: Row(children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(wert.isEmpty ? '--:--' : wert,
                    style: TextStyle(color: wert.isEmpty ? F.mu2 : F.tx, fontSize: 16)),
              ),
            ),
            if (leerErlaubt && wert.isNotEmpty)
              InkWell(onTap: () => geaendert(''), child: const Icon(Icons.close, size: 16, color: F.mu)),
          ]),
        ),
      );
}

/// Knopf „Guter Tag“ (gold, wenn gesetzt).
Widget guterTagKnopf(AppState app, String k, {required bool heute}) {
  final an = app.taper.st.good.contains(k);
  return knopf(
    an ? tr('Guter Tag', 'Good day') : (heute ? tr('Heute war ein guter Tag', 'Today was a good day') : tr('Das war ein guter Tag', 'That was a good day')),
    () {
      app.taper.toggleGood(k);
      app.aenderung();
    },
    icon: Icons.wb_sunny_outlined,
    nachIcon: an ? Icons.check : null,
    hinten: an ? F.gold : null,
    vorne: an ? const Color(0xFF2B2200) : null,
    rand: an ? F.gold : null,
  );
}

const _gesichter = [
  Icons.sentiment_very_satisfied,
  Icons.sentiment_satisfied,
  Icons.sentiment_neutral,
  Icons.sentiment_dissatisfied,
  Icons.sentiment_very_dissatisfied,
];

/// Inhalt für einen Tag. Für heute: nur Befinden und Notiz.
class TagInhalt extends StatefulWidget {
  const TagInhalt({super.key, required this.app, required this.tag, this.kurz = false});
  final AppState app;
  final String tag;

  /// Im Tag-Fenster: ohne den langen Befinden-Text (steht unter dem Kalender), damit die Notiz gleich sichtbar ist.
  final bool kurz;
  @override
  State<TagInhalt> createState() => _TagInhaltState();
}

class _TagInhaltState extends State<TagInhalt> {
  late Note _entwurf;
  late final TextEditingController _text;
  final _menge = TextEditingController();
  String _zeit = '';
  bool _gespeichert = false;

  /// Tag-Fenster: eine vorhandene Notiz steht fest, erst „Bearbeiten“ macht sie änderbar.
  bool _bearbeiten = false;
  bool _mengeFehler = false;

  /// Gespeicherte Notiz, aus der der Entwurf stammt. Ändert sie sich woanders
  /// (z. B. auf der Tagesseite), wird der Entwurf neu geladen.
  String _basis = '';

  String _gespeicherteNotiz() {
    final n = widget.app.taper.st.notes[widget.tag];
    return n == null ? '' : '${n.sym}|${n.sx.join(',')}|${n.text}';
  }

  void _entwurfLaden() {
    final n = widget.app.taper.st.notes[widget.tag];
    _entwurf = Note(sx: List.of(n?.sx ?? const []), sym: n?.sym ?? 0, text: n?.text ?? '');
    _basis = _gespeicherteNotiz();
  }

  @override
  void initState() {
    super.initState();
    _entwurfLaden();
    _text = TextEditingController(text: _entwurf.text);
  }

  @override
  void didUpdateWidget(TagInhalt old) {
    super.didUpdateWidget(old);
    if (_gespeicherteNotiz() != _basis) {
      _entwurfLaden();
      _text.text = _entwurf.text;
      _gespeichert = false;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _menge.dispose();
    super.dispose();
  }

  Future<void> _nachtragen() async {
    final v = zahl(_menge.text);
    if (v == null || !(v >= 0)) {
      setState(() => _mengeFehler = true);
      return;
    }
    setState(() => _mengeFehler = false);
    if (await einnahmeEintragen(context, widget.app, v, t: _zeit, k: widget.tag)) {
      _menge.clear();
      if (mounted) setState(() => _zeit = '');
    }
  }

  void _speichern() {
    _entwurf.text = _text.text;
    widget.app.taper.saveNote(widget.tag, _entwurf);
    _basis = _gespeicherteNotiz();
    widget.app.aenderung();
    setState(() {
      _gespeichert = true;
      _bearbeiten = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final ta = app.taper;
    final s = ta.st;
    final nd = widget.tag;
    final heute = ta.today;
    final w = <Widget>[];

    if (nd.compareTo(heute) < 0) {
      final pe = s.log[nd];
      final kannNach = ta.daysAgo(nd) <= 7;
      w.add(Row(children: [
        Flexible(child: Feldname(tr('Einnahme an diesem Tag', 'Intake on this day'), oben: 0)),
        const Padding(padding: EdgeInsets.only(bottom: 6), child: HilfeKnopf('back')),
      ]));
      if (pe != null) {
        final its = ta.dayIt(pe);
        for (var i = 0; i < its.length; i++) {
          w.add(EinnahmeZeile(
            zeit: its[i].t,
            menge: '${fz(its[i].v)} ${s.unit}',
            loeschen: kannNach
                ? () {
                    ta.delIntake(i, nd);
                    app.aenderung();
                  }
                : null,
          ));
        }
        w.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: pe.r == 'lapse'
              ? IconText(Icons.close, tr('über Plan (${fz(pe.plan ?? 0)} ${s.unit})', 'above plan (${fz(pe.plan ?? 0)} ${s.unit})'), farbe: F.bad)
              : IconText(Icons.check, tr('im Plan', 'on plan'), farbe: F.ok),
        ));
      } else {
        w.add(Sub(tr('Nichts eingetragen.', 'Nothing logged.')));
      }
      if (kannNach) {
        final pp = ta.planAm(nd);
        if (pe == null) {
          w.add(const SizedBox(height: 8));
          w.add(hauptKnopf(tr('Nachtragen: ${fz(pp.plan)} ${s.unit} wie geplant', 'Add: ${fz(pp.plan)} ${s.unit} as planned'),
              () => einnahmeEintragen(context, app, pp.plan, t: '', k: nd),
              icon: Icons.check));
        }
        w.add(const SizedBox(height: 8));
        final menge = TextField(
          key: const Key('nachMenge'),
          controller: _menge,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: feldStil(hinweis: tr('andere Menge', 'other amount'), fehler: _mengeFehler),
        );
        final zeit = UhrzeitFeld(wert: _zeit, leerErlaubt: true, geaendert: (z) => setState(() => _zeit = z));
        final plus = SizedBox(width: 56, child: knopf('+', _nachtragen, key: const Key('nachPlus')));
        w.add(LayoutBuilder(
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
      } else {
        w.add(Sub(tr('Nachtragen geht bis 7 Tage zurück.', 'You can add entries up to 7 days back.'), oben: 4));
      }
    }

    if (nd.compareTo(heute) < 0) {
      w.add(const SizedBox(height: 12));
      w.add(guterTagKnopf(app, nd, heute: false));
    }
    // Ab hier: Notizen. Im Tag-Fenster (kurz) stehen sie oben, die Einnahmen klein darunter.
    final notizStart = w.length;
    if (nd.compareTo(heute) <= 0) {
      final n = s.notes[nd];
      final hatNotiz = n != null && (n.text.trim().isNotEmpty || n.sym > 0);
      final nurLesen = widget.kurz && hatNotiz && !_bearbeiten;
      // Unter dem Kalender: eine gespeicherte Notiz wird nicht angezeigt, nur vermerkt.
      // Lesen und Ändern über den Tag im Kalender (und im Notizbuch).
      final versteckt = !widget.kurz && hatNotiz;
      if (versteckt) {
        w.add(Container(
          key: const Key('notizVersteckt'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: F.card2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: F.line2),
          ),
          child: Row(children: [
            const Icon(Icons.check, color: F.ok, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  tr('Notiz für heute gespeichert. Tipp auf den Tag im Kalender, um sie zu lesen oder zu ändern.',
                      'Note for today saved. Tap the day in the calendar to read or change it.'),
                  style: const TextStyle(color: F.mu, height: 1.35)),
            ),
          ]),
        ));
      }
      if (versteckt) {
        // nichts weiter
      } else if (widget.kurz) {
        w.add(Text(hatNotiz ? tr('Notiz', 'Note') : tr('Notiz nachtragen', 'Add a note'),
            key: const Key('notizKopf'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)));
        w.add(const SizedBox(height: 8));
      }
      if (nurLesen) {
        // Feststehend: Smiley + Text, darunter „Bearbeiten“.
        w.add(Container(
          key: const Key('notizLesen'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: F.card2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: F.line2),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (n.sym > 0) ...[
              Icon(_gesichter[n.sym - 1], size: 26, color: F.ac2),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: n.text.trim().isEmpty
                  ? Text(tr('Nur Befinden, kein Text.', 'Feelings only, no text.'), style: TextStyle(color: F.mu))
                  : SelectableText(n.text, style: const TextStyle(fontSize: 15.5, height: 1.35)),
            ),
          ]),
        ));
        w.add(const SizedBox(height: 10));
        w.add(knopf(tr('Bearbeiten', 'Edit'), () => setState(() => _bearbeiten = true),
            icon: Icons.edit_outlined, key: const Key('notizBearbeiten')));
      }
      if (!widget.kurz && !versteckt) w.add(Feldname(tr('Befinden', 'How you feel')));
      // Eingabe (Smileys, Feld, Speichern) nur, wenn nicht feststehend
      if (!nurLesen && !versteckt) {
        if (!widget.kurz) {
          w.add(const BefindenText());
          w.add(const SizedBox(height: 12));
        }
        w.add(Row(children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 4 ? 8 : 0),
                child: OutlinedButton(
                  key: Key('sym${i + 1}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    backgroundColor: _entwurf.sym == i + 1 ? F.acs2 : F.card2,
                    foregroundColor: _entwurf.sym == i + 1 ? F.ac2 : F.mu,
                    side: BorderSide(color: _entwurf.sym == i + 1 ? F.ac : F.line2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => setState(() {
                    _entwurf.sym = _entwurf.sym == i + 1 ? 0 : i + 1;
                    _gespeichert = false;
                  }),
                  child: Icon(_gesichter[i], size: 26),
                ),
              ),
            ),
        ]));
        if (!widget.kurz) w.add(const SizedBox(height: 8));
        if (!widget.kurz)
          w.add(Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            const HilfeKnopf('bind'),
            Text(tr('Mehr dazu: ', 'More on this: '), style: TextStyle(color: F.mu, fontSize: 14)),
            _Link(tr('Befragung zu Langzeitfolgen (PLOS ONE, 2023)', 'Survey on long-term effects (PLOS ONE, 2023)'), 'https://doi.org/10.1371/journal.pone.0285584'),
            const Text(' · ', style: TextStyle(color: F.mu, fontSize: 14)),
            _Link(tr('Ashton 1991: verlängerte Symptome', 'Ashton 1991: protracted symptoms'), 'https://mail.benzo.org.uk/ashpws.htm'),
          ]));
        // Feldbeschriftung entfernt – nur noch Platzhalter.
        w.add(const SizedBox(height: 12));
        w.add(TextField(
          key: const Key('notiz'),
          controller: _text,
          minLines: 3,
          maxLines: 6,
          decoration: feldStil(hinweis: tr('z. B. 4 Kaffee, neues Medikament', 'e.g. 4 coffees, new medication')),
          onChanged: (_) {
            if (_gespeichert) setState(() => _gespeichert = false);
          },
        ));
        w.add(const SizedBox(height: 12));
        w.add(hauptKnopf(_gespeichert ? tr('Gespeichert', 'Saved') : tr('Notiz speichern', 'Save note'), _speichern,
            nachIcon: _gespeichert ? Icons.check : null, key: const Key('notizSpeichern')));
      }
    }
    if (widget.kurz && notizStart > 0 && notizStart < w.length) {
      final einnahmen = w.sublist(0, notizStart);
      w
        ..removeRange(0, notizStart)
        ..add(const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)))
        ..add(Text(tr('Einnahmen', 'Intakes'), style: TextStyle(fontWeight: FontWeight.w600, color: F.mu)))
        ..add(const SizedBox(height: 4))
        ..addAll(einnahmen);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: w);
  }
}

class _Link extends StatelessWidget {
  const _Link(this.text, this.url);
  final String text;
  final String url;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Text(text,
            style: const TextStyle(
                color: F.ac2, fontSize: 14, decoration: TextDecoration.underline, decorationColor: F.ac2)),
      );
}

/// Text über den Smileys und dem Notizfeld .
class BefindenText extends StatelessWidget {
  const BefindenText({super.key});
  static const _stil = TextStyle(color: F.mu, fontSize: 14, height: 1.4);
  static const _fett = TextStyle(fontWeight: FontWeight.w700, color: F.tx);
  @override
  Widget build(BuildContext context) => Column(
        key: Key('befindenText'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              tr('Bei einer Langzeiteinnahme und während des Benzodiazepin-Entzugs kann vieles paradox wirken. Auch '
              'Medikamente, Nahrungsergänzungsmittel, Lebensmittel, Koffein oder Nikotin können das Befinden '
              'beeinflussen.', 'During long-term use and benzodiazepine withdrawal, a lot can seem paradoxical. Medication, supplements, food, caffeine or nicotine can also affect how you feel.'),
              style: _stil),
          SizedBox(height: 8),
          Text.rich(TextSpan(style: _stil, children: [
            TextSpan(text: tr('Mustererkennung statt ständigem Symptomcheck:', 'Pattern recognition instead of constant symptom checking:'), style: _fett),
            TextSpan(
                text: tr(' Es geht darum, mögliche Unverträglichkeiten und Zusammenhänge im Nachhinein nachvollziehen '
                    'zu können.', ' The point is to be able to retrace possible intolerances and connections afterwards.')),
          ])),
          SizedBox(height: 8),
          Text.rich(TextSpan(style: _stil, children: [
            TextSpan(text: tr('Persönliche Erfahrung des Entwicklers:', 'Developer’s personal experience:'), style: _fett),
            TextSpan(
                text: tr(' Bei mir war beispielsweise das Vapen ein Faktor, den ich lange nicht auf dem Schirm hatte. '
                    'Mir ging es teilweise so schlecht, dass ich zunächst den Benzodiazepin-Entzug dafür '
                    'verantwortlich machte. Erst rückblickend konnte ich den Zusammenhang mit dem Vapen erkennen.', ' For me, for example, vaping was a factor I did not have on my radar for a long time. I sometimes felt so bad that I first blamed benzodiazepine withdrawal for it. Only in hindsight could I see the connection with vaping.')),
          ])),
          SizedBox(height: 8),
          Text(
              tr('Halte deshalb auch scheinbar nebensächliche Dinge fest. Manchmal wird ein Zusammenhang erst durch '
              'den Blick auf mehrere Tage deutlich.', 'That is why you should also note down seemingly minor things. Sometimes a connection only becomes clear when you look at several days.'),
              style: _stil),
        ],
      );
}
