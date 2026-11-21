import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'state.dart';

/// Verschlüsselte Sicherungsdatei.
///
/// Aufbau: lesbarer JSON-Kopf + verschlüsselte Daten.
/// ```
/// {"format":"tapering-buddy-sicherung","v":1,
///  "kdf":"argon2id","m":19456,"t":2,"p":1,"salt":"…",
///  "nonce":"…","daten":"…"}
/// ```
/// - Schlüssel: Argon2id aus dem Sicherungspasswort (eigenes Passwort, nicht die PIN).
/// - Verschlüsselung: AES-256-GCM. `daten` = Geheimtext + 16 Byte Prüfwert (Base64).
/// - Der Kopf (Format, Version, Argon2-Werte, Salt) ist als Zusatzdaten (AAD) in den
///   Prüfwert eingebunden: wer daran dreht, bekommt beim Öffnen einen Fehler.
/// - Ohne Passwort gibt es keinen Weg an die Daten. Passwort vergessen = Sicherung weg.
///
/// Unverschlüsselte Sicherungen bleiben das alte `strike-v1`-JSON ([TaperState.toJson]).
/// [istVerschluesselt] unterscheidet beides; der Import nimmt beide an.
const sicherungFormat = 'tapering-buddy-sicherung';
const sicherungVersion = 1;

/// Mindestlänge für das Sicherungspasswort (prüft die Oberfläche vor dem Export).
const minPasswortLaenge = 8;

/// Argon2id-Werte. Standard: OWASP-Empfehlung (19 MiB, 2 Durchläufe, 1 Spur).
class KdfWerte {
  const KdfWerte({this.speicherKiB = 19456, this.durchlaeufe = 2, this.spuren = 1});
  final int speicherKiB;
  final int durchlaeufe;
  final int spuren;

  /// Grenzen beim Öffnen: eine präparierte Datei soll das Handy nicht lahmlegen.
  bool get zulaessig =>
      speicherKiB >= 8 * spuren &&
      speicherKiB <= 262144 &&
      durchlaeufe >= 1 &&
      durchlaeufe <= 10 &&
      spuren >= 1 &&
      spuren <= 4;
}

enum SicherungFehler {
  /// Keine gültige Sicherungsdatei (beschädigt, abgeschnitten, fremdes Format).
  kaputt,

  /// Passwort stimmt nicht – oder die Datei wurde verändert (lässt sich nicht unterscheiden).
  passwortFalsch,

  /// Datei stammt aus einer neueren App-Version.
  zuNeu,
}

class SicherungException implements Exception {
  SicherungException(this.fehler);
  final SicherungFehler fehler;

  @override
  String toString() => 'SicherungException($fehler)';
}

/// Ist [text] eine verschlüsselte Sicherung (und nicht das alte Klartext-JSON)?
bool istVerschluesselt(String text) {
  try {
    final o = jsonDecode(text);
    return o is Map && o['format'] == sicherungFormat;
  } catch (_) {
    return false;
  }
}

List<int> _aad(int v, KdfWerte k, String salt) =>
    utf8.encode('$sicherungFormat|v$v|argon2id|${k.speicherKiB}|${k.durchlaeufe}|${k.spuren}|$salt');

Future<SecretKey> _schluessel(String passwort, List<int> salt, KdfWerte k) => DartArgon2id(
      parallelism: k.spuren,
      memory: k.speicherKiB,
      iterations: k.durchlaeufe,
      hashLength: 32,
    ).deriveKeyFromPassword(password: passwort, nonce: salt);

/// Verschlüsselt den Sicherungs-JSON-Text [klartext] mit [passwort].
/// [testSalt]/[testNonce] nur für Tests; sonst kryptografisch sicherer Zufall.
Future<String> sicherungVerschluesseln(String klartext, String passwort,
    {KdfWerte werte = const KdfWerte(), List<int>? testSalt, List<int>? testNonce}) async {
  if (passwort.isEmpty) throw ArgumentError('Passwort fehlt');
  final aes = DartAesGcm.with256bits();
  final salt = testSalt ?? SecretKeyData.random(length: 16).bytes;
  final nonce = testNonce ?? aes.newNonce();
  final saltB64 = base64.encode(salt);
  final key = await _schluessel(passwort, salt, werte);
  final box = await aes.encrypt(utf8.encode(klartext),
      secretKey: key, nonce: nonce, aad: _aad(sicherungVersion, werte, saltB64));
  return jsonEncode({
    'format': sicherungFormat,
    'v': sicherungVersion,
    'kdf': 'argon2id',
    'm': werte.speicherKiB,
    't': werte.durchlaeufe,
    'p': werte.spuren,
    'salt': saltB64,
    'nonce': base64.encode(nonce),
    'daten': base64.encode([...box.cipherText, ...box.mac.bytes]),
  });
}

