// Sprache der Oberfläche. Es ist immer nur eine Sprache aktiv (Deutsch oder Englisch); sie wird beim
// ersten Start gewählt und lässt sich in „Mehr“ wechseln. Texte stehen im Quelltext als Paar
// (`tr('Heute', 'Today')`): Deutsch und Englisch bleiben nebeneinander, nichts geht auseinander.
import 'package:tapering_core/tapering_core.dart';

class Txt {
  Txt._();

  /// Englisch aktiv? (Standard: Deutsch.) Wird von `AppState` gesetzt.
  static bool en = false;

  static String get code => en ? 'en' : 'de';

  static void setzen(String? code) => en = code == 'en';
}

/// Text in der aktiven Sprache.
String tr(String de, String en) => Txt.en ? en : de;

/// Zahl: Deutsch „2,5“, Englisch „2.5“.
String fz(num x) {
  final s = fmt(x);
  return Txt.en ? s.replaceAll(',', '.') : s;
}

/// Zahl aus einem Kern-Wert (z. B. `numStr`) in der aktiven Schreibweise.
String zahlText(String s) => Txt.en ? s : s.replaceAll('.', ',');

/// Datum „JJJJ-MM-TT“ → Deutsch „TT.MM.JJJJ“, Englisch „DD/MM/YYYY“.
String datum(String k) {
  if (!Txt.en) return dmy(k);
  final p = k.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

/// Kurzes Datum ohne Jahr: Deutsch „TT.MM.“, Englisch „DD/MM“.
String datumKurz(String k) {
  final p = k.split('-');
  return Txt.en ? '${p[2]}/${p[1]}' : '${p[2]}.${p[1]}.';
}

/// Wochentage, Montag zuerst.
List<String> wochentageKurz() =>
    Txt.en ? const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'] : const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// Wochentage, Sonntag zuerst (wie JavaScript `getDay`).
List<String> wochentageKurzSo() =>
    Txt.en ? const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'] : const ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

List<String> monatsnamen() => Txt.en
    ? const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']
    : const ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

/// Zusammenfassung eines Plans ab Stufe [sg]: „5 mg jetzt · 4 Stufen · ca. 56 Tage“ (Gegenstück zu
/// `Taper.planSum` im Kern, das den deutschen Text fürs Protokoll liefert).
String planSumme(Taper ta, List<double> plan, List<int>? days, int sg) {
  var t = 0;
  for (var i = sg; i < plan.length; i++) {
    t += (days != null && i < days.length && days[i] > 0) ? days[i] : ta.st.target;
  }
  final u = ta.st.unit;
  return tr('${fz(plan[sg])} $u jetzt · ${plan.length - sg} Stufen · ca. $t Tage',
      '${fz(plan[sg])} $u now · ${plan.length - sg} steps · approx. $t days');
}

/// Text der vorgemerkten Änderung (die gespeicherte Fassung `Pend.txt` ist Deutsch und gehört ins Protokoll).
String pendText(Taper ta, Pend p) {
  if (p.kind == 'left' && p.stage != null && p.next != null) {
    return tr('Stufe ${p.stage! + 1} verlängern, nächste Stufe ab ${datum(p.next!)}',
        'Extend step ${p.stage! + 1}, next step from ${datum(p.next!)}');
  }
  final o = p.o;
  final a = ta.s;
  if (p.kind == 'plan' && o != null && a != null) {
    return tr('Plan ändern: ', 'Change plan: ') + '${planSumme(ta, a.plan, a.days, a.stage)} → ${planSumme(ta, o.plan, o.days, o.stage)}';
  }
  return p.txt;
}
