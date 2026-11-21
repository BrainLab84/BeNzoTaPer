// PIN-Sperre: Sperrbildschirm, Einrichten, „PIN vergessen“.
// Sperrt beim Öffnen und nach 1 Minute im Hintergrund. Die PIN (4–8 Ziffern) liegt gehasht im Stand (`pin`).
// nach dem ersten eigenen Plan einmal anbieten (überspringbar), sonst in „Mehr“.
import 'i18n/txt.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'sos.dart';

String get pinErklaerung =>
    tr('Sperrt beim Öffnen und nach 1 Minute im Hintergrund. Schützt vor neugierigen Blicken, ist aber keine Verschlüsselung.', 'Locks on opening and after 1 minute in the background. Protects against prying eyes, but is not encryption.');

/// Sperrbildschirm (liegt über allem, solange [AppState.gesperrt]).
class SperrSeite extends StatefulWidget {
  const SperrSeite({super.key, required this.app});
  final AppState app;
  @override
  State<SperrSeite> createState() => _SperrSeiteState();
}

class _SperrSeiteState extends State<SperrSeite> {
  final _pin = TextEditingController();
  String _fehler = '';
  bool _vergessen = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _entsperren() {
    if (!widget.app.entsperren(_pin.text)) {
      _pin.clear();
      setState(() => _fehler = tr('Falsche PIN.', 'Wrong PIN.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = <Widget>[
      const Center(child: Icon(Icons.lock_outline, size: 40, color: F.ac2)),
      const SizedBox(height: 8),
      Center(child: Text(tr('Gesperrt', 'Locked'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
      const SizedBox(height: 16),
    ];
    if (_vergessen) {
      k.addAll([
        Text(tr('Ohne PIN kommt niemand an die Daten – auch du nicht. Alles löschen und neu anfangen?', 'Without the PIN nobody can get at the data – not even you. Delete everything and start over?')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: knopf(tr('Abbrechen', 'Cancel'), () => setState(() => _vergessen = false))),
          const SizedBox(width: 8),
          Expanded(
            child: knopf(tr('Alles löschen', 'Delete everything'), () => widget.app.allesLoeschen(),
                hinten: F.bads, vorne: const Color(0xFFF0A7A4), rand: F.bad, key: const Key('allesLoeschen')),
          ),
        ]),
      ]);
    } else {
      k.addAll([
        TextField(
          key: const Key('pinEingabe'),
          controller: _pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: feldStil(hinweis: 'PIN'),
          onSubmitted: (_) => _entsperren(),
        ),
        const SizedBox(height: 10),
        hauptKnopf(tr('Entsperren', 'Unlock'), _entsperren, key: const Key('entsperren')),
        if (_fehler.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_fehler, style: const TextStyle(color: F.bad))),
        const SizedBox(height: 14),
        TextButton(onPressed: () => setState(() => _vergessen = true), child: Text(tr('PIN vergessen?', 'Forgot PIN?'))),
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: sosKopfKnopf(context, widget.app),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Karte(children: k),
            ),
          ),
        ),
      ),
    );
  }
}

/// PIN festlegen (4–8 Ziffern, zweimal). Gibt `true` zurück, wenn gespeichert.
/// [nachPlan]: direkt nach dem ersten eigenen Plan angeboten → Knopf „Überspringen“.
class PinEinrichtenSeite extends StatefulWidget {
  const PinEinrichtenSeite({super.key, required this.app, this.nachPlan = false});
  final AppState app;
  final bool nachPlan;
  @override
  State<PinEinrichtenSeite> createState() => _PinEinrichtenSeiteState();
}

