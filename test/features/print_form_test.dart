import 'package:flutter_test/flutter_test.dart';
import 'package:okutio/features/print_form/print_form_screen.dart';

void main() {
  test('PDF dosya adı Türkçe harfleri sadeleştirir', () {
    expect(
      pdfFileName('Fen Bilimleri 1. Yazılı: Şubat/Çarşamba'),
      'okutio-fen-bilimleri-1-yazili-subatcarsamba.pdf',
    );
    expect(pdfFileName('  ***  '), 'okutio-form.pdf');
  });
}
