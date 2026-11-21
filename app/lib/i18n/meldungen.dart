// Texte zu den Meldungen des Kerns (Code + Werte → Satz in der aktiven Sprache).
import 'package:tapering_core/tapering_core.dart';

import 'txt.dart';

String _nr(Object nr) => (nr as int) > 0 ? tr('Abschnitt $nr: ', 'Section $nr: ') : '';

String meldungText(Meldung m) {
  final w = m.werte;
  switch (m.code) {
    case MeldungCode.setupDosis:
      return tr('Bitte aktuelle Tagesdosis eintragen.', 'Please enter your current daily dose.');
    case MeldungCode.setupSchritt:
      return tr('Bitte eintragen, um wie viel pro Stufe reduziert wird.', 'Please enter how much to reduce per step.');
    case MeldungCode.setupWerteZiel:
      return tr('Bitte Werte prüfen (Zieldosis muss unter der Startdosis liegen).',
          'Please check the values (the target dose must be below the starting dose).');
    case MeldungCode.werteKurz:
      return tr('Bitte Werte prüfen.', 'Please check the values.');
    case MeldungCode.editWerteZiel:
      return tr('Bitte Werte prüfen (Zieldosis unter der Tagesdosis).',
          'Please check the values (target dose below the daily dose).');
    case MeldungCode.stufenBerechnet:
      return tr('${w[0]} Stufen berechnet.', '${w[0]} steps calculated.');
    case MeldungCode.keineDosierungen:
      return tr('Keine Dosierungen erkannt. Pro Zeile etwa „Woche 1–2: 10 mg“ – oder unten Schritte von Hand anlegen.',
          'No doses found. One per line, e.g. “Week 1–2: 10 mg” – or add steps by hand below.');
    case MeldungCode.schritteErkannt:
      final g = w[1] as int;
      return tr('${w[0]} Schritte erkannt.', '${w[0]} steps found.') +
          (g > 0
              ? tr(' $g mit geschätzter Dauer (orange) – bitte prüfen.', ' $g with an estimated duration (orange) – please check.')
              : '');
    case MeldungCode.vorgemerktPruefen:
      return tr('Vorgemerkte Änderung – bitte prüfen und übernehmen.', 'Pending change – please review and apply.');
    case MeldungCode.keineSchritte:
      return tr('Noch keine Schritte angelegt.', 'No steps added yet.');
    case MeldungCode.sicherTippen:
      return tr('Bitte „Ich bin mir sicher“ eintippen.', 'Please type “I am sure”.');
    case MeldungCode.stufeDosisFehlt:
      return tr('Stufe ${w[0]}: Dosis fehlt.', 'Step ${w[0]}: dose missing.');
    case MeldungCode.stufeTageFehlen:
      return tr('Stufe ${w[0]}: Tage fehlen (mind. 1).', 'Step ${w[0]}: days missing (at least 1).');
    case MeldungCode.stufeMaxTage:
      return tr('Stufe ${w[0]}: höchstens ${w[1]} Tage.', 'Step ${w[0]}: at most ${w[1]} days.');
    case MeldungCode.begruenden:
      return tr('Bitte kurz begründen, warum.', 'Please briefly say why.');
    case MeldungCode.planZuLang:
      return tr('Der Plan wäre über 100 Jahre lang – bitte die Tage prüfen.',
          'The plan would be over 100 years long – please check the days.');
    case MeldungCode.pinZiffern:
      return tr('4 bis 8 Ziffern.', '4 to 8 digits.');
    case MeldungCode.pinUngleich:
      return tr('Die beiden PINs stimmen nicht überein.', 'The two PINs do not match.');
    case MeldungCode.abschnittStartdosis:
      return tr('Bitte deine aktuelle Tagesdosis eintragen.', 'Please enter your current daily dose.');
    case MeldungCode.abschnittKeiner:
      return tr('Bitte mindestens einen Abschnitt eintragen.', 'Please add at least one section.');
    case MeldungCode.abschnittSchritt:
      return _nr(w[0]) + tr('Bitte eintragen, um wie viel du jeweils runtergehst.', 'Please enter how much you reduce each time.');
    case MeldungCode.abschnittTage:
      return _nr(w[0]) + tr('Bitte eintragen, alle wie viele Tage.', 'Please enter the number of days between reductions.');
    case MeldungCode.abschnittMaxTage:
      return _nr(w[0]) + tr('Höchstens alle ${w[1]} Tage.', 'At most every ${w[1]} days.');
    case MeldungCode.abschnittBisFehlt:
      return _nr(w[0]) +
          tr('Bitte bei „bis“ eintragen, wo dieser Abschnitt aufhören soll.',
              'Please enter under “until” where this section should end.');
    case MeldungCode.abschnittBisNegativ:
      return _nr(w[0]) + tr('„Bis“ darf nicht unter 0 liegen.', '“Until” must not be below 0.');
    case MeldungCode.abschnittEndetBeiNull:
      final i = w[0] as int;
      return tr('Abschnitt $i endet schon bei 0 – trag dort bei „bis“ ein, wo er aufhören soll, oder lösch Abschnitt ${i + 1}.',
          'Section $i already ends at 0 – enter under “until” where it should end, or delete section ${i + 1}.');
    case MeldungCode.abschnittBisUeberStart:
      return _nr(w[0]) +
          tr('„Bis“ muss kleiner sein als die Startdosis (${fz(w[1] as double)}).',
              '“Until” must be lower than the starting dose (${fz(w[1] as double)}).');
    case MeldungCode.abschnittBisUeberVorigem:
      return _nr(w[0]) +
          tr('„Bis“ muss kleiner sein als ${fz(w[1] as double)} (dort endet Abschnitt ${w[2]}).',
              '“Until” must be lower than ${fz(w[1] as double)} (where section ${w[2]} ends).');
    case MeldungCode.abschnittZuViele:
      return tr('Das wären über 2000 Stufen – bitte größere Schritte.', 'That would be over 2000 steps – please use larger steps.');
  }
}

String sicherungFehlerText(SicherungFehler f) => switch (f) {
      SicherungFehler.kaputt =>
        tr('Die Datei ist keine gültige Sicherung oder beschädigt.', 'The file is not a valid backup or is damaged.'),
      SicherungFehler.passwortFalsch =>
        tr('Passwort falsch – oder die Datei wurde verändert.', 'Wrong password – or the file was modified.'),
      SicherungFehler.zuNeu => tr('Diese Sicherung stammt aus einer neueren App-Version. Bitte die App aktualisieren.',
          'This backup comes from a newer app version. Please update the app.'),
    };
