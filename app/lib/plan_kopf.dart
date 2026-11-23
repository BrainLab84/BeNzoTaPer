// Oben im Kalender (und auf Heute, solange es keinen Plan gibt): Begrüßung, Plan in einer Zeile,
// „Neuen Plan erstellen“ und „Plan importieren“ nebeneinander. Dazu die Planübersicht.
import 'i18n/txt.dart';
import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'pin.dart';
import 'plan_neu.dart';
import 'sicherung.dart';

/// Öffnet „Neuen Plan erstellen“ bzw. „Plan importieren“ und meldet das Ergebnis.
Future<void> planNeuOeffnen(BuildContext context, AppState app, PlanArt art, {PlanEdit? vorgemerkt}) async {
  final messenger = ScaffoldMessenger.of(context);
  // Es gibt schon einen eigenen Plan: neuer Plan = Neustart (alles weg). Erst „Bist du dir sicher?“.
  // Gelöscht wird erst beim Speichern des neuen Plans; Abbrechen lässt alles, wie es war.
  final ersetzt = app.taper.s != null && !app.beispiel;
  final neustart = ersetzt && vorgemerkt == null;
  if (neustart && !await planSicherFragen(context)) return;
  if (!context.mounted) return;
  final warBeispiel = app.beispiel;
  app.beispielWeg();
  final r = await Navigator.of(context).push<PlanErgebnis>(
      MaterialPageRoute(builder: (_) => PlanNeuSeite(app: app, art: art, vorgemerkt: vorgemerkt, neustart: neustart)));
  if (warBeispiel && app.taper.s == null) {
    app.beispielLaden();
    app.aenderung();
  }
  if (r == PlanErgebnis.uebernommen) {
    messenger.showSnackBar(SnackBar(content: Text(tr('Dein Plan ist gespeichert.', 'Your plan has been saved.'))));
    // Erster eigener Plan (auch nach einem Neustart): einmal PIN anbieten, überspringbar.
    if (vorgemerkt == null && !app.hatPin && context.mounted) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => PinEinrichtenSeite(app: app, nachPlan: true)));
    }
  } else if (r == PlanErgebnis.vorgemerkt) {
    messenger
        .showSnackBar(SnackBar(content: Text(tr('Vorgemerkt – in 48 Stunden kannst du den neuen Plan übernehmen.', 'Scheduled – in 48 hours you can apply the new plan.'))));
  }
}

/// Satz, der eingetippt werden muss (Groß-/Kleinschreibung, Komma und Leerzeichen egal).
String get planSicherSatz => tr('Ja, ich bin mir sicher', 'Yes, I am sure');
String get planBackupSatz => tr('Ich bestätige hiermit, dass ich ohne eine Sicherung nichts davon wiederherstellen kann.',
    'I hereby confirm that without a backup I cannot restore any of it.');

bool planSicherPasst(String s) =>
    const {'ja ich bin mir sicher', 'yes i am sure'}
        .contains(s.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß ]'), ' ').trim().replaceAll(RegExp(r'\s+'), ' '));

/// Wie [planSicherPasst], zusätzlich ohne „Ja“ („Ich bin mir sicher.“ / „I am sure“).
bool sicherPasst(String s) {
  final t = s.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß ]'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
  return planSicherPasst(t) || const {'ich bin mir sicher', 'i am sure'}.contains(t);
}

/// Fenster vor einem neuen Plan, wenn schon einer existiert: Satz eintippen + Häkchen. `true` = weiter.
Future<bool> planSicherFragen(BuildContext context) async {
  final r = await showDialog<bool>(context: context, builder: (_) => const _PlanSicherDialog());
  return r ?? false;
}

