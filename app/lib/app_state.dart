import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:tapering_core/tapering_core.dart';

import 'beispiel.dart';
import 'erinnerung.dart';
import 'i18n/meldungen.dart';
import 'i18n/txt.dart';
import 'notizbuch.dart';
import 'sicherung.dart';
import 'store.dart';

/// Verbindet den Kern ([Taper]) mit der Oberfläche und der Ablage.
/// Die Oberfläche ruft nur [taper] auf und danach [aenderung]; Rechenregeln liegen im Kern.
class AppState extends ChangeNotifier {
  AppState(this.store, {Clock? clock, Dateien? dateien, Erinnerer? erinnerer})
      : taper = Taper(clock: clock),
        dateien = dateien ?? SystemDateien(),
        erinnerer = erinnerer ?? SystemErinnerer();

  /// Benachrichtigungen (in Tests ersetzt).
  final Erinnerer erinnerer;

  final Store store;

  /// Teilen/Öffnen von Sicherungsdateien (in Tests ersetzt).
  final Dateien dateien;
  final Taper taper;

  /// Reiter-Wechsel von Unterseiten aus (z. B. runder Kalender-Knopf in „Mehr“). Die Shell hört zu.
  final reiterWunsch = ValueNotifier<int?>(null);

  /// Zählt hoch, wenn der ganze Stand ersetzt wurde (Sicherung geladen). Die Oberfläche baut sich
  /// dann frisch auf, damit keine Eingabefelder alte Werte zeigen.
  int stand = 0;

  /// Beispielplan zum Umschauen (nur im Speicher, nie gespeichert). Solange er angezeigt wird,
  /// ist [beispiel] wahr; jeder eigene Plan oder eine geladene Sicherung ersetzt ihn.
  TaperState? _beispiel;
  bool get beispiel => taper.s != null && identical(taper.s, _beispiel);

  void beispielLaden() {
    _beispiel = TaperState.fromJson(beispielJson(ymd(taper.clock())));
    taper.s = _beispiel;
    if (taper.s != null) taper.refresh();
  }

  /// Beispiel ausblenden (vor „Neuen Plan erstellen“), damit der eigene Plan als erster Plan zählt.
  void beispielWeg() {
    if (beispiel) taper.s = null;
  }

  bool bereit = false;
  bool hinweisGesehen = false;

  /// Nur für Tests: Sprache, die gilt, wenn noch keine gewählt wurde (überspringt die Sprachwahl).
  static String? spracheStandard;

  /// Gewählte Sprache `'de'` / `'en'`; `null` = beim ersten Start noch nicht gewählt.
  /// Liegt in der Einstellungen-Datei (nicht in der Sicherung) und überlebt „Zurücksetzen“.
  String? sprache;

  /// Ändert sich bei jedem Sprachwechsel; die App baut sich dann komplett neu auf.
  final spracheNotifier = ValueNotifier<String?>(null);

  Future<void> spracheWaehlen(String code) async {
    sprache = code == 'en' ? 'en' : 'de';
    Txt.setzen(sprache);
    spracheNotifier.value = sprache;
    await _einstellungenSchreiben();
    _erinnerungenPlanen();
    notifyListeners();
  }
  bool _speichernLaeuft = false;
  String? _nochZuSchreiben;
  bool _schreibenOffen = false;

  /// Fehler beim Öffnen der gespeicherten Daten (z. B. App-Ordner nicht erreichbar). Dann zeigt die App
  /// eine Fehlerseite statt ewig am Logo zu hängen; gespeichert wird nichts, bis es klappt.
  String? ladeFehler;

  Future<void> laden() async {
    try {
      await _laden();
      ladeFehler = null;
    } catch (e) {
      ladeFehler = '$e';
    }
    bereit = true;
    notifyListeners();
  }

