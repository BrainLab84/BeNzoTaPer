// Bilder aller Seiten wie auf einem Handy (1080 × 2340, Statusleiste 32 dp), Look „Dämmerung“.
// Benutzung (siehe tools/README.md): nach app/test/ kopieren, dann
//   SPR=en (englisch) SHOTS=/tmp/shots NUR=01,03 flutter test test/alle_seiten_shots_test.dart --update-goldens
// NUR = Liste von Anfängen der Fallnamen (leer = alle). Danach die Kopie wieder löschen.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapering_buddy/app_state.dart';
import 'package:tapering_buddy/bericht.dart';
import 'package:tapering_buddy/main.dart';
import 'package:tapering_buddy/store.dart';
import 'package:tapering_buddy/lob.dart';
import 'package:tapering_core/tapering_core.dart';

final ziel = Platform.environment['SHOTS'] ?? '/tmp/shots';
final nur = Platform.environment['NUR'];
final en = Platform.environment['SPR'] == 'en'; // SPR=en: englische Fassung

Future<void> font(String fam, List<String> files) async {
  final l = FontLoader(fam);
  for (final f in files) {
    l.addFont(Future.value(ByteData.sublistView(
        File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/$f').readAsBytesSync())));
  }
  await l.load();
}

String k(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, dynamic> geschichte() {
  final plan = <num>[10, 9.5, 9, 8.5, 8, 7.5, 7, 6.5, 6, 5.5, 5, 4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1, 0.5, 0];
  final start = DateTime.utc(2026, 8, 12);
  final log = <String, dynamic>{};
  final abw = {3: 1.0, 9: 0.5, 17: 1.5, 18: 1.0, 30: 0.5, 44: -0.5, 51: 1.0, 52: 0.5, 66: 0.5, 79: 1.0, 85: -0.5};
  for (var i = 0; i < 99; i++) {
    final st = i ~/ 14;
    final p = plan[st].toDouble();
    final v = p + (abw[i] ?? 0);
    log[k(start.add(Duration(days: i)))] = {
      'it': [{'t': '08:00', 'v': v, 'ts': 0}],
      'dose': v, 'plan': p, 'stage': st, 'r': v > p + 1e-9 ? 'lapse' : 'ok',
    };
  }
  return {
    'name': 'Diazepam', 'unit': 'mg', 'person': 'Alex', 'step': 0.5, 'min': 0.5, 'target': 14,
    'plan': plan, 'days': [for (final _ in plan) 14], 'stage': 7,
    'stageStart': k(start.add(const Duration(days: 98))), 't0': k(start), 'log': log,
    'notes': {k(start.add(const Duration(days: 97))): {'sx': 3, 'text': '4 Kaffee'}},
    'tabs': {'s': [5, 2], 'n': {'5': 3, '2': 6}},
  };
}

void main() {
  Future<AppState> start(WidgetTester t, {bool eigen = true, bool disc = true, double hoehe = 2340}) async {
    await t.runAsync(() async {
      await font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
      await font('MaterialIcons', ['MaterialIcons-Regular.otf']);
    });
    t.view.physicalSize = Size(1080, hoehe);
    t.view.devicePixelRatio = 2.625;
    t.view.padding = const FakeViewPadding(top: 2.625 * 32, bottom: 2.625 * 16);
    t.view.viewPadding = const FakeViewPadding(top: 2.625 * 32, bottom: 2.625 * 16);
    addTearDown(t.view.reset);
    final app = AppState(MemStore()..disc = disc, clock: () => DateTime.utc(2026, 11, 19, 12, 48));
    await t.runAsync(app.laden);
    await t.runAsync(() => app.spracheWaehlen(en ? 'en' : 'de'));
    if (eigen) expect(app.taper.importJson(geschichte()), isTrue);
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    return app;
  }

  Future<void> reiter(WidgetTester t, String name) async {
    await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(en ? {'Heute': 'Today', 'Fortschritt': 'Progress'}[name] ?? name : name)));
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String n, {bool settle = true}) async {
    if (settle) await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$ziel/$n.png'));
  }

  void fall(String n, Future<void> Function(WidgetTester) f) {
    testWidgets(n, (t) async {
      if (nur != null && !nur!.split(',').any((x) => n.startsWith(x))) return;
      await f(t);
    });
  }

  fall('01_beispiel_handy', (t) async {
    await start(t, eigen: false);
    await shot(t, '01_beispiel_handy');
  });
  fall('02_beispiel_lang', (t) async {
    await start(t, eigen: false, hoehe: 6200);
    await shot(t, '02_beispiel_lang');
  });
  fall('03_kalender_lang', (t) async {
    await start(t, hoehe: 6000);
    await shot(t, '03_kalender_lang');
  });
  fall('04_heute', (t) async {
    await start(t, hoehe: 5200);
    await reiter(t, 'Heute');
    await shot(t, '04_heute');
  });
  fall('05_plan', (t) async {
    await start(t, hoehe: 6400);
    await reiter(t, 'Plan');
    await shot(t, '05_plan');
  });
  fall('06_fortschritt', (t) async {
    await start(t, hoehe: 4600);
    await reiter(t, 'Fortschritt');
    await shot(t, '06_fortschritt');
  });
  fall('07_mehr', (t) async {
    await start(t, hoehe: 4400);
    await t.tap(find.byTooltip(en ? 'More' : 'Mehr'));
    await t.pumpAndSettle();
    await shot(t, '07_mehr');
  });
  fall('08_notizbuch', (t) async {
    final app = await start(t);
    app.notizSchreiben('Heute war ein ruhiger Tag. Spaziergang am Fluss, kaum Unruhe.');
    await t.tap(find.byKey(const Key('notizbuchKnopf')));
    await t.pumpAndSettle();
    await shot(t, '08_notizbuch');
  });
  fall('09_tagfenster', (t) async {
    await start(t);
    await t.scrollUntilVisible(find.byKey(const Key('tag-2026-11-17')), 300, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const Key('tag-2026-11-17')));
    await t.pumpAndSettle();
    await shot(t, '09_tagfenster');
  });
  fall('10_sos', (t) async {
    await start(t, hoehe: 3600);
    await t.tap(find.byKey(const Key('sosKnopf')));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    await shot(t, '10_sos', settle: false);
  });
  fall('11_hinweise', (t) async {
    await start(t, eigen: false, disc: false, hoehe: 4000);
    await shot(t, '11_hinweise');
  });
  fall('12_sperre', (t) async {
    final app = await start(t);
    app.pinSetzen('1234', '1234');
    app.sperren();
    await t.pumpAndSettle();
    await shot(t, '12_sperre');
  });
  fall('13_plan_neu', (t) async {
    await start(t, eigen: false, hoehe: 3600);
    await t.tap(find.text(en ? 'Create new plan' : 'Neuen Plan erstellen').first);
    await t.pumpAndSettle();
    await shot(t, '13_plan_neu');
  });

  fall('14_lob', (t) async {
    await t.runAsync(() async {
      await font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
      await font('MaterialIcons', ['MaterialIcons-Regular.otf']);
    });
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;
    t.view.padding = const FakeViewPadding(top: 2.625 * 32, bottom: 2.625 * 16);
    t.view.viewPadding = const FakeViewPadding(top: 2.625 * 32, bottom: 2.625 * 16);
    addTearDown(t.view.reset);
    var jetzt = DateTime.utc(2026, 11, 19, 12, 48);
    final app = AppState(MemStore()..disc = true, clock: () => jetzt);
    await t.runAsync(app.laden);
    await t.runAsync(() => app.spracheWaehlen(en ? 'en' : 'de'));
    expect(app.taper.importJson(geschichte()), isTrue);
    app.taper.startHold(null);
    final tage = lobTage(app.taper.st.holdSince!, bis: 40);
    for (var d = 0; d < tage[1]; d++) {
      app.taper.addIntake(app.taper.st.plan[app.taper.st.stage], force: true);
      jetzt = jetzt.add(const Duration(days: 1));
      app.taper.refresh();
    }
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    final lob = find.byKey(const Key('haltenLob'));
    await t.scrollUntilVisible(lob, 300, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    final y = t.getTopLeft(lob).dy;
    await t.drag(find.byType(Scrollable).first, Offset(0, -(y - 330)));
    await shot(t, '14_lob');
  });

  // „Voraussichtlich bei 0 mg: …“ statt „Plan pausiert“ – rückt beim Halten mit.
  Future<AppState> gehalten(WidgetTester t, int? tageHalten, int schonGehalten, {double hoehe = 2340}) async {
    await t.runAsync(() async {
      await font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
      await font('MaterialIcons', ['MaterialIcons-Regular.otf']);
    });
    t.view.physicalSize = Size(1080, hoehe);
    t.view.devicePixelRatio = 2.625;
    t.view.padding = const FakeViewPadding(top: 2.625 * 32, bottom: 2.625 * 16);
    t.view.viewPadding = const FakeViewPadding(top: 2.625 * 32, bottom: 2.625 * 16);
    addTearDown(t.view.reset);
    var jetzt = DateTime.utc(2026, 11, 19, 12, 48);
    final app = AppState(MemStore()..disc = true, clock: () => jetzt);
    await t.runAsync(app.laden);
    await t.runAsync(() => app.spracheWaehlen(en ? 'en' : 'de'));
    expect(app.taper.importJson(geschichte()), isTrue);
    app.taper.startHold(tageHalten);
    for (var d = 0; d < schonGehalten; d++) {
      app.taper.addIntake(app.taper.st.plan[app.taper.st.stage], force: true);
      jetzt = jetzt.add(const Duration(days: 1));
      app.taper.refresh();
    }
    await t.pumpWidget(TaperingBuddy(app: app, splashDauer: const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    return app;
  }

  fall('15_plan_ohne_halten', (t) async {
    await start(t);
    await reiter(t, 'Plan');
    await shot(t, '15_plan_ohne_halten');
  });
  fall('16_plan_halten_5_tage', (t) async {
    await gehalten(t, 5, 0);
    await reiter(t, 'Plan');
    await shot(t, '16_plan_halten_5_tage');
  });
  fall('17_plan_halten_ohne_ende_tag6', (t) async {
    await gehalten(t, null, 6);
    await reiter(t, 'Plan');
    await shot(t, '17_plan_halten_ohne_ende_tag6');
  });
  fall('18_kalender_halten', (t) async {
    await gehalten(t, 5, 0, hoehe: 4200);
    await shot(t, '18_kalender_halten');
  });
  fall('19_fortschritt_halten', (t) async {
    await gehalten(t, 5, 0);
    await reiter(t, 'Fortschritt');
    await shot(t, '19_fortschritt_halten');
  });
  fall('20_vorrat_halten', (t) async {
    final app = await gehalten(t, 5, 0, hoehe: 2900);
    app.taper.setStock(20, 5);
    app.aenderung();
    await reiter(t, 'Plan');
    await shot(t, '20_vorrat_halten');
  });

  // Verlauf für den Arzt
  fall('21_fortschritt_knoepfe', (t) async {
    await start(t, hoehe: 3000);
    await reiter(t, 'Fortschritt');
    await shot(t, '21_fortschritt_knoepfe');
  });
  fall('22_bericht_lesen', (t) async {
    await start(t, hoehe: 3000);
    await reiter(t, 'Fortschritt');
    await t.tap(find.byKey(const Key('berichtLesen')));
    for (var i = 0; i < 20 && find.byKey(const Key('berichtBlatt')).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
    }
    // Bild dekodieren lassen
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pump();
    await shot(t, '22_bericht_lesen');
  });
  fall('23_bericht_datei', (t) async {
    final app = await start(t);
    final schrift = Theme.of(t.element(find.byType(Scaffold).first)).textTheme.bodyMedium!;
    await t.runAsync(() async {
      final png = await berichtBild(app, schrift: schrift);
      File('$ziel/23_bericht_blatt.png').writeAsBytesSync(png);
      File('$ziel/23_bericht.pdf').writeAsBytesSync(await berichtPdf(png));
    });
  });
  // Heute beim Halten – „bis“ = letzter Haltetag
  fall('24_heute_halten', (t) async {
    await gehalten(t, 7, 0, hoehe: 3400);
    await reiter(t, 'Heute');
    await shot(t, '24_heute_halten');
  });
}
