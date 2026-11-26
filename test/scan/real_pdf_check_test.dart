// Gerçek PDF'ten basılmış gibi bir fotoğrafla elle kontrol. Yalnızca
// OKUTIO_REAL_* ortam değişkenleri verildiğinde çalışır.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/form/form_layout.dart';
import 'package:okutio/core/form/form_pdf.dart';
import 'package:okutio/core/scan/sheet_reader.dart';

void main() {
  final pdfOut = Platform.environment['OKUTIO_REAL_PDF'];
  final photo = Platform.environment['OKUTIO_REAL_PHOTO'];
  final layout = FormLayout.compute(
    (ExamDraft(
      choiceCount: 20,
      openCount: 2,
    )..bookletCount = 2).build(id: 'sinav-42', now: DateTime(2026)),
  );

  test('gerçek PDF üret', () async {
    await initializeDateFormatting('tr');
    ByteData load(String n) =>
        ByteData.sublistView(File('assets/fonts/$n').readAsBytesSync());
    final fonts = FormFonts.fromBytes(
      regular: load('Roboto-Regular.ttf'),
      bold: load('Roboto-Bold.ttf'),
    );
    File(pdfOut!).writeAsBytesSync(await FormPdf(layout, fonts).build());
    // Yuvarlak merkezleri (mm) Python betiğine.
    final p = layout.pages.first;
    File('$pdfOut.json').writeAsStringSync(
      jsonEncode({
        'choices': [
          for (final r in p.choiceRows)
            [
              for (final b in r.bubbles) [b.cx, b.cy],
            ],
        ],
        'digits': [
          for (final d in p.studentNumber)
            [
              for (final b in d.bubbles) [b.cx, b.cy],
            ],
        ],
        'booklet': [
          for (final b in p.bookletBubbles) [b.cx, b.cy],
        ],
        'r': FormLayout.bubbleRadius,
      }),
    );
  }, skip: pdfOut == null);

  test('fotoğrafı oku', () {
    final r = SheetReader(layout).readBytes(File(photo!).readAsBytesSync());
    // ignore: avoid_print
    print({
      'qr': r.qrText,
      'no': r.studentNumber,
      'kitapcik': r.bookletIndex,
      'isaretler': {
        for (final c in r.choices)
          if (c.marked.isNotEmpty) c.number: c.marked.toList(),
      },
      'silik': r.unsureQuestions,
      'uyari': r.warnings,
    });
  }, skip: photo == null);
}
