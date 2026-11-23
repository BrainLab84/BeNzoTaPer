// Verlaufsbericht (Logbuch): Inhalt, Zählung, keine Notizen/Begründungen, PDF.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/logbuch.dart';

import 'hilfen.dart';
import 'sicherung_ui_test.dart' show FakeDateien;

Map<String, dynamic> _stand() {
  final j = basis(start: '2026-03-01', log: {
    for (var d = 1; d <= 3; d++) '2026-03-0$d': eintrag(10, 10),
    // 04.03.: mehr als geplant, zwei Einnahmen mit Uhrzeit
    '2026-03-04': {
      'it': [
        {'t': '08:15', 'v': 10, 'ts': 0},
        {'t': '21:40', 'v': 2.5, 'ts': 1},
      ],
      'dose': 12.5,
      'plan': 10,
      'stage': 0,
      'r': 'lapse',
    },
    '2026-03-05': eintrag(7.5, 10), // weniger
    // 06.03. fehlt (?), 07.03. „weiß ich nicht mehr“
    for (var d = 8; d <= 9; d++) '2026-03-0$d': eintrag(10, 10),
  });
  j['unk'] = ['2026-03-07'];
  j['notes'] = {
    '2026-03-04': {'sx': [], 'sym': 4, 'text': 'geheime Notiz'},
  };
  j['chg'] = [
    {'ts': 1, 'd': '2026-03-02', 't': 'Stufe 1 gehalten für 3 Tage (bis 05.03.2026)'},
    {'ts': 2, 'd': '2026-03-05', 't': 'Halten nach Plan beendet (05.03.2026)'},
    {'ts': 3, 'd': '2026-03-08', 't': 'Vorgemerkt (48 h): Plan ändern: x → y · Grund: geheimer Grund'},
    {'ts': 4, 'd': '2026-03-09', 't': 'Nachgetragen (06.03., 10 mg)'},
  ];
  return j;
}

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Logbuch: Tage, Zählung, Halten, Ereignisse ohne Begründung', (t) async {
    final app = await starte(t, json: _stand());
    final b = logbuchErstellen(app.taper);
    expect(b.tage.map((x) => x.tag).first, '2026-03-01');
    expect(b.tage.map((x) => x.tag).last, '2026-03-09', reason: 'heute ohne Eintrag kommt nicht als ?');
    expect(b.zahl(TagArt.imPlan), 5);
    expect(b.zahl(TagArt.mehr), 1);
    expect(b.zahl(TagArt.weniger), 1);
    expect(b.zahl(TagArt.offen), 2, reason: '06.03. und 07.03.');
    expect(b.gehalten, 3, reason: '02.–04.03.');
    final mehr = b.tage.firstWhere((x) => x.tag == '2026-03-04');
    expect([for (final i in mehr.its) '${i.t} ${i.v}'], ['08:15 10.0', '21:40 2.5']);
    expect(b.ereignisse.map((e) => e.$2), ['Dosis gehalten (Stufe 1), 3 Tage', 'Halten beendet'],
        reason: 'Vormerkung (mit Grund) und Nachtragen gehören nicht hinein');
    expect(b.wochen.first.avg, closeTo((10 * 3 + 12.5 + 7.5) / 5, 1e-9), reason: '01.–07.03.: 5 Tage eingetragen');
    expect(b.wochen.first.n, 5);
  });

  testWidgets('Lesen: Logbuch in der App, keine Notiz, kein Grund; Teilen als PDF', (t) async {
    final d = FakeDateien();
    final app = await starte(t, json: _stand(), aufReiter: 'Fortschritt', dateien: d);
    expect(find.byKey(const Key('logbuchKarte')), findsOneWidget);
    expect(find.byKey(const Key('berichtTeilen')), findsOneWidget, reason: 'Diagramm-PDF bleibt daneben');
    await tippe(t, find.byKey(const Key('logbuchLesen')));
    expect(find.text('Verlaufsbericht für den Arzt'), findsOneWidget);
    expect(txt('Mehr als geplant: 1'), findsOneWidget);
    expect(txt('Ohne Eintrag (?): 2'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('logTag-2026-03-04')), 200,
        scrollable: find.descendant(of: find.byKey(const Key('logbuchListe')), matching: find.byType(Scrollable)).first);
    expect(txt('08:15 10, 21:40 2,5'), findsOneWidget, reason: 'Einnahmen mit Uhrzeit');
    expect(txt('mehr als geplant (+2,5 mg)'), findsOneWidget);
    expect(txt('geheime Notiz'), findsNothing);
    expect(txt('geheimer Grund'), findsNothing);
    expect(txt('Grund'), findsNothing);

    await t.runAsync(() async {
      final pdf = await logbuchPdf(app);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });
    await t.tap(find.byKey(const Key('logbuchTeilenSeite')));
    for (var i = 0; i < 50 && d.bytes == null; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    expect(d.bytesName, 'Verlaufsbericht_2026-03-10.pdf');
    expect(d.bytesMime, 'application/pdf');
  });
}
