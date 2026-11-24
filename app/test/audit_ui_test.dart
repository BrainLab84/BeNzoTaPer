// QA-Audit der Oberfläche: 100 zufällige, reproduzierbare Szenarien (Seed 1–100).
//
// Jedes Szenario: eigener Plan (Rechner oder Import, auch Grenzfälle), dann eine zufällige Folge aus
// Einnahmen, Nachtragen, Löschen, vergessenen Tagen, „Weiß ich nicht mehr“, Halten mit/ohne Ende, Weiter,
// Stufe kürzer, neuem Plan, Vorrat zählen/nachkaufen, Reiterwechseln, Auffrischen, Tageswechseln.
// Danach wird jeder Reiter gerendert und gegen eine UNABHÄNGIGE Rechnung geprüft (Stufe, Dosis,
// „Voraussichtlich bei …“, Kalendertage, Stufentag, Vorrat, Fortschritt, Diagramm). Dann Neustart der
// App aus dem gespeicherten Stand: Alle Reiter müssen danach Wort für Wort dasselbe zeigen.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/bausteine.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/heute.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_buddy/verlauf.dart';
import 'package:tapering_core/tapering_core.dart';

import 'hilfen.dart';

List<String> _texte(Finder wo) => [
      for (final e in find.descendant(of: wo, matching: find.byType(Text), matchRoot: true).evaluate())
        ((e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '').replaceAll('\uFFFC', '').trim()
    ];

/// Unabhängige Rechnung (wie core/test/audit_test.dart).
class Soll {
  Soll(this.s, this.heute);
  final TaperState s;
  final String heute;
  int need(int i) => (s.days != null && i < s.days!.length && s.days![i] > 0) ? s.days![i] : s.target;

  /// Stufe an einem künftigen Tag (unabhängig, wie [dosis]).
  int? stufeAm(String k) {
    if (s.frz != null) return null;
    final last = s.plan.length - 1;
    var sg = s.stage;
    var start = s.stageStart!;
    if (s.hold) {
      if (s.holdUntil == null || k.compareTo(s.holdUntil!) < 0) return sg;
      start = addD(start, dBetween(s.holdSince!, s.holdUntil!));
    }
    while (sg < last && k.compareTo(addD(start, need(sg))) >= 0) {
      start = addD(start, need(sg));
      sg++;
    }
    return sg;
  }

  double? dosis(String k) {
    if (s.frz != null) return null;
    final last = s.plan.length - 1;
    var sg = s.stage;
    var start = s.stageStart!;
    if (s.hold) {
      if (s.holdUntil == null || k.compareTo(s.holdUntil!) < 0) return s.plan[sg];
      start = addD(start, dBetween(s.holdSince!, s.holdUntil!));
    }
    while (sg < last && k.compareTo(addD(start, need(sg))) >= 0) {
      start = addD(start, need(sg));
      sg++;
    }
    return s.plan[sg];
  }

  String? ende() {
    if (s.frz != null || s.plan.length < 2) return null;
    var k = s.stageStart!;
    if (s.hold) k = addD(k, max(0, dBetween(s.holdSince!, s.holdUntil ?? heute)));
    for (var i = s.stage; i < s.plan.length - 1; i++) {
      k = addD(k, need(i));
    }
    if (s.hold && k.compareTo(s.holdUntil ?? heute) < 0) k = s.holdUntil ?? heute;
    return k;
  }

  String? voraussichtlich() {
    final e = ende();
    if (e == null) return null;
    return 'Voraussichtlich bei ${fmt(s.plan.last)} ${s.unit}: ${dmy(e)}${s.hold ? ' (Dosis wird gehalten)' : ''}';
  }
}

Future<void> _ruhe(WidgetTester t) async {
  // Speichern läuft asynchron (Schreibschleife) – echte Zeit geben.
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  await t.pumpAndSettle();
}

/// Alle Reiter rendern, gegen [Soll] prüfen und als Text-Schnappschuss zurückgeben.
Future<String> _pruefeAlles(WidgetTester t, AppState app, String grund) async {
  final ta = app.taper;
  final s = ta.st;
  final soll = Soll(s, ta.today);
  final n = s.plan.length;
  final last = s.stage >= n - 1;
  final stufe = 'Stufe ${s.stage + 1} von $n';
  final schnapp = StringBuffer();

  // --- Plan
  await reiter(t, 'Plan');
  final plan = _texte(find.byKey(const Key('planKarte')));
  expect(plan, contains('$stufe · jetzt ${fmt(s.plan[s.stage])} ${s.unit}'), reason: 'Plan-Karte Stufe. $grund');
  if (s.frz != null) {
    expect(plan, contains('Offene Tage – Anzeigen pausieren bis zum Nachtragen.'), reason: grund);
  } else if (soll.voraussichtlich() != null) {
    expect(plan, contains(soll.voraussichtlich()), reason: 'Plan-Karte Ende. $grund');
  }
  schnapp.writeln('PLAN ${plan.join('|')}');

  // --- Kalender
  await reiter(t, 'Kalender');
  final alle = _texte(find.byType(Scaffold).first).join('\n');
  if (s.frz == null && soll.voraussichtlich() != null) {
    expect(alle, contains(soll.voraussichtlich()!.replaceFirst(': ', ': ')), reason: 'Kalender-Ende. $grund');
  }
  for (var i = 1; i <= 10; i++) {
    final k = addD(ta.today, i);
    final zelle = find.byKey(Key('tag-$k'));
    if (zelle.evaluate().isEmpty) continue; // anderer Monat
    final d = soll.dosis(k);
    if (d == null) continue;
    expect(_texte(zelle).last, fmt(d), reason: 'Kalender $k. $grund');
  }
  final sd = ta.stageDay();
  final fertig = last && (!(s.plan.last > 0) || sd >= soll.need(s.stage));
  if (find.byKey(const Key('kalenderFortschritt')).evaluate().isNotEmpty && n >= 2 && !fertig) {
    final kf = _texte(find.byKey(const Key('kalenderFortschritt'))).join('|');
    expect(kf, contains('Tag ${min(sd + 1, soll.need(s.stage))}/${soll.need(s.stage)}'), reason: 'Stufentag. $grund');
  }
  schnapp.writeln('KAL ${alle.replaceAll(RegExp(r'\d\d:\d\d'), 'hh:mm')}');

  // --- Heute
  await reiter(t, 'Heute');
  final heute = _texte(find.byType(Scaffold).first);
  if (s.frz == null) {
    expect(_texte(find.byKey(const Key('dosis'))).join(), '${fmt(s.plan[s.stage])} ${s.unit}', reason: grund);
    expect(heute.any((x) => x.startsWith('${s.name} · $stufe')), isTrue, reason: 'Heute Stufe. $grund');
  }
  // Datumsangaben auf Heute gegen die unabhängige Prognose (gleiche Quelle wie der Kalender)
  if (s.frz == null && !last && s.pend == null) {
    final alles = heute.join('\n');
    if (s.hold && s.holdUntil != null) {
      final bis = addD(s.holdUntil!, -1);
      expect(alles, contains('gehalten bis ${dmy(bis)} (noch ${tage(dBetween(ta.today, s.holdUntil!))}).'),
          reason: 'Heute Halte-Ende. $grund');
      expect(soll.stufeAm(bis), s.stage, reason: 'letzter Haltetag noch gehalten. $grund');
    } else if (!s.hold) {
      var k = addD(ta.today, 1);
      while (soll.stufeAm(k) == s.stage) {
        k = addD(k, 1);
      }
      final n = dBetween(ta.today, k);
      expect(alles, contains('Nächste Stufe ${n == 1 ? 'morgen' : 'in $n Tagen'} (${dmy(k)})'),
          reason: 'Heute nächste Stufe. $grund');
    }
  }
  schnapp.writeln('HEUTE ${heute.join('|')}');

  // --- Vorrat (unten in Heute)
  await t.scrollUntilVisible(find.byKey(const Key('vorratKarte')), 300,
      scrollable: find.descendant(of: find.byType(HeuteSeite), matching: find.byType(Scrollable)).first);
  final si = ta.stockInfo();
  if (si != null) {
    final z = _texte(find.byKey(const Key('vorratZeile'))).join();
    final String erw;
    if (si.days < 1) {
      erw = 'Reicht nicht mehr für heute';
    } else if (si.days.isFinite) {
      erw = 'Reicht noch ca. ${tage(si.days.toInt())} (bis ${dmy(addD(ta.today, si.days.toInt() - 1))})';
    } else {
      erw = 'Reicht bis zum Ende des Plans';
    }
    expect(z, erw, reason: 'Vorrat-Zeile. $grund');
  }
  if (si != null) schnapp.writeln('VORRAT ${_texte(find.byKey(const Key('vorratKarte'))).take(4).join('|')}');

  // --- Fortschritt
  await reiter(t, 'Fortschritt');
  final weg = _texte(find.byKey(const Key('wegKarte')));
  expect(weg, contains('${s.stage + 1} von $n'), reason: grund);
  final e = soll.ende();
  expect(weg, contains(last ? 'Erreicht' : (e != null ? dmy(e) : '–')), reason: 'Fortschritt-Ziel. $grund');
  final maler = t
      .widget<CustomPaint>(find.descendant(
          of: find.byKey(const Key('diagramm')),
          matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is VerlaufMaler)))
      .painter! as VerlaufMaler;
  final v = ta.verlauf();
  expect(maler.tage.length, v.tage.length, reason: grund);
  expect(maler.tage.last.tag, v.bis, reason: grund);
  if (!last && s.frz == null && !(s.hold && s.holdUntil == null)) {
    expect(v.bis, e, reason: 'Diagramm endet beim voraussichtlichen Ende. $grund');
  }
  schnapp.writeln('WEG ${weg.join('|')} DIAGRAMM ${v.start}..${v.bis} ${maler.tage.length}');
  return schnapp.toString();
}

