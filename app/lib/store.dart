import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Ablage der Daten. Eine Schnittstelle, damit Tests ohne Dateisystem laufen.
abstract class Store {
  Future<String?> readState();
  Future<void> writeState(String? json);
  Future<bool> discSeen();
  Future<void> setDiscSeen();

  /// Einstellungen (Erinnerung), getrennt vom Stand.
  Future<String?> readEinstellungen();
  Future<void> writeEinstellungen(String json);

  /// Allgemeines Notizbuch (tagesunabhängig), getrennt vom Stand.
  Future<String?> readNotizbuch();
  Future<void> writeNotizbuch(String json);
}

/// Speichert in einer JSON-Datei im App-Ordner. Schreiben atomar (erst .tmp, dann umbenennen),
/// damit ein Absturz mitten im Schreiben nie den alten Stand zerstört.
class FileStore implements Store {
  FileStore([this._dir]);
  Directory? _dir;

  /// Schreibvorgänge je Datei nacheinander: Zwei schnelle Änderungen hätten sonst
  /// gleichzeitig dieselbe .tmp-Datei beschrieben; das zweite Umbenennen wäre ins Leere gelaufen.
  final _warteschlange = <String, Future<void>>{};
  Future<void> _nacheinander(String name, Future<void> Function() f) {
    final weiter = (_warteschlange[name] ?? Future<void>.value()).catchError((_) {}).then((_) => f());
    _warteschlange[name] = weiter;
    return weiter;
  }

  Future<Directory> _d() async => _dir ??= await getApplicationDocumentsDirectory();

  @override
  Future<String?> readState() async {
    final f = File('${(await _d()).path}/strike-v1.json');
    if (await f.exists()) return utf8.decode(await f.readAsBytes());
    return null;
  }

  @override
  Future<void> writeState(String? json) => _nacheinander('strike-v1.json', () => _writeState(json));

  Future<void> _writeState(String? json) async {
    final dir = await _d();
    final f = File('${dir.path}/strike-v1.json');
    if (json == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    final tmp = File('${dir.path}/strike-v1.json.tmp');
    await tmp.writeAsBytes(utf8.encode(json), flush: true);
    await tmp.rename(f.path);
  }

  // Hinweis-Bestätigung liegt getrennt vom Stand: „Alles löschen“ fragt den Disclaimer nicht neu ab.
  @override
  Future<bool> discSeen() async => File('${(await _d()).path}/strike-disc').exists();

  @override
  Future<void> setDiscSeen() async {
    await File('${(await _d()).path}/strike-disc').writeAsString('1', flush: true);
  }

  @override
  Future<String?> readEinstellungen() async {
    final f = File('${(await _d()).path}/einstellungen.json');
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> writeEinstellungen(String json) => _schreibe('einstellungen.json', json);

  @override
  Future<String?> readNotizbuch() async {
    final f = File('${(await _d()).path}/notizbuch.json');
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> writeNotizbuch(String json) => _schreibe('notizbuch.json', json);

  Future<void> _schreibe(String name, String json) => _nacheinander(name, () => _schreibeJetzt(name, json));

  Future<void> _schreibeJetzt(String name, String json) async {
    final dir = await _d();
    final tmp = File('${dir.path}/$name.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename('${dir.path}/$name');
  }
}

/// Nur im Speicher (Tests).
class MemStore implements Store {
  String? state;
  bool disc = false;
  @override
  Future<String?> readState() async => state;
  @override
  Future<void> writeState(String? json) async => state = json;
  @override
  Future<bool> discSeen() async => disc;
  @override
  Future<void> setDiscSeen() async => disc = true;
  String? einstellungen;
  @override
  Future<String?> readEinstellungen() async => einstellungen;
  @override
  Future<void> writeEinstellungen(String json) async => einstellungen = json;
  String? notizbuch;
  @override
  Future<String?> readNotizbuch() async => notizbuch;
  @override
  Future<void> writeNotizbuch(String json) async => notizbuch = json;
}
