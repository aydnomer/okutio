import 'package:flutter_test/flutter_test.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/models/student_sheet.dart';
import 'package:okutio/core/results/class_report.dart';

void main() {
  // 10 soru, her biri 10 puan, cevap anahtarı hep A.
  final base = ExamDraft(
    choiceCount: 10,
    openCount: 0,
  ).build(id: 'e', now: DateTime(2026));
  final exam = base.copyWith(
    choiceQuestions: [
      for (final q in base.choiceQuestions) q.copyWith(correctOptions: {0}),
    ],
  );

  StudentSheet sheet(String id, int correctCount) => StudentSheet(
    id: id,
    examId: 'e',
    createdAt: DateTime(2026),
    studentNumber: id,
    choiceMarks: {
      for (var q = 1; q <= 10; q++) q: {q <= correctCount ? 0 : 1},
    },
  );

  test('geçme oranı 50 ve üstünü sayar', () {
    final r = ClassReport(exam, [sheet('1', 3), sheet('2', 5), sheet('3', 9)]);
    expect(r.passRate, closeTo(2 / 3, 1e-9));
    expect(r.highest, 90);
    expect(r.lowest, 30);
  });

  test('iptal edilen soru istatistiğe girmez ve numarası listelenir', () {
    final cancelled = exam.copyWith(
      choiceQuestions: [
        for (final q in exam.choiceQuestions)
          q.number == 10 ? q.copyWith(cancelled: true) : q,
      ],
    );
    final r = ClassReport(cancelled, [sheet('1', 5), sheet('2', 8)]);
    expect(r.cancelledNumbers, [10]);
    expect(r.questionStats().map((q) => q.number), isNot(contains(10)));
    // Herkese doğru sayıldığı için iki öğrenci de 10 puan kazanır.
    expect(r.scores.map((s) => s.total), [60, 90]);
  });

  test('boş sınıf raporu sıfır döner, hata vermez', () {
    final r = ClassReport(exam, const []);
    expect(r.count, 0);
    expect(r.average, 0);
    expect(r.passRate, 0);
    expect(r.hardest(), isEmpty);
  });
}
