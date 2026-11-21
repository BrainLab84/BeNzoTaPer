// Gemeinsame Bausteine der Oberfläche: Farben, Karten, Kartentitel, ?-Knopf, Zahlen lesen.
import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'anleitung.dart';
import 'deko.dart';
import 'i18n/txt.dart';

/// Farben im Look „Dämmerung“: Dämmerblau, Glas-Karten,
/// Grün für „genommen“/erledigt, Lavendel für Kommendes. Davor „Wie das Symbol“ (Nachtblau + Türkis).
class F {
  static const ok = Color(0xFFA8DC86);
  static const oks = Color(0x2EA8DC86);
  static const warn = Color(0xFFFFC98A);
  static const bad = Color(0xFFFF9AA6);
  static const bads = Color(0x33FF9AA6);
  static const ac = Color(0xFFA8DC86);
  static const ac2 = Color(0xFFC9EDAE);
  static const acs = Color(0x2EA8DC86);
  static const acs2 = Color(0x4DA8DC86);
  static const pri = Color(0xFF5E9E48);
  static const gold = Color(0xFFFFE08A);
  static const mu = Color(0xFFE3E7F3);
  static const mu2 = Color(0xFFBCC6E2);
  static const tx = Color(0xFFFBF7FB);
  static const bg = Color(0xFF2F4A70);
  static const card = Color(0xFF4A6690);
  static const card2 = Color(0xFF55719A);
  static const line = Color(0xFF6B83AA);
  static const line2 = Color(0xFF8C9FC4);
  // neu mit „Dämmerung“
  static const rosa = Color(0xFFFBEAF3); // Kartentitel, Überschriften
  static const lav = Color(0xFFC2BDF0); // kommende Stufen
  static const mauve = Color(0xFF9A6F92); // „Tag x/y“
  static const glas = Color(0x1FFFFFFF);
  static const glasRand = Color(0x4DFFFFFF);
  static const acRand = Color(0x99C9EDAE); // hervorgehobene Karte
  static const acFlaeche = Color(0x1FA8DC86);
  static const sos = Color(0xFFD9505F);
}

/// Wie `parseFloat(text.replace(',', '.'))` : führende Zahl, sonst null.
double? zahl(String s) {
  final v = jsParseFloat(s.replaceFirst(',', '.'));
  // „1e400“ wäre unendlich – zählt als keine Zahl.
  return (v == null || !v.isFinite) ? null : v;
}

/// Ganze Zahl wie `Math.round(num(...))`.
int? ganzZahl(String s) {
  final v = zahl(s);
  return v == null ? null : jsRound(v).toInt();
}

/// "1 Tag" / "3 Tage".
String tage(int n) => tr('$n ${n == 1 ? 'Tag' : 'Tage'}', '$n ${n == 1 ? 'day' : 'days'}');

/// Karte im Look „Dämmerung“ als Glas: halbdurchsichtig, heller Rand, weicher
/// Schatten nur nach außen. [hintergrund] liegt hinter dem Inhalt (z. B. Landschaft, Lavendel), auf die
/// Kartenform zugeschnitten.
class Karte extends StatelessWidget {
  const Karte(
      {super.key, required this.children, this.rand, this.farbe, this.mitte = false, this.padding, this.hintergrund});
  final List<Widget> children;
  final Color? rand;
  final Color? farbe;
  final bool mitte;
  final EdgeInsets? padding;
  final Widget? hintergrund;
  @override
  Widget build(BuildContext context) {
    final inhalt = Padding(
      padding: padding ?? const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: mitte ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: hintergrund == null ? Clip.none : Clip.antiAlias,
      decoration: BoxDecoration(
        color: farbe,
        gradient: farbe != null
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x29FFFFFF), Color(0x14FFFFFF)]),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: rand ?? F.glasRand),
        boxShadow: const [
          BoxShadow(color: Color(0x330B1830), blurRadius: 20, blurStyle: BlurStyle.outer)
        ],
      ),
      child: hintergrund == null
          ? inhalt
          : Stack(children: [Positioned.fill(child: IgnorePointer(child: hintergrund!)), inhalt]),
    );
  }
}

/// Kartentitel (klein, Großbuchstaben, grau). [hilfe] = ?-Knopf.
class KartenTitel extends StatelessWidget {
  const KartenTitel(this.text, {super.key, this.icon, this.hilfe, this.farbe});
  final String text;
  final IconData? icon;
  final String? hilfe;
  final Color? farbe;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 17, color: farbe ?? F.rosa), const SizedBox(width: 8)],
          Flexible(
            child: Text(text.toUpperCase(),
                style: TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w600, color: farbe ?? F.rosa)),
          ),
          if (hilfe != null) HilfeKnopf(hilfe!),
        ]),
      );
}

/// Kleiner ?-Knopf, öffnet die passende Stelle der Anleitung.
class HilfeKnopf extends StatelessWidget {
  const HilfeKnopf(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tr('Erklärung', 'Explanation'),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => zeigeHilfe(context, id),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x99FFFFFF))),
              child: const Text('?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: F.mu)),
            ),
          ),
        ),
      );
}

/// Grauer Hinweistext wie `.sub`.
class Sub extends StatelessWidget {
  const Sub(this.text, {super.key, this.oben = 0, this.mitte = false});
  final String text;
  final double oben;
  final bool mitte;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: oben),
        child: Text(text,
            textAlign: mitte ? TextAlign.center : TextAlign.start, style: const TextStyle(color: F.mu, fontSize: 14)),
      );
}

