// Vergleichstest für Plan-Rechnung, Tablettenkombination und Text-Import gegen eingefrorene Referenzdaten (test/golden/).
import 'dart:convert';
import 'dart:io';

import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';
import 'golden_test.dart' show diff;

Object? comboJson(Combo? c) {
  if (c == null) return null;
  List parts(List<ComboPart>? l) => l == null
      ? []
      : [
          for (final p in l) {'s': p.s, 'f': p.f}
        ];
  if (c.exact) return {'exact': true, 'parts': parts(c.parts), 'val': c.val};
  return {
    'exact': false,
    'lo': c.lo,
    'hi': c.hi,
    'loParts': parts(c.loParts),
    'hiParts': c.hiParts == null ? null : parts(c.hiParts),
  };
}

void main() {
  final f = File('test/golden/math.json.gz');
  final g = jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync()))) as Map<String, dynamic>;

  test('makePlan wie in den Referenzdaten', () {
    var n = 0;
    for (final c in g['plan'] as List) {
      final got = makePlan(
          (c[0] as num).toDouble(), (c[1] as num).toDouble(), (c[2] as num).toDouble(), (c[3] as num).toDouble());
      final d = diff(c[4], got);
      expect(d, isNull, reason: 'makePlan(${c.take(4).join(', ')})');
      n++;
    }
    expect(n, greaterThan(2000));
  });

  test('Tablettenkombination wie in den Referenzdaten', () {
    for (final c in g['combo'] as List) {
      final got = combo((c[0] as num).toDouble(), (c[1] as List).map((x) => (x as num).toDouble()).toList(),
          (c[2] as num).toDouble());
      final gotJson = jsonDecode(jsonEncode(comboJson(got)));
      expect(diff(c[3], gotJson), isNull, reason: 'combo(${c[0]}, ${c[1]}, ${c[2]})');
    }
  });

  test('Zahlen- und Bruchformat wie in den Referenzdaten', () {
    for (final c in g['fmt'] as List) {
      expect(fmt((c[0] as num).toDouble()), c[1], reason: 'fmt(${c[0]})');
    }
    for (final c in g['frac'] as List) {
      if (c[0] == 'parts') {
        final parts = [for (final p in c[1] as List) ComboPart((p['s'] as num).toDouble(), (p['f'] as num).toDouble())];
        expect(partsStr(parts, c[2] as String), c[3]);
      } else {
        expect(fracStr((c[0] as num).toDouble()), c[1], reason: 'fracStr(${c[0]})');
      }
    }
  });

  test('Text-Import wie in den Referenzdaten', () {
    var withRows = 0;
    for (final c in g['text'] as List) {
      final got = parsePlanText(c[0] as String, c[1] as int, DateTime(2026, 11, 16));
      final gotJson = jsonDecode(jsonEncode({
        'rows': [
          for (final r in got.rows) {'dose': r.dose, 'days': r.days, 'guess': r.guess}
        ],
        'unit': got.unit,
      }));
      expect(diff(c[2], gotJson), isNull, reason: 'Text:\n${c[0]}');
      if (got.rows.isNotEmpty) withRows++;
    }
    expect(withRows, greaterThan(100));
  });
}
