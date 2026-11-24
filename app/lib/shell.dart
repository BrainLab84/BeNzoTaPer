import 'i18n/txt.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'anleitung.dart';
import 'app_state.dart';
import 'erinnerung.dart';
import 'notizbuch.dart';
import 'pin.dart';
import 'bausteine.dart';
import 'heute.dart';
import 'kalender.dart';
import 'plan_kopf.dart';
import 'plan_neu.dart';
import 'plan_reiter.dart';
import 'sicherung.dart';
import 'sos.dart';
import 'start.dart';
import 'verlauf.dart';

/// Rahmen mit vier Reitern (Heute, Kalender, Plan, Fortschritt), Start in Heute.
/// Wischen wechselt den Reiter; Zurück: Dialog → Seite → Kalender → Ende.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.app});
  final AppState app;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  // Heute · Kalender · Plan · Fortschritt, Start in Heute,
  // oben ein runder Kalender-Knopf.
  static List<(IconData, IconData, String)> get reiter => [
    (Icons.event_available_outlined, Icons.event_available_outlined, tr('Heute', 'Today')),
    (Icons.calendar_month_outlined, Icons.calendar_month_outlined, tr('Kalender', 'Calendar')),
    (Icons.route_outlined, Icons.route_outlined, tr('Plan', 'Plan')),
    (Icons.signal_cellular_alt_rounded, Icons.signal_cellular_alt_rounded, tr('Fortschritt', 'Progress')),
  ];
  static const heute = 0;
  static const kalender = 1;

  final _seiten = PageController(initialPage: heute);
  int _i = heute;
  Timer? _minute;
  String? _tag;
  final _wahl = TagWahl();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tag = widget.app.taper.today;
    widget.app.reiterWunsch.addListener(_wunsch);
    // Blieb die App über Mitternacht offen, neu rechnen und zeichnen.
    // Jede Minute auch für die Stunden-Anzeige der Bedenkzeit.
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => _pruefen());
    // Vorrat-Hinweis: ggf. einmal nach der Erlaubnis fragen (Update/neues Handy, siehe AppState).
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.app.vorratErlaubnisEinmal());
  }

  void _pruefen() {
    final t = widget.app.taper.today;
    if (t != _tag || widget.app.taper.s?.pend != null) {
      _tag = t;
      widget.app.auffrischen();
    }
  }

  @override
  void dispose() {
    _minute?.cancel();
    widget.app.reiterWunsch.removeListener(_wunsch);
    _wahl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _seiten.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // PIN-Sperre: nach der gewählten Zeit im Hintergrund wieder sperren.
    if (s == AppLifecycleState.resumed) {
      widget.app.vordergrund();
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      widget.app.hintergrund();
    }
  }

  void _wunsch() {
    final i = widget.app.reiterWunsch.value;
    if (i == null) return;
    widget.app.reiterWunsch.value = null;
    _gehe(i);
  }

  void _gehe(int i) {
    setState(() => _i = i);
    _seiten.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final schmal = MediaQuery.sizeOf(context).width < 360;
    return PopScope(
      canPop: _i == heute,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _i != heute) _gehe(heute);
      },
      child: Scaffold(
        // Kopfzeile: links Notizbuch, Mitte SOS, rechts Kalender + Mehr.
        // Der Name des Reiters steht unten in der Leiste.
        appBar: AppBar(
          toolbarHeight: 64,
          titleSpacing: 8,
          // Schmale Handys (unter 360 dp): nur der runde Knopf, sonst wird SOS in der Mitte zu eng.
          leadingWidth: schmal ? 58 : 136,
          leading: InkWell(
            key: const Key('notizbuchKnopf'),
            borderRadius: BorderRadius.circular(24),
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NotizbuchSeite(app: widget.app))),
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(children: [
                GlasKreis(
                    groesse: 40,
                    child: Icon(Icons.menu_book_outlined, size: 20, color: F.rosa, semanticLabel: tr('Notizbuch', 'Notebook'))),
                if (!schmal) ...[
                  const SizedBox(width: 7),
                  // Text direkt neben dem Knopf
                  Flexible(
                    child: Text(tr('Notizen für\nden Alltag', 'Notes for\neveryday life'),
                        maxLines: 2,
                        overflow: TextOverflow.fade,
                        style: TextStyle(fontSize: 11.5, height: 1.15, color: F.rosa)),
                  ),
                ],
              ]),
            ),
          ),
          centerTitle: true,
          title: sosKopfKnopf(context, widget.app),
          actions: [
            kalenderKnopf(() => _gehe(kalender)),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: glasKnopf(
                tooltip: tr('Mehr', 'More'),
                icon: Icons.settings_outlined,
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MehrSeite(app: widget.app))),
              ),
            ),
          ],
        ),
        body: PageView(
          controller: _seiten,
          onPageChanged: (i) => setState(() => _i = i),
          children: [
            HeuteSeite(
              app: widget.app,
              tagOeffnen: (k) {
                _wahl.waehle(k);
                _gehe(kalender);
              },
              planEditor: (e) => planNeuOeffnen(context, widget.app, PlanArt.erstellen, vorgemerkt: e),
            ),
            KalenderSeite(app: widget.app, wahl: _wahl),
            PlanReiter(app: widget.app),
            VerlaufSeite(app: widget.app),
          ],
        ),
        // Untere Leiste: Glas mit runden Ecken, gewählter Reiter als helle Fläche
        // um Symbol und Namen.
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x33FFFFFF), Color(0x1FFFFFFF)]),
            border: Border.fromBorderSide(BorderSide(color: Color(0x4DFFFFFF))),
            boxShadow: [BoxShadow(color: Color(0x2E0B1830), blurRadius: 18, blurStyle: BlurStyle.outer)],
          ),
          child: NavigationBar(
            selectedIndex: _i,
            onDestinationSelected: _gehe,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            height: 88,
            indicatorColor: Colors.transparent,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            destinations: [
              for (final r in reiter)
                NavigationDestination(
                    icon: _NavPunkt(r.$1, r.$3, false), selectedIcon: _NavPunkt(r.$2, r.$3, true), label: r.$3)
            ],
          ),
        ),
      ),
    );
  }
}

