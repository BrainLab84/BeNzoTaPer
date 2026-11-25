// Kleine Helfer: Datum als "JJJJ-MM-TT"-Text, Rundung.
//
// Alle Tagesrechnungen laufen über UTC-Mitternacht, damit Sommer-/Winterzeit
// nie einen Tag verschiebt.

/// Rundet wie JavaScript `Math.round` (.5 geht nach oben, auch bei negativen Zahlen).
double jsRound(double x) {
  final f = x.floorToDouble();
  return (x - f >= 0.5) ? f + 1 : f;
}

/// Auf 3 Nachkommastellen runden .
double round3(double x) => jsRound(x * 1000) / 1000;

/// Auf 2 Nachkommastellen runden (Durchschnitte, damit 0,01-mg-Schritte sichtbar sind).
double round2(double x) => jsRound(x * 100) / 100;

/// Auf 1 Nachkommastelle runden .
double round1(double x) => jsRound(x * 10) / 10;

/// Zahl als Text mit Komma, ohne ".0" .
String fmt(num x) => numStr(round3(x.toDouble())).replaceAll('.', ',');

/// Zahl wie JavaScript `String(x)`: ganze Zahlen ohne ".0".
String numStr(double x) {
  if (x.isInfinite) return x < 0 ? '-Infinity' : 'Infinity';
  if (x.isNaN) return 'NaN';
  if (x == x.truncateToDouble() && x.abs() < 1e21) return x.toInt().toString();
  return x.toString();
}

String _p2(int n) => n < 10 ? '0$n' : '$n';

/// Datum als "JJJJ-MM-TT".
String ymd(DateTime d) => '${d.year}-${_p2(d.month)}-${_p2(d.day)}';

DateTime _utc(String k) {
  final p = k.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// "JJJJ-MM-TT" -> Wochentag, 0 = Sonntag ... 6 = Samstag (wie JavaScript `getDay`).
int weekday0(String k) => _utc(k).weekday % 7;

/// Tag plus n Tage.
String addD(String k, int n) => ymd(_utc(k).add(Duration(days: n)));

/// Tage von a bis b (b später = positiv).
int dBetween(String a, String b) => (_utc(b).difference(_utc(a)).inHours / 24).round();

/// "JJJJ-MM-TT" -> "TT.MM.JJJJ".
String dmy(String k) {
  final p = k.split('-');
  return '${p[2]}.${p[1]}.${p[0]}';
}

/// "JJJJ-MM-TT" -> "TT.MM."
String lbl(String k) {
  final p = k.split('-');
  return '${p[2]}.${p[1]}.';
}

final RegExp _dateRx = RegExp(r'^\d{4}-\d{2}-\d{2}$');
bool isDateKey(Object? s) => s is String && _dateRx.hasMatch(s);

/// Wie JavaScript `parseInt(s, 10)`: führende Ziffern, sonst null.
int? jsParseInt(String s) {
  final m = RegExp(r'^\s*([-+]?\d+)').firstMatch(s);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Wie `parseFloat(s.replace(',', '.'))`: führende Zahl, sonst null.
double? jsParseFloat(String s) {
  final m = RegExp(r'^\s*([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)').firstMatch(s);
  return m == null ? null : double.parse(m.group(1)!);
}

int gcd(int a, int b) {
  a = a.abs();
  b = b.abs();
  while (b != 0) {
    final t = b;
    b = a % b;
    a = t;
  }
  return a;
}

/// Datumstexte ("JJJJ-MM-TT") lassen sich direkt vergleichen.
extension DateKeyCompare on String {
  bool operator <(String o) => compareTo(o) < 0;
  bool operator >(String o) => compareTo(o) > 0;
  bool operator <=(String o) => compareTo(o) <= 0;
  bool operator >=(String o) => compareTo(o) >= 0;
}
