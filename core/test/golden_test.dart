// Vergleichstest: spielt Abläufe ab, die mit einer früheren Fassung aufgezeichnet wurden
// (test/golden/), und prüft nach jedem Tag, dass der Dart-Kern denselben Zustand hat.
import 'dart:convert';
import 'dart:io';

import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';
import 'sim.dart';

double _d(Object? x) => (x as num).toDouble();

/// Tage, deren Eintrag angelegt wurde, während ein älterer Tag offen war (Anzeigen pausiert). Die Referenz
/// speicherte dafür die eingefrorene Stufe; seit v0.2.2 speichert der Kern die echte Planposition (Prüfer-
/// befund: sonst fehlt „Kurz innehalten“ und die Reichweite ist falsch). Für diese Tage werden Plan, Stufe
/// und Bewertung nicht mit der Referenz verglichen; eigene Prüfung: vorrat_test, pruefer_befunde_test.
final eingefroren = <String>{};

void exec(Sim w, List op, List<Map<String, dynamic>> snaps, int Function() nextSnap,
    void Function(Map<String, dynamic>) check) {
  final e = w.e;
  switch (op[0] as String) {
    case 'setup':
      w.setup(_d(op[1]), _d(op[2]), op[3] as int);
    case 'tabs':
      w.st.tabs = Tabs(str: (op[1] as List).map(_d).toList(), split: _d(op[2]));
    case 'stock':
      w.st.stock = Stock(_d(op[1]), w.now.millisecondsSinceEpoch, w.today);
    case 'stockAdd':
      w.st.stock!.mg += _d(op[1]);
    case 'at':
      w.at(op[1] as int, op[2] as int);
    case 'day':
      w.day(op[1] as int, op[2] as int);
    case 'take':
      if (w.st.frz != null) eingefroren.add((op[3] as String).isEmpty ? w.today : op[3] as String);
      w.take(_d(op[1]), op[2] as String, op[3] as String);
    case 'takeP':
      if (w.st.frz != null) eingefroren.add(w.today);
      final t = (op[2] as String).isEmpty ? null : op[2] as String;
      if (e.addIntake(_d(op[1]), t: t) == IntakeResult.needsPause) {
        e.addIntake(_d(op[1]), t: t, force: true);
      }
    case 'hold':
      expect(e.startHold(op[1] as int?), isTrue);
    case 'stopHold':
      e.stopHold();
    case 'left':
      final n = op[1] as int;
      if (e.saveLeft(n) == LeftResult.needsWhy) e.saveLeft(n, why: 'Grund');
    case 'usePend':
      final ed = e.usePend();
      if (ed != null) {
        ed.conf = 'Ich bin mir sicher';
        e.applyPlan(ed);
      }
    case 'dropPend':
      e.dropPend();
    case 'markUnk':
      e.markUnk();
    case 'good':
      e.toggleGood(op[1] as String);
    case 'note':
      break; // Ergebnis steht im folgenden "setNoteCheck"
    case 'setNoteCheck':
      e.saveNote(op[1] as String, Note(sym: op[2] as int, text: op[3] as String));
    case 'editor':
      final ed = e.openEditor();
      final r = ed.rows[op[1] as int];
      if (op[2] == 'days') {
        r.days = op[3] as int;
      } else {
        r.dose = _d(op[3]);
      }
      ed.conf = 'Ich bin mir sicher';
      final res = e.applyPlan(ed);
      if (res.askWhy) {
        ed.why = 'weil';
        e.applyPlan(ed);
      }
    case 'import':
      expect(e.importJson(jsonDecode(op[1] as String)), isTrue);
    case 'sos':
      e.sosDone();
    case 'snap':
      check(snaps[nextSnap()]);
    default:
      fail('unbekannter Befehl ${op[0]}');
  }
}

