// Deutsche Texte von Anleitung und Hinweisen. Die englische Fassung steht in `i18n/texte_en.dart`
// (gleiche Reihenfolge, die ?-Knöpfe verweisen über die Nummer des Abschnitts).

import 'i18n/texte_en.dart';
import 'i18n/txt.dart';

enum B { p, h, li, wichtigKopf, wichtig }

class Absatz {
  const Absatz(this.art, this.text);
  final B art;
  final String text;
}

class Abschnitt {
  const Abschnitt(this.titel, this.teile);
  final String titel;
  final List<Absatz> teile;
}

const anleitungDe = <Abschnitt>[
  Abschnitt('1. Wofür ist diese Anwendung gedacht?', [
    Absatz(B.p,
        'Diese Anwendung wurde entwickelt, um einen geplanten Benzodiazepin-Reduktionsverlauf übersichtlich zu organisieren und den persönlichen Fortschritt nachvollziehbar zu machen.'),
    Absatz(B.p,
        'Der Schwerpunkt liegt nicht auf der permanenten Beobachtung möglicher Entzugssymptome, sondern auf dem Weg, den du Schritt für Schritt zurücklegst.'),
    Absatz(B.p,
        'Der Kalender, die Tagesübersicht und die Fortschrittsanzeige helfen dir dabei, den Überblick zu behalten und bereits erreichte Etappen sichtbar zu machen.'),
    Absatz(B.p, 'Die Anwendung soll dich begleiten, nicht zusätzlich beschäftigen.'),
  ]),
  Abschnitt('2. Dein persönlicher Reduktionsplan', [
    Absatz(B.p, 'Du kannst deinen individuellen Reduktionsplan in der Anwendung hinterlegen und verwalten.'),
    Absatz(B.p,
        'Die einzelnen Reduktionsstufen werden übersichtlich dargestellt und den entsprechenden Zeiträumen zugeordnet.'),
    Absatz(B.p, 'Ein bestehender Plan kann bearbeitet und an veränderte Rahmenbedingungen angepasst werden.'),
    Absatz(B.p,
        'Wichtig ist dabei die Unterscheidung zwischen organisatorischen Änderungen und medizinischen Entscheidungen: Die Anwendung verwaltet deinen Plan, bestimmt aber nicht eigenständig, wie schnell reduziert werden soll.'),
  ]),
  Abschnitt('3. Der Kalender und deine täglichen Fortschritte', [
    Absatz(B.p, 'Der Kalender bildet das Herzstück der Anwendung.'),
    Absatz(B.p, 'Er ermöglicht dir, jeden Tag entsprechend deinem persönlichen Plan zu dokumentieren.'),
    Absatz(B.p,
        'Erledigte Tage können mit einem Häkchen markiert werden. Dadurch wird dein bisheriger Fortschritt unmittelbar sichtbar.'),
    Absatz(B.p, 'Du kannst jederzeit nachvollziehen:'),
    Absatz(B.li, 'Welche Tage bereits dokumentiert sind.'),
    Absatz(B.li, 'Wo du dich aktuell im Plan befindest.'),
    Absatz(B.li, 'Welche Etappen bereits abgeschlossen wurden.'),
    Absatz(B.li, 'Welche Schritte noch vor dir liegen.'),
    Absatz(B.p,
        'Die Übersicht soll dir helfen, deinen Fortschritt wahrzunehmen, statt dich ständig mit dem Entzug beschäftigen zu müssen.'),
  ]),
  Abschnitt('4. Zusätzliche Zeit und Plananpassungen', [
    Absatz(B.p, 'Nicht jeder Reduktionsverlauf lässt sich exakt nach einem ursprünglichen Zeitplan organisieren.'),
    Absatz(B.p, 'Deshalb kannst du zusätzliche Tage eintragen, wenn eine bestehende Etappe verlängert werden soll.'),
    Absatz(B.p, 'Die nachfolgenden Zeiträume werden entsprechend dynamisch verschoben.'),
    Absatz(B.p,
        'Dadurch bleibt dein Kalender übersichtlich und der ursprüngliche Ablauf muss nicht jedes Mal vollständig neu angelegt werden.'),
    Absatz(B.p,
        'Die technische Möglichkeit zur Verlängerung stellt keine medizinische Empfehlung dar. Die Dauer einer Reduktionsstufe sollte medizinisch abgestimmt sein.'),
  ]),
  Abschnitt('5. Verpasste Tage und nachträgliche Einträge', [
    Absatz(B.p, 'Nicht jeder Tag wird zwangsläufig unmittelbar dokumentiert.'),
    Absatz(B.p, 'Deshalb ist die Möglichkeit vorgesehen, Einträge nachträglich vorzunehmen.'),
    Absatz(B.p, 'Ein fehlender Eintrag bedeutet nicht automatisch, dass ein Tag nicht planmäßig verlaufen ist.'),
    Absatz(
        B.p, 'Die nachträgliche Dokumentation dient dazu, den tatsächlichen Verlauf möglichst vollständig abzubilden.'),
  ]),
  Abschnitt('6. Entzug oder Langzeitnebenwirkung?', [
    Absatz(B.p,
        'Nicht alles ist Entzug. Auch Umstände können Beschwerden auslösen oder verstärken, zum Beispiel Vapen, Medikamente (auch gegen Allergien), Essen, Vitamine oder Magnesium.'),
    Absatz(B.h, 'Warum notieren?'),
    Absatz(B.p,
        'Bei einer plötzlichen Verschlechterung greifen viele zur höheren Dosis. Das hilft kurz, löst die Ursache aber nicht und endet oft im Jojo-Effekt. Wer nachvollziehen kann, was davor war, findet die Ursache leichter.'),
    Absatz(B.h, 'Langzeitnebenwirkungen'),
    Absatz(B.p,
        'Nach Jahren mit Benzodiazepinen kann sich etwas verändern: chronische Erschöpfung, Müdigkeit, Antriebsschwäche, Medikamente wirken anders. Das fühlt sich oft wie eine eigene Krankheit an. Vieles kann auch von einer Grunderkrankung kommen.'),
    Absatz(B.p, '„Toleranzentzug“ als Erklärung trifft nicht immer zu.'),
    Absatz(B.p, 'Das sind meine Erfahrungen, nicht unbedingt deine. 🙂'),
  ]),
  Abschnitt('7. Dokumentation statt ständiger Selbstbeobachtung', [
    Absatz(B.p, 'Diese Anwendung ist bewusst nicht als Symptomtagebuch konzipiert.'),
    Absatz(B.p,
        'Es geht nicht darum, jede körperliche Empfindung zu erfassen, täglich nach Beschwerden zu suchen oder jede Veränderung medizinisch zu interpretieren.'),
    Absatz(B.p, 'Der Fokus liegt auf deinem persönlichen Fortschritt und einer nachvollziehbaren Dokumentation.'),
    Absatz(B.p, 'Du entscheidest selbst, welche zusätzlichen Informationen du festhalten möchtest.'),
  ]),
  Abschnitt('8. Dein Fortschritt zählt', [
    Absatz(B.p, 'Ein Reduktionsverlauf ist ein längerer Prozess.'),
    Absatz(B.p, 'Der Kalender soll dir helfen, bereits geschaffte Tage sichtbar zu machen.'),
    Absatz(B.p, 'Konzentriere dich auf deinen Weg und die nächsten Schritte.'),
    Absatz(
        B.p, 'Nicht jeder Tag muss perfekt dokumentiert sein, damit dein bisheriger Fortschritt seinen Wert behält.'),
    Absatz(B.p,
        'Diese Anwendung soll dir helfen, den Überblick zu behalten und deinen Weg Schritt für Schritt zu organisieren.'),
  ]),
  Abschnitt('9. Der Wochen-Durchschnitt', [
    Absatz(B.p, 'Der Wochen-Durchschnitt ist als Motivation gedacht.'),
    Absatz(B.p,
        'Ein einzelner Tag über Plan fühlt sich schnell wie ein Rückschlag an. Gerade dann ist die Versuchung groß, alles hinzuwerfen.'),
    Absatz(B.p,
        'Der Durchschnitt zeigt dir, wie wenig ein einmaliger Ausrutscher am Gesamtbild ändert: Ein Tag zählt nur ein Siebtel der Woche, und mit den nächsten Tagen im Plan bist du wieder auf Kurs.'),
    Absatz(B.p,
        'Er rechnet nur mit eingetragenen Tagen. Ein Tag ohne Eintrag zählt nicht mit, auch nicht als 0 mg.'),
    Absatz(B.p,
        'Vor allem Diazepam hat eine sehr lange Halbwertszeit. Der Wirkstoffspiegel im Körper ergibt sich deshalb eher aus dem Verlauf über viele Tage als aus einem einzelnen Tag. Bei kurz wirksamen Benzodiazepinen ist dieser Ausgleich weniger ausgeprägt.'),
    Absatz(B.p,
        'Entscheidend ist der Trend über Wochen, nicht der einzelne Tag. Am nächsten Tag gilt einfach wieder deine geplante Dosis.'),
    Absatz(B.p,
        'Häufen sich Tage über Plan, ist das eher ein Zeichen, dass der aktuelle Schritt zu groß ist. Dafür gibt es „Dosis halten“.'),
  ]),
  Abschnitt('10. Zeichen im Kalender', [
    Absatz(B.li, '✓ = im Plan'),
    Absatz(B.li, '✗ mit Zahl = mehr genommen (mg)'),
    Absatz(B.li, 'Zahl ohne Zeichen = geplante Dosis an diesem Tag'),
    Absatz(B.li, '? = kein Eintrag'),
    Absatz(B.li, 'Strich oben am Tag = neue Stufe beginnt'),
    Absatz(B.li, 'Sonne = guter Tag'),
    Absatz(B.li, 'Punkt = Notiz vorhanden'),
    Absatz(B.p, 'Tag antippen: nachtragen oder Notiz.'),
  ]),
  Abschnitt('11. Tage ohne Eintrag', [
    Absatz(B.p, 'Die App rät nichts. Ein Tag ohne Eintrag ist ein Fragezeichen, nie „wie geplant“ und nie 0 mg.'),
    Absatz(B.p,
        'Fehlt ein Tag, pausieren die Anzeigen: Dosis-Karte, Wochen-Ø und Kalender-Vorschau sind ausgegraut. Die Startseite fragt dann nur nach dem fehlenden Tag.'),
    Absatz(B.p,
        'Trag den Tag nach (bis 7 Tage zurück), dann geht alles normal weiter. Am Plan ändert sich dadurch nichts. Er verschiebt sich nur, wenn du die Dosis hältst oder ihn selbst änderst.'),
    Absatz(B.p,
        'Liegt ein Tag mehr als 7 Tage zurück, kannst du „Weiß ich nicht mehr“ wählen. Dann bleibt er dauerhaft ein Fragezeichen, und die App läuft weiter.'),
    Absatz(B.p,
        'Wochen-Ø und Kurve rechnen nur mit eingetragenen Tagen. Tage ohne Eintrag gehen nie als 0 mg in eine Rechnung ein.'),
    Absatz(B.p,
        'Nach dem Ziel (0 mg) trägst du weiter ein, auch wenn du nichts genommen hast („Heute nichts genommen“). So bleibt auch ein Rückfall dokumentierbar.'),
  ]),
];