/// Feldbeschriftung wie `label`.
class Feldname extends StatelessWidget {
  const Feldname(this.text, {super.key, this.oben = 14});
  final String text;
  final double oben;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: oben, bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 13, color: F.mu, fontWeight: FontWeight.w500)),
      );
}

/// Zeile Icon + Text (für Statuszeilen).
class IconText extends StatelessWidget {
  const IconText(this.icon, this.text, {super.key, this.farbe, this.gross = 16, this.fett = false, this.mitte = false});
  final IconData icon;
  final String text;
  final Color? farbe;
  final double gross;
  final bool fett;
  final bool mitte;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: mitte ? MainAxisAlignment.center : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 6),
            child: Icon(icon, size: gross + 2, color: farbe),
          ),
          Flexible(
            child: Text(text,
                style: TextStyle(color: farbe, fontSize: gross, fontWeight: fett ? FontWeight.w700 : FontWeight.w400)),
          ),
        ],
      );
}

/// Eingabefeld (Glas), mit roter Umrandung bei [fehler].
InputDecoration feldStil({String? hinweis, bool fehler = false}) => InputDecoration(
      hintText: hinweis,
      hintStyle: const TextStyle(color: F.mu2),
      isDense: true,
      filled: true,
      fillColor: const Color(0x14FFFFFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: fehler ? F.bad : const Color(0x66FFFFFF))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: fehler ? F.bad : F.ac2, width: 1.5)),
    );

/// Knöpfe: [hauptKnopf] gefüllt, [knopf] umrandet.
/// Beschriftung mit optionalem Icon hinter dem Text (z. B. „Gespeichert ✓“).
Widget _beschriftung(String text, IconData? nachIcon) => nachIcon == null
    ? Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))
    : Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 6),
        Icon(nachIcon, size: 18),
      ]);

/// Grüner Verlauf des Hauptknopfs.
const gruenVerlauf = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF94C862), Color(0xFF5E9E48), Color(0xFF2E6C3B)],
  stops: [0, .55, 1],
);

/// Hauptknopf: grüne Pille mit Blattzweig rechts (rechts mehr Innenabstand, damit das Blatt frei steht).
/// [blatt] = false für halbbreite Knöpfe neben einem anderen Knopf. Ohne LayoutBuilder, damit der Knopf
/// auch in `IntrinsicHeight` funktioniert.
Widget hauptKnopf(String text, VoidCallback? onTap,
        {IconData? icon, IconData? nachIcon, Key? key, bool blatt = true}) =>
    SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          gradient: onTap == null ? null : gruenVerlauf,
          color: onTap == null ? const Color(0x1AFFFFFF) : null,
          border: Border.all(color: onTap == null ? const Color(0x33FFFFFF) : const Color(0x80D5F0B8)),
          boxShadow:
              onTap == null ? null : const [BoxShadow(color: Color(0x33102414), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Stack(fit: StackFit.passthrough, children: [
          if (onTap != null && blatt)
            const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: KnopfBlattMaler()))),
          FilledButton.icon(
            key: key,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledForegroundColor: const Color(0x99FFFFFF),
              padding: blatt ? const EdgeInsets.fromLTRB(22, 16, 46, 16) : const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            onPressed: onTap,
            icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 22),
            label: DefaultTextStyle.merge(style: const TextStyle(fontSize: 16.5), child: _beschriftung(text, nachIcon)),
          ),
        ]),
      ),
    );

/// Zweitknopf: Glas mit hellem Rand.
Widget knopf(String text, VoidCallback? onTap,
        {IconData? icon, IconData? nachIcon, Color? hinten, Color? vorne, Color? rand, bool breit = true, Key? key}) =>
    SizedBox(
      width: breit ? double.infinity : null,
      child: OutlinedButton.icon(
        key: key,
        style: OutlinedButton.styleFrom(
          backgroundColor: hinten ?? const Color(0x1AFFFFFF),
          foregroundColor: vorne ?? F.tx,
          side: BorderSide(color: rand ?? const Color(0x66FFFFFF)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        onPressed: onTap,
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
        label: _beschriftung(text, nachIcon),
      ),
    );

/// Icon mitten im Text.
WidgetSpan ikon(IconData i, {double groesse = 16, Color? farbe}) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Icon(i, size: groesse, color: farbe),
    );

/// Ist mindestens [dp] Platz – gemessen bei normaler Schriftgröße? Mit großer Schrift braucht derselbe
/// Inhalt mehr Platz; auf schmalen Handys kommen Knöpfe und Felder dann untereinander, damit kein Wort
/// mitten drin umbricht.
bool genugPlatz(BuildContext context, BoxConstraints c, double dp) =>
    c.maxWidth >= MediaQuery.textScalerOf(context).scale(dp);

/// Runder Glas-Kreis (Kopfzeile), Schatten nur nach außen.
class GlasKreis extends StatelessWidget {
  const GlasKreis({super.key, required this.child, this.groesse = 48});
  final Widget child;
  final double groesse;
  @override
  Widget build(BuildContext context) => Container(
        width: groesse,
        height: groesse,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x3DFFFFFF), Color(0x1FFFFFFF)]),
          border: Border.fromBorderSide(BorderSide(color: Color(0x40FFFFFF))),
          boxShadow: [BoxShadow(color: Color(0x400B1830), blurRadius: 12, blurStyle: BlurStyle.outer)],
        ),
        child: child,
      );
}

/// Runder Glas-Knopf mit Symbol (Kalender, Zahnrad).
Widget glasKnopf({Key? key, required IconData icon, required VoidCallback onTap, String? tooltip}) => GlasKreis(
      child: IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onTap,
        iconSize: 24,
        color: F.rosa,
        icon: Icon(icon),
      ),
    );
