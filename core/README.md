# tapering_core – Rechenkern

Reines Dart, keine Oberfläche, kein Flutter. Hier steckt alles, was rechnet und entscheidet:
Plan berechnen, Stufen und Enddatum, „Dosis halten“, ?-Tage, 48-h-Bedenkzeit, Vorrat,
Tablettenkombination, Text-Import eines Plans, PIN-Hash, Sicherung laden/prüfen.
Die Flutter-App ruft nur `Taper` auf und zeigt das Ergebnis an.

- `lib/engine.dart` – `Taper`: der Zustand und alle Änderungen daran (mit steuerbarer Uhr)
- `lib/state.dart` – Datenmodell. JSON-Format `strike-v1`,
  alte Sicherungen laden direkt. Alte Felder (Prozent, Meilensteine, Tags …) werden still ignoriert.
- `lib/plan_math.dart` – `makePlan`, `combo` (Tablettenkombination), Bruchschreibweise
- `lib/plan_parser.dart` – Text → Stufen („Woche 1–2: 10 mg“, „ab 01.12.: 8 mg“ …), deutsch und englisch
  („week 1–2: 10 mg“, „from 01/12: 8 mg“, „drops“, „tab“). PDF/Word → Text macht die Oberfläche.
- `lib/meldung.dart` – `Meldung(code, werte)`: Fehler und Hinweise des Kerns als Code mit Werten.
  Den Text in der jeweiligen Sprache baut die App (`app/lib/i18n/meldungen.dart`). Der Kern enthält keine Anzeigetexte.
- Die Bestätigungssätze „ich bin mir sicher“ und „i am sure“ werden beide akzeptiert.

## Prüfen

```
cd core
dart pub get
dart analyze
dart test        # 96 Tests
```

- `test/scenarios_test.dart` – Szenarien (Halten, Änderungen, Editor)
- `test/longsim_test.dart` – 10 Verläufe × 400 Tage mit Zufallsereignissen und täglichen Invarianten
- `test/parser_englisch_test.dart` – englische Einheiten, Datumsformate und Stoppwörter im Import
- `test/golden_test.dart` – **Vergleich mit eingefrorenen Referenzdaten**: 14 aufgezeichnete Zufallsverläufe
  (über 3000 Tage, mit Halten, Lücken, Vormerkung, Editor, Import) müssen Tag für Tag denselben
  Zustand ergeben. `test/golden_math_test.dart` vergleicht Plan, Tablettenkombination und Text-Import.

### Referenzdaten

Die Dateien in `test/golden/` wurden einmalig aufgezeichnet und sind
eingefroren. Ändert man eine Regel bewusst, die Referenz aus dem Dart-Kern neu festschreiben und den
Grund in der Commit-Nachricht nennen.
