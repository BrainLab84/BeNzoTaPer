// BeNzoTaPer – native Android-App (Flutter/Dart). Kein WebView, kein HTML, kein JavaScript.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'bausteine.dart';
import 'deko.dart';
import 'pin.dart';
import 'shell.dart';
import 'start.dart';
import 'store.dart';

void main() {
  // Erst die Flutter-Anbindung, dann Daten laden (Plattform-Aufrufe brauchen sie).
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TaperingBuddy(app: AppState(FileStore())..laden()));
}

class TaperingBuddy extends StatefulWidget {
  const TaperingBuddy({super.key, required this.app, this.splashDauer = const Duration(seconds: 3)});
  final AppState app;
  final Duration splashDauer;
  @override
  State<TaperingBuddy> createState() => _TaperingBuddyState();
}

/// Fläche für Dialoge und Fenster von unten (etwas heller als der Seitenhintergrund).
const flaeche = Color(0xFF4A6790);

/// Legt den Hintergrund (Verlauf + Zweig) um jede Seite – auch während des Übergangs, damit sich
/// zwei durchsichtige Seiten nie überlagern.
class _MitHintergrund extends PageTransitionsBuilder {
  const _MitHintergrund();
  static const _basis = ZoomPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
          PageRoute<T> route, BuildContext context, Animation<double> a, Animation<double> b, Widget child) =>
      _basis.buildTransitions(route, context, a, b, Hintergrund(child: child));
}

/// Look „Dämmerung“: Dämmerblau, Glas, Grün, Lavendel.
ThemeData _thema() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6FAF55), brightness: Brightness.dark).copyWith(
    primary: F.ac,
    onPrimary: const Color(0xFF14321B),
    primaryContainer: const Color(0xFF3F7A3A),
    onPrimaryContainer: F.tx,
    secondary: F.lav,
    onSecondary: const Color(0xFF221D45),
    secondaryContainer: const Color(0x33FFFFFF),
    onSecondaryContainer: F.tx,
    surface: flaeche,
    onSurface: F.tx,
    onSurfaceVariant: F.mu,
    surfaceContainerLowest: const Color(0xFF3D5A82),
    surfaceContainerLow: const Color(0xFF44618A),
    surfaceContainer: flaeche,
    surfaceContainerHigh: const Color(0xFF526E97),
    surfaceContainerHighest: const Color(0xFF5B779F),
    outline: const Color(0x99FFFFFF),
    outlineVariant: const Color(0x4DFFFFFF),
    error: F.bad,
    onError: const Color(0xFF4A0D16),
    errorContainer: const Color(0x66B03A4A),
    onErrorContainer: F.tx,
  );
  final basis = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final p in TargetPlatform.values) p: const _MitHintergrund(),
    }),
  );
  return basis.copyWith(
    textTheme: basis.textTheme.apply(bodyColor: F.tx, displayColor: F.tx),
    iconTheme: const IconThemeData(color: F.tx),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: F.rosa,
      titleTextStyle: basis.textTheme.titleLarge!.copyWith(fontSize: 24, fontWeight: FontWeight.w700, color: F.rosa),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: flaeche,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26), side: const BorderSide(color: Color(0x40FFFFFF))),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: flaeche,
      modalBackgroundColor: flaeche,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Color(0x80FFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: F.bg,
      contentTextStyle: const TextStyle(color: F.tx),
      actionTextColor: F.ac2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    popupMenuTheme: const PopupMenuThemeData(color: flaeche, surfaceTintColor: Colors.transparent),
    timePickerTheme: const TimePickerThemeData(backgroundColor: flaeche),
    datePickerTheme: const DatePickerThemeData(backgroundColor: flaeche, surfaceTintColor: Colors.transparent),
    dividerTheme: const DividerThemeData(color: Color(0x33FFFFFF)),
    listTileTheme: const ListTileThemeData(iconColor: F.mu, textColor: F.tx),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: F.ac2)),
  );
}

class _TaperingBuddyState extends State<TaperingBuddy> {
  bool _splashVorbei = false;

  @override
  Widget build(BuildContext context) {
    // Neuer Schlüssel bei jedem Sprachwechsel: die App baut sich komplett neu auf (alle Texte frisch).
    return ValueListenableBuilder<String?>(
        valueListenable: widget.app.spracheNotifier,
        builder: (context, sprache, _) => _app(sprache));
  }

  Widget _app(String? sprache) {
    return MaterialApp(
      key: ValueKey('sprache_$sprache'),
      title: 'BeNzoTaPer',
      debugShowCheckedModeBanner: false,
      theme: _thema(),
      // Eingebaute Dialoge (Datum, Uhrzeit) folgen der App-Sprache, nicht der Handysprache.
      // Englisch als en_GB: Woche ab Montag, Datum TT/MM/JJJJ wie im Rest der App.
      locale: sprache == 'en' ? const Locale('en', 'GB') : const Locale('de'),
      supportedLocales: const [Locale('de'), Locale('en', 'GB')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // PIN-Sperre liegt über allem (auch über geöffneten Seiten); darunter bleibt alles erhalten.
      builder: (context, kind) => ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          final zu = _splashVorbei && widget.app.bereit && widget.app.gesperrt;
          return Stack(children: [
            Offstage(offstage: zu, child: kind),
            if (zu)
              HeroControllerScope.none(
                child: Navigator(
                  key: const ValueKey('sperre'),
                  onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => SperrSeite(app: widget.app)),
                ),
              ),
          ]);
        },
      ),
      home: ListenableBuilder(
        listenable: widget.app,
        builder: (context, _) {
          final a = widget.app;
          if (!_splashVorbei || !a.bereit) {
            return Splash(dauer: widget.splashDauer, weiter: () => setState(() => _splashVorbei = true));
          }
          if (a.ladeFehler != null) return LadeFehlerSeite(app: a);
          if (a.sprache == null) return SprachWahlSeite(app: a);
          if (!a.hinweisGesehen) return HinweisSeite(app: a);
          // Neuer Schlüssel nach geladener Sicherung: alles frisch, nichts Altes in Feldern.
          return Shell(key: ValueKey(a.stand), app: a);
        },
      ),
    );
  }
}
