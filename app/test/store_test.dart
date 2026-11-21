// Echte Ablage auf dem Gerät (FileStore) – bisher liefen alle Tests nur mit MemStore.
// Prüft Hin und zurück, Löschen, getrennte Dateien, atomares Schreiben (keine .tmp-Reste) und viele
// gleichzeitige Schreibvorgänge (früher: dieselbe .tmp-Datei, zweites Umbenennen ins Leere).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_core/tapering_core.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('tb_store_'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> dateien() => dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  test('Stand, Einstellungen, Notizbuch, Hinweis: hin und zurück, getrennt, ohne .tmp-Reste', () async {
    final st = FileStore(dir);
    expect(await st.readState(), isNull);
    expect(await st.discSeen(), isFalse);
    await st.writeState('{"a":"Ärger – ü"}');
    await st.writeEinstellungen('{"an":true}');
    await st.writeNotizbuch('[1]');
    await st.setDiscSeen();
    final neu = FileStore(dir); // wie nach einem Neustart
    expect(await neu.readState(), '{"a":"Ärger – ü"}');
    expect(await neu.readEinstellungen(), '{"an":true}');
    expect(await neu.readNotizbuch(), '[1]');
    expect(await neu.discSeen(), isTrue);
    expect(dateien().where((n) => n.endsWith('.tmp')), isEmpty);
    await neu.writeState(null);
    expect(await neu.readState(), isNull);
    expect(await neu.discSeen(), isTrue, reason: 'Hinweis bleibt (überlebt Zurücksetzen)');
    await neu.writeState(null); // zweimal löschen geht auch
  });

  test('Viele gleichzeitige Schreibvorgänge: kein Fehler, der letzte gewinnt', () async {
    final st = FileStore(dir);
    await Future.wait([
      for (var i = 0; i < 40; i++) ...[
        st.writeEinstellungen('{"i":$i}'),
        st.writeNotizbuch('[$i]'),
        st.writeState('{"s":$i}'),
      ]
    ]);
    expect(await st.readEinstellungen(), '{"i":39}');
    expect(await st.readNotizbuch(), '[39]');
    expect(await st.readState(), '{"s":39}');
    expect(dateien().where((n) => n.endsWith('.tmp')), isEmpty);
  });

  test('Liegengebliebene .tmp-Datei (Absturz beim Schreiben) stört nicht', () async {
    final st = FileStore(dir);
    await st.writeState('{"alt":1}');
    File('${dir.path}/strike-v1.json.tmp').writeAsStringSync('{"halb');
    expect(await FileStore(dir).readState(), '{"alt":1}', reason: 'alter Stand bleibt lesbar');
    await st.writeState('{"neu":2}');
    expect(await FileStore(dir).readState(), '{"neu":2}');
  });

  test('AppState mit echter Ablage: Plan + Einstellungen überleben den Neustart', () async {
    final uhr = DateTime.utc(2026, 3, 10, 12);
    final a1 = AppState(FileStore(dir), clock: () => uhr);
    await a1.laden();
    expect(a1.beispiel, isTrue, reason: 'ohne Stand: Beispiel');
    a1.beispielWeg();
    expect(a1.taper.setup(dose: 10, step: 1, minStep: .5, days: 14, goal: 0), isNull);
    a1.taper.addIntake(10, force: true);
    a1.taper.setStock(30, 5);
    a1.aenderung();
    await a1.vorratPushSetzen(false); // Plattform wird hier nicht gebraucht (nur beim Einschalten)
    // Schreibschleife zu Ende laufen lassen
    for (var i = 0; i < 50 && !File('${dir.path}/strike-v1.json').existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final a2 = AppState(FileStore(dir), clock: () => uhr);
    await a2.laden();
    expect(a2.eingerichtet, isTrue);
    expect(jsonEncode(a2.taper.exportJson()), jsonEncode(a1.taper.exportJson()));
    expect(a2.taper.stockInfo()!.rem, 150, reason: 'Einnahme vor dem Zählen zieht nicht ab');
    expect(a2.vorratPush, isFalse);
    expect(a2.taper.voraussichtlichesEnde(), a1.taper.voraussichtlichesEnde());
    expect(TaperState.fromJson(jsonDecode(File('${dir.path}/strike-v1.json').readAsStringSync())), isNotNull);
  });
}
