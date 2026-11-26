import 'package:flutter_test/flutter_test.dart';
import 'package:okutio/core/models/question.dart';
import 'package:okutio/core/scoring/answer_input.dart';

void main() {
  group('AnswerInput.parse', () {
    test('harfleri ve boşları sırayla okur', () {
      final r = AnswerInput.parse(
        'abcd -BCA',
        optionCount: 4,
        questionCount: 10,
      );
      expect(r.ok, isTrue);
      expect(r.answers, [0, 1, 2, 3, null, 1, 2, 0]);
    });

    test('4 şıklı sınavda E geçersizdir', () {
      final r = AnswerInput.parse('ABE', optionCount: 4, questionCount: 5);
      expect(r.ok, isFalse);
      expect(r.error, contains('3. cevaptaki'));
    });

    test('soru sayısından fazla cevap hata verir', () {
      final r = AnswerInput.parse('ABCDA B', optionCount: 5, questionCount: 5);
      expect(r.ok, isFalse);
    });

    test('virgül ve noktalı virgül ayraç sayılır', () {
      final r = AnswerInput.parse('A,B;C', optionCount: 4, questionCount: 5);
      expect(r.answers, [0, 1, 2]);
    });
  });

  test('format beşerli gruplar yazar', () {
    final qs = [
      for (var i = 1; i <= 7; i++)
        ChoiceQuestion(number: i, correctOptions: i == 3 ? {} : {i % 4}),
    ];
    expect(AnswerInput.format(qs), 'BC-AB CD');
  });
}