Map<String, dynamic> snap(Sim w) {
  final e = w.e, S = w.st, today = w.today;
  final si = e.stockInfo();
  final pj = e.projMap(addD(today, 21));
  final ks = S.log.keys.toList()..sort();
  var ds = 0.0;
  for (final k in ks) {
    ds += S.log[k]!.dose;
  }
  Object? pend;
  if (S.pend != null) {
    final p = S.pend!;
    pend = {
      'kind': p.kind,
      'stage': p.stage,
      'nd': p.nd,
      'next': p.next,
      'why': p.why,
      'txt': p.txt,
      'base': p.base,
      'at': p.at,
      'o': p.o == null
          ? null
          : {'plan': p.o!.plan, 'days': p.o!.days, 'stage': p.o!.stage, 'name': p.o!.name, 'unit': p.o!.unit},
    };
  }
  return {
    'today': today,
    'stage': S.stage,
    'stageStart': S.stageStart,
    'adv': S.adv,
    'hold': S.hold,
    'holdSince': S.holdSince,
    'holdUntil': S.holdUntil,
    'frz': S.frz,
    'frzFloor': S.frzFloor,
    't0': S.t0,
    'plan': S.plan,
    'days': S.days,
    'target': S.target,
    'unit': S.unit,
    'name': S.name,
    'pend': pend,
    'unk': S.unk.toList()..sort(),
    'good': S.good.toList()..sort(),
    'notes': S.notes.keys.toList()..sort(),
    'logN': ks.length,
    'doseSum': ds,
    'lastLog': ks.reversed.take(8).toList().reversed.map((k) {
      final x = S.log[k]!;
      return [k, x.dose, x.plan, x.stage, x.r, x.it.length];
    }).toList(),
    'stock': [si?.rem, si == null ? null : (si.days.isInfinite ? 'inf' : si.days)],
    'wk': e.weekAvgs(w.now, 4).map((x) => [x.avg, x.n]).toList(),
    'end': pj.end,
    'proj': [
      for (var i = 1; i <= 21; i++)
        pj.map[addD(today, i)] == null ? null : [pj.map[addD(today, i)]!.v, pj.map[addD(today, i)]!.ch ? 1 : 0]
    ],
    'openN': e.openDays().length,
    'q': e.qCount(),
    'chgN': S.chg.length,
    'chgLast': S.chg.reversed.take(3).toList().reversed.map((c) => c.t).toList(),
    'sosN': S.sosN,
    'minStep': e.minStep(),
  };
}

/// Erster Unterschied als Text, oder null.
String? diff(Object? a, Object? b, [String path = '']) {
  if (a is num && b is num) {
    return (a.toDouble() - b.toDouble()).abs() < 1e-9 ? null : '$path: $a ≠ $b';
  }
  if (a is Map && b is Map) {
    for (final k in {...a.keys, ...b.keys}) {
      final d = diff(a[k], b[k], '$path.$k');
      if (d != null) return d;
    }
    return null;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return '$path: Länge ${a.length} ≠ ${b.length}';
    for (var i = 0; i < a.length; i++) {
      final d = diff(a[i], b[i], '$path[$i]');
      if (d != null) return d;
    }
    return null;
  }
  return a == b ? null : '$path: $a ≠ $b';
}

/// Zustand für den Endvergleich vereinheitlichen (nur Felder, die beide Seiten kennen).
Map<String, dynamic> finalView(Map<String, dynamic> s) {
  Object? clean(Object? x) {
    if (x is Map) {
      return {
        for (final e in x.entries)
          if (e.value != null) e.key: clean(e.value)
      };
    }
    if (x is List) return x.map(clean).toList();
    return x;
  }

  final out = <String, dynamic>{};
  for (final k in [
    'name',
    'unit',
    'target',
    'plan',
    'days',
    'stage',
    'stageStart',
    'adv',
    't0',
    'holdSince',
    'holdUntil',
    'frz',
    'frzFloor',
    'sosN',
    'pin',
    'wkSeen',
    'step',
    'min'
  ]) {
    out[k] = s[k];
  }
  out['hold'] = s['hold'] == true;
  out['sosN'] = s['sosN'] ?? 0;
  out['unk'] = (s['unk'] as Map? ?? {}).keys.toList()..sort();
  out['good'] = (s['good'] as Map? ?? {}).keys.toList()..sort();
  out['notes'] = {
    for (final e in (s['notes'] as Map? ?? {}).entries) e.key: {'sym': e.value['sym'], 'text': e.value['text']}
  };
  out['log'] = s['log'];
  out['tabs'] = s['tabs'];
  out['stock'] = s['stock'];
  out['chg'] = s['chg'] ?? [];
  out['pend'] = s['pend'];
  return Map<String, dynamic>.from(clean(out) as Map);
}