const hilfe = <String, List<int>>{
  'avg': [8],
  'prog': [0, 7],
  'plan': [1],
  'cal': [9, 2],
  'time': [3],
  'back': [4, 10],
  'gap': [10],
  'notes': [5, 6],
  'bind': [5],
};

const disclaimerTitelDe = 'Wichtige Hinweise zur Nutzung';
const disclaimerDe = <Absatz>[
  Absatz(B.h, 'Medizinischer Disclaimer'),
  Absatz(B.p,
      'Diese Anwendung ist ein organisatorisches und dokumentarisches Hilfsmittel zur Begleitung einer geplanten Reduktion von Benzodiazepinen.'),
  Absatz(B.p,
      'Sie ersetzt weder eine ärztliche Beratung noch eine medizinische Behandlung oder therapeutische Begleitung.'),
  Absatz(B.p,
      'Die Anwendung stellt keine Diagnosen, gibt keine medizinischen Behandlungsempfehlungen und entscheidet nicht über Dosierungen oder Reduktionsgeschwindigkeiten.'),
  Absatz(B.p,
      'Alle Dosierungspläne müssen individuell medizinisch abgestimmt werden. Änderungen an der Dosierung oder am Reduktionsverlauf sollten ausschließlich in Abstimmung mit einer entsprechend qualifizierten medizinischen Fachperson erfolgen.'),
  Absatz(B.wichtigKopf, 'Wichtig:'),
  Absatz(B.wichtig,
      'Benzodiazepine dürfen nach längerer Einnahme nicht eigenständig abrupt abgesetzt werden. Ein unsachgemäßer Entzug kann schwerwiegende gesundheitliche Folgen haben.'),
  Absatz(B.wichtig,
      'Bei schweren Entzugssymptomen, Krampfanfällen, ausgeprägter Verwirrtheit oder anderen akuten gesundheitlichen Problemen ist unverzüglich medizinische Hilfe in Anspruch zu nehmen.'),
  Absatz(B.h, 'Keine Diagnose und keine Ursachenermittlung'),
  Absatz(B.p,
      'Die in der Anwendung dokumentierten Angaben zu Medikamenten, Vitaminen, Nahrungsergänzungsmitteln, Nikotin, Vaping, Koffein und sonstigen Einflussfaktoren dienen ausschließlich der persönlichen Dokumentation.'),
  Absatz(B.p,
      'Ein zeitlicher Zusammenhang zwischen einer Einnahme oder einem Ereignis und einer Veränderung des Befindens beweist nicht, dass dieses Ereignis die Ursache war.'),
  Absatz(B.p, 'Die Anwendung nimmt keine medizinische Bewertung dieser Zusammenhänge vor.'),
  Absatz(B.h, 'Eigenverantwortung und Dateneingabe'),
  Absatz(B.p, 'Die Verantwortung für die Richtigkeit der eingegebenen Daten liegt beim Nutzer.'),
  Absatz(B.p,
      'Die Anwendung kann nur mit den Informationen arbeiten, die tatsächlich eingetragen wurden. Sie übernimmt keine Gewähr für die medizinische Richtigkeit oder Vollständigkeit eines eingegebenen Reduktionsplans.'),
  Absatz(B.h, 'Zweck der Anwendung'),
  Absatz(B.p,
      'Das Ziel ist eine übersichtliche, möglichst unkomplizierte Begleitung während eines individuell festgelegten Reduktionsverlaufs.'),
  Absatz(B.p, 'Im Mittelpunkt stehen Planung, Fortschrittsübersicht, Dokumentation und persönliche Motivation.'),
  Absatz(
      B.p, 'Die Anwendung soll den Nutzer organisatorisch unterstützen, ohne eine medizinische Betreuung zu ersetzen.'),
];

/// Anleitung und Hinweise in der aktiven Sprache.
List<Abschnitt> get anleitung => Txt.en ? anleitungEn : anleitungDe;
List<Absatz> get disclaimer => Txt.en ? disclaimerEn : disclaimerDe;
String get disclaimerTitel => Txt.en ? disclaimerTitelEn : disclaimerTitelDe;
