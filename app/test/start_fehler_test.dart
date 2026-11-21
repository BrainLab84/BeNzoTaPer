// Start darf nie am Logo hängen bleiben: Fehler beim Öffnen der Daten → Fehlerseite + „Nochmal versuchen“.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/start.dart';
import 'package:tapering_buddy/store.dart';

import 'hilfen.dart';

class KaputterStore extends MemStore {
  bool kaputt = true;
  @override
  Future<bool> discSeen() async {
    if (kaputt) throw Exception('App-Ordner nicht erreichbar');
    return super.discSeen();
  }
}

void main() {
  testWidgets('Daten nicht lesbar: Fehlerseite statt Logo, nichts überschrieben, nochmal versuchen', (t) async {
    final store = KaputterStore()
      ..disc = true
      ..state = null;
    final app = AppState(store, clock: () => jetzt);
    await t.runAsync(app.laden);
    expect(app.bereit, isTrue, reason: 'laden() endet immer');
    expect(app.ladeFehler, contains('App-Ordner nicht erreichbar'));
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(find.byType(LadeFehlerSeite), findsOneWidget);
    expect(find.byType(Splash), findsNothing);
    store.kaputt = false;
    await t.tap(find.byKey(const Key('nochmalLaden')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pumpAndSettle();
    expect(app.ladeFehler, isNull);
    expect(find.byType(LadeFehlerSeite), findsNothing);
    expect(find.text('Schön, dass du da bist.'), findsOneWidget, reason: 'danach normal (Startkarte im Kalender)');
  });
}
