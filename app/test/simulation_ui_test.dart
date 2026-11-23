// Simulation über die Oberfläche: Wochen werden per Tippen durchgespielt (wie geplant, Ausrutscher,
// vergessen + im Kalender nachtragen, Halten, neuer Plan). Nach jedem Tag müssen Plan-Reiter, Kalender,
// Heute und Fortschritt dasselbe zeigen wie der Kern – Stufe, Dosis, Planende, kommende Tage.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/bausteine.dart';
import 'package:tapering_buddy/erinnerung.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/pin.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_buddy/verlauf.dart';
import 'package:tapering_core/tapering_core.dart';

import 'hilfen.dart';

Finder _in(String key, Finder f) => find.descendant(of: find.byKey(Key(key)), matching: f);

List<String> _texte(Finder wo) => [
      for (final e in find.descendant(of: wo, matching: find.byType(Text)).evaluate())
        (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? ''
    ];

class _Erinnerer implements Erinnerer {
  List<DateTime> geplant = const [];
  @override
  Future<bool> erlaubnis() async => true;
  @override
  Future<void> planen(List<DateTime> zeiten, {List<VorratPush> vorrat = const []}) async => geplant = zeiten;
}

/// Erwartete Vorrat-Zeile, unabhängig aus Rest und Plan berechnet.
String _vorratZeile(double tageReichweite, String heute) {
  if (tageReichweite < 1) return 'Reicht nicht mehr für heute';
  if (!tageReichweite.isFinite) return 'Reicht bis zum Ende des Plans';
  final d = tageReichweite.toInt();
  return 'Reicht noch ca. ${tage(d)} (bis ${dmy(addD(heute, d - 1))})';
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  final alle = <String, int>{};
  for (final seed in [1, 2, 3]) {
    testWidgets('Oberfläche simuliert, Seed $seed: alle Reiter zeigen dasselbe', (t) async {
      final r = Random(seed);
      jetzt = DateTime.utc(2026, 3, 2, 9);
      t.view.physicalSize = const Size(1000, 7000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final erin = _Erinnerer();
      final app = AppState(MemStore()..disc = true, clock: () => jetzt, erinnerer: erin);
      await t.runAsync(app.laden);
      app.taper.setup(dose: 8, step: 1, minStep: 0.5, days: 5, goal: 0);
      // Erinnerung an, PIN gesetzt (beides soll die Abläufe nicht stören).
      await t.runAsync(() => app.erinnerungSetzen(app.erinnerung.mit(an: true)));
      expect(app.pinSetzen('2468', '2468'), isNull);
      await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      final ta = app.taper;
      final t0 = ta.today;
      String? geaendertAm;
      // Vorrat über die Oberfläche: 20 × 2 mg = 40 mg. Unabhängig mitgezählt in [vorratSoll].
      await reiter(t, 'Heute');
      await t.enterText(find.byKey(const Key('anzahl0')), '20');
      await t.enterText(find.byKey(const Key('staerke0')), '2');
      await _tap(t, find.byKey(const Key('vorratSpeichern')));
      expect(ta.st.stock!.mg, 40);
      var vorratSoll = 40.0;
      jetzt = jetzt.add(const Duration(minutes: 1));
      double eingenommen() => [for (final e in ta.st.log.values) ...e.it.map((i) => i.v)].fold(0.0, (a, b) => a + b);
      var vorherEingenommen = eingenommen();
      final log = <String>[];
      final ereignisse = <String, int>{};
      void merke(String w) {
        log.add('${ta.today}: $w');
        ereignisse[w] = (ereignisse[w] ?? 0) + 1;
      }

      String spur() => log.reversed.take(8).join('\n');

      for (var tag = 0; tag < 45; tag++) {
        final s = ta.st;
        await reiter(t, 'Heute');
        final x = r.nextDouble();
        // --- Aktionen über die Oberfläche ---
        if (s.frz != null) {
          // Nachtragen über Heute → Kalender (Tag-Fenster)
          if (find.byKey(const Key('nachtragenOffen')).evaluate().isNotEmpty && r.nextDouble() < .8) {
            await _tap(t, find.byKey(const Key('nachtragenOffen')));
            for (var i = 0; i < 8; i++) {
              final b = find.byWidgetPredicate((w) =>
                  w is Text && (w.data ?? '').startsWith('Nachtragen: ') && (w.data ?? '').endsWith('wie geplant'));
              if (b.evaluate().isEmpty) break;
              await _tap(t, b.first);
              merke('nachgetragen');
            }
            // Tag-Fenster (von unten) wieder schließen
            if (find.byKey(const Key('tagFenster')).evaluate().isNotEmpty) {
              await _tap(t, find.byTooltip('Schließen'));
            }
            await reiter(t, 'Heute');
          } else if (find.text('Weiß ich nicht mehr').evaluate().isNotEmpty) {
            await _tap(t, find.text('Weiß ich nicht mehr'));
            await _tap(t, find.text('Ja, weiß ich nicht mehr'));
            merke('weiß nicht mehr');
          }
        }
        if (ta.st.frz == null) {
          final zielStufe = ta.st.stage >= ta.st.plan.length - 1; // bei 0 mg gibt es kein „Halten“
          if (!zielStufe && !ta.st.hold && x < .09 && find.byKey(const Key('halten')).evaluate().isEmpty) {
            fail('Kein „Dosis halten“ auf Heute: Stufe ${ta.st.stage + 1}/${ta.st.plan.length}, '
                '${_texte(find.byType(Scaffold).first).take(40).join(' | ')}\n${spur()}');
          }
          if (!zielStufe && !ta.st.hold && x < .09) {
            await _tap(t, find.byKey(const Key('halten')));
            if (r.nextBool()) {
              await t.enterText(find.byKey(const Key('haltenTage')), '${2 + r.nextInt(6)}');
              await _tap(t, find.byKey(const Key('haltenStart')));
            } else {
              await _tap(t, find.text('Ohne Enddatum halten'));
            }
            expect(ta.st.hold, isTrue);
            merke('halten');
          } else if (ta.st.hold && x < .25) {
            await _tap(t, find.byKey(const Key('halten')));
            expect(ta.st.hold, isFalse);
            merke('weiter abdosieren');
          } else if (x < .28 && ta.st.stage < ta.st.plan.length - 2) {
            // Neuer, schnellerer Plan ab der aktuellen Dosis (über den Kern, Oberfläche zieht nach)
            final vorher = '${ta.st.plan}|${[for (var i = 0; i < ta.st.plan.length; i++) ta.need(i)]}|${ta.st.stage}';
            final e = ta.openEditor(neu: true);
            ta.editCalc(e, dose: ta.st.plan[ta.st.stage], step: 1, minStep: .5, days: 3, goal: 0);
            e.conf = 'Ich bin mir sicher';
            if (ta.applyPlan(e).applied) {
              app.aenderung();
              await t.pumpAndSettle();
              merke('neuer Plan');
              final nachher =
                  '${ta.st.plan}|${[for (var i = 0; i < ta.st.plan.length; i++) ta.need(i)]}|${ta.st.stage}';
              if (nachher != vorher) geaendertAm = ta.today; // gleicher Plan nochmal = keine Änderung
            }
          }
        }
        // Nachkauf über die Vorrat-Karte
        if (r.nextDouble() < .12) {
          await reiter(t, 'Heute');
          final vorher = ta.stockInfo()!.rem;
          if (find.byKey(const Key('anzahl0')).evaluate().isEmpty) await _tap(t, find.text('VORRAT ÄNDERN'));
          await t.enterText(find.byKey(const Key('anzahl0')), '10');
          await t.enterText(find.byKey(const Key('staerke0')), '2');
          await _tap(t, find.byKey(const Key('nachkauf')));
          expect(ta.stockInfo()!.rem, closeTo(vorher + 20, 1e-9), reason: 'Nachkauf ${spur()}');
          vorratSoll += 20;
          jetzt = jetzt.add(const Duration(minutes: 1));
          merke('Nachkauf');
        }
        // App 3 Minuten im Hintergrund → PIN-Sperre (Standard 2 Minuten), entsperren
        if (r.nextDouble() < .08) {
          app.hintergrund();
          jetzt = jetzt.add(const Duration(minutes: 3));
          app.vordergrund();
          await t.pumpAndSettle();
          expect(find.byType(SperrSeite), findsOneWidget);
          await t.enterText(find.byKey(const Key('pinEingabe')), '2468');
          await _tap(t, find.byKey(const Key('entsperren')));
          expect(app.gesperrt, isFalse);
          merke('gesperrt');
        }
        final heute = ta.today;
        final y = r.nextDouble();
        // „Dosis genommen“ steht in Heute.
        await reiter(t, 'Heute');
        if (ta.st.log[heute] == null && find.byKey(const Key('wieGeplant')).evaluate().isNotEmpty) {
          if (y < .1) {
            merke('vergessen');
          } else if (y < .2) {
            await t.enterText(find.byKey(const Key('menge')), fmt(ta.st.plan[ta.st.stage] + 1));
            await _tap(t, find.byKey(const Key('plus')));
            await _tap(t, find.text('Eintragen'));
            expect(find.byKey(const Key('mehrAlsGeplant')), findsOneWidget, reason: 'Fenster nach dem Eintragen');
            await _tap(t, find.byKey(const Key('mehrAlsGeplantOk')));
            merke('Ausrutscher');
          } else {
            await _tap(t, find.byKey(const Key('wieGeplant')));
            merke('wie geplant');
          }
        }

        // --- Prüfen: alle Reiter gegen den Kern ---
        final a = ta.st;
        final n = a.plan.length;
        final stufe = 'Stufe ${a.stage + 1} von $n';
        final ende = ta.planEndNow();
        final normal = !a.hold && a.frz == null;
        final letzte = a.stage >= n - 1;
        final grund = 'Tag $tag, $heute, hold=${a.hold}, frz=${a.frz}\n${spur()}';

        await reiter(t, 'Plan');
        final plan = _texte(find.byKey(const Key('planKarte')));
        expect(plan, contains('$stufe · jetzt ${fmt(a.plan[a.stage])} ${a.unit}'), reason: grund);
        if (a.frz != null) {
          expect(plan, contains('Offene Tage – Anzeigen pausieren bis zum Nachtragen.'), reason: grund);
        } else if (a.hold) {
          // Unabhängig: Ende ohne Halten + Halte-Tage (bis Enddatum bzw. bis heute)
          final ohne = Taper.planEnd(a.plan, a.days, a.stage, a.stageStart!, a.target);
          final d = dBetween(a.holdSince!, a.holdUntil ?? heute);
          expect(plan, contains('Voraussichtlich bei ${fmt(a.plan.last)} ${a.unit}: ${dmy(addD(ohne, d))} (Dosis wird gehalten)'),
              reason: grund);
        } else {
          expect(plan, contains('Voraussichtlich bei ${fmt(a.plan.last)} ${a.unit}: ${dmy(ende!)}'), reason: grund);
        }
        expect(plan,
            contains('Plan gestartet am ${dmy(t0)}${geaendertAm != null ? ' · geändert am ${dmy(geaendertAm)}' : ''}'),
            reason: 'Plan-Datum $grund');
        // Vorrat: Rest unabhängig mitgezählt, Reichweite und Zeile wie der Kern
        final jetztEingenommen = eingenommen();
        vorratSoll -= jetztEingenommen - vorherEingenommen;
        vorherEingenommen = jetztEingenommen;
        final si = ta.stockInfo()!;
        expect(si.rem, closeTo(vorratSoll, 1e-9), reason: 'Vorrat-Rest $grund');

        await reiter(t, 'Kalender');
        if (normal && n > 1) {
          expect(find.textContaining(dmy(ende!), findRichText: true), findsWidgets, reason: 'Kalender-Ende $grund');
        }
        if (normal) {
          final pm = ta.projMap(addD(heute, 6)).map;
          for (var i = 1; i <= 6; i++) {
            final k = addD(heute, i);
            final zelle = find.byKey(Key('tag-$k'));
            if (zelle.evaluate().isEmpty) continue; // anderer Monat
            // Zelle: oben die Tageszahl, darunter die geplante Dosis.
            expect(_texte(zelle).last, fmt(pm[k]!.v), reason: 'Kalender $k soll ${pm[k]!.v} zeigen. $grund');
          }
        }

        // Tagebuch unter dem Kalender (nur ohne offene Tage)
        expect(find.byKey(const Key('tagebuchHeute')), a.frz == null ? findsOneWidget : findsNothing, reason: grund);

        await reiter(t, 'Heute');
        expect(t.widget<Text>(find.byKey(const Key('vorratZeile'))).data, _vorratZeile(si.days, heute),
            reason: 'Vorrat-Zeile (unten in Heute) $grund');
        expect(find.byKey(const Key('vorratWarnung')), si.days <= 14 ? findsOneWidget : findsNothing,
            reason: 'Vorrat-Warnung bei ${si.days} Tagen. $grund');
        // Erinnerung: heute 20:00 nur ohne Eintrag (und wenn noch nicht vorbei), sonst ab morgen
        final lokal = jetzt.toLocal();
        final hatHeute = a.log[heute]?.it.isNotEmpty ?? false;
        final heute20 = DateTime(lokal.year, lokal.month, lokal.day, 20);
        final erste =
            (!hatHeute && heute20.isAfter(lokal)) ? heute20 : DateTime(lokal.year, lokal.month, lokal.day + 1, 20);
        expect(erin.geplant.first, erste, reason: 'Erinnerung $grund');
        expect(erin.geplant.length, erinnerungTage - (erste == heute20 ? 0 : 1), reason: grund);
        if (a.frz == null) {
          final erwartet = !letzte ? stufe : (a.plan[a.stage] > 0 ? 'Letzte Stufe' : 'Ziel erreicht');
          expect(find.textContaining(erwartet, findRichText: true), findsWidgets, reason: 'Heute $grund');
        }

        await reiter(t, 'Fortschritt');
        final weg = _texte(find.byKey(const Key('wegKarte')));
        expect(weg, contains('${a.stage + 1} von $n'), reason: grund);
        // auch beim Halten ein voraussichtliches Datum (Ende ohne Halten + Halte-Tage)
        String voraus() {
          final ohne = Taper.planEnd(a.plan, a.days, a.stage, a.stageStart!, a.target);
          return a.hold ? addD(ohne, dBetween(a.holdSince!, a.holdUntil ?? heute)) : ohne;
        }
        final ziel = letzte ? 'Erreicht' : (a.frz == null ? dmy(voraus()) : '–');
        expect(weg, contains(ziel), reason: 'Fortschritt-Ziel $grund');
        final maler = t
            .widget<CustomPaint>(
                _in('diagramm', find.byWidgetPredicate((w) => w is CustomPaint && w.painter is VerlaufMaler)))
            .painter! as VerlaufMaler;
        expect(maler.tage[maler.heuteIdx].tag, heute, reason: grund);
        if (normal && !letzte) {
          expect(maler.tage.last.tag, ende, reason: 'Diagramm endet am Planende. $grund');
          final pm = ta.projMap(ende!).map;
          for (final d in maler.tage.where((d) => d.zukunft)) {
            expect(d.plan, pm[d.tag]!.v, reason: 'Diagramm ${d.tag}. $grund');
          }
        }
        for (final d in maler.tage.where((d) => !d.zukunft)) {
          expect(d.dosis, a.log[d.tag]?.dose, reason: 'Diagramm-Dosis ${d.tag}. $grund');
        }

        // --- nächster Tag ---
        jetzt = jetzt.add(const Duration(days: 1));
        app.auffrischen();
        await t.pumpAndSettle();
      }
      ereignisse.forEach((k, v) => alle[k] = (alle[k] ?? 0) + v);
      // ignore: avoid_print
      print('Seed $seed: $ereignisse, Stufe ${ta.st.stage + 1}/${ta.st.plan.length}');
    });
  }

  test('Abdeckung: alle Ereignisse kamen in der Simulation vor', () {
    for (final w in [
      'wie geplant',
      'Ausrutscher',
      'vergessen',
      'nachgetragen',
      'halten',
      'weiter abdosieren',
      'neuer Plan',
      'Nachkauf',
      'gesperrt'
    ]) {
      expect(alle[w] ?? 0, greaterThan(0), reason: '„$w“ kam nie vor: $alle');
    }
  });
}
