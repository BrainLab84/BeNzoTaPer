// Tablettenvorrat: eintragen, Nachkauf, Reichweite.
// Steht unten im Reiter Heute; oben dort zusätzlich eine Warnung, wenn er für 14 Tage oder weniger reicht.
import 'i18n/txt.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';

class VorratKarte extends StatefulWidget {
  const VorratKarte({super.key, required this.app, this.gross = false});
  final AppState app;

  /// Auffälliger (Reiter Heute): größere Reichweite, farbiger Rand.
  final bool gross;
  @override
  State<VorratKarte> createState() => _VorratKarteState();
}

/// Eine Zeile „Anzahl Tbl à Stärke mg“.
class _Zeile {
  _Zeile({String staerke = ''}) : staerke = TextEditingController(text: staerke);
  final anzahl = TextEditingController();
  final TextEditingController staerke;
  bool fehler = false;
  void dispose() {
    anzahl.dispose();
    staerke.dispose();
  }
}

/// einfach Anzahl und Stärke eintragen; die App rechnet sofort aus, wie viel mg
/// das sind und wie lange es beim aktuellen Plan reicht (mit Stufenwechseln und Halten). Keine doppelte
/// Eingabe der Stärke mehr. Rechnung im Kern (`Taper.reichweite`).
class _VorratKarteState extends State<VorratKarte> {
  bool _offen = false;
  final _zeilen = <_Zeile>[];
  final _loesung = TextEditingController();
  double _teilbar = 1;

  AppState get app => widget.app;
  Taper get ta => app.taper;

  @override
  void initState() {
    super.initState();
    _ausGespeichert();
  }

  void _ausGespeichert() {
    for (final z in _zeilen) {
      z.dispose();
    }
    _zeilen.clear();
    final t = ta.s?.tabs;
    for (final x in t?.str ?? const <double>[]) {
      _zeilen.add(_Zeile(staerke: fz(x)));
    }
    if (_zeilen.isEmpty) _zeilen.add(_Zeile());
    _loesung.text = (t?.liq != null) ? fz(t!.liq!) : '';
    final sp = t?.split ?? 1;
    _teilbar = const [1.0, 0.5, 0.25].contains(sp) ? sp : 1;
  }

  @override
  void dispose() {
    for (final z in _zeilen) {
      z.dispose();
    }
    _loesung.dispose();
    super.dispose();
  }

  /// Summe der eingetragenen Zeilen in mg (null = nichts Gültiges eingetragen).
  double? _summe() {
    var sum = 0.0;
    var etwas = false;
    for (final z in _zeilen) {
      final n = zahl(z.anzahl.text), st = zahl(z.staerke.text);
      if (n != null && n > 0 && st != null && st > 0) {
        sum += n * st;
        etwas = true;
      }
    }
    return etwas ? round3(sum) : null;
  }

  String _reicht(double anzahl) {
    if (anzahl < 1) return tr('reicht nicht mehr für heute', 'not enough for today');
    if (!anzahl.isFinite) return tr('reicht bis zum Ende des Plans', 'lasts until the end of the plan');
    final d = anzahl.toInt();
    return tr('reicht ca. ${tage(d)} (bis ${datum(addD(ta.today, d - 1))})', 'lasts approx. ${tage(d)} (until ${datum(addD(ta.today, d - 1))})');
  }

  void _speichern({required bool dazu}) {
    // Zeile mit Anzahl, aber ohne Stärke → rot.
    var ok = true;
    for (final z in _zeilen) {
      final n = zahl(z.anzahl.text), st = zahl(z.staerke.text);
      z.fehler = (z.anzahl.text.trim().isNotEmpty && !(n != null && n > 0)) ||
          (z.anzahl.text.trim().isNotEmpty && !(st != null && st > 0));
      if (z.fehler) ok = false;
    }
    if (!ok) {
      setState(() {});
      return;
    }
    final staerken = <double>[];
    for (final z in _zeilen) {
      final st = zahl(z.staerke.text);
      if (st != null && st > 0 && !staerken.contains(st)) staerken.add(st);
    }
    final l = zahl(_loesung.text);
    ta.saveTabs(staerken, _teilbar, (l != null && l > 0) ? l : null);
    final sum = _summe();
    if (sum != null) ta.setStock(sum, 1, add: dazu);
    setState(() {
      _offen = false;
      _ausGespeichert();
    });
    app.aenderung();
    if (sum != null) app.vorratGespeichert();
  }

