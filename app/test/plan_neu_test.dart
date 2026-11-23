import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/pin.dart';
import 'package:tapering_buddy/plan_kopf.dart';
import 'package:tapering_buddy/plan_lesen.dart';
import 'package:tapering_buddy/plan_neu.dart';
import 'package:tapering_core/tapering_core.dart' show EditRow;
import 'package:tapering_buddy/sicherung.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';

class DateiAttrappe implements Dateien {
  ({String name, List<int> bytes})? datei;
  @override
  Future<({String name, List<int> bytes})?> dateiWaehlen() async => datei;
  @override
  Future<String?> oeffnen() async => null;
  @override
  Future<void> teilen(String name, String inhalt) async {}
  @override
  Future<void> teilenBytes(String name, List<int> bytes, String mime) async {}
}

Future<AppState> ohnePlan(WidgetTester t, {Dateien? dateien}) async {
  t.view.physicalSize = const Size(1000, 6000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final app = AppState(MemStore()..disc = true, clock: () => jetzt, dateien: dateien);
  await t.runAsync(app.laden);
  await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpAndSettle();
  return app;
}

Future<void> weiter(WidgetTester t) => tippe(t, find.byKey(const Key('planWeiter')));

Future<void> abschnitt(WidgetTester t, int i, String schritt, String tage, String bis) async {
  await t.enterText(find.byKey(Key('abSchritt$i')), schritt);
  await t.enterText(find.byKey(Key('abTage$i')), tage);
  await t.enterText(find.byKey(Key('abBis$i')), bis);
  await t.pump();
}

List<int> docx(String text) {
  final xml = '<?xml version="1.0"?><w:document><w:body>'
      '${text.split('\n').map((z) => '<w:p><w:r><w:t>${z.replaceAll('&', '&amp;')}</w:t></w:r></w:p>').join()}'
      '</w:body></w:document>';
  final a = Archive()..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 12));

  testWidgets('Startdatum in 5 Tagen: Heute ruhig, Kalender leer bis zum Start, dann normal', (t) async {
    final app = await ohnePlan(t);
    await tippe(t, find.byKey(const Key('planErstellen')));
    await weiter(t);
    expect(find.text('Heute (10.03.2026)'), findsOneWidget, reason: 'vorausgewählt heute');
    expect(txt('Schon mitten im Abdosieren? Fang einfach mit deiner aktuellen Dosis an.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('planDosis')), '10');
    await abschnitt(t, 0, '1', '14', '0');
    // 10 Stufenwechsel à 14 = 140 Tage ab heute → 28.07.2026
    expect(txt('Voraussichtlich bei 0 mg: 28.07.2026'), findsOneWidget);
    await tippe(t, find.byKey(const Key('planStart')));
    await tippe(t, find.text('15'));
    await tippe(t, find.text('OK'));
    expect(find.text('15.03.2026'), findsOneWidget);
    expect(txt('Voraussichtlich bei 0 mg: 02.08.2026'), findsOneWidget, reason: 'Vorschau ab Startdatum');
    await weiter(t);
    await weiter(t);
    await tippe(t, find.text("Los geht's"));
    await tippe(t, find.text('Überspringen'));

    final s = app.taper.st;
    expect(s.t0, '2026-03-15');
    expect(app.taper.vorStart, isTrue);
    await reiter(t, 'Heute');
    expect(find.byKey(const Key('vorStart')), findsOneWidget);
    expect(txt('Plan startet am 15.03.2026'), findsOneWidget);
    expect(txt('Startdosis: 10 mg pro Tag'), findsOneWidget);
    expect(find.byKey(const Key('einnahme')), findsNothing, reason: 'nichts zum Eintragen');
    expect(find.byKey(const Key('dosis')), findsNothing);
    expect(find.byKey(const Key('vorratKarte')), findsOneWidget, reason: 'Vorrat kann man schon eintragen');
    await reiter(t, 'Kalender');
    expect(txt('Plan startet am 15.03.2026'), findsOneWidget);
    expect(txt('Voraussichtlich bei 0 mg: 02.08.2026'), findsOneWidget);
    String zelle(String k) => [
          for (final e in find.descendant(of: find.byKey(Key('tag-$k')), matching: find.byType(Text)).evaluate())
            (e.widget as Text).data ?? ''
        ].join('|');
    expect(zelle('2026-03-12'), isNot(contains('10')), reason: 'vor dem Start keine Dosis');
    expect(zelle('2026-03-15'), contains('10'), reason: 'ab Start die Startdosis');

    // Starttag: alles wie gewohnt.
    jetzt = DateTime.utc(2026, 3, 15, 9);
    app.auffrischen();
    await t.pumpAndSettle();
    await reiter(t, 'Heute');
    expect(app.taper.vorStart, isFalse);
    expect(find.byKey(const Key('vorStart')), findsNothing);
    expect(find.byKey(const Key('einnahme')), findsOneWidget);
    expect(app.taper.st.frz, isNull, reason: 'Vorlauftage sind keine offenen Tage');
    await nehme(t, '10');
    expect(app.taper.st.log['2026-03-15']!.dose, 10);
  });

  testWidgets('Erster Plan: Name, zwei Abschnitte, Arzt, „passt sich an“ → Begrüßung', (t) async {
    final app = await ohnePlan(t);
    await tippe(t, find.byKey(const Key('planErstellen')));
    expect(find.text('Schön, dass du da bist.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('planPerson')), 'Alex');
    await weiter(t);

    expect(find.text('Wie sieht dein Abdosierplan aus?'), findsOneWidget);
    await weiter(t);
    expect(find.text('Bitte deine aktuelle Tagesdosis eintragen.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('planDosis')), '20');
    await abschnitt(t, 0, '2,5', '14', '10');
    await tippe(t, find.byKey(const Key('abschnittPlus')));
    await abschnitt(t, 1, '1', '21', '0');
    expect(find.text('15 Stufen · 20 → 0 mg'), findsOneWidget);
    // 4 Stufen à 14 + 10 Stufen à 21 = 266 Tage ab 10.03.2026
    expect(txt('Voraussichtlich bei 0 mg: 01.12.2026'), findsOneWidget);
    await weiter(t);

    expect(find.text('Bitte sprich deinen Plan mit deinem Arzt ab.'), findsOneWidget);
    await weiter(t);
    expect(find.text('Wichtig: Dein Plan passt sich an'), findsOneWidget);
    expect(find.byKey(const Key('planSicher')), findsNothing, reason: 'erster Plan: keine Bestätigung nötig');
    await tippe(t, find.text("Los geht's"));

    final s = app.taper.st;
    expect(s.person, 'Alex');
    expect(s.name, 'Diazepam');
    expect(s.plan, [20, 17.5, 15, 12.5, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);
    expect(app.taper.need(4), 21);
    // Danach einmal die PIN anbieten, überspringbar.
    expect(find.byType(PinEinrichtenSeite), findsOneWidget);
    expect(find.text('Möchtest du die App mit einer PIN schützen?'), findsOneWidget);
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.pin, isNull);
    expect(find.text('Hallo Alex'), findsOneWidget);
    expect(find.text('Dein Plan ist gespeichert.'), findsOneWidget);
    await reiter(t, 'Kalender');
    expect(txt('Voraussichtlich bei 0 mg: 01.12.2026'), findsOneWidget, reason: 'Kalender rechnet gleich');
    await reiter(t, 'Plan');
    expect(find.text('Diazepam · 20 → 0 mg'), findsOneWidget);
    expect(txt('Voraussichtlich bei 0 mg: 01.12.2026'), findsOneWidget);
  });

  testWidgets('Ohne Namen: keine Begrüßung; Zurück behält die Eingaben', (t) async {
    final app = await ohnePlan(t);
    await tippe(t, find.byKey(const Key('planErstellen')));
    await weiter(t);
    await t.enterText(find.byKey(const Key('planDosis')), '10');
    await abschnitt(t, 0, '1', '14', '0');
    await weiter(t);
    await tippe(t, find.text('Zurück'));
    expect(find.widgetWithText(TextField, '10'), findsOneWidget);
    await weiter(t);
    await weiter(t);
    await tippe(t, find.byKey(const Key('planLos')));
    expect(app.taper.st.person, isNull);
    expect(find.byKey(const Key('begruessung')), findsNothing);
    expect(app.taper.st.plan.length, 11);
  });

  testWidgets('Fehler im Abschnitt werden genannt', (t) async {
    await ohnePlan(t);
    await tippe(t, find.byKey(const Key('planErstellen')));
    await weiter(t);
    await t.enterText(find.byKey(const Key('planDosis')), '10');
    await abschnitt(t, 0, '1', '14', '12');
    await weiter(t);
    expect(find.text('„Bis“ muss kleiner sein als die Startdosis (10).'), findsOneWidget);
    await abschnitt(t, 0, '', '14', '0');
    await weiter(t);
    expect(find.text('Bitte eintragen, um wie viel du jeweils runtergehst.'), findsOneWidget);
  });

  testWidgets('Weiterer Abschnitt: vorheriges „bis 0“ wird geleert, klare Meldungen', (t) async {
    await ohnePlan(t);
    await tippe(t, find.byKey(const Key('planErstellen')));
    await weiter(t);
    await t.enterText(find.byKey(const Key('planDosis')), '20');
    await abschnitt(t, 0, '2', '14', '0');
    await tippe(t, find.byKey(const Key('abschnittPlus')));
    TextField feld(String k) => t.widget<TextField>(find.byKey(Key(k)));
    expect(feld('abBis0').controller!.text, '', reason: 'Abschnitt 1 ging bis 0 → leer');
    expect(feld('abBis0').decoration!.hintText, 'z. B. 20');
    expect(feld('abBis1').controller!.text, '0', reason: 'der neue geht bis zum Ziel');
    await t.enterText(find.byKey(const Key('abSchritt1')), '1');
    await weiter(t);
    expect(txt('Abschnitt 1: Bitte bei „bis“ eintragen, wo dieser Abschnitt aufhören soll.'), findsOneWidget);
    // Der alte Fehlerfall: Abschnitt 1 wieder bis 0 → verständliche Meldung statt „unter 0“
    await t.enterText(find.byKey(const Key('abBis0')), '0');
    await weiter(t);
    expect(txt('Abschnitt 1 endet schon bei 0 – trag dort bei „bis“ ein, wo er aufhören soll, oder lösch Abschnitt 2.'),
        findsOneWidget);
    expect(txt('unter 0'), findsNothing);
    await t.enterText(find.byKey(const Key('abBis0')), '10');
    await t.pumpAndSettle();
    expect(find.text('16 Stufen · 20 → 0 mg'), findsOneWidget, reason: '20…10 in 2er-, dann 9…0 in 1er-Schritten');
    // Selbst eingetragenes Zwischenziel bleibt beim nächsten Abschnitt stehen
    await tippe(t, find.byKey(const Key('abschnittPlus')));
    expect(feld('abBis0').controller!.text, '10');
  });

  testWidgets('Neuer Plan bei bestehendem: erst „Bist du dir sicher?“; schneller sofort', (t) async {
    final app = await starte(t, aufReiter: 'Plan');
    app.taper.st.person = 'Alex';
    await tippe(t, find.byKey(const Key('planErstellen')));
    expect(find.text('Bist du dir sicher?'), findsOneWidget);
    expect(txt(planBackupSatz), findsOneWidget);
    bool weiterAn() => t.widget<FilledButton>(find.byKey(const Key('planSicherWeiter'))).onPressed != null;
    expect(weiterAn(), isFalse);
    await t.enterText(find.byKey(const Key('planSicherText')), 'ja ich bin mir');
    await tippe(t, find.byKey(const Key('planBackupHaken')));
    expect(weiterAn(), isFalse, reason: 'Satz unvollständig');
    await t.enterText(find.byKey(const Key('planSicherText')), 'ja,  Ich bin mir sicher.');
    await t.pumpAndSettle();
    expect(weiterAn(), isTrue);
    await tippe(t, find.byKey(const Key('planBackupHaken')));
    expect(weiterAn(), isFalse, reason: 'ohne Häkchen');
    await tippe(t, find.text('Abbrechen'));
    expect(find.byKey(const Key('planSicherDialog')), findsNothing);
    expect(find.byType(PlanNeuSeite), findsNothing, reason: 'Abbrechen = kein Fragebogen');

    await tippe(t, find.byKey(const Key('planErstellen')));
    await planSicherBestaetigen(t);
    // Neustart = wie neu installiert: nichts vom alten Plan vorbelegt
    expect(t.widget<TextField>(find.byKey(const Key('planPerson'))).controller!.text, '');
    await weiter(t);
    expect(t.widget<TextField>(find.byKey(const Key('planDosis'))).controller!.text, '', reason: 'keine alte Dosis');
    await t.enterText(find.byKey(const Key('planDosis')), '10');
    await abschnitt(t, 0, '2', '14', '0');
    await weiter(t);
    await weiter(t);
    expect(txt('Kalender und Tagebuch bleiben erhalten.'), findsNothing, reason: 'Neustart: nichts bleibt');
    expect(find.byKey(const Key('planSicher')), findsNothing, reason: 'schon im Fenster bestätigt');
    await tippe(t, find.byKey(const Key('planLos')));
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.plan, [10, 8, 6, 4, 2, 0]);
    expect(app.taper.st.pend, isNull);
    // Neustart: ein frischer Plan, kein „geändert am“.
    await reiter(t, 'Plan');
    expect(find.text('Plan gestartet am 10.03.2026'), findsOneWidget);
  });

  testWidgets('Plan-Karte: „Plan gestartet am …“ ohne Änderung', (t) async {
    await starte(t, json: basis(), aufReiter: 'Plan');
    expect(find.text('Plan gestartet am 01.03.2026'), findsOneWidget);
  });

  testWidgets('Langsamerer neuer Plan: Neustart sofort, keine Bedenkzeit', (t) async {
    final app = await starte(t, aufReiter: 'Plan');
    await tippe(t, find.byKey(const Key('planErstellen')));
    await planSicherBestaetigen(t);
    await weiter(t);
    await t.enterText(find.byKey(const Key('planDosis')), '10');
    await abschnitt(t, 0, '0,5', '21', '0');
    await weiter(t);
    await weiter(t);
    await tippe(t, find.byKey(const Key('planLos')));
    expect(txt('48 Stunden Bedenkzeit'), findsNothing);
    await tippe(t, find.text('Überspringen'));
    expect(app.taper.st.pend, isNull);
    expect(app.taper.st.plan.length, 21);
    expect(app.taper.need(0), 21);
  });

  testWidgets('Alte Vormerkung (frühere Version): nach 48 h auf Heute übernehmen', (t) async {
    final app = await starte(t, aufReiter: 'Heute');
    // So entstand eine Vormerkung bis v0.2.1: Plan über den bestehenden ersetzt, langsamer, mit Grund.
    final e = app.taper.openEditor(neu: true)
      ..rows = [for (var i = 0; i < 21; i++) EditRow(10 - i * 0.5, 21)]
      ..conf = 'Ich bin mir sicher';
    expect(app.taper.applyPlan(e).askWhy, isTrue);
    e.why = 'Zu schnell für mich';
    expect(app.taper.applyPlan(e).pended, isTrue);
    app.aenderung();
    await t.pumpAndSettle();
    expect(app.taper.st.plan.length, 11, reason: 'alter Plan gilt weiter');
    app.taper.addIntake(10, k: '2026-03-10', force: true);
    jetzt = DateTime.utc(2026, 3, 12, 13);
    app.taper.addIntake(10, k: '2026-03-11');
    app.auffrischen();
    await t.pumpAndSettle();
    expect(txt('Die Bedenkzeit ist vorbei.'), findsOneWidget);
    await tippe(t, find.text('Übernehmen'));
    expect(find.byKey(const Key('planSicherDialog')), findsNothing, reason: 'Vormerkung ist kein Neustart');
    expect(find.text('Vorgemerkte Änderung – bitte prüfen und übernehmen.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('planSicher')), 'Ich bin mir sicher');
    await tippe(t, find.byKey(const Key('planLos')));
    expect(app.taper.st.pend, isNull);
    expect(app.taper.st.plan.length, 21);
    expect(app.taper.st.log, isNotEmpty, reason: 'Vormerkung ändert den Plan, löscht nichts');
  });

  testWidgets('Importieren: Text einfügen, prüfen, „Ich bin gerade bei“', (t) async {
    final app = await ohnePlan(t);
    await tippe(t, find.byKey(const Key('planImportieren')));
    await t.enterText(find.byKey(const Key('planPerson')), 'Petra');
    await weiter(t);
    expect(find.text('Plan übernehmen'), findsOneWidget);
    await weiter(t);
    expect(find.text('Noch keine Schritte angelegt.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('importText')), 'Woche 1-2: 10 mg\nWoche 3-4: 9 mg\nWoche 5-6: 8 mg');
    await tippe(t, find.byKey(const Key('textAuslesen')));
    expect(txt('3 Schritte erkannt.'), findsOneWidget);
    expect(txt('3 Stufen · 10 → 8 mg'), findsOneWidget);
    await t.enterText(find.byKey(const Key('zDosis2')), '7,5');
    await t.pump();
    await tippe(t, find.byKey(const ValueKey('start-3')));
    await tippe(t, find.text('Stufe 2 · 9 mg').last);
    await weiter(t);
    await weiter(t);
    await tippe(t, find.byKey(const Key('planLos')));
    final s = app.taper.st;
    expect(s.plan, [10, 9, 7.5]);
    expect(s.stage, 1);
    expect(s.person, 'Petra');
    await tippe(t, find.text('Überspringen'));
    expect(find.text('Hallo Petra'), findsOneWidget);
  });

  testWidgets('Importieren aus Datei (Word)', (t) async {
    final d = DateiAttrappe()..datei = (name: 'plan.docx', bytes: docx('Tag 1–14: 10 mg\nTag 15–28: 9,5 mg'));
    await ohnePlan(t, dateien: d);
    await tippe(t, find.byKey(const Key('planImportieren')));
    await weiter(t);
    await tippe(t, find.byKey(const Key('dateiWaehlen')));
    expect(txt('2 Schritte erkannt.'), findsOneWidget);
    expect(find.widgetWithText(TextField, '9,5'), findsOneWidget);
  });

  testWidgets('Importieren: Foto wird freundlich abgelehnt', (t) async {
    final d = DateiAttrappe()..datei = (name: 'scan.jpg', bytes: [1, 2, 3]);
    await ohnePlan(t, dateien: d);
    await tippe(t, find.byKey(const Key('planImportieren')));
    await weiter(t);
    await tippe(t, find.byKey(const Key('dateiWaehlen')));
    expect(find.text('Fotos und Scans gehen nicht. Bitte den Text abtippen oder einfügen.'), findsOneWidget);
  });

  testWidgets('Plan-Reiter: alle Stufen, aktuelle markiert', (t) async {
    await starte(t, aufReiter: 'Plan');
    expect(titel('Stufen'), findsOneWidget);
    expect(txt('Stufe 1 · jetzt'), findsOneWidget);
    expect(txt('Stufe 11'), findsOneWidget);
    expect(find.text('0 mg'), findsWidgets);
  });

  test('Datei lesen: Word, Text, PDF über Leser, alte .doc', () async {
    expect(
        await textAusDatei('a.docx', docx('Woche 1: 5 mg\nWoche 2: 4 & 3 mg')), 'Woche 1: 5 mg\nWoche 2: 4 & 3 mg\n');
    expect(await textAusDatei('a.txt', utf8.encode('10 mg für 14 Tage')), '10 mg für 14 Tage');
    expect(await textAusDatei('a.PDF', [0], pdf: (_) async => 'aus PDF'), 'aus PDF');
    await expectLater(textAusDatei('a.doc', [0]), throwsA(isA<LeseFehler>()));
    await expectLater(textAusDatei('kaputt.docx', [1, 2, 3]), throwsA(isA<LeseFehler>()));
  });
}
