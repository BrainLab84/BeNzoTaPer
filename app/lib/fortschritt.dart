// Stufen-Fortschrittsbalken der Dosis-Karte.
import 'i18n/txt.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tapering_core/tapering_core.dart';

import 'bausteine.dart';

class Fortschritt extends StatefulWidget {
  const Fortschritt({super.key, required this.taper});
  final Taper taper;
  @override
  State<Fortschritt> createState() => _FortschrittState();
}

class _FortschrittState extends State<Fortschritt> {
  final _scroll = ScrollController();
  double? _gescrolltBei;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ta = widget.taper;
    final s = ta.st;
    final n = s.plan.length;
    if (n < 2) return const SizedBox.shrink();
    final ndy = ta.need(s.stage);
    final sd = ta.stageDay();
    final last = s.stage >= n - 1;
    final done = last && (!(s.plan[n - 1] > 0) || sd >= ndy);
    final frac = last ? 1.0 : math.min((sd + 1) / ndy, 1.0);

    // Look „Dämmerung“: erledigt grün, aktuelle Stufe dunkelgrün mit weißem Ring,
    // kommende lavendel; darüber „Tag x/y“ als Pille. Der Abschnitt zur nächsten Stufe ist breiter
    // und hat einen Strich pro Tag, damit man den Fortschritt innerhalb der Stufe sieht.
    const linie = 66.0; // Mitte der Linie
    const gewichtAktuell = 2.6;
    return LayoutBuilder(builder: (context, c) {
      final avail = c.maxWidth;
      final segMin = last ? 0.0 : math.min(260.0, math.max(150.0, ndy * 9.0));
      final inner = math.max(avail, (n - 2) * 70.0 + segMin + 88);
      final tw = inner - 88;
      // Breite je Abschnitt: der aktuelle zählt [gewichtAktuell]-fach, mindestens [segMin].
      final summe = (n - 1) + (last ? 0 : gewichtAktuell - 1);
      var einheit = tw / summe;
      var segAkt = last ? 0.0 : einheit * gewichtAktuell;
      if (!last && segAkt < segMin) {
        segAkt = segMin;
        einheit = (tw - segAkt) / math.max(1, n - 2);
      }
      double seg(int i) => (!last && i == s.stage) ? segAkt : einheit;
      double x(int i) {
        var p = 44.0;
        for (var j = 0; j < i; j++) {
          p += seg(j);
        }
        return p;
      }

      final fillPx = last ? tw : (x(s.stage) - 44) + frac * segAkt;
      final fill = math.min(1.0, fillPx / tw);

      // So scrollen, dass die aktuelle Position mittig steht.
      if (_gescrolltBei != fill) {
        _gescrolltBei = fill;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          final px = 44 + fillPx;
          _scroll.jumpTo((px - avail / 2).clamp(0, _scroll.position.maxScrollExtent));
        });
      }

      final kinder = <Widget>[
        Positioned(
          left: 44,
          top: linie - 4,
          width: tw,
          height: 8,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: const LinearGradient(colors: [Color(0xE6EAD3EA), Color(0xB3AFAADB)]),
            ),
          ),
        ),
        Positioned(
          left: 44,
          top: linie - 4,
          width: fillPx,
          height: 8,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: const LinearGradient(colors: [Color(0xFF7DBA55), Color(0xFFB8E890)]),
              boxShadow: const [BoxShadow(color: Color(0x5598D872), blurRadius: 8)],
            ),
          ),
        ),
      ];
      // Tagesstriche auf dem aktuellen Abschnitt (nur, wenn genug Platz ist).
      if (!last && ndy > 1 && segAkt / ndy >= 6) {
        for (var j = 1; j < ndy; j++) {
          final px = x(s.stage) + segAkt * j / ndy;
          final vorbei = j <= sd;
          kinder.add(Positioned(
            key: Key('strich$j'),
            left: px - 1,
            top: linie - 7,
            width: 2,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: vorbei ? const Color(0xE6FFFFFF) : const Color(0x99AFAADB),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ));
        }
      }
      for (var i = 0; i < n; i++) {
        final dn = i < s.stage || (i == n - 1 && s.stage == n - 1 && done);
        final cu = i == s.stage && !dn;
        final ende = i == n - 1;
        final d = ende ? 28.0 : (cu ? 26.0 : 21.0);
        kinder.add(Positioned(
          left: x(i) - d / 2,
          top: linie - d / 2,
          width: d,
          height: d,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dn ? const Color(0xFF86C25E) : (cu ? const Color(0xFF2C5A34) : const Color(0xCC6A79A8)),
              border: Border.all(
                  color: dn ? const Color(0xFFCDEFAE) : (cu ? Colors.white : F.lav), width: cu ? 3 : 2),
              boxShadow: cu ? const [BoxShadow(color: Color(0x99A8DC86), blurRadius: 12, spreadRadius: 2)] : null,
            ),
            child: ende ? Icon(Icons.flag, size: 14, color: dn || cu ? Colors.white : F.lav) : null,
          ),
        ));
        kinder.add(Positioned(
          left: x(i) - 50,
          top: linie + 20,
          width: 100,
          child: Text(
            '${fz(s.plan[i])} ${s.unit}',
            textAlign: TextAlign.center,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: cu ? 16 : 14.5,
              color: dn ? const Color(0xFFCDE8A9) : (cu ? Colors.white : F.lav),
              fontWeight: cu ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ));
      }
      if (!(s.stage == n - 1 && done)) {
        kinder.add(Positioned(
          left: 44 + fillPx,
          top: 0,
          child: FractionalTranslation(
            translation: Offset(-(0.15 + fill * 0.7), 0),
            child: Container(
              key: const Key('fortschrittBlase'),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xE69A6F92),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x33FFFFFF)),
                boxShadow: const [BoxShadow(color: Color(0x40301030), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Tag ${math.min(sd + 1, ndy)}/$ndy', 'Day ${math.min(sd + 1, ndy)}/$ndy'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                if (s.hold) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.pause, size: 14, color: Colors.white),
                ],
              ]),
            ),
          ),
        ));
      }
      return SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: inner, height: linie + 46, child: Stack(clipBehavior: Clip.none, children: kinder)),
      );
    });
  }
}
