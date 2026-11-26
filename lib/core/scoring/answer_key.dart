import '../models/booklet.dart';
import '../models/exam.dart';
import '../models/question.dart';

/// Ana kitapçık anahtarından diğer kitapçıkların anahtarını üretir.
class AnswerKeyBuilder {
  const AnswerKeyBuilder();

  /// Kitapçıktaki soru numarası → doğru şık harfleri (ör. "B" ya da "A/C").
  /// Cevabı girilmemiş sorular "-", iptal edilenler "İPTAL" olarak döner.
  Map<int, String> keyFor(Exam exam, Booklet booklet) {
    final byNumber = {for (final q in exam.choiceQuestions) q.number: q};
    final key = <int, String>{};
    for (var pos = 1; pos <= booklet.questionCount; pos++) {
      final master = booklet.masterNumberOf(pos);
      final q = byNumber[master];
      if (q == null || q.cancelled) {
        key[pos] = q == null ? '-' : 'İPTAL';
        continue;
      }
      if (!q.hasAnswer) {
        key[pos] = '-';
        continue;
      }
      final letters =
          q.correctOptions
              .map((o) => booklet.bookletOptionOf(master, o))
              .toList()
            ..sort();
      key[pos] = letters.map((i) => optionLetters[i]).join('/');
    }
    return key;
  }
}
