// Optionale Erinnerung zum Eintragen (standardmäßig aus, Uhrzeit einstellbar,
// leise, kein Pop-up in der App). Kommt nur an Tagen, an denen bis zur Uhrzeit noch nichts eingetragen ist.
//
// Technik: Android kann zur Weckzeit nicht in die App schauen. Deshalb plant die App die nächsten
// [erinnerungTage] Tage einzeln vor und lässt Tage mit Eintrag aus; nach jeder Änderung wird neu geplant.
// Wer die App länger als [erinnerungTage] Tage nicht öffnet, bekommt danach keine Erinnerung mehr.
// Paket: flutter_local_notifications (BSD-3-Clause), timezone (BSD-2-Clause) – beide FOSS.
import 'i18n/txt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdaten;
import 'package:timezone/timezone.dart' as tz;

import 'package:tapering_core/tapering_core.dart';

import 'app_state.dart';
import 'bausteine.dart';

const erinnerungTage = 30;
String get erinnerungText => tr('Heute noch nichts eingetragen.', 'Nothing logged today yet.');

/// Einstellung, getrennt vom Stand gespeichert (nicht in der Sicherung).
class ErinnerungEinstellung {
  const ErinnerungEinstellung({this.an = false, this.stunde = 20, this.minute = 0});
  final bool an;
  final int stunde;
  final int minute;

  String get uhrzeit => '${stunde.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  ErinnerungEinstellung mit({bool? an, int? stunde, int? minute}) =>
      ErinnerungEinstellung(an: an ?? this.an, stunde: stunde ?? this.stunde, minute: minute ?? this.minute);

  Map<String, dynamic> toJson() => {'an': an, 'h': stunde, 'm': minute};

  static ErinnerungEinstellung fromJson(Object? j) {
    if (j is! Map) return const ErinnerungEinstellung();
    int zahl(Object? v, int std, int max) => v is int && v >= 0 && v <= max ? v : std;
    return ErinnerungEinstellung(an: j['an'] == true, stunde: zahl(j['h'], 20, 23), minute: zahl(j['m'], 0, 59));
  }
}

/// Plattform-Teil (in Tests ersetzt).
abstract class Erinnerer {
  /// Fragt (ab Android 13) nach der Erlaubnis für Benachrichtigungen. `true` = erlaubt.
  Future<bool> erlaubnis();

  /// Ersetzt alle geplanten Erinnerungen durch [zeiten] (lokale Uhrzeit) und die Vorrat-Hinweise
  /// durch [vorrat].
  Future<void> planen(List<DateTime> zeiten, {List<VorratPush> vorrat = const []});
}

/// Vorrat-Push: einmal, wenn der Vorrat noch [vorratSchwellen] Tage reicht.
const vorratSchwellen = [14, 7];
const vorratPushStunde = 10;

class VorratPush {
  const VorratPush(this.zeit, this.text);
  final DateTime zeit;
  final String text;
  @override
  String toString() => '${zeit.toIso8601String()} $text';
}

/// Text des Vorrat-Push.
String vorratPushText(int tage, String bis) => tr(
    'Vorrat reicht noch ca. $tage Tage (bis $bis). Kümmere dich rechtzeitig um Nachschub.',
    'Supply lasts about $tage more days (until $bis). Arrange your resupply in good time.');

/// Wann der Vorrat die Schwellen erreicht: Tag D mit „reicht noch T Tage“ (wie die Vorrat-Karte, inkl. D),
/// jeweils um [vorratPushStunde] Uhr. Nur künftige Zeitpunkte; wer schon drunter ist, sieht die Warnung
/// in der App. Rechnet mit der Reichweite von heute (Plan, Stufenwechsel, Halten).
List<VorratPush> vorratPushZeiten(AppState app) {
  if (!app.vorratPush || !app.eingerichtet) return const [];
  final ta = app.taper;
  final si = ta.stockInfo();
  if (si == null || !si.days.isFinite) return const [];
  final n = si.days.toInt();
  final jetzt = ta.clock().toLocal();
  final out = <VorratPush>[];
  for (final t in vorratSchwellen) {
    if (n <= t) continue;
    final d = addD(ta.today, n - t);
    final p = d.split('-').map(int.parse).toList();
    final z = DateTime(p[0], p[1], p[2], vorratPushStunde);
    if (!z.isAfter(jetzt)) continue;
    out.add(VorratPush(z, vorratPushText(t, datum(addD(d, t - 1)))));
  }
  return out;
}

class SystemErinnerer implements Erinnerer {
  final _p = FlutterLocalNotificationsPlugin();
  bool _bereit = false;

