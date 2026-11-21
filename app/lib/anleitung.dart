import 'i18n/txt.dart';
import 'package:flutter/material.dart';

import 'start.dart';
import 'texte.dart';

/// Ganze Anleitung als Seite.
class AnleitungSeite extends StatelessWidget {
  const AnleitungSeite({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Bedienungsanleitung', 'Guide'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(tr('Dein persönlicher Abdosier-Begleiter', 'Your personal tapering companion'), style: Theme.of(context).textTheme.bodySmall),
          for (final s in anleitung) ...[
            Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 4),
                child: Text(s.titel,
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700))),
            ...absaetze(context, s.teile),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Zurück zur App', 'Back to the app'))),
        ]),
      );
}

/// ?-Hilfe: kleine Erklärung aus der Anleitung (Schlüssel wie bisher: avg, prog, plan, …).
Future<void> zeigeHilfe(BuildContext context, String id) {
  final idx = hilfe[id] ?? const [];
  return showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final i in idx) ...[
                Text(anleitung[i].titel,
                    style: Theme.of(c).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
                ...absaetze(c, anleitung[i].teile),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(tr('Ganze Anleitung', 'Full guide')),
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AnleitungSeite()));
                },
              ),
              FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('Verstanden', 'Got it'))),
            ]),
          ),
        ]),
      ),
    ),
  );
}