void main() {
  final dir = Directory('test/golden');
  final files = dir.existsSync()
      ? (dir
          .listSync()
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.startsWith('seed') && f.path.endsWith('.json.gz'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  test('Golden-Dateien vorhanden', () => expect(files, isNotEmpty));
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    test('Abläufe aus den Referenzdaten: $name', () {
      final g = jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync()))) as Map<String, dynamic>;
      final snaps = (g['snaps'] as List).cast<Map<String, dynamic>>();
      final w = Sim(start: '2026-11-16T07:00:00');
      eingefroren.clear();
      var si = 0;
      var n = 0;
      for (final op in g['ops'] as List) {
        exec(w, op as List, snaps, () => si++, (want) {
          final got = jsonDecode(jsonEncode(snap(w))) as Map<String, dynamic>;
          // Bewusst anders als in den Referenzdaten: Vorrat-Reichweite beim Halten mit Enddatum rechnet nach
          // dem Halte-Ende laut Plan weiter. Eigene Prüfung: scenarios_test V1, simulation_test.
          if (got['hold'] == true && got['holdUntil'] != null) {
            (want['stock'] as List)[1] = null;
            (got['stock'] as List)[1] = null;
            // Ebenso: Kalender-Prognose läuft nach dem Halte-Ende laut Plan weiter.
            want['proj'] = got['proj'] = null;
          }
          // Bewusst anders seit v0.2.2 (Doc 28/29): Tage ohne Eintrag ziehen die geplante Dosis vom Vorrat ab,
          // und die Reichweite rechnet mit der echten Planposition, auch wenn offene Tage die Anzeigen pausieren.
          // Die Referenz kannte beides nicht. Eigene Prüfung: vorrat_test, longsim_test.
          if ((w.e.stockInfo()?.geschaetzt ?? 0) > 0) {
            want['stock'] = got['stock'] = null;
          } else if (got['frz'] != null && got['stock'] is List) {
            (want['stock'] as List)[1] = null;
            (got['stock'] as List)[1] = null;
          }
          final ll = [want['lastLog'] as List, got['lastLog'] as List];
          for (var i = 0; i < ll[0].length && i < ll[1].length; i++) {
            if (eingefroren.contains((ll[0][i] as List)[0])) {
              for (final l in ll) {
                (l[i] as List)[2] = (l[i] as List)[3] = (l[i] as List)[4] = null;
              }
            }
          }
          if (eingefroren.contains(want['today'])) want['wk'] = got['wk'] = null;
          final d = diff(want, got);
          if (d != null) {
            fail(
                'Tag-Zustand ${si - 1} (${want['today']}) weicht ab: $d\n  Ref:  ${jsonEncode(want)}\n  Dart: ${jsonEncode(got)}');
          }
          n++;
        });
      }
      expect(n, snaps.length);
      final soll = finalView(g['final'] as Map<String, dynamic>);
      final ist = finalView(jsonDecode(jsonEncode(w.e.exportJson())) as Map<String, dynamic>);
      for (final v in [soll, ist]) {
        final log = v['log'] as Map?;
        if (log == null) continue;
        for (final k in eingefroren) {
          final x = log[k];
          if (x is Map) {
            x.remove('plan');
            x.remove('stage');
            x.remove('r');
          }
        }
      }
      final fin = diff(soll, ist);
      expect(fin, isNull, reason: 'Endzustand');
    });
  }
}
