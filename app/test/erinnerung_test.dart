// Erinnerung zum Eintragen: standardmäßig aus, Erlaubnis, Uhrzeit, nur Tage ohne Eintrag.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/erinnerung.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';

class FakeErinnerer implements Erinnerer {
  bool erlaubt = true;
  int gefragt = 0;
  List<DateTime>? geplant;
  List<VorratPush> vorrat = const [];
  int aufrufe = 0;
  @override
  Future<bool> erlaubnis() async {
    gefragt++;
    return erlaubt;
  }

  @override
  Future<void> planen(List<DateTime> zeiten, {List<VorratPush> vorrat = const []}) async {
    aufrufe++;
    geplant = zeiten;
    this.vorrat = vorrat;
  }
}

Future<(AppState, FakeErinnerer, MemStore)> los(WidgetTester t, {bool plan = true}) async {
  t.view.physicalSize = const Size(1000, 5000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final f = FakeErinnerer();
  final store = MemStore()..disc = true;
  final app = AppState(store, clock: () => jetzt, erinnerer: f);
  await t.runAsync(app.laden);
  if (plan) expect(app.taper.setup(dose: 10, step: 1, minStep: .5, days: 14, goal: 0), isNull);
  await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpAndSettle();
  return (app, f, store);
}

void main() {
  // Mittags (lokal), damit 20:00 heute noch kommt – in jeder Zeitzone.
  setUp(() => jetzt = DateTime(2026, 3, 10, 12).toUtc());

  testWidgets('Standard aus: nichts geplant, nicht gefragt', (t) async {
    final (app, f, _) = await los(t);
    app.aenderung();
    await t.pumpAndSettle();
    expect(app.erinnerung.an, isFalse);
    expect(f.gefragt, 0);
    expect(f.aufrufe, 0);
  });

  testWidgets('Einschalten in Mehr: Erlaubnis, 30 Tage ab heute 20:00, gespeichert', (t) async {
    final (app, f, store) = await los(t);
    await tippe(t, find.byTooltip('Mehr'));
    expect(txt('Kein Ton, kein Pop-up.'), findsOneWidget);
    await tippe(t, find.byKey(const Key('erinnerungSchalter')));
    expect(f.gefragt, 1);
    expect(app.erinnerung.an, isTrue);
    expect(f.geplant!.length, erinnerungTage);
    expect(f.geplant!.first, DateTime(2026, 3, 10, 20));
    expect(store.einstellungen, contains('"an":true'));
    expect(find.byKey(const Key('erinnerungUhrzeit')), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
  });

  testWidgets('Erlaubnis verweigert: bleibt aus, kurzer Hinweis', (t) async {
    final (app, f, _) = await los(t);
    f.erlaubt = false;
    await tippe(t, find.byTooltip('Mehr'));
    await tippe(t, find.byKey(const Key('erinnerungSchalter')));
    expect(app.erinnerung.an, isFalse);
    expect(txt('Benachrichtigungen sind für die App aus.'), findsOneWidget);
    expect(f.aufrufe, 0);
  });

  testWidgets('Heute eingetragen: heute keine Erinnerung, ab morgen schon', (t) async {
    final (app, f, _) = await los(t);
    await app.erinnerungSetzen(app.erinnerung.mit(an: true));
    await t.pumpAndSettle();
    expect(f.geplant!.first.day, 10);
    app.taper.addIntake(10);
    app.aenderung();
    await t.pumpAndSettle();
    expect(f.geplant!.first, DateTime(2026, 3, 11, 20));
    // Eintrag gelöscht → heute wieder dabei
    app.taper.delIntake(0, app.taper.today);
    app.aenderung();
    await t.pumpAndSettle();
    expect(f.geplant!.first.day, 10);
  });

  testWidgets('Uhrzeit schon vorbei: erst morgen; Ausschalten löscht alles', (t) async {
    jetzt = DateTime(2026, 3, 10, 21).toUtc();
    final (app, f, _) = await los(t);
    await app.erinnerungSetzen(app.erinnerung.mit(an: true, stunde: 7, minute: 30));
    await t.pumpAndSettle();
    expect(f.geplant!.first, DateTime(2026, 3, 11, 7, 30));
    await app.erinnerungSetzen(app.erinnerung.mit(an: false));
    await t.pumpAndSettle();
    expect(f.geplant, isEmpty);
  });

  testWidgets('Beispielplan: keine Erinnerung möglich', (t) async {
    final (app, f, _) = await los(t, plan: false);
    expect(app.beispiel, isTrue);
    await tippe(t, find.byTooltip('Mehr'));
    expect(find.byKey(const Key('erinnerungSchalter')), findsNothing);
    expect(erinnerungZeiten(app, const ErinnerungEinstellung(an: true)), isEmpty);
    expect(f.aufrufe, 0);
  });

  test('Einstellung: kaputte Werte → Standard', () {
    expect(ErinnerungEinstellung.fromJson({'an': true, 'h': 99, 'm': -1}).uhrzeit, '20:00');
    expect(ErinnerungEinstellung.fromJson('x').an, isFalse);
    expect(ErinnerungEinstellung.fromJson({'an': true, 'h': 7, 'm': 5}).uhrzeit, '07:05');
  });

  // Vorrat-Push bei 14 und 7 Tagen, „Fakten + Nachschub“, an sobald Vorrat eingetragen.
  testWidgets('Vorrat-Push: 14 und 7 Tage vorher um 10 Uhr, Text, abschaltbar', (t) async {
    final (app, f, store) = await los(t);
    expect(app.vorratPush, isTrue, reason: 'Standard an');
    app.taper.setStock(200, 1); // 14 × 10 + 6 × 9 = 194 → reicht 20 Tage (10.3.–29.3.)
    app.aenderung();
    await app.vorratGespeichert();
    await t.pumpAndSettle();
    expect(app.taper.stockInfo()!.days, 20);
    expect(f.gefragt, 1, reason: 'Erlaubnis beim ersten Vorrat');
    expect(f.vorrat.map((v) => v.zeit).toList(), [DateTime(2026, 3, 16, 10), DateTime(2026, 3, 23, 10)]);
    expect(f.vorrat.first.text,
        'Vorrat reicht noch ca. 14 Tage (bis 29.03.2026). Kümmere dich rechtzeitig um Nachschub.');
    expect(f.vorrat.last.text, 'Vorrat reicht noch ca. 7 Tage (bis 29.03.2026). Kümmere dich rechtzeitig um Nachschub.');
    expect(f.geplant, isEmpty, reason: 'Eintrage-Erinnerung bleibt aus');

    await tippe(t, find.byTooltip('Mehr'));
    await tippe(t, find.byKey(const Key('vorratPushSchalter')));
    expect(app.vorratPush, isFalse);
    expect(f.vorrat, isEmpty);
    expect(store.einstellungen, contains('"vp":false'));
  });

  testWidgets('Vorrat-Push: schon knapp → nur die 7-Tage-Meldung; ≤ 7 → keine', (t) async {
    final (app, f, _) = await los(t);
    app.taper.setStock(100, 1); // 10 Tage
    app.aenderung();
    await t.pumpAndSettle();
    expect(f.vorrat.map((v) => v.zeit).toList(), [DateTime(2026, 3, 13, 10)]);
    app.taper.setStock(60, 1); // 6 Tage
    app.aenderung();
    await t.pumpAndSettle();
    expect(f.vorrat, isEmpty);
  });

  testWidgets('Vorrat-Push: Erlaubnis verweigert → aus', (t) async {
    final (app, f, _) = await los(t);
    f.erlaubt = false;
    app.taper.setStock(200, 1);
    app.aenderung();
    await app.vorratGespeichert();
    await t.pumpAndSettle();
    expect(app.vorratPush, isFalse);
    expect(f.vorrat, isEmpty);
  });

  // Vorrat schon da, aber nie gefragt (Update von 106 / Sicherung auf neuem Handy).
  testWidgets('Vorrat-Hinweis: einmal nachfragen, wenn ein Vorrat schon da ist – danach nie wieder', (t) async {
    final (app, f, store) = await los(t);
    app.taper.setStock(200, 1);
    app.aenderung();
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(f.gefragt, 0, reason: 'nur Kern geändert, nichts gespeichert über die Karte');
    // Neustart wie nach dem Update: Einstellungen ohne „vpq“
    store.einstellungen = null;
    final f2 = FakeErinnerer();
    final app2 = AppState(store, clock: () => jetzt, erinnerer: f2);
    await t.runAsync(app2.laden);
    await t.pumpWidget(const SizedBox()); // frischer Start (sonst übernimmt Flutter die alte Shell)
    await t.pumpWidget(TaperingBuddy(app: app2, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(f2.gefragt, 1, reason: 'einmal gefragt');
    expect(app2.vorratPush, isTrue);
    expect(store.einstellungen, contains('"vpq":true'));
    // Nächster Start: nicht nochmal fragen
    final f3 = FakeErinnerer();
    final app3 = AppState(store, clock: () => jetzt, erinnerer: f3);
    await t.runAsync(app3.laden);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(TaperingBuddy(app: app3, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(f3.gefragt, 0);
    expect(f3.vorrat, isNotEmpty, reason: 'Hinweise trotzdem geplant');
  });

  testWidgets('Vorrat-Hinweis: Nachfrage abgelehnt → aus, Schalter zeigt aus', (t) async {
    final (app, _, store) = await los(t);
    app.taper.setStock(200, 1);
    app.aenderung();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    store.einstellungen = null;
    final f2 = FakeErinnerer()..erlaubt = false;
    final app2 = AppState(store, clock: () => jetzt, erinnerer: f2);
    await t.runAsync(app2.laden);
    await t.pumpWidget(const SizedBox()); // frischer Start (sonst übernimmt Flutter die alte Shell)
    await t.pumpWidget(TaperingBuddy(app: app2, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(f2.gefragt, 1);
    expect(app2.vorratPush, isFalse);
    expect(f2.vorrat, isEmpty);
    await tippe(t, find.byTooltip('Mehr'));
    expect(t.widget<SwitchListTile>(find.byKey(const Key('vorratPushSchalter'))).value, isFalse);
  });

  testWidgets('Ohne Vorrat keine Nachfrage beim Start', (t) async {
    final (_, f, _) = await los(t);
    await t.pumpAndSettle();
    expect(f.gefragt, 0);
  });
}
