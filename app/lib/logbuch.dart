// Verlaufsbericht für den Arzt: kleines Logbuch, getrennt vom Diagramm. Plan, tatsächliche Einnahmen mit
// Uhrzeit, Tage mit mehr bzw. weniger als geplant, Haltetage, Planänderungen, Wochen-Ø. Tage ohne Eintrag
// bleiben „?“. Keine Tagesnotizen, keine Begründungen: Ereignisse werden hier neu formuliert, Freitext aus
// der Historie wird nie übernommen. Zahlen nur aus dem Kern.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'i18n/txt.dart';

enum TagArt { imPlan, mehr, weniger, laufend, offen }

class LogbuchTag {
  LogbuchTag(this.tag, this.plan, this.dose, this.its, this.art, this.gehalten);
  final String tag;
  final double? plan;
  final double? dose;
  final List<Intake> its;
  final TagArt art;
  final bool gehalten;
}

class LogbuchWoche {
  LogbuchWoche(this.von, this.bis, this.avg, this.n);
  final String von, bis;
  final double? avg;
  final int n;
}

class Logbuch {
  Logbuch(this.ta, this.tage, this.wochen, this.ereignisse);
  final Taper ta;
  final List<LogbuchTag> tage;
  final List<LogbuchWoche> wochen;
  final List<(String, String)> ereignisse;

  int zahl(TagArt a) => tage.where((t) => t.art == a).length;
  int get gehalten => tage.where((t) => t.gehalten).length;
}

/// Ereignis aus der Historie in eigenen Worten (DE/EN); `null` = gehört nicht in den Bericht.
String? _ereignis(String t) {
  if (t.startsWith('Plan geändert') || t.startsWith('Vorgemerkte Änderung übernommen') || t.startsWith('Übernommen:')) {
    return tr('Plan geändert', 'Plan changed');
  }
  final h = RegExp(r'^Stufe (\d+) gehalten(?: für (\d+) Tage?)?').firstMatch(t);
  if (h != null) {
    final n = h.group(2);
    return n == null
        ? tr('Dosis gehalten (Stufe ${h.group(1)}), ohne Enddatum', 'Dose held (step ${h.group(1)}), no end date')
        : tr('Dosis gehalten (Stufe ${h.group(1)}), $n ${n == '1' ? 'Tag' : 'Tage'}', 'Dose held (step ${h.group(1)}), $n ${n == '1' ? 'day' : 'days'}');
  }
  if (t.startsWith('Halten nach Plan beendet') || t.startsWith('Halten beendet')) {
    return tr('Halten beendet', 'Hold ended');
  }
  if (t.startsWith('Nächste Stufe vorgezogen')) return tr('Nächste Stufe vorgezogen', 'Next step brought forward');
  return null;
}

Logbuch logbuchErstellen(Taper ta) {
  final s = ta.st;
  final heute = ta.today;
  final t0 = ta.t0Of();
  // Halte-Zeiträume aus der Historie, dazu das laufende Halten.
  final halten = <(String, String?)>[];
  String? beginn;
  for (final c in s.chg) {
    if (RegExp(r'^Stufe \d+ gehalten').hasMatch(c.t)) {
      beginn = c.d;
    } else if (beginn != null && (c.t.startsWith('Halten nach Plan beendet') || c.t.startsWith('Halten beendet'))) {
      final m = RegExp(r'\((\d\d)\.(\d\d)\.(\d{4})\)').firstMatch(c.t);
      final ende = m != null ? '${m.group(3)}-${m.group(2)}-${m.group(1)}' : c.d;
      halten.add((beginn, ende));
      beginn = null;
    }
  }
  if (s.hold && s.holdSince != null) halten.add((s.holdSince!, s.holdUntil));
  bool gehalten(String k) => halten.any((h) => k.compareTo(h.$1) >= 0 && (h.$2 == null || k.compareTo(h.$2!) < 0));

  final tage = <LogbuchTag>[];
  if (t0 != null && t0.compareTo(heute) <= 0) {
    for (var k = t0; k.compareTo(heute) <= 0; k = addD(k, 1)) {
      final e = s.log[k];
      if (e == null) {
        if (k == heute) continue; // heute noch nichts: kein „?“
        tage.add(LogbuchTag(k, ta.planFor(k).plan, null, const [], TagArt.offen, gehalten(k)));
        continue;
      }
      final plan = e.plan ?? ta.planFor(k).plan;
      final TagArt art;
      if (ta.partToday(k, e)) {
        art = TagArt.laufend;
      } else if (e.dose > plan + 1e-9) {
        art = TagArt.mehr;
      } else if (e.dose < plan - 1e-9) {
        art = TagArt.weniger;
      } else {
        art = TagArt.imPlan;
      }
      tage.add(LogbuchTag(k, plan, e.dose, ta.dayIt(e), art, gehalten(k)));
    }
  }
  // Wochen-Ø in 7-Tage-Blöcken ab Start; nur eingetragene, abgeschlossene Tage.
  final wochen = <LogbuchWoche>[];
  if (tage.isNotEmpty) {
    for (var von = tage.first.tag; von.compareTo(heute) <= 0; von = addD(von, 7)) {
      final bis = addD(von, 6);
      var sum = 0.0;
      var n = 0;
      for (final t in tage) {
        if (t.tag.compareTo(von) >= 0 && t.tag.compareTo(bis) <= 0 && t.dose != null && t.art != TagArt.laufend) {
          sum += t.dose!;
          n++;
        }
      }
      wochen.add(LogbuchWoche(von, bis.compareTo(heute) > 0 ? heute : bis, n > 0 ? sum / n : null, n));
    }
  }
  final ereignisse = <(String, String)>[
    for (final c in s.chg)
      if (_ereignis(c.t) case final x?) (c.d, x),
  ];
  return Logbuch(ta, tage, wochen, ereignisse);
}

