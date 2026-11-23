import 'i18n/txt.dart';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'i18n/meldungen.dart';
import 'plan_kopf.dart';

/// Dateien teilen und öffnen. Eine Schnittstelle, damit Tests ohne Android laufen.
abstract class Dateien {
  /// Legt [inhalt] als Datei [name] ab und öffnet das Teilen-Menü (Messenger, Mail, Ordner …).
  Future<void> teilen(String name, String inhalt);

  /// Wie [teilen], für fertige Bytes (z. B. das Arzt-PDF).
  Future<void> teilenBytes(String name, List<int> bytes, String mime);

  /// Lässt eine Datei auswählen und gibt ihren Text zurück (null = abgebrochen).
  Future<String?> oeffnen();

  /// Lässt eine Datei auswählen und gibt Name und Inhalt zurück (null = abgebrochen).
  Future<({String name, List<int> bytes})?> dateiWaehlen();
}

class SystemDateien implements Dateien {
  @override
  Future<void> teilen(String name, String inhalt) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsString(inhalt, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')], subject: name));
  }

  @override
  Future<void> teilenBytes(String name, List<int> bytes, String mime) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: mime)], subject: name));
  }

  @override
  Future<({String name, List<int> bytes})?> dateiWaehlen() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null) return null;
    final n = await f.length();
    if (n != null && n > 20 * 1024 * 1024) throw LeseFehlerGross();
    return (name: f.name, bytes: await f.readAsBytes());
  }

  @override
  Future<String?> oeffnen() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null) return null;
    // Sicherungen sind klein; riesige Dateien gar nicht erst einlesen.
    final n = await f.length();
    if (n != null && n > 20 * 1024 * 1024) throw SicherungException(SicherungFehler.kaputt);
    final b = await f.readAsBytes();
    try {
      return utf8.decode(b);
    } catch (_) {
      throw SicherungException(SicherungFehler.kaputt);
    }
  }
}

String _zwei(int n) => n.toString().padLeft(2, '0');

/// Dateiname mit Datum, z. B. `benzotaper-2026-11-18.json`.
String sicherungDateiname(DateTime d) => 'benzotaper-${d.year}-${_zwei(d.month)}-${_zwei(d.day)}.json';

// ---------------------------------------------------------------------------
// Speichern

class SicherungSpeichernSeite extends StatefulWidget {
  const SicherungSpeichernSeite({super.key, required this.app, required this.dateien});
  final AppState app;
  final Dateien dateien;
  @override
  State<SicherungSpeichernSeite> createState() => _SicherungSpeichernSeiteState();
}

class _SicherungSpeichernSeiteState extends State<SicherungSpeichernSeite> {
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _ohne = false;
  bool _zeigen = false;
  bool _laeuft = false;
  String? _fehler;

  @override
  void dispose() {
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _los() async {
    setState(() => _fehler = null);
    if (!_ohne) {
      if (_pw1.text.length < minPasswortLaenge) {
        setState(() => _fehler = tr('Mindestens $minPasswortLaenge Zeichen.', 'At least $minPasswortLaenge characters.'));
        return;
      }
      if (_pw1.text != _pw2.text) {
        setState(() => _fehler = tr('Die Passwörter stimmen nicht überein.', 'The passwords do not match.'));
        return;
      }
    }
    setState(() => _laeuft = true);
    try {
      final text = await widget.app.sicherungErstellen(passwort: _ohne ? null : _pw1.text);
      if (text == null) return;
      await widget.dateien.teilen(sicherungDateiname(widget.app.taper.clock()), text);
      widget.app.sicherungGemacht();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _fehler = tr('Sicherung konnte nicht erstellt werden.', 'The backup could not be created.'));
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sicherung speichern', 'Save backup'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Die Sicherung ist eine Datei mit deinem Plan, Kalender und Tagebuch. '
            'Du kannst sie per Messenger oder Mail verschicken oder in einem Ordner ablegen.', 'The backup is a file with your plan, calendar and diary. You can send it by messenger or mail or put it in a folder.')),
        const SizedBox(height: 16),
        if (!_ohne) ...[
          TextField(
            key: const Key('pw1'),
            controller: _pw1,
            obscureText: !_zeigen,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: tr('Passwort für die Sicherung', 'Backup password'),
              helperText: tr('Mindestens $minPasswortLaenge Zeichen. Nicht deine PIN.', 'At least $minPasswortLaenge characters. Not your PIN.'),
              suffixIcon: IconButton(
                tooltip: _zeigen ? tr('Verbergen', 'Hide') : tr('Anzeigen', 'Show'),
                icon: Icon(_zeigen ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _zeigen = !_zeigen),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pw2'),
            controller: _pw2,
            obscureText: !_zeigen,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: tr('Passwort wiederholen', 'Repeat password')),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.key_outlined, color: th.colorScheme.tertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr('Merk dir das Passwort gut. Ohne Passwort kommt niemand an die Daten – '
                      'auch du nicht. Passwort vergessen = Sicherung weg.', 'Remember the password well. Without it nobody can get at the data – not even you. Password forgotten = backup lost.')),
                ),
              ]),
            ),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Ohne Passwort speichern', 'Save without password')),
          value: _ohne,
          onChanged: _laeuft ? null : (v) => setState(() => _ohne = v),
        ),
        if (_ohne)
          Card(
            color: th.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                tr('Dann kann jeder, der die Datei bekommt, deinen Plan und dein Tagebuch lesen. '
                'Sinnvoll z. B., wenn du sie deinem Arzt geben willst.', 'Then anyone who gets the file can read your plan and diary. Useful, for example, if you want to give it to your doctor.'),
                style: TextStyle(color: th.colorScheme.onErrorContainer),
              ),
            ),
          ),
        if (_fehler != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_fehler!, style: TextStyle(color: th.colorScheme.error)),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _laeuft ? null : _los,
          icon: _laeuft
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share_outlined),
          label: Text(_laeuft ? tr('Wird verschlüsselt …', 'Encrypting …') : tr('Sicherung erstellen und teilen', 'Create and share backup')),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Laden