  Future<void> _init() async {
    if (_bereit) return;
    tzdaten.initializeTimeZones();
    await _p.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_erinnerung')));
    _bereit = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> erlaubnis() async {
    await _init();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> planen(List<DateTime> zeiten, {List<VorratPush> vorrat = const []}) async {
    await _init();
    await _p.cancelAllPendingNotifications();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'erinnerung',
        tr(tr('Erinnerung zum Eintragen', 'Reminder to log'), 'Reminder to log'),
        channelDescription: tr('Leise, nur wenn an dem Tag noch nichts eingetragen ist.',
            'Quiet, only if nothing has been logged that day.'),
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
      ),
    );
    for (var i = 0; i < zeiten.length; i++) {
      await _p.zonedSchedule(
        id: 1000 + i,
        title: 'BeNzoTaPer',
        body: erinnerungText,
        // Lokale Zeit → UTC: Sommer-/Winterzeit rechnet Dart für jeden Tag selbst richtig.
        scheduledDate: tz.TZDateTime.from(zeiten[i].toUtc(), tz.UTC),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
    for (var i = 0; i < vorrat.length; i++) {
      // Langer Text: aufgeklappt ganz lesbar.
      final vorratDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'vorrat',
          tr('Vorrat wird knapp', 'Supply running low'),
          channelDescription: tr('Wenn der Vorrat noch 14 und noch 7 Tage reicht.',
              'When your supply has 14 days and 7 days left.'),
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(vorrat[i].text),
        ),
      );
      await _p.zonedSchedule(
        id: 2000 + i,
        title: 'BeNzoTaPer',
        body: vorrat[i].text,
        scheduledDate: tz.TZDateTime.from(vorrat[i].zeit.toUtc(), tz.UTC),
        notificationDetails: vorratDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

/// Die Zeitpunkte der nächsten Erinnerungen (lokal). Leer, wenn aus oder ohne eigenen Plan.
/// Heute nur, wenn noch nichts eingetragen und die Uhrzeit noch nicht vorbei ist.
List<DateTime> erinnerungZeiten(AppState app, ErinnerungEinstellung e) {
  if (!e.an || !app.eingerichtet) return const [];
  final ta = app.taper;
  final jetzt = ta.clock().toLocal();
  final out = <DateTime>[];
  for (var i = 0; i < erinnerungTage; i++) {
    final z = DateTime(jetzt.year, jetzt.month, jetzt.day + i, e.stunde, e.minute);
    if (!z.isAfter(jetzt)) continue;
    if (i == 0 && (ta.st.log[ta.today]?.it.isNotEmpty ?? false)) continue;
    out.add(z);
  }
  return out;
}

/// Abschnitt „Erinnerung“ in „Mehr“.
class ErinnerungAbschnitt extends StatelessWidget {
  const ErinnerungAbschnitt({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final e = app.erinnerung;
          if (!app.eingerichtet) {
            return ListTile(
              leading: Icon(Icons.notifications_none),
              title: Text(tr('Erinnerung zum Eintragen', 'Reminder to log')),
              subtitle: Text(tr('Geht, sobald du deinen eigenen Plan angelegt hast.', 'Available once you have created your own plan.')),
            );
          }
          return Column(children: [
            SwitchListTile(
              key: const Key('erinnerungSchalter'),
              secondary: const Icon(Icons.notifications_none),
              title: Text(tr('Erinnerung zum Eintragen', 'Reminder to log')),
              subtitle: Text(tr('Leise Benachrichtigung um ${e.uhrzeit}, nur wenn heute noch nichts eingetragen ist. '
                  'Kein Ton, kein Pop-up.', 'Quiet notification at ${e.uhrzeit}, only if nothing has been logged today. No sound, no pop-up.')),
              value: e.an,
              onChanged: (an) async {
                final ok = await app.erinnerungSetzen(e.mit(an: an));
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(tr('Benachrichtigungen sind für die App aus. Du kannst sie in den '
                          'Android-Einstellungen erlauben.', 'Notifications are turned off for the app. You can allow them in the Android settings.'))));
                }
              },
            ),
            SwitchListTile(
              key: const Key('vorratPushSchalter'),
              secondary: const Icon(Icons.medication_outlined),
              title: Text(tr('Hinweis bei knappem Vorrat', 'Low-supply notice')),
              subtitle: Text(tr('Benachrichtigung, wenn der Vorrat noch 14 und noch 7 Tage reicht.', 'Notification when your supply has 14 days and 7 days left.')),
              value: app.vorratPush,
              onChanged: (an) async {
                final ok = await app.vorratPushSetzen(an);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(tr('Benachrichtigungen sind für die App aus. Du kannst sie in den '
                          'Android-Einstellungen erlauben.', 'Notifications are turned off for the app. You can allow them in the Android settings.'))));
                }
              },
            ),
            if (e.an)
              ListTile(
                key: const Key('erinnerungUhrzeit'),
                leading: const SizedBox(width: 24),
                title: Text(tr('Uhrzeit', 'Time')),
                trailing: Text(e.uhrzeit, style: const TextStyle(fontWeight: FontWeight.w700, color: F.ac2)),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: e.stunde, minute: e.minute),
                    builder: (c, kind) =>
                        MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: kind!),
                  );
                  if (t != null) await app.erinnerungSetzen(e.mit(stunde: t.hour, minute: t.minute));
                },
              ),
          ]);
        },
      );
}