class _PinEinrichtenSeiteState extends State<PinEinrichtenSeite> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String _fehler = '';

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _speichern() {
    final f = widget.app.pinSetzen(_a.text, _b.text);
    if (f != null) {
      setState(() => _fehler = f);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('PIN-Sperre', 'PIN lock'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Karte(children: [
            if (widget.nachPlan) ...[
              Text(tr('Möchtest du die App mit einer PIN schützen?', 'Do you want to protect the app with a PIN?'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Sub(tr('Geht auch später jederzeit in „Mehr“.', 'You can also do this later at any time under “More”.'), oben: 4),
              const SizedBox(height: 8),
            ],
            Sub(pinErklaerung),
            Feldname(tr('Neue PIN (4–8 Ziffern)', 'New PIN (4–8 digits)')),
            TextField(
              key: const Key('pinNeu1'),
              controller: _a,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: feldStil(),
            ),
            Feldname(tr('Nochmal', 'Again')),
            TextField(
              key: const Key('pinNeu2'),
              controller: _b,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: feldStil(),
              onSubmitted: (_) => _speichern(),
            ),
            if (_fehler.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 6), child: Text(_fehler, style: const TextStyle(color: F.bad))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: knopf(widget.nachPlan ? tr('Überspringen', 'Skip') : tr('Abbrechen', 'Cancel'), () => Navigator.of(context).pop(false),
                    key: const Key('pinAbbrechen')),
              ),
              const SizedBox(width: 8),
              Expanded(child: hauptKnopf(tr('PIN speichern', 'Save PIN'), _speichern, key: const Key('pinSpeichern'), blatt: false)),
            ]),
          ]),
        ]),
      );
}

/// Abschnitt „PIN-Sperre“ in „Mehr“.
class PinAbschnitt extends StatelessWidget {
  const PinAbschnitt({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (!app.eingerichtet) {
            return ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text(tr('PIN-Sperre', 'PIN lock')),
              subtitle: Text(tr('Geht, sobald du deinen eigenen Plan angelegt hast.', 'Available once you have created your own plan.')),
            );
          }
          if (!app.hatPin) {
            return ListTile(
              key: const Key('pinEinrichten'),
              leading: const Icon(Icons.lock_outline),
              title: Text(tr('PIN-Sperre einrichten', 'Set up PIN lock')),
              subtitle: Text(pinErklaerung),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => PinEinrichtenSeite(app: app))),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              IconText(Icons.lock, tr('PIN-Sperre ist an', 'PIN lock is on'), fett: true),
              Sub(pinErklaerung, oben: 4),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: knopf(tr('Jetzt sperren', 'Lock now'), app.sperren, icon: Icons.lock, key: const Key('jetztSperren'))),
                const SizedBox(width: 8),
                Expanded(child: knopf(tr('PIN-Sperre aus', 'PIN lock off'), app.pinAus, key: const Key('pinAus'))),
              ]),
            ]),
          );
        },
      );
}

/// „Zurücksetzen“ in „Mehr“ : erstes Tippen → „Wirklich löschen?“, zweites löscht alles.
/// Danach wieder das Beispiel. Im Beispiel ausgeblendet (nichts zu löschen).
class ZuruecksetzenKnopf extends StatefulWidget {
  const ZuruecksetzenKnopf({super.key, required this.app});
  final AppState app;
  @override
  State<ZuruecksetzenKnopf> createState() => _ZuruecksetzenKnopfState();
}

class _ZuruecksetzenKnopfState extends State<ZuruecksetzenKnopf> {
  bool _fragen = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          if (!widget.app.eingerichtet) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (_fragen) ...[
                  Expanded(child: knopf(tr('Abbrechen', 'Cancel'), () => setState(() => _fragen = false))),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: knopf(_fragen ? tr('Wirklich löschen?', 'Really delete?') : tr('Zurücksetzen', 'Reset'), () {
                    if (!_fragen) {
                      setState(() => _fragen = true);
                      return;
                    }
                    setState(() => _fragen = false);
                    widget.app.allesLoeschen();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Alles gelöscht.', 'Everything deleted.'))));
                  }, hinten: F.bads, vorne: const Color(0xFFF0A7A4), rand: F.bad, key: const Key('zuruecksetzen')),
                ),
              ]),
            ]),
          );
        },
      );
}