  @override
  Widget build(BuildContext context) {
    final s = ta.st;
    final si = ta.stockInfo();
    final t = s.tabs;
    final kinder = <Widget>[KartenTitel(tr('Tablettenvorrat', 'Tablet supply'), icon: Icons.medication_outlined)];
    if (si != null) {
      final warn = si.days <= 14;
      final String zeile;
      if (si.days < 1) {
        zeile = tr('Reicht nicht mehr für heute', 'Not enough for today');
      } else if (si.days.isFinite) {
        final d = si.days.toInt();
        zeile = tr('Reicht noch ca. ${tage(d)} (bis ${datum(addD(ta.today, d - 1))})', 'Lasts approx. ${tage(d)} more (until ${datum(addD(ta.today, d - 1))})');
      } else {
        zeile = tr('Reicht bis zum Ende des Plans', 'Lasts until the end of the plan');
      }
      kinder.add(Text(zeile,
          key: const Key('vorratZeile'),
          style: TextStyle(fontSize: widget.gross ? 23 : 19, fontWeight: FontWeight.w700, color: warn ? F.warn : F.ok)));
      final rest = math.max(0.0, si.rem);
      final hatT = t != null && t.str.isNotEmpty;
      kinder.add(Sub(
          tr('Rest: ${fz(rest)} ${s.unit}${hatT ? ' (≈ ${fz(jsRound(rest / t.str[0] * 4) / 4)} Tbl à ${fz(t.str[0])})' : ''}', 'Remaining: ${fz(rest)} ${s.unit}${hatT ? " (≈ ${fz(jsRound(rest / t.str[0] * 4) / 4)} tabs of ${fz(t.str[0])})" : ""}'),
          oben: 2));
      if (si.geschaetzt > 0) {
        kinder.add(Sub(
            tr('Darin ${si.geschaetzt == 1 ? '1 Tag' : '${si.geschaetzt} Tage'} ohne Eintrag, mit der geplanten Dosis gerechnet. '
                'Nachtragen macht es genauer.',
                'Includes ${si.geschaetzt == 1 ? '1 day' : '${si.geschaetzt} days'} without an entry, counted with the planned dose. '
                    'Filling them in makes it more accurate.'),
            key: const Key('vorratGeschaetzt'),
            oben: 2));
      }
      kinder.add(Sub(tr('Keine exakte Angabe garantiert – zu viele Variablen, aber ziemlich genau.', 'No exact figure guaranteed – too many variables, but fairly accurate.'),
          key: Key('vorratHinweis'), oben: 2));
      if (warn) {
        kinder.add(Sub(
            tr('Ärzte können ohne Vorwarnung zumachen. Kümmere dich rechtzeitig um Nachschub und halte einen Puffer.', 'Doctors’ practices can close without warning. Arrange your resupply in good time and keep a buffer.'),
            oben: 6));
      }
    } else {
      kinder.add(Text(tr('Trag zuerst ein, was du gerade da hast. Das ist das Wichtigste: Ärzte machen manchmal '
          'ohne Vorwarnung dicht. Mit einem Puffer hast du Zeit, Alternativen zu finden.', 'First enter what you have on hand. That is the most important part: doctors sometimes close without warning. With a buffer you have time to find alternatives.')));
    }
    final offen = si == null || _offen;
    kinder.add(const SizedBox(height: 10));
    kinder.add(InkWell(
      onTap: () => setState(() => _offen = !offen),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Text((si != null ? tr('Vorrat ändern', 'Edit supply') : tr('Vorrat eintragen', 'Enter supply')).toUpperCase(),
                style: const TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w600, color: F.mu)),
          ),
          Icon(offen ? Icons.expand_less : Icons.expand_more, color: F.mu),
        ]),
      ),
    ));
    if (offen) {
      kinder.add(Feldname(tr('Was hast du gerade da?', 'What do you have on hand?'), oben: 8));
      for (var i = 0; i < _zeilen.length; i++) {
        final z = _zeilen[i];
        kinder.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                key: Key('anzahl$i'),
                controller: z.anzahl,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: feldStil(hinweis: tr('Anzahl', 'Count'), fehler: z.fehler),
              ),
            ),
            Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(tr('Tbl à', 'tabs of'))),
            Expanded(
              child: TextField(
                key: Key('staerke$i'),
                controller: z.staerke,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: feldStil(hinweis: s.unit, fehler: z.fehler),
              ),
            ),
            Padding(padding: const EdgeInsets.only(left: 8), child: Text(s.unit)),
            if (_zeilen.length > 1)
              IconButton(
                tooltip: tr('Zeile entfernen', 'Remove row'),
                icon: const Icon(Icons.close, size: 18, color: F.mu),
                onPressed: () => setState(() => _zeilen.removeAt(i).dispose()),
              ),
          ]),
        ));
      }
      kinder.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('staerkePlus'),
          onPressed: () => setState(() => _zeilen.add(_Zeile())),
          icon: const Icon(Icons.add, size: 18),
          label: Text(tr('weitere Tablettenstärke', 'another tablet strength')),
        ),
      ));
      // Sofort ausrechnen: wie viel mg, wie lange beim aktuellen Plan.
      final sum = _summe();
      if (sum != null) {
        final vorschau = <Widget>[
          Text(tr('= ${fz(sum)} ${s.unit} · beim aktuellen Plan ${_reicht(ta.reichweite(sum))}', '= ${fz(sum)} ${s.unit} · at the current plan ${_reicht(ta.reichweite(sum))}'),
              key: const Key('vorratVorschau'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ];
        if (si != null) {
          vorschau.add(Sub(tr('Als Nachkauf dazu: ${_reicht(ta.reichweite(math.max(0.0, si.rem) + sum))}', 'With the refill: ${_reicht(ta.reichweite(math.max(0.0, si.rem) + sum))}'), oben: 2));
        }
        kinder.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: vorschau),
        ));
      }
      final teilbar = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Feldname(tr('Teilbar', 'Divisible')),
        DropdownButtonFormField<double>(
          key: const Key('teilbar'),
          initialValue: _teilbar,
          isExpanded: true,
          decoration: feldStil(),
          items: [
            DropdownMenuItem(value: 1, child: Text(tr('nur ganz', 'whole only'))),
            DropdownMenuItem(value: 0.5, child: Text(tr('halbierbar', 'halvable'))),
            DropdownMenuItem(value: 0.25, child: Text(tr('viertelbar', 'quarterable'))),
          ],
          onChanged: (v) => setState(() => _teilbar = v ?? 1),
        ),
      ]);
      final loesung = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Feldname(tr('Lösung (mg/ml, optional)', 'Solution (mg/ml, optional)')),
        TextField(
          key: const Key('loesung'),
          controller: _loesung,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: feldStil(),
        ),
      ]);
      kinder.add(LayoutBuilder(
        builder: (context, c) => genugPlatz(context, c, 290)
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: teilbar),
                const SizedBox(width: 10),
                Expanded(child: loesung),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [teilbar, loesung]),
      ));
      kinder.add(const SizedBox(height: 12));
      final speichern = hauptKnopf(
          si == null ? tr('Vorrat speichern', 'Save supply') : tr('Als Vorrat speichern (gezählt)', 'Save as supply (counted)'), () => _speichern(dazu: false),
          key: const Key('vorratSpeichern'), blatt: si == null);
      if (si == null) {
        kinder.add(speichern);
      } else {
        final nachkauf = knopf(tr('+ Nachkauf dazu', '+ Add refill'), () => _speichern(dazu: true), key: const Key('nachkauf'));
        kinder.add(LayoutBuilder(
          builder: (context, c) => genugPlatz(context, c, 300)
              ? IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: speichern),
                    const SizedBox(width: 8),
                    Expanded(child: nachkauf),
                  ]),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  speichern,
                  const SizedBox(height: 8),
                  nachkauf,
                ]),
        ));
      }
      kinder.add(Sub(
          tr('Zähl einfach, was gerade da ist. Ab dann rechnet die App jede Einnahme automatisch ab – auch Nachträge.', 'Just count what is on hand. From then on the app deducts every intake automatically – also entries added later.'),
          oben: 6));
    }
    return Karte(
        key: const Key('vorratKarte'),
        rand: widget.gross ? (si != null && si.days <= 14 ? F.warn : F.acRand) : null,
        children: kinder);
  }
}

