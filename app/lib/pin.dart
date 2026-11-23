// PIN-Sperre: Sperrbildschirm, Einrichten (mit Schlüsselwort), „PIN vergessen“ (Schlüsselwort → neue PIN).
// Sperrt beim Öffnen und nach der gewählten Zeit im Hintergrund (2/5/10/30 Minuten, Standard 2). Die PIN (4–8 Ziffern) liegt gehasht im Stand (`pin`).
// nach dem ersten eigenen Plan einmal anbieten (überspringbar), sonst in „Mehr“.
import 'i18n/txt.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'plan_kopf.dart';
import 'sos.dart';

String get pinErklaerung =>
    tr('Sperrt beim Öffnen und nach der gewählten Zeit im Hintergrund. Schützt vor neugierigen Blicken, ist aber keine Verschlüsselung.', 'Locks on opening and after the chosen time in the background. Protects against prying eyes, but is not encryption.');

/// Sperrbildschirm (liegt über allem, solange [AppState.gesperrt]).
class SperrSeite extends StatefulWidget {
  const SperrSeite({super.key, required this.app});
  final AppState app;
  @override
  State<SperrSeite> createState() => _SperrSeiteState();
}

enum _Sperre { pin, vergessen, wortNeu }

class _SperrSeiteState extends State<SperrSeite> {
  final _pin = TextEditingController();
  final _wort = TextEditingController();
  final _neu1 = TextEditingController();
  final _neu2 = TextEditingController();
  final _w1 = TextEditingController();
  final _w2 = TextEditingController();
  String _fehler = '';
  _Sperre _modus = _Sperre.pin;
  String _richtigePin = '';

  AppState get app => widget.app;

  @override
  void dispose() {
    for (final c in [_pin, _wort, _neu1, _neu2, _w1, _w2]) {
      c.dispose();
    }
    super.dispose();
  }

  void _zu(_Sperre m) => setState(() {
        _modus = m;
        _fehler = '';
      });

  void _entsperren() {
    final p = _pin.text;
    if (!app.taper.checkPin(p)) {
      _pin.clear();
      setState(() => _fehler = tr('Falsche PIN.', 'Wrong PIN.'));
      return;
    }
    // Bestehende PIN ohne Schlüsselwort: einmal nachfragen, dann entsperren.
    if (app.wortFragen) {
      _richtigePin = p;
      _zu(_Sperre.wortNeu);
      return;
    }
    app.entsperren(p);
  }

  void _wortSpeichern() {
    final f = app.wortSetzen(_w1.text, _w2.text);
    if (f != null) {
      setState(() => _fehler = f);
      return;
    }
    app.entsperren(_richtigePin);
  }

  void _wortSpaeter() {
    app.wortGefragtMerken();
    app.entsperren(_richtigePin);
  }

  void _pinNeu() {
    final f = app.pinMitWortNeu(_wort.text, _neu1.text, _neu2.text);
    if (f != null) setState(() => _fehler = f);
  }

  Future<void> _allesLoeschen() async {
    if (!await zuruecksetzenSicherFragen(context)) return;
    app.allesLoeschen();
  }

  Widget _fehlerText() => _fehler.isEmpty
      ? const SizedBox.shrink()
      : Padding(padding: const EdgeInsets.only(top: 8), child: Text(_fehler, style: const TextStyle(color: F.bad)));