String _wt(String k) => wochentageKurzSo()[weekday0(k)];

String _artText(LogbuchTag t, String unit) => switch (t.art) {
      TagArt.imPlan => tr('im Plan', 'on plan'),
      TagArt.mehr => tr('mehr als geplant (+${fz(round3(t.dose! - t.plan!))} $unit)', 'more than planned (+${fz(round3(t.dose! - t.plan!))} $unit)'),
      TagArt.weniger => tr('weniger als geplant (−${fz(round3(t.plan! - t.dose!))} $unit)', 'less than planned (−${fz(round3(t.plan! - t.dose!))} $unit)'),
      TagArt.laufend => tr('heute, noch offen', 'today, still open'),
      TagArt.offen => tr('? kein Eintrag', '? no entry'),
    };

String _einnahmen(LogbuchTag t, String unit) =>
    [for (final i in t.its) '${i.t.isEmpty ? '' : '${i.t} '}${fz(i.v)}'].join(', ');

/// Kopf- und Übersichtszeilen (für Lesen und PDF gleich).
List<String> _kopf(Logbuch b) {
  final ta = b.ta;
  final s = ta.st;
  final ende = ta.voraussichtlichesEnde();
  final t0 = ta.t0Of();
  return [
    if (t0 != null) tr('Start: ${datum(t0)} · Stand: ${datum(ta.today)}', 'Start: ${datum(t0)} · As of: ${datum(ta.today)}'),
    tr('Aktuell: Stufe ${s.stage + 1} von ${s.plan.length}, ${fz(s.plan[s.stage])} ${s.unit} pro Tag${s.hold ? ' (gehalten)' : ''}',
        'Current: step ${s.stage + 1} of ${s.plan.length}, ${fz(s.plan[s.stage])} ${s.unit} per day${s.hold ? ' (held)' : ''}'),
    if (ende != null && ende.compareTo(ta.today) > 0)
      tr('Voraussichtlich bei ${fz(s.plan.last)} ${s.unit}: ${datum(ende)}', 'Expected at ${fz(s.plan.last)} ${s.unit}: ${datum(ende)}'),
  ];
}

List<String> _uebersicht(Logbuch b) => [
      tr('Tage seit Start: ${b.tage.length}', 'Days since start: ${b.tage.length}'),
      tr('Im Plan: ${b.zahl(TagArt.imPlan)}', 'On plan: ${b.zahl(TagArt.imPlan)}'),
      tr('Mehr als geplant: ${b.zahl(TagArt.mehr)}', 'More than planned: ${b.zahl(TagArt.mehr)}'),
      tr('Weniger als geplant: ${b.zahl(TagArt.weniger)}', 'Less than planned: ${b.zahl(TagArt.weniger)}'),
      tr('Ohne Eintrag (?): ${b.zahl(TagArt.offen)}', 'No entry (?): ${b.zahl(TagArt.offen)}'),
      tr('Gehaltene Tage: ${b.gehalten}', 'Days held: ${b.gehalten}'),
    ];