  Future<void> _laden() async {
    hinweisGesehen = await store.discSeen();
    try {
      final e = await store.readEinstellungen();
      if (e != null) {
        final j = jsonDecode(e);
        erinnerung = ErinnerungEinstellung.fromJson(j);
        if (j is Map && j['lobWeg'] is String) lobWeg = j['lobWeg'] as String;
        if (j is Map && (j['lang'] == 'de' || j['lang'] == 'en')) sprache = j['lang'] as String;
        if (j is Map && j['vp'] is bool) vorratPush = j['vp'] as bool;
        if (j is Map && j['vpq'] == true) _vpGefragt = true;
        if (j is Map && sperrZeiten.contains(j['sperrMin'])) sperrMinuten = j['sperrMin'] as int;
      }
    } catch (_) {}
    try {
      final n = await store.readNotizbuch();
      notizbuch = n == null ? [] : NotizbuchEintrag.liste(jsonDecode(n));
    } catch (_) {
      notizbuch = [];
    }
    final raw = await store.readState();
    taper.s = null;
    if (raw != null) {
      try {
        final st = TaperState.fromJson(jsonDecode(raw));
        if (st != null) taper.s = st;
      } catch (_) {}
    }
    taper.onSave = _speichern;
    if (taper.s != null) {
      taper.refresh();
    } else {
      beispielLaden();
    }
    // Wer schon vor der Sprachwahl installiert hatte (nur Deutsch), bleibt bei Deutsch.
    sprache ??= hinweisGesehen ? 'de' : spracheStandard;
    Txt.setzen(sprache);
    spracheNotifier.value = sprache;
    gesperrt = hatPin; // beim Öffnen gesperrt
  }

  // ===== Allgemeines Notizbuch =====

  /// Neueste zuerst.
  List<NotizbuchEintrag> notizbuch = [];

  void _notizbuchSpeichern() {
    store.writeNotizbuch(jsonEncode([for (final e in notizbuch) e.toJson()]));
    notifyListeners();
  }

  /// Neu ([id] == null) oder ändern. Leerer Text löscht.
  void notizSchreiben(String text, {int? id}) {
    final t = text.trim();
    final jetzt = taper.clock().millisecondsSinceEpoch;
    if (id != null) {
      final i = notizbuch.indexWhere((e) => e.id == id);
      if (i < 0) return;
      if (t.isEmpty) {
        notizbuch.removeAt(i);
      } else {
        notizbuch[i] = NotizbuchEintrag(id, t, jetzt);
      }
    } else {
      if (t.isEmpty) return;
      notizbuch.insert(0, NotizbuchEintrag(jetzt, t, jetzt));
    }
    _notizbuchSpeichern();
  }

  void notizLoeschen(int id) {
    notizbuch.removeWhere((e) => e.id == id);
    _notizbuchSpeichern();
  }

  // ===== Erinnerung zum Eintragen (optional, standardmäßig aus) =====

  ErinnerungEinstellung erinnerung = const ErinnerungEinstellung();
  String _geplant = '';

  /// Einschalten fragt nach der Erlaubnis. `false`, wenn sie verweigert wurde (dann bleibt es aus).
  Future<bool> erinnerungSetzen(ErinnerungEinstellung e) async {
    if (e.an && !erinnerung.an && !await erinnerer.erlaubnis()) return false;
    erinnerung = e;
    await _einstellungenSchreiben();
    notifyListeners();
    return true;
  }

  /// Vorrat-Push: an, sobald ein Vorrat eingetragen ist; in „Mehr“ abschaltbar.
  bool vorratPush = true;

  /// Schon einmal nach der Erlaubnis für den Vorrat-Hinweis gefragt?
  bool _vpGefragt = false;

  /// Ein-/Ausschalten. Einschalten fragt nach der Erlaubnis; verweigert → bleibt aus, `false`.
  Future<bool> vorratPushSetzen(bool an) async {
    if (an) _vpGefragt = true;
    if (an && !await erinnerer.erlaubnis()) {
      vorratPush = false;
      await _einstellungenSchreiben();
      notifyListeners();
      return false;
    }
    vorratPush = an;
    await _einstellungenSchreiben();
    notifyListeners();
    return true;
  }

