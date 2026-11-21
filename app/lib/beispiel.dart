// Beispielplan zum Umschauen: Solange es keinen eigenen Plan gibt,
// zeigt die App ein deutlich markiertes Beispiel, damit man sieht, wie alles aussieht.
// Das Beispiel wird nie gespeichert; „Neuen Plan erstellen“ oben im Kalender ersetzt es.
import 'package:tapering_core/tapering_core.dart';

import 'i18n/txt.dart';

/// Beispiel: 10 mg in 1-mg-Schritten alle 14 Tage, seit 24 Tagen dabei, jetzt Stufe 2 (9 mg),
/// ein Ausrutscher, eine Notiz, zwei gute Tage, Tabletten zu 5 und 2 mg mit Vorrat.
Map<String, dynamic> beispielJson(String heute) {
  const plan = [10.0, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0];
  final t0 = addD(heute, -24);
  final log = <String, dynamic>{};
  for (var i = 0; i < 24; i++) {
    final k = addD(t0, i);
    final stufe = i < 14 ? 0 : 1;
    final p = plan[stufe];
    final v = i == 17 ? p + 1 : p;
    log[k] = {
      'it': [
        {'t': '08:00', 'v': v, 'ts': 0}
      ],
      'dose': v,
      'plan': p,
      'stage': stufe,
      'r': v > p ? 'lapse' : 'ok',
    };
  }
  return {
    'name': 'Diazepam',
    'unit': 'mg',
    'step': 1,
    'min': 0.5,
    'target': 14,
    'plan': plan,
    'days': [for (final _ in plan) 14],
    'stage': 1,
    'stageStart': addD(t0, 14),
    't0': t0,
    'log': log,
    'notes': {
      addD(t0, 17): {'sx': <String>[], 'sym': 3, 'text': tr('4 Kaffee', '4 coffees')},
    },
    'good': {addD(t0, 20): 1, addD(t0, 22): 1},
    'tabs': {
      'str': [5, 2],
      'split': 0.5,
    },
    'stock': {'mg': 180, 'ts': 0, 'day': addD(heute, -3)},
  };
}