class MehrSeite extends StatelessWidget {
  const MehrSeite({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Mehr', 'More')), actions: [
          kalenderKnopf(() {
            Navigator.of(context).popUntil((r) => r.isFirst);
            app.reiterWunsch.value = _ShellState.kalender;
          }),
        ]),
        body: Column(children: [
          Expanded(
            child: ListView(children: [
              // Karte „Wichtig“ oben in „Mehr“.
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Karte(key: Key('notfallKarte'), rand: Color(0x66FF9AA6), children: [
                  Text.rich(TextSpan(style: TextStyle(height: 1.4), children: [
                    TextSpan(text: tr('Wichtig:', 'Important:'), style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(
                        text: tr(' Nach längerer Einnahme kann abruptes Weglassen Krampfanfälle oder Verwirrtheit '
                            'auslösen. Bei Krampfanfall, Halluzinationen oder starker Verwirrung: Notruf 112.', ' After long-term use, stopping abruptly can cause seizures or confusion. In case of a seizure, hallucinations or severe confusion: call emergency services (112 in Europe, or your local emergency number).')),
                  ])),
                  SizedBox(height: 12),
                  Text.rich(TextSpan(style: TextStyle(height: 1.4), children: [
                    TextSpan(
                        text: tr('Umrechnung zwischen Benzodiazepinen:', 'Converting between benzodiazepines:'), style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(
                        text: tr(' Äquivalenztabellen werden sehr unterschiedlich interpretiert, deshalb gibt es hier '
                            'keine.', ' Equivalence tables are interpreted very differently, so there are none here.')),
                  ])),
                ]),
              ),
              ListTile(
                key: const Key('spracheWechseln'),
                leading: const Icon(Icons.translate),
                title: Text(tr('Sprache', 'Language')),
                subtitle: Text(Txt.en ? 'English' : 'Deutsch'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final neu = await showDialog<String>(
                    context: context,
                    builder: (_) => SimpleDialog(title: Text(tr('Sprache wählen', 'Choose language')), children: [
                      SimpleDialogOption(
                          key: const Key('sprache_de'),
                          onPressed: () => Navigator.pop(context, 'de'),
                          child: const Text('Deutsch')),
                      SimpleDialogOption(
                          key: const Key('sprache_en'),
                          onPressed: () => Navigator.pop(context, 'en'),
                          child: const Text('English')),
                    ]),
                  );
                  if (neu != null && neu != Txt.code) await app.spracheWaehlen(neu);
                },
              ),
              ListTile(
                key: const Key('hinweiseNochmal'),
                leading: const Icon(Icons.info_outline),
                title: Text(tr('Alle Hinweise nochmal lesen', 'Read all notices again')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => HinweisSeite(app: app, nochmal: true))),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(tr('Anleitung', 'Guide')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AnleitungSeite())),
              ),
              const Divider(),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(tr('Daten', 'Data'), style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              PinAbschnitt(app: app),
              ErinnerungAbschnitt(app: app),
              ListTile(
                leading: const Icon(Icons.save_outlined),
                title: Text(tr('Sicherung speichern', 'Save backup')),
                subtitle: Text(tr('Als Datei, mit Passwort verschlüsselt', 'As a file, encrypted with a password')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (app.beispiel) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            tr('Das ist noch der Beispielplan. Leg zuerst oben im Reiter Heute deinen eigenen Plan an.', 'This is still the example plan. First set up your own plan at the top of the Today tab.'))));
                    return;
                  }
                  final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => SicherungSpeichernSeite(app: app, dateien: app.dateien)));
                  if (ok == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Sicherung erstellt.', 'Backup created.'))));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: Text(tr('Sicherung laden', 'Load backup')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => sicherungLadenAblauf(context, app, app.dateien),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(tr('Daten liegen nur auf diesem Gerät.', 'Data is stored only on this device.')),
              ),
              ZuruecksetzenKnopf(app: app),
            ]),
          ),
          const Padding(padding: EdgeInsets.all(16), child: Impressum()),
        ]),
      );
}

