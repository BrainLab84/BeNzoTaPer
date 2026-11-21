import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_core/tapering_core.dart';

Future<AppState> eingerichtet() async {
  final app = AppState(MemStore(), clock: () => DateTime.utc(2026, 3, 10, 12));
  await app.laden();
  final r = app.taper.importJson({
    'name': 'Test',
    'unit': 'mg',
    'step': 0.5,
    'min': 0.5,
    'target': 0,
    'plan': [10, 9.5, 9],
    'days': [14, 14, 14],
    'stage': 0,
    'stageStart': '2026-03-01',
    'log': {
      '2026-03-09': {
        'it': [
          {'t': '08:00', 'v': 10}
        ],
        'dose': 10
      }
    },
  });
  expect(r, isTrue);
  return app;
}

void main() {
  test('Verschlüsselt: hin und zurück, Passwort falsch, alte Sicherung', () async {
    final a = await eingerichtet();
    final enc = (await a.sicherungErstellen(passwort: 'geheim-123'))!;
    expect(a.sicherungBrauchtPasswort(enc), isTrue);
    expect(enc.contains('Test'), isFalse);

    final b = AppState(MemStore(), clock: () => DateTime.utc(2026, 3, 10, 12));
    await b.laden();
    await expectLater(b.sicherungLaden(enc, passwort: 'falsch-123'),
        throwsA(isA<SicherungException>().having((e) => e.fehler, 'f', SicherungFehler.passwortFalsch)));
    await expectLater(b.sicherungLaden(enc),
        throwsA(isA<SicherungException>().having((e) => e.fehler, 'f', SicherungFehler.passwortFalsch)));
    expect(b.eingerichtet, isFalse, reason: 'Fehlschlag lässt den Stand unberührt');

    await b.sicherungLaden(enc, passwort: 'geheim-123');
    expect(b.taper.s!.name, 'Test');
    expect(jsonEncode(b.taper.exportJson()), jsonEncode(a.taper.exportJson()));
    expect((b.store as MemStore).state, isNotNull, reason: 'gleich gespeichert');

    // Alte, unverschlüsselte Sicherung geht weiter.
    final klar = (await a.sicherungErstellen())!;
    expect(a.sicherungBrauchtPasswort(klar), isFalse);
    final c = AppState(MemStore());
    await c.laden();
    await c.sicherungLaden(klar);
    expect(c.taper.s!.name, 'Test');

    await expectLater(c.sicherungLaden('{"quatsch":1}'),
        throwsA(isA<SicherungException>().having((e) => e.fehler, 'f', SicherungFehler.kaputt)));
    expect(c.taper.s!.name, 'Test');
  });
}