List<String> _stufen(Logbuch b) {
  final ta = b.ta;
  final s = ta.st;
  return [
    for (var i = 0; i < s.plan.length; i++)
      '${i == s.stage ? '> ' : ''}${tr('Stufe ${i + 1}', 'Step ${i + 1}')}: ${fz(s.plan[i])} ${s.unit}'
          '${i < s.plan.length - 1 ? tr(', ${ta.need(i)} Tage', ', ${ta.need(i)} days') : tr(' (Ziel)', ' (goal)')}',
  ];
}

String logbuchDateiname(DateTime jetzt) => tr('Verlaufsbericht_${ymd(jetzt)}.pdf', 'Report_${ymd(jetzt)}.pdf');

/// Standardschrift im PDF kennt nur Latin-1: wenige Zeichen ersetzen.
String _pdf(String t) => t
    .replaceAll('–', '-')
    .replaceAll('−', '-')
    .replaceAll('→', '->')
    .replaceAll('…', '...')
    .replaceAll('≈', 'ca.')
    .replaceAll('„', '"')
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .replaceAll('’', "'")
    .replaceAllMapped(RegExp(r'[^\u0000-\u00FF]'), (_) => '?');

Future<Uint8List> logbuchPdf(AppState app) async {
  final b = logbuchErstellen(app.taper);
  final s = app.taper.st;
  final doc = pw.Document(title: tr('Verlaufsbericht', 'Report'));
  pw.Widget h(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
      child: pw.Text(_pdf(t), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)));
  pw.Widget z(String t) => pw.Text(_pdf(t), style: const pw.TextStyle(fontSize: 10));
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => [
      pw.Text(_pdf(tr('Verlaufsbericht · ${s.name}', 'Report · ${s.name}')),
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      for (final k in _kopf(b)) z(k),
      z(tr('Selbst eingetragen. Tage ohne Eintrag stehen als ?, sie werden nicht geschätzt.',
          'Self-reported. Days without an entry are shown as ?, they are not estimated.')),
      h(tr('Übersicht', 'Overview')),
      for (final k in _uebersicht(b)) z(k),
      h(tr('Plan', 'Plan')),
      for (final k in _stufen(b)) z(k),
      if (b.ereignisse.isNotEmpty) ...[
        h(tr('Planänderungen und Halten', 'Plan changes and holds')),
        for (final e in b.ereignisse) z('${datum(e.$1)}  ${e.$2}'),
      ],
      if (b.wochen.isNotEmpty) ...[
        h(tr('Wochen-Durchschnitt', 'Weekly average')),
        for (final w in b.wochen)
          z('${datum(w.von)} - ${datum(w.bis)}:  '
              '${w.avg == null ? '-' : 'Ø ${fz(round1(w.avg!))} ${s.unit}'}  ${tr('(${w.n} Tage eingetragen)', '(${w.n} days logged)')}'),
      ],
      h(tr('Tagesprotokoll', 'Daily log')),
      if (b.tage.isEmpty) z(tr('Noch keine Tage.', 'No days yet.')),
      if (b.tage.isNotEmpty)
        pw.TableHelper.fromTextArray(
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          headers: [
            tr('Datum', 'Date'),
            '${tr('Plan', 'Plan')} (${s.unit})',
            '${tr('Genommen', 'Taken')} (${s.unit})',
            tr('Einnahmen (Uhrzeit Menge)', 'Intakes (time amount)'),
            tr('Hinweis', 'Note'),
          ].map(_pdf).toList(),
          data: [
            for (final t in b.tage)
              [
                '${_wt(t.tag)} ${datum(t.tag)}',
                t.plan == null ? '' : fz(t.plan!),
                t.dose == null ? '?' : fz(t.dose!),
                _einnahmen(t, s.unit),
                '${_artText(t, s.unit)}${t.gehalten ? tr(' · gehalten', ' · held') : ''}',
              ].map(_pdf).toList(),
          ],
        ),
    ],
  ));
  return doc.save();
}

Future<void> logbuchTeilen(BuildContext context, AppState app) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final pdf = await logbuchPdf(app);
    await app.dateien.teilenBytes(logbuchDateiname(app.taper.clock()), pdf, 'application/pdf');
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Der Bericht konnte nicht erstellt werden.', 'The report could not be created.'))));
  }
}

