import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/form/form_layout.dart';
import 'package:okutio/core/form/form_pdf.dart';

FormFonts _fonts() {
  ByteData load(String name) =>
      ByteData.sublistView(File('assets/fonts/$name').readAsBytesSync());
  return FormFonts.fromBytes(
    regular: load('Roboto-Regular.ttf'),
    bold: load('Roboto-Bold.ttf'),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('tr'));

  test('örnek sınavın formu PDF olarak üretilir', () async {
    final exam = buildSampleExam(now: DateTime(2026, 11, 26));
    final layout = FormLayout.compute(exam);
    final bytes = await FormPdf(
      layout,
      _fonts(),
      date: DateTime(2026, 11, 26),
    ).build(copies: 2);

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // İki kopya × sayfa sayısı.
    final pages = RegExp(r'/Type\s*/Page[^s]')
        .allMatches(String.fromCharCodes(bytes));
    expect(pages.length, 2 * layout.pages.length);

    final out = Platform.environment['OKUTIO_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