/// Ablauf „Sicherung laden“: Datei wählen → (ggf. bestätigen, dass der Stand ersetzt wird)
/// → (ggf. Passwort) → einspielen. Gibt true zurück, wenn geladen wurde.
Future<bool> sicherungLadenAblauf(BuildContext context, AppState app, Dateien dateien) async {
  final messenger = ScaffoldMessenger.of(context);
  final String? text;
  try {
    text = await dateien.oeffnen();
  } on SicherungException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(sicherungFehlerText(e.fehler))));
    return false;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Datei konnte nicht geöffnet werden.', 'The file could not be opened.'))));
    return false;
  }
  if (text == null || !context.mounted) return false;

  // Erst prüfen, ob die Datei überhaupt eine Sicherung ist – dann erst fragen, ob ersetzt werden soll.
  final vorab = sicherungVorpruefen(text);
  if (vorab != null) {
    messenger.showSnackBar(SnackBar(content: Text(sicherungFehlerText(vorab))));
    return false;
  }

  if (app.eingerichtet) {
    final ok = await sicherungLadenSicherFragen(context);
    if (!ok || !context.mounted) return false;
  }

  if (app.sicherungBrauchtPasswort(text)) {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PasswortDialog(app: app, text: text!),
    );
    if (ok != true) return false;
  } else {
    try {
      await app.sicherungLaden(text);
    } on SicherungException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(sicherungFehlerText(e.fehler))));
      return false;
    }
  }
  messenger.showSnackBar(SnackBar(content: Text(tr('Sicherung geladen.', 'Backup loaded.'))));
  return true;
}

class _PasswortDialog extends StatefulWidget {
  const _PasswortDialog({required this.app, required this.text});
  final AppState app;
  final String text;
  @override
  State<_PasswortDialog> createState() => _PasswortDialogState();
}

class _PasswortDialogState extends State<_PasswortDialog> {
  final _pw = TextEditingController();
  bool _laeuft = false;
  bool _zeigen = false;
  String? _fehler;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _los() async {
    setState(() {
      _laeuft = true;
      _fehler = null;
    });
    try {
      await widget.app.sicherungLaden(widget.text, passwort: _pw.text);
      if (mounted) Navigator.pop(context, true);
    } on SicherungException catch (e) {
      if (mounted) setState(() => _fehler = sicherungFehlerText(e.fehler));
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Passwort für die Sicherung', 'Backup password')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const Key('pwLaden'),
            controller: _pw,
            autofocus: true,
            obscureText: !_zeigen,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_laeuft,
            onSubmitted: (_) => _laeuft ? null : _los(),
            decoration: InputDecoration(
              labelText: tr('Passwort', 'Password'),
              errorText: _fehler,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: _zeigen ? tr('Verbergen', 'Hide') : tr('Anzeigen', 'Show'),
                icon: Icon(_zeigen ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _zeigen = !_zeigen),
              ),
            ),
          ),
          if (_laeuft) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
        ]),
        actions: [
          TextButton(onPressed: _laeuft ? null : () => Navigator.pop(context, false), child: Text(tr('Abbrechen', 'Cancel'))),
          FilledButton(onPressed: _laeuft ? null : _los, child: Text(tr('Laden', 'Load'))),
        ],
      );
}

/// Datei zu groß für einen Plan oder eine Sicherung.
class LeseFehlerGross implements Exception {}
