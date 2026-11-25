// Allgemeines Notizbuch: oben links, tagesunabhängig, speichern/ändern/löschen,
// bleibt nach Neustart, kommt mit in die Sicherung, „Alles löschen“ leert es. SOS oben in der Mitte.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/notizbuch.dart';
import 'package:tapering_buddy/sos.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';

void main() {
  setUp(() => jetzt = DateTime.utc(2026, 3, 10, 9));
  testWidgets('SOS oben in der Mitte, kein Knopf mehr unten rechts', (t) async {
    await starte(t);
    final sos = find.byKey(const Key('sosKnopf'));
    expect(find.descendant(of: find.byType(AppBar), matching: sos), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    final mitte = t.getCenter(sos).dx;
    final breite = t.view.physicalSize.width / t.view.devicePixelRatio;
    expect((mitte - breite / 2).abs(), lessThan(4), reason: 'mittig');
    await t.tap(sos);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(SosSeite), findsOneWidget);
  });

  testWidgets('Notizbuch: schreiben, ändern, löschen; bleibt nach Neustart', (t) async {
    final app = await starte(t);
    await tippe(t, find.byKey(const Key('notizbuchKnopf')));
    expect(find.byType(NotizbuchSeite), findsOneWidget);
    expect(find.text(notizbuchHinweis), findsOneWidget);
    expect(find.text('Noch keine Notizen.'), findsOneWidget);
    expect(find.byKey(const Key('notizbuchNeu')), findsNothing, reason: 'erst nach „Neue Notiz“');
    await tippe(t, find.byKey(const Key('notizbuchNeueNotiz')));
    await t.enterText(find.byKey(const Key('notizbuchNeu')), 'Morgens spazieren tut gut');
    await t.pump();
    await tippe(t, find.byKey(const Key('notizbuchSpeichern')));
    expect(find.byKey(const Key('notizbuchNeu')), findsNothing, reason: 'nach dem Speichern festgeschrieben');
    jetzt = jetzt.add(const Duration(minutes: 5));
    await tippe(t, find.byKey(const Key('notizbuchNeueNotiz')));
    await t.enterText(find.byKey(const Key('notizbuchNeu')), 'Arzttermin vorbereiten');
    await t.pump();
    await tippe(t, find.byKey(const Key('notizbuchSpeichern')));
    expect(app.notizbuch.map((e) => e.text), ['Arzttermin vorbereiten', 'Morgens spazieren tut gut']);
    expect(
        t.getTopLeft(find.text('Arzttermin vorbereiten')).dy < t.getTopLeft(find.text('Morgens spazieren tut gut')).dy,
        isTrue,
        reason: 'neueste oben');

    // Öffnen = nur lesen
    await tippe(t, find.text('Morgens spazieren tut gut'));
    expect(find.byType(NotizSeite), findsOneWidget);
    expect(find.byKey(const Key('notizbuchText')), findsNothing);
    expect(
        find.descendant(of: find.byKey(const Key('notizbuchLesen')), matching: find.text('Morgens spazieren tut gut')),
        findsOneWidget);
    // Bearbeiten → ändern → Speichern → wieder lesen
    await tippe(t, find.byKey(const Key('notizbuchBearbeiten')));
    await t.enterText(find.byKey(const Key('notizbuchText')), 'Morgens spazieren tut richtig gut');
    await t.pump();
    await tippe(t, find.byKey(const Key('notizbuchAendern')));
    expect(find.byKey(const Key('notizbuchText')), findsNothing);
    expect(find.text('Morgens spazieren tut richtig gut'), findsOneWidget);
    await zurueck(t);
    await t.pumpAndSettle();
    expect(find.text('Morgens spazieren tut richtig gut'), findsOneWidget);

    await tippe(t, find.text('Arzttermin vorbereiten'));
    await tippe(t, find.byKey(const Key('notizbuchLoeschen')));
    expect(find.text('Wirklich löschen?'), findsOneWidget);
    await tippe(t, find.byKey(const Key('notizbuchLoeschen')));
    expect(app.notizbuch.map((e) => e.text), ['Morgens spazieren tut richtig gut']);

    // Neustart: aus dem Speicher
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    final neu = AppState(app.store, clock: () => jetzt);
    await t.runAsync(neu.laden);
    expect(neu.notizbuch.map((e) => e.text), ['Morgens spazieren tut richtig gut']);
  });

  testWidgets('Notizbuch: in der Sicherung, „Alles löschen“ leert es', (t) async {
    final app = await starte(t);
    app.notizSchreiben('Gedanke');
    final datei = (await t.runAsync(() => app.sicherungErstellen()))!;
    expect(jsonDecode(datei)['notizbuch'][0]['text'], 'Gedanke');
    app.allesLoeschen();
    expect(app.notizbuch, isEmpty);
    expect((app.store as MemStore).notizbuch, '[]');
    await t.runAsync(() => app.sicherungLaden(datei));
    expect(app.notizbuch.map((e) => e.text), ['Gedanke'], reason: 'aus der Sicherung zurück');
  });

  testWidgets('Notizbuch geht auch im Beispiel (ohne eigenen Plan)', (t) async {
    final app = await starte(t, einrichten: false, aufReiter: null);
    expect(app.beispiel, isTrue);
    await tippe(t, find.byKey(const Key('notizbuchKnopf')));
    await tippe(t, find.byKey(const Key('notizbuchNeueNotiz')));
    await t.enterText(find.byKey(const Key('notizbuchNeu')), 'Erst mal umschauen');
    await t.pump();
    await tippe(t, find.byKey(const Key('notizbuchSpeichern')));
    expect(app.notizbuch.single.text, 'Erst mal umschauen');
  });
}
