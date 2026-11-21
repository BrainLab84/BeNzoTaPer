// Plan aus einer Datei lesen: PDF (PDFBox-Android, Apache 2.0), Word .docx (ZIP + XML), sonst Text.
import 'i18n/txt.dart';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_pdf_text/read_pdf_text.dart';

/// Liest PDF-Text über die Plattform (in Tests ersetzbar).
typedef PdfLeser = Future<String> Function(List<int> bytes);

Future<String> _pdfSystem(List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/plan_import.pdf');
  await f.writeAsBytes(bytes, flush: true);
  try {
    return await ReadPdfText.getPDFtext(f.path);
  } finally {
    try {
      await f.delete();
    } catch (_) {}
  }
}

class LeseFehler implements Exception {
  LeseFehler(this.text);
  final String text;
}

/// Text aus einer gewählten Datei. Wirft [LeseFehler] mit verständlichem Text.
Future<String> textAusDatei(String name, List<int> bytes, {PdfLeser? pdf}) async {
  final n = name.toLowerCase();
  try {
    if (n.endsWith('.pdf')) return await (pdf ?? _pdfSystem)(bytes);
    if (n.endsWith('.docx')) return docxText(bytes);
    if (n.endsWith('.doc')) {
      throw LeseFehler(tr('Alte Word-Dateien (.doc) gehen leider nicht. Bitte als .docx oder PDF speichern – '
          'oder den Text einfügen.', 'Old Word files (.doc) are not supported, sorry. Please save as .docx or PDF – or paste the text.'));
    }
    if (RegExp(r'\.(png|jpe?g|gif|webp|heic)$').hasMatch(n)) {
      throw LeseFehler(tr('Fotos und Scans gehen nicht. Bitte den Text abtippen oder einfügen.', 'Photos and scans do not work. Please type or paste the text.'));
    }
    return utf8.decode(bytes, allowMalformed: true);
  } on LeseFehler {
    rethrow;
  } catch (_) {
    throw LeseFehler(tr('Datei konnte nicht gelesen werden. Bitte Text einfügen oder abtippen.', 'The file could not be read. Please paste or type the text.'));
  }
}

/// Reiner Text aus einer .docx (wie mammoth `extractRawText`: Absätze = Zeilen).
String docxText(List<int> bytes) {
  final arc = ZipDecoder().decodeBytes(bytes);
  final f = arc.findFile('word/document.xml');
  if (f == null) throw LeseFehler(tr('Das ist keine gültige Word-Datei.', 'This is not a valid Word file.'));
  final xml = utf8.decode(f.content, allowMalformed: true);
  final t = xml
      .replaceAll(RegExp(r'</w:p>'), '\n')
      .replaceAll(RegExp(r'<w:tab\s*/>'), '\t')
      .replaceAll(RegExp(r'<w:br\s*/>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  return t
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
