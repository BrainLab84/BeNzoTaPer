# Werkzeuge (nur für die Entwicklung, nicht Teil der App)

## `pruefung/` – Gegenproben und Rechtschreibung
- `mutation.py <repo> "<testbefehl>" <arbeitsordner> <liste>`: baut nacheinander absichtlich Fehler ein
  (Liste: Datei, alter Text, neuer Text), führt die Tests aus, meldet ERKANNT / NICHT ERKANNT und stellt
  die Datei danach wieder her.
  - Kern: `python3 tools/pruefung/mutation.py . "dart test" core tools/pruefung/mut_kern.txt`
    (ganze Kern-Suite, etwa 1½ Minuten je Gegenprobe; M1–M21, alle erkannt)
  - Oberfläche: `python3 tools/pruefung/mutation.py . "flutter test test/audit_ui_test.dart test/simulation_ui_test.dart test/heute_test.dart test/sicherung_ui_test.dart test/store_test.dart test/erinnerung_test.dart test/bericht_test.dart" app tools/pruefung/mut_ui.txt`
    (etwa 5 Minuten je Gegenprobe; U1–U13, alle erkannt)
  - Währenddessen keine anderen Tests laufen lassen und nichts committen, die Datei ist kurz verändert.
    Bricht ein Lauf ab, danach `git status` prüfen und die Datei ggf. mit `git checkout -- <datei>` zurückholen.
- `rechtschreibung.py`: in `app/` ausführen; listet unbekannte Wörter und Zeichenprobleme in allen
  Texten von `lib/` (braucht `pip install pyspellchecker`). Fachwörter und zusammengesetzte Wörter erscheinen als
  „unbekannt“, sind aber richtig – von Hand durchsehen.

## `screenshots/` – Bilder wie auf einem Handy
`alle_seiten_shots_test.dart` erzeugt Golden-Bilder aller Seiten mit echter Schrift (Roboto aus dem
Flutter-Cache unter `$FLUTTER_ROOT`), Telefon 1080 × 2340 bei 2,625, mit Statusleisten-Abstand.
Testdaten: Name „Alex“, Diazepam 10 → 0 mg, feste Uhr 19.11.2026 12:48.

In `app/`:
```
cp ../tools/screenshots/alle_seiten_shots_test.dart test/
SHOTS=/tmp/shots NUR=01,03 flutter test test/alle_seiten_shots_test.dart --update-goldens
rm test/alle_seiten_shots_test.dart
```
`NUR` leer = alle Seiten. Mit `SPR=en` entstehen die Bilder in der englischen Fassung (für `fastlane/…/en-US`),
ohne `SPR` die deutschen. Schwarze Ränder um Schatten und Kästchen statt „→“ gibt es nur in den Testbildern.

## Release-APK (fester Schlüssel)
Der Workflow `apk-release.yml` braucht die Secrets `TB_KEYSTORE_B64`, `TB_KEYSTORE_PASSWORD`, `TB_KEY_ALIAS`.
1. Vorher in `app/pubspec.yaml` Version und versionCode erhöhen und `fastlane/metadata/android/*/changelogs/<versionCode>.txt` anlegen.
2. Workflow starten (in GitHub unter Actions oder per API):
   `gh api -X POST repos/BrainLab84/BeNzoTaPer/actions/workflows/apk-release.yml/dispatches -f ref=main -f "inputs[release_tag]=v<Version>"`
3. Ohne `release_tag` entsteht nur ein Artefakt, mit `release_tag` zusätzlich ein GitHub-Release mit beiden APKs.
   Der Text des Release steht in `.github/release-notes.md` (`{V}` wird durch die Version ersetzt).
4. Der Workflow bricht ab, wenn die APK nicht mit dem festen Schlüssel signiert ist
   (SHA-256-Fingerabdruck `9d6fd371 … 2bc0`) oder der Tag nicht zur Version passt.

Eine Test-APK, die neben der echten App läuft: `TB_TEST=1 flutter build apk --release` in `app/`
→ App „BeNzoTaPer Test“ (`de.tapering.buddy.test`), mit Debug-Schlüssel, kein Update der echten App.