/// Runder Knopf mit Kalendersymbol oben in der Leiste: direkt zum Kalender.
Widget kalenderKnopf(VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: glasKnopf(key: const Key('kalenderKnopf'), tooltip: tr('Kalender', 'Calendar'), icon: Icons.calendar_month, onTap: onTap),
    );

/// Eintrag der unteren Leiste: Symbol über Namen; gewählt = helle Glasfläche um beides.
class _NavPunkt extends StatelessWidget {
  const _NavPunkt(this.icon, this.name, this.an);
  final IconData icon;
  final String name;
  final bool an;
  @override
  Widget build(BuildContext context) {
    final breite = math.min(96.0, MediaQuery.sizeOf(context).width / 4 - 6);
    return Container(
      key: ValueKey('reiter-$name'),
      width: breite,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: an
          ? BoxDecoration(
              color: const Color(0x30FFFFFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x26FFFFFF)),
            )
          : null,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 27, color: F.rosa),
        const SizedBox(height: 4),
        // Sichtbarer Name als RichText ohne Semantik: Vorgelesen (und in Tests gefunden) wird der
        // versteckte Name von NavigationDestination – so gibt es ihn nur einmal.
        ExcludeSemantics(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Builder(
              builder: (context) => FittedBox(
                fit: BoxFit.scaleDown,
                child: RichText(
                  maxLines: 1,
                  softWrap: false,
                  textScaler: MediaQuery.textScalerOf(context),
                  text: TextSpan(
                      text: name,
                      style: DefaultTextStyle.of(context).style.copyWith(
                          fontSize: 14,
                          color: F.rosa,
                          fontWeight: an ? FontWeight.w600 : FontWeight.w400,
                          height: 1.1)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
