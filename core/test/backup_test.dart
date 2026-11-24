import 'dart:convert';

import 'package:tapering_core/tapering_core.dart';
import 'package:test/test.dart';

import 'sim.dart';

/// Schnelle Argon2-Werte für die meisten Tests; ein Test läuft mit den echten Standardwerten.
const schnell = KdfWerte(speicherKiB: 64, durchlaeufe: 1, spuren: 1);

String echterStand() {
  final w = Sim();
  w.setup(10, 10, 14);
  for (var d = 0; d < 20; d++) {
    w.take(d % 5 != 0 ? 10 : 11);
    w.day();
  }
  return jsonEncode(w.e.exportJson());
}

void main() {
  test('Hin und zurück mit Standardwerten (echter Stand, Umlaute)', () async {
    final klar = echterStand();
    final sw = Stopwatch()..start();
    final enc = await sicherungVerschluesseln(klar, 'Grüße-ß 2026!');
    final dec = await sicherungEntschluesseln(enc, 'Grüße-ß 2026!');
    sw.stop();
    expect(dec, klar);
    expect(istVerschluesselt(enc), isTrue);
    expect(enc.contains('"plan"'), isFalse, reason: 'kein Klartext in der Datei');
    final o = jsonDecode(enc) as Map;
    expect([o['m'], o['t'], o['p']], [19456, 2, 1]);
    // ignore: avoid_print
    print('Standardwerte: ${sw.elapsedMilliseconds} ms für Ver- und Entschlüsseln');

    // Import in den Kern wie bisher.
    final w2 = Sim();
    w2.setup(5);
    expect(w2.e.importJson(jsonDecode(dec)), isTrue);
  });

  test('Falsches Passwort', () async {
    final enc = await sicherungVerschluesseln('{"a":1}', 'richtig123', werte: schnell);
    await expectLater(sicherungEntschluesseln(enc, 'falsch123'),
        throwsA(isA<SicherungException>().having((e) => e.fehler, 'fehler', SicherungFehler.passwortFalsch)));
    await expectLater(sicherungEntschluesseln(enc, ''),
        throwsA(isA<SicherungException>().having((e) => e.fehler, 'fehler', SicherungFehler.passwortFalsch)));
  });

  test('Jede Sicherung anders (Salt/Nonce zufällig)', () async {
    final a = await sicherungVerschluesseln('{"a":1}', 'passwort1', werte: schnell);
    final b = await sicherungVerschluesseln('{"a":1}', 'passwort1', werte: schnell);
    expect(a == b, isFalse);
    expect(jsonDecode(a)['salt'] == jsonDecode(b)['salt'], isFalse);
  });

  Future<void> erwarte(String text, SicherungFehler f) => expectLater(sicherungEntschluesseln(text, 'passwort1'),
      throwsA(isA<SicherungException>().having((e) => e.fehler, 'fehler', f)));

  test('Manipulation fällt auf', () async {
    final enc = await sicherungVerschluesseln('{"plan":[10,9]}', 'passwort1', werte: schnell);
    Map o() => jsonDecode(enc) as Map;

    // Ein Bit in den Daten kippen.
    final d = base64.decode(o()['daten'] as String);
    d[3] ^= 1;
    await erwarte(jsonEncode(o()..['daten'] = base64.encode(d)), SicherungFehler.passwortFalsch);

    // Kopf verändern (Argon2-Werte sind im Prüfwert eingebunden).
    await erwarte(jsonEncode(o()..['t'] = 2), SicherungFehler.passwortFalsch);

    // Nonce verändern.
    final n = base64.decode(o()['nonce'] as String);
    n[0] ^= 1;
    await erwarte(jsonEncode(o()..['nonce'] = base64.encode(n)), SicherungFehler.passwortFalsch);

    // Abgeschnitten.
    final dd = base64.decode(o()['daten'] as String);
    await erwarte(
        jsonEncode(o()..['daten'] = base64.encode(dd.sublist(0, dd.length - 1))), SicherungFehler.passwortFalsch);
    await erwarte(jsonEncode(o()..['daten'] = base64.encode(dd.sublist(0, 6))), SicherungFehler.kaputt);
    await erwarte(enc.substring(0, enc.length - 5), SicherungFehler.kaputt);
  });

  test('Kaputte oder fremde Dateien', () async {
    final enc = await sicherungVerschluesseln('{}', 'passwort1', werte: schnell);
    Map o() => jsonDecode(enc) as Map;
    await erwarte('', SicherungFehler.kaputt);
    await erwarte('kein json', SicherungFehler.kaputt);
    await erwarte('{"plan":[1]}', SicherungFehler.kaputt);
    await erwarte(jsonEncode(o()..['v'] = 2), SicherungFehler.zuNeu);
    await erwarte(jsonEncode(o()..['kdf'] = 'pbkdf2'), SicherungFehler.kaputt);
    await erwarte(jsonEncode(o()..remove('salt')), SicherungFehler.kaputt);
    await erwarte(jsonEncode(o()..['nonce'] = 'AAAA'), SicherungFehler.kaputt);
    await erwarte(jsonEncode(o()..['salt'] = '###'), SicherungFehler.kaputt);
    // Präparierte Riesenwerte werden gar nicht erst gerechnet.
    await erwarte(jsonEncode(o()..['m'] = 4000000), SicherungFehler.kaputt);
    await erwarte(jsonEncode(o()..['t'] = 1000), SicherungFehler.kaputt);
  });

  test('Erkennung: alte Klartext-Sicherung vs. verschlüsselt', () async {
    final klar = echterStand();
    expect(istVerschluesselt(klar), isFalse);
    expect(istVerschluesselt('quatsch'), isFalse);
    expect(istVerschluesselt(await sicherungVerschluesseln(klar, 'passwort1', werte: schnell)), isTrue);
  });

  test('Leeres Passwort beim Verschlüsseln abgelehnt', () {
    expect(() => sicherungVerschluesseln('{}', ''), throwsArgumentError);
  });

  test('Feste Testdatei bleibt lesbar (Format eingefroren)', () async {
    // Mit festen Werten erzeugt; ändert sich das Format versehentlich, schlägt das fehl.
    final enc = await sicherungVerschluesseln('{"plan":[10]}', 'passwort1',
        werte: schnell, testSalt: List.filled(16, 7), testNonce: List.filled(12, 9));
    expect(enc, _eingefroren);
    expect(await sicherungEntschluesseln(_eingefroren, 'passwort1'), '{"plan":[10]}');
  });

  test('Vorab-Prüfung ohne Passwort: kaputt/zu neu vor der Ersetzen-Rückfrage erkennen', () async {
    final t = Taper(clock: () => DateTime.utc(2026, 3, 10, 12));
    expect(t.setup(dose: 10, step: 1, minStep: .5, days: 14, goal: 0), isNull);
    final klar = jsonEncode(t.exportJson());
    expect(sicherungVorpruefen(klar), isNull, reason: 'alte Klartext-Sicherung');
    final ver = await sicherungVerschluesseln(klar, 'geheim123', werte: const KdfWerte(speicherKiB: 64, durchlaeufe: 1));
    expect(sicherungVorpruefen(ver), isNull, reason: 'verschlüsselt, Aufbau gültig');
    expect(sicherungVorpruefen('kein json'), SicherungFehler.kaputt);
    expect(sicherungVorpruefen('{"irgendwas": 1}'), SicherungFehler.kaputt);
    expect(sicherungVorpruefen(klar.substring(0, klar.length ~/ 2)), SicherungFehler.kaputt, reason: 'abgeschnitten');
    final o = jsonDecode(ver) as Map;
    expect(sicherungVorpruefen(jsonEncode({...o, 'v': sicherungVersion + 1})), SicherungFehler.zuNeu);
    expect(sicherungVorpruefen(jsonEncode({...o, 'nonce': 'AAAA'})), SicherungFehler.kaputt);
    expect(sicherungVorpruefen(jsonEncode({...o, 'm': 999999999})), SicherungFehler.kaputt, reason: 'Argon2-Grenzen');
    // Was die Vorprüfung durchlässt, muss auch entschlüsselbar sein (gleiche Regeln)
    expect(await sicherungEntschluesseln(ver, 'geheim123'), klar);
  });
}

const _eingefroren =
    '{"format":"tapering-buddy-sicherung","v":1,"kdf":"argon2id","m":64,"t":1,"p":1,"salt":"BwcHBwcHBwcHBwcHBwcHBw==","nonce":"CQkJCQkJCQkJCQkJ","daten":"vYdaZzfpbeckxSMq82Lyt45gD4lP49mOszJUdNI="}';
