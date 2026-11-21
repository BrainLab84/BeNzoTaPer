// Allgemeines Notizbuch, unabhängig vom Kalender, für Gedanken, Überlegungen und Alltag. Eigene Datei, kommt mit in die Sicherung,
// „Alles löschen“ leert es. Erreichbar über den Knopf oben links.
import 'i18n/txt.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'bausteine.dart';

class NotizbuchEintrag {
  const NotizbuchEintrag(this.id, this.text, this.geaendert);

  /// Erstellt (ms seit 1970), dient als Kennung.
  final int id;
  final String text;
  final int geaendert;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'g': geaendert};

  static List<NotizbuchEintrag> liste(Object? j) => [
        if (j is List)
          for (final e in j)
            if (e is Map && e['id'] is int && e['text'] is String && (e['text'] as String).trim().isNotEmpty)
              NotizbuchEintrag(e['id'] as int, e['text'] as String, e['g'] is int ? e['g'] as int : e['id'] as int),
      ];
}

String get notizbuchHinweis => tr('Für Gedanken, Überlegungen und Alltag – unabhängig vom Kalender.', 'For thoughts, reflections and everyday life – independent of the calendar.');

String _wann(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '${datum(k)}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Notizbuch: oben „+ Neue Notiz“ → neues Blöckchen zum Schreiben, „Speichern“ schreibt es fest.
/// Gespeicherte Notizen stehen als Blöckchen untereinander (neueste oben). Antippen = öffnen zum Lesen,
/// dort „Bearbeiten“ → ändern → „Speichern“.
class NotizbuchSeite extends StatefulWidget {
  const NotizbuchSeite({super.key, required this.app});
  final AppState app;
  @override
  State<NotizbuchSeite> createState() => _NotizbuchSeiteState();
}

class _NotizbuchSeiteState extends State<NotizbuchSeite> {
  final _neu = TextEditingController();
  bool _schreibt = false;

  @override
  void dispose() {
    _neu.dispose();
    super.dispose();
  }

  void _speichern() {
    if (_neu.text.trim().isEmpty) return;
    widget.app.notizSchreiben(_neu.text);
    setState(() {
      _neu.clear();
      _schreibt = false;
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Notizbuch', 'Notebook'))),
        body: ListenableBuilder(
          listenable: widget.app,
          builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 10), child: Sub(notizbuchHinweis)),
            if (!_schreibt)
              hauptKnopf(tr('Neue Notiz', 'New note'), () => setState(() => _schreibt = true),
                  icon: Icons.add, key: const Key('notizbuchNeueNotiz')),
            if (_schreibt)
              Karte(key: const Key('notizbuchNeuBlock'), children: [
                TextField(
                  key: const Key('notizbuchNeu'),
                  controller: _neu,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: feldStil(hinweis: tr('Was geht dir durch den Kopf?', 'What is on your mind?')),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: knopf(tr('Abbrechen', 'Cancel'), () {
                      setState(() {
                        _neu.clear();
                        _schreibt = false;
                      });
                      FocusScope.of(context).unfocus();
                    }, key: const Key('notizbuchAbbrechen')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: hauptKnopf(tr('Speichern', 'Save'), _neu.text.trim().isEmpty ? null : _speichern,
                        icon: Icons.check, key: const Key('notizbuchSpeichern'), blatt: false),
                  ),
                ]),
              ]),
            const SizedBox(height: 4),
            if (widget.app.notizbuch.isEmpty && !_schreibt)
              Padding(padding: EdgeInsets.only(top: 12), child: Center(child: Sub(tr('Noch keine Notizen.', 'No notes yet.')))),
            for (final e in widget.app.notizbuch)
              Karte(key: ValueKey('notiz-${e.id}'), children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => NotizSeite(app: widget.app, id: e.id))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(_wann(e.geaendert), style: const TextStyle(color: F.mu, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(e.text, maxLines: 4, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
          ]),
        ),
      );
}

/// Eine Notiz geöffnet: zuerst nur lesen, „Bearbeiten“ → ändern → „Speichern“ (dann wieder lesen).
class NotizSeite extends StatefulWidget {
  const NotizSeite({super.key, required this.app, required this.id});
  final AppState app;
  final int id;
  @override
  State<NotizSeite> createState() => _NotizSeiteState();
}

class _NotizSeiteState extends State<NotizSeite> {
  final _t = TextEditingController();
  bool _bearbeiten = false;
  bool _loeschenFragen = false;

  NotizbuchEintrag? get _e {
    for (final e in widget.app.notizbuch) {
      if (e.id == widget.id) return e;
    }
    return null;
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = _e;
    if (e == null) return Scaffold(appBar: AppBar(title: Text(tr('Notiz', 'Note'))));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Notiz', 'Note'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Sub(tr('Erstellt ${_wann(e.id)}${e.geaendert != e.id ? ' · geändert ${_wann(e.geaendert)}' : ''}', 'Created ${_wann(e.id)}${e.geaendert != e.id ? " · edited ${_wann(e.geaendert)}" : ""}')),
        const SizedBox(height: 8),
        if (!_bearbeiten) ...[
          Karte(key: const Key('notizbuchLesen'), children: [
            SelectableText(e.text, style: const TextStyle(fontSize: 16, height: 1.4)),
          ]),
          hauptKnopf(tr('Bearbeiten', 'Edit'), () {
            _t.text = e.text;
            setState(() {
              _bearbeiten = true;
              _loeschenFragen = false;
            });
          }, icon: Icons.edit_outlined, key: const Key('notizbuchBearbeiten')),
          const SizedBox(height: 8),
          knopf(_loeschenFragen ? tr('Wirklich löschen?', 'Really delete?') : tr('Löschen', 'Delete'), () {
            if (!_loeschenFragen) {
              setState(() => _loeschenFragen = true);
              return;
            }
            widget.app.notizLoeschen(e.id);
            Navigator.of(context).pop();
          }, hinten: F.bads, vorne: const Color(0xFFF0A7A4), rand: F.bad, key: const Key('notizbuchLoeschen')),
        ] else ...[
          TextField(
            key: const Key('notizbuchText'),
            controller: _t,
            autofocus: true,
            minLines: 6,
            maxLines: 20,
            textCapitalization: TextCapitalization.sentences,
            decoration: feldStil(),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: knopf(tr('Abbrechen', 'Cancel'), () => setState(() => _bearbeiten = false))),
            const SizedBox(width: 8),
            Expanded(
              child: hauptKnopf(tr('Speichern', 'Save'), () {
                final leer = _t.text.trim().isEmpty;
                widget.app.notizSchreiben(_t.text, id: e.id);
                if (leer) {
                  Navigator.of(context).pop(); // leerer Text = gelöscht
                  return;
                }
                FocusScope.of(context).unfocus();
                setState(() => _bearbeiten = false);
              }, icon: Icons.check, key: const Key('notizbuchAendern'), blatt: false),
            ),
          ]),
        ],
      ]),
    );
  }
}