/// Gleiches Fenster vor „Zurücksetzen“: Satz eintippen + Häkchen. `true` = löschen.
Future<bool> zuruecksetzenSicherFragen(BuildContext context) async {
  final r = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanSicherDialog(
            dialogKey: const Key('resetSicherDialog'),
            text: tr('Wie eine neu installierte App: Alles auf diesem Gerät wird gelöscht – Plan, Einnahmen, Vorrat, '
                    'Notizen, Notizbuch, PIN und Einstellungen.',
                'Like a newly installed app: everything on this device will be deleted – plan, intakes, supply, '
                    'notes, notebook, PIN and settings.'),
            haken: tr('Ich weiß: Ohne Sicherung kann ich nichts davon wiederherstellen.',
                'I know: without a backup I cannot restore any of it.'),
            weiter: tr('Alles löschen', 'Delete everything'),
            passt: sicherPasst,
          ));
  return r ?? false;
}

/// Vor „Sicherung laden“, wenn schon Daten da sind: nur Satz eintippen (kein Häkchen). `true` = laden.
Future<bool> sicherungLadenSicherFragen(BuildContext context) async {
  final r = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanSicherDialog(
            dialogKey: const Key('ladenSicherDialog'),
            titel: tr('Sicherung laden?', 'Load backup?'),
            text: tr('Dein aktueller Stand auf diesem Gerät wird dabei ersetzt.', 'Your current data on this device will be replaced.'),
            ohneHaken: true,
            weiter: tr('Laden', 'Load'),
            passt: sicherPasst,
          ));
  return r ?? false;
}

class _PlanSicherDialog extends StatefulWidget {
  const _PlanSicherDialog(
      {this.dialogKey, this.titel, this.text, this.haken, this.ohneHaken = false, this.weiter, this.passt = planSicherPasst});
  final Key? dialogKey;
  final String? titel;
  final String? text;
  final String? haken;
  final bool ohneHaken;
  final String? weiter;
  final bool Function(String) passt;
  @override
  State<_PlanSicherDialog> createState() => _PlanSicherDialogState();
}

class _PlanSicherDialogState extends State<_PlanSicherDialog> {
  final _text = TextEditingController();
  bool _haken = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = (_haken || widget.ohneHaken) && widget.passt(_text.text);
    return AlertDialog(
      key: widget.dialogKey ?? const Key('planSicherDialog'),
      title: Text(widget.titel ?? tr('Bist du dir sicher?', 'Are you sure?')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.text ??
              tr('Ein neuer Plan ist ein Neustart – wie eine neu installierte App. Alles auf diesem Gerät wird gelöscht: '
                  'Plan, Einnahmen, Vorrat, Notizen, Notizbuch, PIN und Einstellungen. Gelöscht wird erst, wenn du den '
                  'neuen Plan speicherst.',
                  'A new plan is a fresh start – like a newly installed app. Everything on this device will be deleted: '
                      'plan, intakes, supply, notes, notebook, PIN and settings. Deletion happens only when you save the new plan.')),
          Feldname(tr('Bitte eintippen: $planSicherSatz', 'Please type: $planSicherSatz')),
          TextField(
            key: const Key('planSicherText'),
            controller: _text,
            autocorrect: false,
            enableSuggestions: false,
            decoration: feldStil(hinweis: planSicherSatz),
            onChanged: (_) => setState(() {}),
          ),
          if (!widget.ohneHaken) const SizedBox(height: 8),
          if (!widget.ohneHaken) CheckboxListTile(
            key: const Key('planBackupHaken'),
            value: _haken,
            onChanged: (v) => setState(() => _haken = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(widget.haken ?? planBackupSatz),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Abbrechen', 'Cancel'))),
        FilledButton(
          key: const Key('planSicherWeiter'),
          onPressed: ok ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.weiter ?? tr('Weiter', 'Continue')),
        ),
      ],
    );
  }
}

