/// Cevap anahtarını tek satırda yazarak girmek için ayrıştırıcı.
///
/// Örnek: `ABCD -BCA` → 1:A, 2:B, 3:C, 4:D, 5:boş, 6:B, 7:C, 8:A.
/// Boşluklar yok sayılır; `-`, `_`, `.` ya da `?` o soruyu boş bırakır.
library;

import '../models/question.dart';

class AnswerInputResult {
  const AnswerInputResult(this.answers, this.error);

  /// Her soru için seçilen şık; `null` boş demektir.
  final List<int?> answers;

  /// Hata varsa öğretmene gösterilecek açıklama.
  final String? error;

  bool get ok => error == null;
}

abstract final class AnswerInput {
  static const _blank = {'-', '_', '.', '?'};

  static AnswerInputResult parse(
    String text, {
    required int optionCount,
    required int questionCount,
  }) {
    final answers = <int?>[];
    final allowed = optionLetters.take(optionCount).toList();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (ch.trim().isEmpty || ch == ',' || ch == ';') continue;
      if (_blank.contains(ch)) {
        answers.add(null);
        continue;
      }
      final index = allowed.indexOf(ch.toUpperCase());
      if (index < 0) {
        return AnswerInputResult(
          answers,
          '${answers.length + 1}. cevaptaki "$ch" geçersiz. '
          'Yalnızca ${allowed.first}-${allowed.last} harfleri ve boş için "-" kullanın.',
        );
      }
      answers.add(index);
    }
    if (answers.length > questionCount) {
      return AnswerInputResult(
        answers,
        '${answers.length} cevap yazdınız ama sınavda $questionCount soru var.',
      );
    }
    return AnswerInputResult(answers, null);
  }

  /// Var olan anahtarı tek satır metne çevirir (çoklu doğrular ilk şıkla).
  static String format(List<ChoiceQuestion> questions) {
    final buffer = StringBuffer();
    for (var i = 0; i < questions.length; i++) {
      if (i > 0 && i % 5 == 0) buffer.write(' ');
      final q = questions[i];
      if (q.correctOptions.isEmpty) {
        buffer.write('-');
      } else {
        final first = (q.correctOptions.toList()..sort()).first;
        buffer.write(optionLetters[first]);
      }
    }
    return buffer.toString();
  }
}