  @override
  Widget build(BuildContext context) {
    final k = <Widget>[
      const Center(child: Icon(Icons.lock_outline, size: 40, color: F.ac2)),
      const SizedBox(height: 8),
      Center(child: Text(tr('Gesperrt', 'Locked'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
      const SizedBox(height: 16),
    ];
    switch (_modus) {
      case _Sperre.vergessen:
        k.add(Text(tr('Die App ist offline und hat kein Konto – niemand kann die PIN für dich zurückholen.',
            'The app is offline and has no account – nobody can recover the PIN for you.')));
        if (app.hatWort) {
          k.addAll([
            Feldname(tr('Dein Schlüsselwort', 'Your keyword')),
            TextField(key: const Key('wortEingabe'), controller: _wort, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: feldStil()),
            Feldname(tr('Neue PIN (4–8 Ziffern)', 'New PIN (4–8 digits)')),
            TextField(key: const Key('pinNeu1'), controller: _neu1, obscureText: true, keyboardType: TextInputType.number, decoration: feldStil()),
            Feldname(tr('Nochmal', 'Again')),
            TextField(
                key: const Key('pinNeu2'),
                controller: _neu2,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: feldStil(),
                onSubmitted: (_) => _pinNeu()),
            _fehlerText(),
            const SizedBox(height: 12),
            hauptKnopf(tr('Neue PIN speichern', 'Save new PIN'), _pinNeu, key: const Key('pinZuruecksetzen')),
          ]);
        }
        k.addAll([
          Sub(
              app.hatWort
                  ? tr('Schlüsselwort auch vergessen? Dann bleibt nur Zurücksetzen: Alle Daten auf diesem Gerät werden '
                      'gelöscht. Eine Sicherung kannst du danach wieder laden.',
                      'Forgot the keyword too? Then the only option is a reset: all data on this device will be deleted. '
                          'You can load a backup afterwards.')
                  : tr('Ohne Schlüsselwort bleibt nur Zurücksetzen: Alle Daten auf diesem Gerät werden gelöscht. Eine '
                      'Sicherung kannst du danach wieder laden.',
                      'Without a keyword the only option is a reset: all data on this device will be deleted. You can '
                          'load a backup afterwards.'),
              oben: 14),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: knopf(tr('Abbrechen', 'Cancel'), () => _zu(_Sperre.pin))),
            const SizedBox(width: 8),
            Expanded(
              child: knopf(tr('Alles löschen', 'Delete everything'), _allesLoeschen,
                  hinten: F.bads, vorne: const Color(0xFFF0A7A4), rand: F.bad, key: const Key('allesLoeschen')),
            ),
          ]),
        ]);
      case _Sperre.wortNeu:
        k.addAll([
          Text(tr('Neu: Lege ein Schlüsselwort fest.', 'New: set a keyword.'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ...wortFelder(_w1, _w2, onSubmitted: _wortSpeichern),
          _fehlerText(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: knopf(tr('Später', 'Later'), _wortSpaeter, key: const Key('wortSpaeter'))),
            const SizedBox(width: 8),
            Expanded(child: hauptKnopf(tr('Speichern', 'Save'), _wortSpeichern, key: const Key('wortSpeichern'), blatt: false)),
          ]),
        ]);
      case _Sperre.pin:
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
          _fehlerText(),
          const SizedBox(height: 14),
          TextButton(onPressed: () => _zu(_Sperre.vergessen), child: Text(tr('PIN vergessen?', 'Forgot PIN?'))),
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
  final _w1 = TextEditingController();
  final _w2 = TextEditingController();
  String _fehler = '';

  @override
  void dispose() {
    for (final c in [_a, _b, _w1, _w2]) {
      c.dispose();
    }
    super.dispose();
  }

  void _speichern() {
    // Erst beides prüfen, dann speichern – nie eine PIN ohne Schlüsselwort.
    final w = widget.app.wortFehler(_w1.text, _w2.text);
    final f = widget.app.pinSetzen(_a.text, _b.text, nurPruefen: true) ?? w;
    if (f != null) {
      setState(() => _fehler = f);
      return;
    }
    widget.app.pinSetzen(_a.text, _b.text);
    widget.app.wortSetzen(_w1.text, _w2.text);
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
            ),
            ...wortFelder(_w1, _w2, onSubmitted: _speichern),
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

/// Hinweis zum Schlüsselwort (Einrichten und einmalige Nachfrage).
String get wortHinweis => tr(
    'Damit kannst du die PIN zurücksetzen, falls du sie vergisst. Wähl ein Wort, das andere nicht leicht '
        'erraten – den Namen der Mutter kennen oft andere. Groß-/Kleinschreibung ist egal.',
    'With it you can reset the PIN if you forget it. Choose a word others cannot easily guess – '
        "many people know your mother's name. Upper/lower case does not matter.");

List<Widget> wortFelder(TextEditingController a, TextEditingController b, {VoidCallback? onSubmitted}) => [
      Feldname(tr('Schlüsselwort', 'Keyword')),
      Sub(wortHinweis),
      const SizedBox(height: 6),
      TextField(key: const Key('wortNeu1'), controller: a, obscureText: true, autocorrect: false, enableSuggestions: false, decoration: feldStil()),
      Feldname(tr('Schlüsselwort nochmal', 'Keyword again')),
      TextField(
        key: const Key('wortNeu2'),
        controller: b,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: feldStil(),
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      ),
    ];

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
              const SizedBox(height: 10),
              Text(tr('Sperren nach', 'Lock after'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final m in AppState.sperrZeiten)
                  ChoiceChip(
                    key: Key('sperr$m'),
                    label: Text(tr('$m Min.', '$m min')),
                    selected: app.sperrMinuten == m,
                    onSelected: (_) => app.sperrZeitSetzen(m),
                  ),
              ]),
              const SizedBox(height: 10),
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

/// „Zurücksetzen“ in „Mehr“: Fenster wie beim neuen Plan (Satz eintippen + Häkchen), dann
/// ist alles gelöscht. Danach wieder das Beispiel. Im Beispiel ausgeblendet (nichts zu löschen).
class ZuruecksetzenKnopf extends StatelessWidget {
  const ZuruecksetzenKnopf({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (!app.eingerichtet) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: knopf(tr('Zurücksetzen', 'Reset'), () async {
              final messenger = ScaffoldMessenger.of(context);
              if (!await zuruecksetzenSicherFragen(context)) return;
              app.allesLoeschen();
              messenger.showSnackBar(SnackBar(content: Text(tr('Alles gelöscht.', 'Everything deleted.'))));
            }, hinten: F.bads, vorne: const Color(0xFFF0A7A4), rand: F.bad, key: const Key('zuruecksetzen')),
          );
        },
      );
}
