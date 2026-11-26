import 'dart:math';

import '../models/booklet.dart';
import '../models/exam.dart';
import '../models/question.dart';

/// Ana kitapçıktan karıştırılmış kitapçıklar üretir.
///
/// Aynı sınav kimliği ve kitapçık koduyla her zaman aynı sonucu verir; böylece
/// bir kitapçık yeniden üretilse bile basılmış kâğıtlarla uyumlu kalır.
class BookletGenerator {
  const BookletGenerator();

  Booklet generate({
    required String examId,
    required String code,
    required int questionCount,
    required int optionCount,
    bool shuffleQuestions = true,
    bool shuffleOptions = false,
  }) {
    final random = Random(_seed('$examId/$code'));
    final order = [for (var i = 1; i <= questionCount; i++) i];
    if (shuffleQuestions) order.shuffle(random);
    final optionMaps = <int, List<int>>{};
    if (shuffleOptions) {
      for (var q = 1; q <= questionCount; q++) {
        final map = [for (var i = 0; i < optionCount; i++) i]..shuffle(random);
        optionMaps[q] = map;
      }
    }
    return Booklet(code: code, questionOrder: order, optionMaps: optionMaps);
  }

  /// Sınav için istenen sayıda kitapçık üretir. İlki her zaman ana kitapçıktır.
  List<Booklet> generateAll(
    Exam exam, {
    required int count,
    bool shuffleOptions = false,
  }) {
    final n = exam.choiceCount;
    return [
      Booklet.master(n),
      for (var i = 1; i < count; i++)
        generate(
          examId: exam.id,
          code: optionLetters[i],
          questionCount: n,
          optionCount: exam.optionCount,
          shuffleOptions: shuffleOptions,
        ),
    ];
  }

  /// Platformdan bağımsız, kararlı bir tohum (FNV-1a).
  static int _seed(String s) {
    var hash = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