/// Kurze Warnung auf Heute: nur wenn der Vorrat für 14 Tage oder weniger reicht.
/// Texte wie in der Vorrat-Karte. Antippen scrollt zur Vorrat-Karte.
class VorratWarnung extends StatelessWidget {
  const VorratWarnung({super.key, required this.si, required this.unit, required this.heute, this.oeffnen});
  final StockInfo si;
  final String unit;
  final String heute;
  final VoidCallback? oeffnen;
  @override
  Widget build(BuildContext context) {
    final String zeile;
    if (si.days < 1) {
      zeile = tr('Reicht nicht mehr für heute', 'Not enough for today');
    } else {
      final d = si.days.toInt();
      zeile = tr('Reicht noch ca. ${tage(d)} (bis ${datum(addD(heute, d - 1))})', 'Lasts approx. ${tage(d)} more (until ${datum(addD(heute, d - 1))})');
    }
    // Material + InkWell statt InkWell um eine Karte: so ist beim Antippen die Welle sichtbar
    // und nur die Karte selbst (ohne Abstand darunter) tippbar.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        key: const Key('vorratWarnung'),
        color: F.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: F.warn)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: oeffnen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              const Icon(Icons.medication_outlined, color: F.warn),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(zeile, style: const TextStyle(fontWeight: FontWeight.w700, color: F.warn)),
                  Sub(
                      tr('Ärzte können ohne Vorwarnung zumachen. Kümmere dich rechtzeitig um Nachschub und halte '
                      'einen Puffer.', 'Doctors’ practices can close without warning. Arrange your resupply in good time and keep a buffer.'),
                      oben: 2),
                ]),
              ),
              if (oeffnen != null) const Icon(Icons.chevron_right, color: F.mu),
            ]),
          ),
        ),
      ),
    );
  }
}
