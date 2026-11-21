import 'i18n/txt.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'texte.dart';

/// Splash, 3 Sekunden mit Logo.
class Splash extends StatefulWidget {
  const Splash({super.key, required this.weiter, this.dauer = const Duration(seconds: 3)});
  final VoidCallback weiter;
  final Duration dauer;
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(widget.dauer, widget.weiter);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            // Logo deutlich größer – 85 % der Breite, max. 420 dp, nie verzerrt.
            final breite = (c.maxWidth * .85).clamp(0.0, 420.0);
            return Column(children: [
              Expanded(
                child: Center(
                  child: ClipPath(
                    clipper: const _LogoForm(),
                    child: Image.asset('assets/logo.jpg',
                        key: const ValueKey('splashLogo'),
                        width: breite,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 20), child: Impressum()),
            ]);
          }),
        ),
      );
}

/// Schneidet das Logo genau an seiner pinken Kante ab (das Bild hat außen schwarze Ecken, die auf dem
/// blauen Hintergrund stören). Maße aus `assets/logo.jpg` (611 × 640): oben 12, unten 16 px Rand, Radius ~150.
class _LogoForm extends CustomClipper<Path> {
  const _LogoForm();
  @override
  Path getClip(Size s) => Path()
    ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(s.width * .005, s.height * 14 / 640, s.width * .995, s.height * 622 / 640),
        Radius.circular(s.width * .245)));
  @override
  bool shouldReclip(_LogoForm old) => false;
}

/// Urheber-Zeilen – im Splash und unten in „Mehr“.
const impressumZeilen = [
  'Designed & Developed by Benzo Brain',
  '© 2026 Benzo Brain',
];

class Impressum extends StatelessWidget {
  const Impressum({super.key});
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.bodySmall;
    return Column(
      key: const ValueKey('impressum'),
      mainAxisSize: MainAxisSize.min,
      children: [for (final z in impressumZeilen) Text(z, style: s, textAlign: TextAlign.center)],
    );
  }
}

/// Text-Absätze (Disclaimer, Anleitung) einheitlich darstellen.
List<Widget> absaetze(BuildContext context, List<Absatz> teile) {
  final t = Theme.of(context).textTheme;
  final out = <Widget>[];
  var imWichtig = <Widget>[];
  void wichtigAbschliessen() {
    if (imWichtig.isEmpty) return;
    out.add(Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .25),
        border: Border(left: BorderSide(color: Theme.of(context).colorScheme.error, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: imWichtig),
    ));
    imWichtig = [];
  }

  for (final a in teile) {
    switch (a.art) {
      case B.wichtigKopf:
        imWichtig.add(Text(a.text, style: t.bodyLarge!.copyWith(fontWeight: FontWeight.w700)));
      case B.wichtig:
        imWichtig.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(a.text, style: t.bodyLarge)));
      case B.h:
        wichtigAbschliessen();
        out.add(Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(a.text, style: t.titleMedium!.copyWith(fontWeight: FontWeight.w700))));
      case B.li:
        wichtigAbschliessen();
        out.add(Padding(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  '),
              Expanded(child: Text(a.text, style: t.bodyLarge)),
            ])));
      case B.p:
        wichtigAbschliessen();
        out.add(Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(a.text, style: t.bodyLarge)));
    }
  }
  wichtigAbschliessen();
  return out;
}

/// Erster Start: Sprache wählen (wie in einem Spiel). Zweisprachig, weil noch keine Sprache gilt.
class SprachWahlSeite extends StatelessWidget {
  const SprachWahlSeite({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.translate, size: 40, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('Bitte Sprache wählen', textAlign: TextAlign.center, style: t.titleLarge),
                const SizedBox(height: 4),
                Text('Please choose a language', textAlign: TextAlign.center, style: t.titleMedium),
                const SizedBox(height: 28),
                FilledButton(
                    key: const Key('sprache_de'), onPressed: () => app.spracheWaehlen('de'), child: const Text('Deutsch')),
                const SizedBox(height: 12),
                FilledButton(
                    key: const Key('sprache_en'), onPressed: () => app.spracheWaehlen('en'), child: const Text('English')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hinweise beim ersten Start: „Weiter“ erst nach Häkchen.
class HinweisSeite extends StatefulWidget {
  const HinweisSeite({super.key, required this.app, this.nochmal = false});
  final AppState app;

  /// Aus „Mehr“ geöffnet (Häkchen ist schon gesetzt, „Weiter“ schließt die Seite).
  final bool nochmal;
  @override
  State<HinweisSeite> createState() => _HinweisSeiteState();
}

class _HinweisSeiteState extends State<HinweisSeite> {
  late bool _ok = widget.nochmal;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(disclaimerTitel,
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w700)),
              ...absaetze(context, disclaimer),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _ok,
                onChanged: (v) => setState(() => _ok = v ?? false),
                title: Text(tr('Ich habe die Hinweise gelesen und verstanden.', 'I have read and understood the notices.'),
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              FilledButton(
                onPressed: !_ok
                    ? null
                    : widget.nochmal
                        ? () => Navigator.of(context).pop()
                        : widget.app.hinweisBestaetigt,
                child: Text(tr('Weiter', 'Continue')),
              ),
            ],
          ),
        ),
      );
}

/// Wenn die gespeicherten Daten nicht geöffnet werden konnten: Fehler zeigen statt am Logo zu hängen.
class LadeFehlerSeite extends StatelessWidget {
  const LadeFehlerSeite({super.key, required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(tr('Die App konnte ihre Daten nicht öffnen.', 'The app could not open its data.'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(tr('Es wurde nichts gelöscht. Versuch es nochmal oder starte das Handy neu.', 'Nothing was deleted. Try again or restart your phone.')),
            const SizedBox(height: 16),
            FilledButton(key: const Key('nochmalLaden'), onPressed: app.laden, child: Text(tr('Nochmal versuchen', 'Try again'))),
            const SizedBox(height: 24),
            SelectableText(app.ladeFehler ?? '', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
