// „Neuen Plan erstellen“ / „Plan importieren“: ein freundlicher Ablauf, eine Frage pro Seite.
// Plan erstellen oder importieren. Regeln bleiben im Kern (`applyPlan`): bei bestehendem Plan
// „Ich bin mir sicher“, Dosis rauf oder langsamer nur mit 48 Stunden Bedenkzeit und Begründung.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'i18n/meldungen.dart';
import 'i18n/txt.dart';
import 'plan_lesen.dart';
import 'sicherung.dart';

enum PlanArt { erstellen, importieren }

enum PlanErgebnis { uebernommen, vorgemerkt }

class _AbschnittFelder {
  _AbschnittFelder({String schritt = '', String tage = '14', String bis = '0'})
      : schritt = TextEditingController(text: schritt),
        tage = TextEditingController(text: tage),
        bis = TextEditingController(text: bis);
  final TextEditingController schritt, tage, bis;
  void dispose() {
    schritt.dispose();
    tage.dispose();
    bis.dispose();
  }
}

class _ZeileFelder {
  _ZeileFelder(EditRow r)
      : dosis = TextEditingController(text: r.dose == null ? '' : fz(r.dose!)),
        tage = TextEditingController(text: r.days == null ? '' : '${r.days}'),
        geschaetzt = r.guess;
  final TextEditingController dosis, tage;
  bool geschaetzt;
  void dispose() {
    dosis.dispose();
    tage.dispose();
  }
}

class PlanNeuSeite extends StatefulWidget {
  const PlanNeuSeite(
      {super.key, required this.app, this.art = PlanArt.erstellen, this.vorgemerkt, this.pdf});
  final AppState app;
  final PlanArt art;

  /// Vorgemerkte Planänderung nach der Bedenkzeit: nur noch bestätigen.
  final PlanEdit? vorgemerkt;

  /// PDF-Leser (in Tests ersetzt).
  final PdfLeser? pdf;
  @override
  State<PlanNeuSeite> createState() => _PlanNeuSeiteState();
}

class _PlanNeuSeiteState extends State<PlanNeuSeite> {
  int _schritt = 0;
  final _person = TextEditingController();
  final _med = TextEditingController();
  final _dosis = TextEditingController();
  final _abschnitte = <_AbschnittFelder>[];
  final _text = TextEditingController();
  final _zeilen = <_ZeileFelder>[];
  final _conf = TextEditingController();
  final _warum = TextEditingController();
  String _unit = 'mg';
  int _start = 0;

  /// Startdatum (JJJJ-MM-TT) des ersten eigenen Plans; `null` = heute.
  String? _beginn;
  String get _beginnTag => _beginn ?? ta.today;
  String? _fehler;
  String? _meldung;
  bool _warumFragen = false;
  bool _liest = false;
  List<EditRow> _rows = [];

  AppState get app => widget.app;
  Taper get ta => app.taper;
  /// Gilt ein bestehender Plan weiter (nur beim Übernehmen einer alten Vormerkung)? Beim Neustart nicht.
  bool get _gibtPlan => ta.s != null;

  List<String> get _schritte => widget.vorgemerkt != null
      ? const ['los']
      : ['name', widget.art == PlanArt.erstellen ? 'plan' : 'import', 'arzt', 'los'];

  @override
  void initState() {
    super.initState();
    final s = ta.s;
    _person.text = s?.person ?? '';
    _med.text = s?.name ?? 'Diazepam';
    _unit = s?.unit ?? 'mg';
    if (s != null) _dosis.text = fz(s.plan[s.stage]);
    _abschnitte.add(_AbschnittFelder(tage: '${s?.target ?? 14}'));
    final v = widget.vorgemerkt;
    if (v != null) _rows = v.rows;
  }

