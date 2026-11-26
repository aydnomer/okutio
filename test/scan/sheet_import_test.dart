import 'package:flutter_test/flutter_test.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/form/form_layout.dart';
import 'package:okutio/core/models/exam.dart';
import 'package:okutio/core/models/student_sheet.dart';
import 'package:okutio/core/results/class_report.dart';
import 'package:okutio/core/scan/sheet_import.dart';
import 'package:okutio/core/scan/sheet_reader.dart';

import '../support/synthetic_sheet.dart';

Exam _withKey(Exam e, List<int> key) => e.copyWith(
  choiceQuestions: [
    for (final (i, q) in e.choiceQuestions.indexed)
      q.copyWith(correctOptions: {key[i]}),
  ],
);

void main() {
  final key = [0, 1, 2, 3, 0, 1, 2, 3, 0, 1];
  final exam = _withKey(
    ExamDraft(
      choiceCount: 10,
      openCount: 2,
    ).build(id: 'e', now: DateTime(2026)),
    key,
  );
  final layout = FormLayout.compute(exam);

  StudentSheet scan(Map<int, Set<int>> marks, String no) {
    final photo = photograph(
      renderSheet(
        layout.pages.first,
        StudentMarks(choices: marks, studentNumber: no),
      ),
      const Camera(brightness: 0.4),
    );
    return sheetFromReading(
      exam: exam,
      reading: SheetReader(layout).readBytes(photo),
      id: no,
      now: DateTime(2026),
    );
  }

  test('okunan kâğıt puanlanır, açık uçlu puan bekler', () {
    final s = scan({
      for (var q = 1; q <= 8; q++) q: {key[q - 1]},
      9: {3},
    }, '15');
    expect(s.studentNumber, '15');
    final score = s.score(exam);
    expect(score.correct, 8);
    expect(score.wrong, 1);
    expect(score.blank, 1);
    expect(score.isFinal, isFalse);
    expect(s.issues(exam), contains('Açık uçlu puan bekliyor'));
    expect(s.openImageCount, 2);

    final graded = s.copyWith(openScores: {1: 10, 2: 5});
    expect(graded.score(exam).isFinal, isTrue);
    // Test soruları 80/10 = 8 puan: 8 doğru × 8 + 15 = 79
    expect(graded.score(exam).total, 79);
    expect(StudentSheet.fromJson(graded.toJson()).score(exam).total, 79);
  });

  test('sınıf raporu ortalama ve zor soruları bulur', () {
    final a = scan({
      for (var q = 1; q <= 10; q++) q: {key[q - 1]},
    }, '1').copyWith(openScores: {1: 10, 2: 10});
    final b = scan({
      for (var q = 1; q <= 9; q++) q: {key[q - 1]},
      10: {0},
    }, '2').copyWith(openScores: {1: 0, 2: 0});
    final report = ClassReport(exam, [a, b]);
    expect(report.count, 2);
    expect(report.highest, 100);
    expect(report.lowest, 72);
    expect(report.average, 86);
    expect(report.hardest().map((q) => q.number), [10]);
  });
}