  /// Nach dem Speichern eines Vorrats: Erlaubnis holen (Android fragt nur, solange nicht entschieden).
  /// Verweigert → Vorrat-Push aus.
  Future<void> vorratGespeichert() async {
    if (!vorratPush) return;
    bool ok;
    try {
      ok = await erinnerer.erlaubnis();
    } catch (_) {
      return; // Plattform nicht erreichbar (z. B. in Tests): nichts ändern
    }
    final vorher = _vpGefragt;
    _vpGefragt = true;
    if (!ok) vorratPush = false;
    if (!ok || !vorher) {
      await _einstellungenSchreiben();
      notifyListeners();
    }
  }

  /// Einmalig nachfragen, wenn schon ein Vorrat eingetragen ist, aber noch nie gefragt wurde,
  /// etwa nach dem Update von einer Version ohne Vorrat-Hinweis oder nach „Sicherung laden“
  /// auf einem neuen Handy. Sonst stünde der Schalter auf „an“, Android zeigte aber nichts.
  Future<void> vorratErlaubnisEinmal() async {
    if (_vpGefragt || !vorratPush || !eingerichtet || taper.st.stock == null) return;
    await vorratGespeichert();
  }

  /// Einstellungen-Datei: Erinnerung, Vorrat-Push + zuletzt weggetipptes Lob.
  Future<void> _einstellungenSchreiben() => store.writeEinstellungen(jsonEncode(
      {
        ...erinnerung.toJson(),
        'vp': vorratPush,
        if (_vpGefragt) 'vpq': true,
        if (lobWeg != null) 'lobWeg': lobWeg,
        if (sprache != null) 'lang': sprache,
        'sperrMin': sperrMinuten,
      }));

  // ===== Lob beim Halten (lob.dart) =====

  /// Schlüssel „Halten-Beginn|Tag“ des zuletzt weggetippten Lobs.
  String? lobWeg;

  void lobWegtippen(String schluessel) {
    lobWeg = schluessel;
    _einstellungenSchreiben();
    notifyListeners();
  }

  /// Plant die Erinnerungen neu, wenn sich etwas geändert hat (nach jeder Änderung aufgerufen).
  void _erinnerungenPlanen() {
    final z = erinnerungZeiten(this, erinnerung);
    final v = vorratPushZeiten(this);
    final k = '${Txt.code}|${z.map((d) => d.toIso8601String()).join(',')}|${v.join(',')}';
    if (k == _geplant) return;
    // Beim allerersten Mal ohne Erinnerungen nichts anfassen (sonst Plattformaufruf in jedem Test).
    if (_geplant.isEmpty && z.isEmpty && v.isEmpty && !erinnerung.an) return;
    _geplant = k;
    erinnerer.planen(z, vorrat: v).catchError((_) {});
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (bereit) _erinnerungenPlanen();
  }

  void _speichern(TaperState? s) {
    if (s != null && identical(s, _beispiel)) return; // Beispiel wird nie gespeichert
    _nochZuSchreiben = s == null ? '' : jsonEncode(s.toJson());
    _schreibenOffen = true;
    if (!_speichernLaeuft) _schreibeSchleife();
  }

  Future<void> _schreibeSchleife() async {
    _speichernLaeuft = true;
    while (_schreibenOffen) {
      _schreibenOffen = false;
      final j = _nochZuSchreiben;
      await store.writeState(j == null || j.isEmpty ? null : j);
    }
    _speichernLaeuft = false;
  }

  /// Nach jeder Änderung am Kern aufrufen.
  void aenderung() => notifyListeners();

  /// Beim Zurückkehren in die App oder nach Mitternacht.
  void auffrischen() {
    if (taper.s != null) taper.refresh();
    notifyListeners();
  }

  Future<void> hinweisBestaetigt() async {
    hinweisGesehen = true;
    await store.setDiscSeen();
    notifyListeners();
  }

  // ===== PIN-Sperre =====

  /// Sperrbildschirm liegt über allem.
  bool gesperrt = false;
  bool get hatPin => eingerichtet && taper.s!.pin != null;
  DateTime? _hintergrundSeit;

  bool entsperren(String pin) {
    if (!taper.checkPin(pin)) return false;
    gesperrt = false;
    notifyListeners();
    return true;
  }

  void sperren() {
    if (!hatPin) return;
    gesperrt = true;
    notifyListeners();
  }