  @override
  void dispose() {
    for (final c in [_person, _med, _dosis, _text, _conf, _warum]) {
      c.dispose();
    }
    for (final a in _abschnitte) {
      a.dispose();
    }
    for (final z in _zeilen) {
      z.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- Rechnen

  AbschnittsPlan _ausAbschnitten() {
    final start = zahl(_dosis.text) ?? double.nan;
    return planAusAbschnitten(start, [
      for (final a in _abschnitte)
        Abschnitt(zahl(a.schritt.text) ?? double.nan, ganzZahl(a.tage.text) ?? 0, zahl(a.bis.text) ?? double.nan),
    ]);
  }

  /// Zeilen aus dem Import lesen; Fehlertext oder null.
  Meldung? _zeilenLesen() {
    if (_zeilen.isEmpty) return const Meldung(MeldungCode.keineSchritte);
    final rows = <EditRow>[];
    for (var i = 0; i < _zeilen.length; i++) {
      final d = zahl(_zeilen[i].dosis.text);
      final n = ganzZahl(_zeilen[i].tage.text);
      if (d == null || !(d >= 0)) return Meldung(MeldungCode.stufeDosisFehlt, [i + 1]);
      if (n == null || n < 1) return Meldung(MeldungCode.stufeTageFehlen, [i + 1]);
      if (n > maxStufenTage) return Meldung(MeldungCode.stufeMaxTage, [i + 1, maxStufenTage]);
      rows.add(EditRow(d, n));
    }
    final lang = planLaengeFehler([for (var i = 0; i < rows.length - 1; i++) rows[i].days!]);
    if (lang != null) return lang;
    _rows = rows;
    if (_start >= rows.length) _start = rows.length - 1;
    return null;
  }

  void _weiter() {
    final was = _schritte[_schritt];
    Meldung? f;
    if (was == 'plan') {
      final r = _ausAbschnitten();
      f = r.fehler;
      if (f == null) {
        _rows = [for (var i = 0; i < r.plan.length; i++) EditRow(r.plan[i], r.days[i])];
        _start = 0;
      }
    } else if (was == 'import') {
      f = _zeilenLesen();
    }
    setState(() {
      _fehler = f == null ? null : meldungText(f);
      if (f == null) _schritt++;
    });
  }

  void _zurueck() => setState(() {
        _fehler = null;
        _schritt--;
      });

  Future<void> _dateiWaehlen() async {
    setState(() {
      _liest = true;
      _fehler = null;
      _meldung = null;
    });
    try {
      final d = await app.dateien.dateiWaehlen();
      if (d == null) return;
      final t = await textAusDatei(d.name, d.bytes, pdf: widget.pdf);
      _text.text = t;
      _auslesen();
    } on LeseFehler catch (e) {
      setState(() => _fehler = e.text);
    } on LeseFehlerGross {
      setState(() => _fehler = tr('Die Datei ist zu groß.', 'The file is too large.'));
    } catch (_) {
      setState(() => _fehler = tr('Datei konnte nicht gelesen werden. Bitte Text einfügen oder abtippen.', 'The file could not be read. Please paste or type the text.'));
    } finally {
      if (mounted) setState(() => _liest = false);
    }
  }

  void _auslesen() {
    final e = ta.openEditor(neu: true);
    ta.editParse(e, _text.text, englisch: Txt.en);
    setState(() {
      if (e.err != null) {
        _fehler = meldungText(e.err!);
        _meldung = null;
        return;
      }
      for (final z in _zeilen) {
        z.dispose();
      }
      _zeilen
        ..clear()
        ..addAll(e.rows.map(_ZeileFelder.new));
      _unit = e.unit;
      _start = 0;
      if (e.startDatum != null) _beginn = e.startDatum;
      _fehler = null;
      _meldung = e.msg == null ? null : meldungText(e.msg!);
    });
  }

  void _uebernehmen() {
    final v = widget.vorgemerkt;
    final e = v ?? ta.openEditor(neu: true);
    if (v == null) {
      e
        ..name = _med.text.trim().isEmpty ? tr('Medikament', 'Medication') : _med.text
        ..unit = _unit
        ..rows = _rows
        ..start = _start
        ..startDatum = _gibtPlan ? null : _beginn;
    }
    e
      ..conf = _conf.text
      ..why = _warum.text
      ..askWhy = _warumFragen;
    final r = ta.applyPlan(e);
    if (r.askWhy) {
      setState(() {
        _warumFragen = true;
        _fehler = null;
      });
      return;
    }
    if (r.err != null) {
      setState(() => _fehler = meldungText(r.err!));
      return;
    }
    if (v == null && ta.s != null) {
      final p = _person.text.trim();
      ta.st.person = p.isEmpty ? null : p;
      ta.save();
    }
    app.aenderung();
    Navigator.pop(context, r.pended ? PlanErgebnis.vorgemerkt : PlanErgebnis.uebernommen);
  }

  // ---------------------------------------------------------------- Aufbau

  @override
  Widget build(BuildContext context) {
    final was = _schritte[_schritt];
    final titel = widget.vorgemerkt != null
        ? tr('Vorgemerkte Änderung', 'Scheduled change')
        : (widget.art == PlanArt.erstellen ? tr('Neuer Plan', 'New plan') : tr('Plan importieren', 'Import plan'));
    final inhalt = switch (was) {
      'name' => _nameSeite(),
      'plan' => _planSeite(),
      'import' => _importSeite(),
      'arzt' => _arztSeite(),
      _ => _losSeite(),
    };
    final letzte = _schritt == _schritte.length - 1;
    return PopScope(
      canPop: _schritt == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _zurueck();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(titel)),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
          if (_schritte.length > 1) _punkte(),
          const SizedBox(height: 12),
          ...inhalt,
          if (_fehler != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_fehler!, key: const Key('planFehler'), style: const TextStyle(color: F.bad)),
            ),
          const SizedBox(height: 20),
          Row(children: [
            if (_schritt > 0) ...[
              Expanded(child: knopf(tr('Zurück', 'Back'), _zurueck)),
              const SizedBox(width: 10),
            ],
            Expanded(
              flex: 2,
              child: letzte
                  ? hauptKnopf(
                      !_gibtPlan
                          ? tr("Los geht's", 'Let’s go')
                          : (_warumFragen && widget.vorgemerkt == null ? tr('In 48 h übernehmen', 'Apply in 48 h') : tr('Plan übernehmen', 'Apply plan')),
                      _uebernehmen,
                      key: const Key('planLos'), blatt: false)
                  : hauptKnopf(tr('Weiter', 'Next'), _weiter, key: const Key('planWeiter'), blatt: false),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _punkte() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < _schritte.length; i++)
          Container(
            width: i == _schritt ? 22 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: i <= _schritt ? F.ac : F.line2,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ]);

  Widget _ueberschrift(String t, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, color: F.ac2, size: 26)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.25))),
        ]),
      );

  Widget _absatz(String t) => Padding(
      padding: const EdgeInsets.only(top: 8), child: Text(t, style: const TextStyle(fontSize: 16, height: 1.4)));

  List<Widget> _nameSeite() => [
        _ueberschrift(tr('Schön, dass du da bist.', 'Nice to have you here.'), icon: Icons.waving_hand_outlined),
        _absatz(tr('Wie heißt du? Das ist freiwillig – wenn du magst, begrüßt dich die App mit deinem Namen.', 'What is your name? This is optional – if you like, the app greets you by name.')),
        const SizedBox(height: 16),
        TextField(
          key: const Key('planPerson'),
          controller: _person,
          textCapitalization: TextCapitalization.words,
          decoration: feldStil(hinweis: tr('Dein Vorname', 'Your first name')),
          onSubmitted: (_) => _weiter(),
        ),
      ];

  List<Widget> _planSeite() {
    final w = <Widget>[
      _ueberschrift(tr('Wie sieht dein Abdosierplan aus?', 'What does your tapering plan look like?'), icon: Icons.route_outlined),
      _absatz(tr('Trag deine aktuelle Tagesdosis ein und wie es weitergehen soll. Du kannst den Plan in Abschnitte '
          'teilen – zum Beispiel erst in größeren Schritten, später langsamer.', 'Enter your current daily dose and how it should continue. You can split the plan into sections – for example larger steps first, slower later.')),
      Feldname(tr('Medikament', 'Medication')),
      TextField(key: const Key('planMed'), controller: _med, decoration: feldStil()),
      Feldname(tr('Aktuelle Tagesdosis ($_unit)', 'Current daily dose ($_unit)')),
      TextField(
        key: const Key('planDosis'),
        controller: _dosis,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: feldStil(hinweis: tr('z. B. 10', 'e.g. 10')),
        onChanged: (_) => setState(() {}),
      ),
      ..._startFeld(),
    ];
    for (var i = 0; i < _abschnitte.length; i++) {
      final a = _abschnitte[i];
      Widget feld(String name, TextEditingController c, String key, {bool ganz = false}) => Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Feldname(name, oben: 6),
              TextField(
                key: Key('$key$i'),
                controller: c,
                keyboardType: ganz ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
                decoration: feldStil(hinweis: key == 'abBis' && i < _abschnitte.length - 1 ? tr('z. B. 20', 'e.g. 20') : null),
                onChanged: (_) => setState(() {}),
              ),
            ]),
          );
      w.add(const SizedBox(height: 14));
      w.add(Karte(
        farbe: F.card2.withValues(alpha: .5),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 14),
        children: [
          Row(children: [
            Expanded(
              child: Text(_abschnitte.length > 1 ? tr('Abschnitt ${i + 1}', 'Section ${i + 1}') : tr('So geht es weiter', 'How it continues'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (_abschnitte.length > 1)
              IconButton(
                tooltip: tr('Abschnitt entfernen', 'Remove section'),
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _abschnitte.removeAt(i).dispose()),
              ),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            feld(tr('runter um ($_unit)', 'reduce by ($_unit)'), a.schritt, 'abSchritt'),
            const SizedBox(width: 8),
            feld(tr('alle … Tage', 'every … days'), a.tage, 'abTage', ganz: true),
            const SizedBox(width: 8),
            feld(tr('bis ($_unit)', 'until ($_unit)'), a.bis, 'abBis'),
          ]),
        ],
      ));
    }
    w.add(knopf(tr('Weiterer Abschnitt', 'Another section'), () {
      final l = _abschnitte.last;
      setState(() {
        // Der bisher letzte Abschnitt ging meist bis zum Ziel: dort „bis“ leeren, damit man einträgt, wo er
        // aufhören soll; der neue geht dann bis zum Ziel.
        // Nur leeren, wenn er bis 0 ging; ein selbst eingetragenes Zwischenziel bleibt stehen.
        if (zahl(l.bis.text) == 0) l.bis.clear();
        _abschnitte.add(_AbschnittFelder(tage: l.tage.text));
      });
    }, icon: Icons.add, key: const Key('abschnittPlus')));

    final r = _ausAbschnitten();
    if (r.fehler == null) {
      final gesamt = r.days.take(r.days.length - 1).fold<int>(0, (a, b) => a + b);
      final ende = addD(_gibtPlan ? ta.today : _beginnTag, gesamt);
      w.add(const SizedBox(height: 14));
      w.add(Karte(rand: F.acRand, children: [
        Text(tr('${r.plan.length} Stufen · ${fz(r.plan.first)} → ${fz(r.plan.last)} $_unit', '${r.plan.length} steps · ${fz(r.plan.first)} → ${fz(r.plan.last)} $_unit'),
            key: const Key('planVorschau'), style: const TextStyle(fontWeight: FontWeight.w700)),
        Sub(tr('Voraussichtlich bei ${fz(r.plan.last)} $_unit: ${datum(ende)} (ca. ${(gesamt / 7).round()} Wochen)', 'Expected at ${fz(r.plan.last)} $_unit: ${datum(ende)} (approx. ${(gesamt / 7).round()} weeks)'), oben: 4),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr('Stufen ansehen', 'View steps'), style: TextStyle(fontSize: 14, color: F.ac2)),
              children: [
                for (var i = 0; i < r.plan.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text(tr('Stufe ${i + 1}', 'Step ${i + 1}'), style: const TextStyle(color: F.mu))),
                      Text('${fz(r.plan[i])} $_unit'),
                      SizedBox(
                          width: 80,
                          child: Text(i < r.plan.length - 1 ? tr('${r.days[i]} Tage', '${r.days[i]} days') : tr('Ziel', 'Goal'),
                              textAlign: TextAlign.right, style: const TextStyle(color: F.mu))),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      ]));
    }
    return w;
  }

  List<Widget> _importSeite() {
    final w = <Widget>[
      _ueberschrift(tr('Plan übernehmen', 'Apply plan'), icon: Icons.upload_file_outlined),
      _absatz(tr('Datei wählen (PDF, DOCX, TXT, CSV) – ich lese die Schritte aus. Danach kannst du alles anpassen.', 'Choose a file (PDF, DOCX, TXT, CSV) – I read the steps from it. Afterwards you can adjust everything.')),
      const SizedBox(height: 12),
      knopf(_liest ? tr('Lese Datei …', 'Reading file …') : tr('Datei auswählen', 'Choose file'), _liest ? null : _dateiWaehlen,
          icon: Icons.description_outlined, key: const Key('dateiWaehlen')),
      Feldname(tr('Oder Text einfügen / abtippen (eine Stufe pro Zeile)', 'Or paste / type text (one step per line)')),
      TextField(
        key: const Key('importText'),
        controller: _text,
        minLines: 4,
        maxLines: 10,
        decoration: feldStil(hinweis: tr('Woche 1–2: 10 mg\nWoche 3–4: 9 mg\nab 15.12.: 8 mg', 'Week 1–2: 10 mg\nWeek 3–4: 9 mg\nfrom 15/12: 8 mg')),
      ),
      const SizedBox(height: 10),
      knopf(tr('Text auslesen', 'Read text'), _auslesen, key: const Key('textAuslesen')),
      if (_meldung != null)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text(_meldung!, style: const TextStyle(color: F.ok))),
      Sub(
          tr('Erkannt werden z. B. „Woche 1–2: 10 mg“, „Tag 1–14: 7,5 mg“, „10 mg für 14 Tage“, „ab 01.12.: 8 mg“, '
          'Tabellenzeilen und „morgens 5 mg, abends 2,5 mg“. Scans und Fotos gehen nicht.', 'Examples it recognises: “Week 1–2: 10 mg”, “Day 1–14: 7.5 mg”, “10 mg for 14 days”, “from 01/12: 8 mg”, table rows and “morning 5 mg, evening 2.5 mg”. Scans and photos do not work.'),
          oben: 10),
    ];
    if (_zeilen.isNotEmpty) {
      w.add(const SizedBox(height: 16));
      final k = <Widget>[
        KartenTitel(tr('Schritte', 'Steps'), hilfe: 'plan'),
        Feldname(tr('Medikament', 'Medication'), oben: 0),
        TextField(key: const Key('importMed'), controller: _med, decoration: feldStil()),
        const SizedBox(height: 10),
        Row(children: [
          SizedBox(width: 28),
          Expanded(child: Text(tr('Tagesdosis', 'Daily dose'), style: TextStyle(color: F.mu, fontSize: 12))),
          SizedBox(width: 8),
          Expanded(child: Text(tr('Tage', 'Days'), style: TextStyle(color: F.mu, fontSize: 12))),
          SizedBox(width: 48),
        ]),
      ];
      for (var i = 0; i < _zeilen.length; i++) {
        final z = _zeilen[i];
        final d = zahl(z.dosis.text), vor = i > 0 ? zahl(_zeilen[i - 1].dosis.text) : null;
        k.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(color: F.mu))),
            Expanded(
              child: TextField(
                key: Key('zDosis$i'),
                controller: z.dosis,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: feldStil(),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: Key('zTage$i'),
                controller: z.tage,
                keyboardType: TextInputType.number,
                decoration: feldStil().copyWith(
                  enabledBorder: z.geschaetzt
                      ? OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: F.warn))
                      : null,
                ),
                onChanged: (_) => setState(() => z.geschaetzt = false),
              ),
            ),
            IconButton(
              tooltip: tr('Schritt löschen', 'Delete step'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() {
                _zeilen.removeAt(i).dispose();
                if (_start >= _zeilen.length) _start = math.max(0, _zeilen.length - 1);
              }),
            ),
          ]),
        ));
        if (d != null && vor != null && d > vor) {
          k.add(Padding(
              padding: EdgeInsets.only(left: 30, top: 2),
              child: Text(tr('↑ Dosis steigt', '↑ Dose increases'), style: TextStyle(color: F.warn, fontSize: 12))));
        }
      }
      k.add(const SizedBox(height: 10));
      k.add(knopf(tr('+ Schritt hinzufügen', '+ Add step'), () {
        final l = _zeilen.isEmpty ? null : _zeilen.last;
        setState(() => _zeilen.add(_ZeileFelder(EditRow(
            l == null ? null : math.max(0, zahl(l.dosis.text) ?? 0).toDouble(),
            l == null ? 14 : (ganzZahl(l.tage.text) ?? 14)))));
      }));
      final ok = [
        for (final z in _zeilen)
          if (zahl(z.dosis.text) != null && (ganzZahl(z.tage.text) ?? 0) > 0) z
      ];
      if (ok.isNotEmpty) {
        final tot = ok.fold<int>(0, (a, z) => a + ganzZahl(z.tage.text)!);
        k.add(Sub(
            tr('${ok.length} Stufen · ${fz(zahl(ok.first.dosis.text)!)} → ${fz(zahl(ok.last.dosis.text)!)} $_unit · '
            '$tot Tage (≈ ${(tot / 7).round()} Wochen)', '${ok.length} steps · ${fz(zahl(ok.first.dosis.text)!)} → ${fz(zahl(ok.last.dosis.text)!)} $_unit · $tot days (≈ ${(tot / 7).round()} weeks)'),
            oben: 10));
      }
      k.add(Feldname(tr('Ich bin gerade bei', 'I am currently at')));
      k.add(DropdownButtonFormField<int>(
        key: ValueKey('start-${_zeilen.length}'),
        initialValue: _start.clamp(0, _zeilen.length - 1),
        isExpanded: true,
        decoration: feldStil(),
        items: [
          for (var i = 0; i < _zeilen.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(tr('Stufe ${i + 1}'
                  '${zahl(_zeilen[i].dosis.text) != null ? ' · ${fz(zahl(_zeilen[i].dosis.text)!)} $_unit' : ''}', 'Step ${i + 1}${zahl(_zeilen[i].dosis.text) != null ? " · ${fz(zahl(_zeilen[i].dosis.text)!)} $_unit" : ""}')),
            ),
        ],
        onChanged: (v) => setState(() => _start = v ?? 0),
      ));
      k.add(Sub(tr('Die Tage pro Stufe zählen ab Beginn der Stufe.', 'The days per step count from the start of the step.'), oben: 10));
      w.add(Karte(children: k));
      w.addAll(_startFeld());
    }
    return w;
  }

  /// Startdatum: vorausgewählt heute, Kalender nur heute oder später. Nur beim ersten eigenen Plan.
  List<Widget> _startFeld() {
    if (_gibtPlan) return const [];
    final heute = ta.today;
    return [
      Feldname(tr('Startdatum', 'Start date')),
      InkWell(
        key: const Key('planStart'),
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          DateTime tagDatum(String k) => DateTime.parse('${k}T12:00:00');
          final h = tagDatum(heute);
          final w = await showDatePicker(
            context: context,
            initialDate: tagDatum(_beginnTag),
            firstDate: h,
            lastDate: h.add(const Duration(days: 365)),
          );
          if (w != null) {
            final k = ymd(w);
            setState(() => _beginn = k.compareTo(heute) > 0 ? k : null);
          }
        },
        child: InputDecorator(
          decoration: feldStil(),
          child: Row(children: [
            const Icon(Icons.event_outlined, size: 20, color: F.ac2),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  _beginnTag == heute ? tr('Heute (${datum(heute)})', 'Today (${datum(heute)})') : datum(_beginnTag),
                  key: const Key('planStartText')),
            ),
          ]),
        ),
      ),
      Sub(tr('Schon mitten im Abdosieren? Fang einfach mit deiner aktuellen Dosis an.',
          'Already in the middle of tapering? Just start with your current dose.'), oben: 6),
    ];
  }

  List<Widget> _arztSeite() => [
        _ueberschrift(tr('Bitte sprich deinen Plan mit deinem Arzt ab.', 'Please discuss your plan with your doctor.'), icon: Icons.medical_services_outlined),
        _absatz(tr('Die App hilft dir, bei deinem Plan zu bleiben und zu sehen, was du schon geschafft hast. '
            'Wie schnell du reduzierst, entscheidet sie nicht.', 'The app helps you stick to your plan and see what you have already achieved. It does not decide how fast you reduce.')),
        _absatz(tr('Wichtig: Nach längerer Einnahme kann abruptes Weglassen Krampfanfälle oder Verwirrtheit auslösen. '
            'Bei Krampfanfall, Halluzinationen oder starker Verwirrung: Notruf 112.', 'Important: After long-term use, stopping abruptly can cause seizures or confusion. In case of a seizure, hallucinations or severe confusion: call emergency services (112 in Europe, or your local emergency number).')),
      ];

  List<Widget> _losSeite() {
    final w = <Widget>[];
    final v = widget.vorgemerkt;
    if (v != null) {
      w.add(_ueberschrift(tr('Vorgemerkte Änderung', 'Scheduled change'), icon: Icons.hourglass_empty));
      w.add(_absatz(tr('Vorgemerkte Änderung – bitte prüfen und übernehmen.', 'Scheduled change – please review and apply.')));
      w.add(Sub(
          planSumme(ta, [for (final r in v.rows) r.dose ?? 0], [for (final r in v.rows) r.days ?? 0],
              v.start.clamp(0, v.rows.length - 1)),
          oben: 6));
    } else {
      w.add(_ueberschrift(tr('Wichtig: Dein Plan passt sich an', 'Important: Your plan adapts'), icon: Icons.autorenew));
      w.add(_absatz(tr('Du musst nicht alles perfekt planen.', 'You do not have to plan everything perfectly.')));
      w.add(_absatz(tr('Merkst du, dass du noch nicht weiter runter kannst, drück auf „Dosis halten“. Dann wartet der '
          'Plan auf dich und verschiebt sich um die gehaltenen Tage.', 'If you notice you cannot go down further yet, tap “Hold dose”. The plan then waits for you and shifts by the days held.')));
      w.add(_absatz(tr('Sobald du weitermachst, läuft er automatisch weiter.', 'As soon as you carry on, it continues automatically.')));
      w.add(_absatz(tr('Was die Zeichen und Knöpfe bedeuten, erklären die ?-Symbole und die Anleitung.', 'What the symbols and buttons mean is explained by the ? icons and the guide.')));
    }
    if (_gibtPlan) {
      w.add(Sub(tr('Kalender und Notizen bleiben erhalten.', 'Calendar and notes are kept.'), oben: 16));
    }
    if (_gibtPlan) {
      w.add(Feldname(tr('Zum Speichern bitte eintippen: Ich bin mir sicher', 'To save, please type: I am sure')));
      w.add(TextField(
        key: const Key('planSicher'),
        controller: _conf,
        autocorrect: false,
        enableSuggestions: false,
        decoration: feldStil(hinweis: tr('Ich bin mir sicher', 'I am sure')),
      ));
    }
    if (_warumFragen && v == null) {
      w.add(const SizedBox(height: 14));
      w.add(Karte(rand: F.ac, children: [
        IconText(Icons.hourglass_empty, tr('48 Stunden Bedenkzeit', '48-hour reflection period'), fett: true),
        Sub(
            tr('Diese Änderung erhöht die Dosis oder macht den Plan langsamer. Sie wird erst nach 48 Stunden wirksam, '
            'bis dahin gilt der bisherige Plan. „Dosis halten“ geht jederzeit sofort.', 'This change increases the dose or makes the plan slower. It only takes effect after 48 hours; until then the current plan applies. “Hold dose” works immediately at any time.'),
            oben: 4),
        Feldname(tr('Warum?', 'Why?')),
        TextField(key: const Key('planWarum'), controller: _warum, minLines: 2, maxLines: 4, decoration: feldStil()),
      ]));
    }
    return w;
  }
}