void main() {
  final zaehler = <String, int>{};
  for (var seed = 1; seed <= 100; seed++) {
    testWidgets('Audit Oberfläche, Szenario $seed: alle Reiter stimmen, Neustart zeigt dasselbe', (t) async {
      final r = Random(seed);
      final y = [2026, 2027, 2028][r.nextInt(3)];
      final mo = [1, 2, 3, 6, 10, 12][r.nextInt(6)];
      jetzt = DateTime.utc(y, mo, mo == 2 ? 20 + r.nextInt(9) : 1 + r.nextInt(28), 9);
      t.view.physicalSize = const Size(1000, 7000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = MemStore()..disc = true;
      final app = AppState(store, clock: () => jetzt);
      await t.runAsync(app.laden);
      final ta = app.taper;
      final spur = <String>[];
      void merke(String w) {
        spur.add('${ta.today}: $w');
        final k = w.split(' ').first;
        zaehler[k] = (zaehler[k] ?? 0) + 1;
      }

      // Plan anlegen (wie „Neuen Plan erstellen“: Beispiel vorher weg)
      app.beispielWeg();
      if (r.nextInt(3) > 0) {
        final dose = [10.0, 20.0, 6.0, 2.5][r.nextInt(4)];
        expect(
            ta.setup(
                dose: dose,
                step: [0.5, 1.0, 2.5][r.nextInt(3)],
                minStep: 0.25,
                days: 3 + r.nextInt(12),
                goal: r.nextInt(4) == 0 ? dose / 2 : 0),
            isNull);
        merke('Setup');
      } else {
        final k = [1, 2, 4, 12][r.nextInt(4)];
        final rows = [for (var i = 0; i < k; i++) EditRow(k == 1 ? 5 : round3(10 - 10 * i / (k - 1)), 1 + r.nextInt(14))];
        expect(ta.applyPlan(ta.openEditor(neu: true)..rows = rows).applied, isTrue);
        merke('Import $k');
      }
      if (r.nextBool()) {
        ta.setStock(20 + r.nextInt(80).toDouble(), [1.0, 2.0, 5.0][r.nextInt(3)]);
        merke('Vorrat');
      }
      await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
      await t.pumpAndSettle();

      final schritte = 8 + r.nextInt(30);
      for (var i = 0; i < schritte; i++) {
        final s = ta.st;
        final lastSt = s.stage >= s.plan.length - 1;
        final w = r.nextInt(100);
        if (w < 30) {
          ta.addIntake([s.plan[s.stage], s.plan[s.stage] / 2, s.plan[s.stage] + 1][r.nextInt(3)], force: true);
          merke('Einnahme');
        } else if (w < 37) {
          final k = addD(ta.today, -(1 + r.nextInt(7)));
          ta.addIntake(ta.planFor(k).plan, k: k, t: '0${r.nextInt(10)}:15', force: true);
          merke('Nachtragen');
        } else if (w < 42) {
          final ks = s.log.keys.where((k) => ta.daysAgo(k) <= 7).toList();
          if (ks.isNotEmpty) {
            final k = ks[r.nextInt(ks.length)];
            ta.delIntake(r.nextInt(ta.dayIt(s.log[k]!).length), k);
            merke('Löschen');
          }
        } else if (w < 47) {
          for (final k in ta.openDays()) {
            if (ta.daysAgo(k) <= 7) ta.addIntake(ta.planFor(k).plan, k: k, force: true);
          }
          if (ta.openDays().isNotEmpty) ta.markUnk();
          merke('Lücken');
        } else if (w < 55) {
          if (!s.hold && !lastSt && s.frz == null) {
            ta.startHold(r.nextBool() ? null : 1 + r.nextInt(10));
            merke('Halten');
          } else if (s.hold) {
            ta.stopHold();
            merke('Weiter');
          }
        } else if (w < 58) {
          if (!s.hold && !lastSt && s.frz == null) {
            final ni = max(1, ta.need(s.stage) - ta.stageDay());
            if (ni > 1) {
              ta.saveLeft(1 + r.nextInt(ni - 1));
              merke('Kürzer');
            }
          }
        } else if (w < 61) {
          if (!lastSt && s.frz == null) {
            final e = ta.openEditor(neu: true);
            ta.editCalc(e, dose: s.plan[s.stage], step: 1, minStep: .5, days: 2 + r.nextInt(5), goal: 0);
            e.conf = 'Ich bin mir sicher';
            if (e.err == null) {
              final res = ta.applyPlan(e);
              if (res.askWhy) {
                ta.applyPlan(e..why = 'brauche Zeit');
              }
              merke('Plan');
            }
          }
        } else if (w < 64) {
          ta.setStock(10, 2, add: r.nextBool() && s.stock != null);
          merke('Vorrat');
        } else if (w < 72) {
          await reiter(t, ['Kalender', 'Heute', 'Plan', 'Fortschritt'][r.nextInt(4)]);
          merke('Reiter');
        } else if (w < 75) {
          app.auffrischen();
          merke('Auffrischen');
        } else if (w < 93) {
          jetzt = DateTime.utc(jetzt.year, jetzt.month, jetzt.day + 1, [0, 9, 21][r.nextInt(3)], 30);
          app.auffrischen();
          merke('Tag');
        } else {
          jetzt = DateTime.utc(jetzt.year, jetzt.month, jetzt.day + 2 + r.nextInt(9), 9);
          app.auffrischen();
          merke('Vergessen');
        }
        app.aenderung();
        await t.pumpAndSettle();
      }

      final grund = 'Seed $seed\n${spur.reversed.take(10).toList().reversed.join('\n')}';
      final vorher = await _pruefeAlles(t, app, grund);
      await _ruhe(t);

      // Neustart: neuer AppState aus demselben Speicher
      final app2 = AppState(store, clock: () => jetzt);
      await t.runAsync(app2.laden);
      expect(app2.eingerichtet, isTrue, reason: 'Plan nach Neustart weg. $grund');
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(TaperingBuddy(app: app2, splashDauer: const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 50));
      await t.pumpAndSettle();
      final nachher = await _pruefeAlles(t, app2, 'nach Neustart. $grund');
      expect(nachher, vorher, reason: 'Neustart zeigt etwas anderes. $grund');
    });
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('Audit Oberfläche – Aktionen: $zaehler');
  });
}