/// „Lesen“: das Logbuch in der App, unten Teilen.
class LogbuchSeite extends StatelessWidget {
  const LogbuchSeite({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final b = logbuchErstellen(app.taper);
    final s = app.taper.st;
    Widget h(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)));
    Widget z(String t) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(t));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Verlaufsbericht für den Arzt', 'Report for the doctor'))),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(key: const Key('logbuchListe'), padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
              Text(tr('Verlaufsbericht · ${s.name}', 'Report · ${s.name}'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final k in _kopf(b)) z(k),
              Sub(tr('Selbst eingetragen. Tage ohne Eintrag stehen als ?, sie werden nicht geschätzt.',
                  'Self-reported. Days without an entry are shown as ?, they are not estimated.'), oben: 4),
              h(tr('Übersicht', 'Overview')),
              for (final k in _uebersicht(b)) z(k),
              h(tr('Plan', 'Plan')),
              for (final k in _stufen(b)) z(k),
              if (b.ereignisse.isNotEmpty) ...[
                h(tr('Planänderungen und Halten', 'Plan changes and holds')),
                for (final e in b.ereignisse) z('${datum(e.$1)}  ${e.$2}'),
              ],
              if (b.wochen.isNotEmpty) ...[
                h(tr('Wochen-Durchschnitt', 'Weekly average')),
                for (final w in b.wochen)
                  z('${datum(w.von)} – ${datum(w.bis)}:  '
                      '${w.avg == null ? '–' : 'Ø ${fz(round1(w.avg!))} ${s.unit}'}  ${tr('(${w.n} Tage eingetragen)', '(${w.n} days logged)')}'),
              ],
              h(tr('Tagesprotokoll', 'Daily log')),
              if (b.tage.isEmpty) z(tr('Noch keine Tage.', 'No days yet.')),
              for (final t in b.tage.reversed)
                Container(
                  key: Key('logTag-${t.tag}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: F.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_wt(t.tag)} ${datum(t.tag)} · ${tr('Plan', 'Plan')} ${t.plan == null ? '–' : '${fz(t.plan!)} ${s.unit}'}'
                        ' · ${tr('genommen', 'taken')} ${t.dose == null ? '?' : '${fz(t.dose!)} ${s.unit}'}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (t.its.isNotEmpty) Text(_einnahmen(t, s.unit), style: const TextStyle(color: F.mu)),
                    Text('${_artText(t, s.unit)}${t.gehalten ? tr(' · gehalten', ' · held') : ''}',
                        style: TextStyle(
                            color: t.art == TagArt.mehr ? F.bad : (t.art == TagArt.offen ? F.warn : F.mu), fontSize: 13)),
                  ]),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: knopf(tr('Als PDF teilen', 'Share as PDF'), () => logbuchTeilen(context, app),
                icon: Icons.share_outlined, key: const Key('logbuchTeilenSeite')),
          ),
        ]),
      ),
    );
  }
}

/// Karte im Fortschritt: Verlaufsbericht teilen und lesen.
class LogbuchKarte extends StatelessWidget {
  const LogbuchKarte({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => Karte(key: const Key('logbuchKarte'), children: [
        KartenTitel(tr('Verlaufsbericht für den Arzt', 'Report for the doctor'), icon: Icons.description_outlined),
        Sub(tr('Logbuch: Plan, Einnahmen mit Uhrzeit, Tage mit mehr oder weniger als geplant, Halten, Wochen-Ø. '
            'Ohne Notizen.', 'Log: plan, intakes with time, days with more or less than planned, holds, weekly avg. No notes.')),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          final teilen = knopf(tr('Bericht als PDF teilen', 'Share report as PDF'), () => logbuchTeilen(context, app),
              icon: Icons.picture_as_pdf_outlined, key: const Key('logbuchTeilen'));
          final lesen = knopf(tr('Lesen', 'Read'), () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => LogbuchSeite(app: app)));
          }, icon: Icons.visibility_outlined, key: const Key('logbuchLesen'));
          if (c.maxWidth < MediaQuery.textScalerOf(context).scale(310)) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [teilen, const SizedBox(height: 8), lesen]);
          }
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: teilen),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: lesen),
            ]),
          );
        }),
      ]);
}