/// Aufbau einer verschlüsselten Sicherung (ohne Passwort prüfbar).
class _Behaelter {
  _Behaelter(this.v, this.k, this.saltB64, this.salt, this.nonce, this.daten);
  final int v;
  final KdfWerte k;
  final String saltB64;
  final Uint8List salt, nonce, daten;
}

/// Liest den Behälter und prüft seinen Aufbau. Wirft [SicherungException].
_Behaelter _behaelter(String text) {
  Map o;
  try {
    final j = jsonDecode(text);
    if (j is! Map || j['format'] != sicherungFormat) throw 0;
    o = j;
  } catch (_) {
    throw SicherungException(SicherungFehler.kaputt);
  }
  final v = o['v'];
  if (v is! int) throw SicherungException(SicherungFehler.kaputt);
  if (v > sicherungVersion) throw SicherungException(SicherungFehler.zuNeu);
  if (v < 1 || o['kdf'] != 'argon2id') throw SicherungException(SicherungFehler.kaputt);

  final KdfWerte k;
  final String saltB64;
  final Uint8List salt, nonce, daten;
  try {
    k = KdfWerte(speicherKiB: o['m'] as int, durchlaeufe: o['t'] as int, spuren: o['p'] as int);
    saltB64 = o['salt'] as String;
    salt = base64.decode(saltB64);
    nonce = base64.decode(o['nonce'] as String);
    daten = base64.decode(o['daten'] as String);
  } catch (_) {
    throw SicherungException(SicherungFehler.kaputt);
  }
  if (!k.zulaessig || salt.length < 8 || nonce.length != 12 || daten.length < 16) {
    throw SicherungException(SicherungFehler.kaputt);
  }
  return _Behaelter(v, k, saltB64, salt, nonce, daten);
}

/// Vorab-Prüfung beim Laden, noch bevor gefragt wird, ob der Stand ersetzt werden soll
/// (vorher kam bei einer kaputten Datei erst „Stand ersetzen?“ und danach die Fehlermeldung).
/// Verschlüsselt: Aufbau prüfen (der Inhalt geht erst mit Passwort). Unverschlüsselt: muss ein Stand
/// sein, den [TaperState.fromJson] annimmt. `null` = sieht gültig aus.
SicherungFehler? sicherungVorpruefen(String text) {
  if (istVerschluesselt(text)) {
    try {
      _behaelter(text);
      return null;
    } on SicherungException catch (e) {
      return e.fehler;
    }
  }
  try {
    return TaperState.fromJson(jsonDecode(text)) == null ? SicherungFehler.kaputt : null;
  } catch (_) {
    return SicherungFehler.kaputt;
  }
}

/// Entschlüsselt eine Sicherung und gibt den JSON-Text zurück.
/// Wirft [SicherungException].
Future<String> sicherungEntschluesseln(String text, String passwort) async {
  final b = _behaelter(text);
  final v = b.v, k = b.k, saltB64 = b.saltB64, salt = b.salt, nonce = b.nonce, daten = b.daten;

  final key = await _schluessel(passwort, salt, k);
  final box = SecretBox(daten.sublist(0, daten.length - 16), nonce: nonce, mac: Mac(daten.sublist(daten.length - 16)));
  final List<int> klar;
  try {
    klar = await DartAesGcm.with256bits().decrypt(box, secretKey: key, aad: _aad(v, k, saltB64));
  } on SecretBoxAuthenticationError {
    throw SicherungException(SicherungFehler.passwortFalsch);
  }
  try {
    return utf8.decode(klar);
  } catch (_) {
    throw SicherungException(SicherungFehler.kaputt);
  }
}