/// Startkarte, solange es keinen eigenen Plan gibt (oben in Heute):
/// „Schön, dass du da bist“, „Neuen Plan erstellen“ / „Plan importieren“, „Sicherung laden“.
class PlanKopf extends StatelessWidget {
  const PlanKopf({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) => Karte(
        key: const Key('planKopf'),
        rand: F.acRand,
        children: [
          Text(tr('Schön, dass du da bist.', 'Nice to have you here.'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Sub(
              tr('Schau dich in Ruhe um. Wenn du so weit bist, legst du hier deinen Abdosierplan an – '
              'oder übernimmst den Plan von deinem Arzt.', 'Take a look around. When you are ready, you set up your tapering plan here – or import the plan from your doctor.'),
              oben: 6),
          const SizedBox(height: 14),
          planKnoepfe(context, app, betont: true),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('sicherungLadenStart'),
              onPressed: () => sicherungLadenAblauf(context, app, app.dateien),
              icon: const Icon(Icons.restore, size: 18),
              label: Text(tr('Sicherung laden', 'Load backup')),
            ),
          ),
        ],
      );
}

/// „Neuen Plan erstellen“ und „Plan importieren“ nebeneinander, gleich hoch. Auf schmalen Handys
/// oder mit großer Schrift untereinander, damit kein Wort mitten drin umbricht.
Widget planKnoepfe(BuildContext context, AppState app, {bool betont = false}) => LayoutBuilder(builder: (context, c) {
      final erstellen = betont
          ? hauptKnopf(tr('Neuen Plan erstellen', 'Create new plan'), () => planNeuOeffnen(context, app, PlanArt.erstellen),
              icon: Icons.add, key: const Key('planErstellen'), blatt: false)
          : knopf(tr('Neuen Plan erstellen', 'Create new plan'), () => planNeuOeffnen(context, app, PlanArt.erstellen),
              icon: Icons.add, key: const Key('planErstellen'));
      final importieren = knopf(tr('Plan importieren', 'Import plan'), () => planNeuOeffnen(context, app, PlanArt.importieren),
          icon: Icons.upload_file_outlined, key: const Key('planImportieren'));
      if (c.maxWidth < MediaQuery.textScalerOf(context).scale(310)) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          erstellen,
          const SizedBox(height: 8),
          importieren,
        ]);
      }
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: erstellen),
          const SizedBox(width: 8),
          Expanded(child: importieren),
        ]),
      );
    });

/// Begrüßung oben in Heute, wenn ein Name eingetragen ist.
class Begruessung extends StatelessWidget {
  const Begruessung({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('planKopf'),
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        child: Text.rich(
            TextSpan(children: [
              TextSpan(text: tr('Hallo ', 'Hello ')),
              TextSpan(text: name, style: const TextStyle(color: F.ac2)),
            ]),
            key: const Key('begruessung'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
      );
}

/// Plan, Heute und Fortschritt, solange es noch keinen Plan gibt: nur ein kurzer Satz, was hier
/// später steht. „Neuen Plan erstellen“ gibt es nur einmal – oben in Heute.
class OhnePlanHinweis extends StatelessWidget {
  const OhnePlanHinweis(this.text, {super.key, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
        Karte(key: const Key('ohnePlan'), children: [
          Row(children: [
            Icon(icon, color: F.mu),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(color: F.mu, height: 1.4))),
          ]),
        ]),
      ]);
}

/// Markierung, solange der Beispielplan angezeigt wird.
class BeispielHinweis extends StatelessWidget {
  const BeispielHinweis({super.key});
  @override
  Widget build(BuildContext context) => Karte(
        key: const Key('beispielHinweis'),
        padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
        children: [
          Row(children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.visibility_outlined, color: F.rosa, size: 28),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text.rich(TextSpan(style: TextStyle(color: F.tx, height: 1.45, fontSize: 15), children: [
                TextSpan(text: tr('Beispiel. ', 'Example. '), style: TextStyle(fontWeight: FontWeight.w700, color: F.tx)),
                TextSpan(
                    text: tr('So sieht die App mit einem Plan aus. Hier wird nichts gespeichert – '
                        'deinen eigenen Plan legst du oben im Reiter Heute an.', 'This is what the app looks like with a plan. Nothing is saved here – you set up your own plan at the top of the Today tab.')),
              ])),
            ),
          ]),
        ],
      );
}