  /// Gibt einen Fehlertext zurück, sonst `null` (dann ist die PIN gespeichert).
  String? pinSetzen(String a, String b) {
    if (!eingerichtet) return tr('Erst einen eigenen Plan anlegen.', 'Create your own plan first.');
    final f = taper.setPin(a, b);
    if (f == null) notifyListeners();
    return f == null ? null : meldungText(f);
  }

  void pinAus() {
    if (!eingerichtet) return;
    taper.clearPin();
    gesperrt = false;
    notifyListeners();
  }

  /// Wählbare Sperrzeiten in Minuten.
  static const sperrZeiten = [2, 5, 10, 30];

  /// Nach so vielen Minuten im Hintergrund wird wieder gesperrt (Einstellungen-Datei).
  int sperrMinuten = 2;

  Future<void> sperrZeitSetzen(int min) async {
    if (!sperrZeiten.contains(min)) return;
    sperrMinuten = min;
    notifyListeners();
    await _einstellungenSchreiben();
  }

  /// App geht in den Hintergrund / kommt zurück: nach mehr als [sperrMinuten] wieder sperren.
  void hintergrund() => _hintergrundSeit ??= taper.clock();
  void vordergrund() {
    final seit = _hintergrundSeit;
    _hintergrundSeit = null;
    if (seit != null && hatPin && taper.clock().difference(seit) > Duration(minutes: sperrMinuten)) gesperrt = true;
    auffrischen();
  }

  /// „PIN vergessen? → Alles löschen“: Stand weg, danach wieder das Beispiel.
  void allesLoeschen() {
    taper.wipe();
    gesperrt = false;
    erinnerung = const ErinnerungEinstellung();
    vorratPush = true;
    _vpGefragt = false;
    lobWeg = null;
    _einstellungenSchreiben();
    notizbuch = [];
    store.writeNotizbuch('[]');
    beispielLaden();
    stand++;
    notifyListeners();
  }

  /// Gibt es einen eigenen Plan? (Der Beispielplan zählt nicht.)
  bool get eingerichtet => taper.s != null && !beispiel;

  /// Sicherung als Text für die Datei. Mit [passwort] verschlüsselt (Argon2id + AES-256-GCM),
  /// ohne Passwort als altes Klartext-JSON. Die Schlüsselrechnung läuft in einem eigenen Isolate,
  /// damit die Oberfläche währenddessen nicht hängt.
  Future<String?> sicherungErstellen({String? passwort}) async {
    final j = taper.exportJson();
    if (j == null) return null;
    // Notizbuch kommt mit in die Sicherung (eigener Schlüssel).
    final klar = jsonEncode({
      ...j,
      if (notizbuch.isNotEmpty) 'notizbuch': [for (final e in notizbuch) e.toJson()]
    });
    if (passwort == null || passwort.isEmpty) return klar;
    return Isolate.run(() => sicherungVerschluesseln(klar, passwort));
  }

  /// Braucht diese Datei ein Passwort? (Vor dem Import fragen.)
  bool sicherungBrauchtPasswort(String text) => istVerschluesselt(text);

  /// Spielt eine Sicherung ein (verschlüsselt oder alt/unverschlüsselt).
  /// Wirft [SicherungException] (Passwort falsch, kaputt, zu neu).
  /// Bei Erfolg ist der alte Stand ersetzt und gespeichert.
  Future<void> sicherungLaden(String text, {String? passwort}) async {
    var klar = text;
    if (istVerschluesselt(text)) {
      final pw = passwort ?? '';
      klar = await Isolate.run(() => sicherungEntschluesseln(text, pw));
    }
    Object? o;
    try {
      o = jsonDecode(klar);
    } catch (_) {
      throw SicherungException(SicherungFehler.kaputt);
    }
    if (!taper.importJson(o)) throw SicherungException(SicherungFehler.kaputt);
    if (o is Map && o['notizbuch'] != null) {
      notizbuch = NotizbuchEintrag.liste(o['notizbuch']);
      store.writeNotizbuch(jsonEncode([for (final e in notizbuch) e.toJson()]));
    }
    gesperrt = false; // nach dem Laden entsperrt
    stand++;
    notifyListeners();
    vorratErlaubnisEinmal();
  }
}
