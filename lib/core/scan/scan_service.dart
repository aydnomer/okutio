/// Fotoğrafları arka planda okur (telefonda ayrı iş parçacığında, web'de
/// arayüzü kilitlemeden).
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;

import '../form/form_layout.dart';
import '../models/exam.dart';
import 'sheet_reader.dart';

/// Bir fotoğrafın okunma sonucu: ya okuma ya da öğretmene gösterilecek hata.
class ScanOutcome {
  const ScanOutcome.ok(SheetReading this.reading) : error = null;
  const ScanOutcome.failed(String this.error) : reading = null;

  final SheetReading? reading;
  final String? error;
}

ScanOutcome _readSync((Exam, Uint8List) args) {
  final (exam, bytes) = args;
  try {
    final reading = SheetReader(FormLayout.compute(exam)).readBytes(bytes);
    return ScanOutcome.ok(reading);
  } on ScanFailure catch (e) {
    return ScanOutcome.failed(e.message);
  } on Object {
    return const ScanOutcome.failed(
      'Bu fotoğraf okunamadı. Kâğıdın tamamı görünecek şekilde tekrar çekin.',
    );
  }
}

Future<ScanOutcome> readSheetPhoto(Exam exam, Uint8List bytes) async {
  if (kIsWeb) {
    // Web'de iş parçacığı yok: arayüz bir kare çizebilsin diye kısa bekle.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    return _readSync((exam, bytes));
  }
  return compute(_readSync, (exam, bytes));
}
