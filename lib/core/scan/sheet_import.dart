/// Tarama sonucunu öğrenci kâğıdına çevirir.
library;

import '../models/exam.dart';
import '../models/student_sheet.dart';
import '../scoring/scoring_engine.dart';
import 'sheet_reader.dart';

StudentSheet sheetFromReading({
  required Exam exam,
  required SheetReading reading,
  required String id,
  required DateTime now,
}) {
  final marks = <int, Set<int>>{
    for (final c in reading.choices)
      if (c.marked.isNotEmpty) c.number: c.marked,
  };

  String? booklet;
  var source = BookletSource.single;
  if (exam.usesBooklets) {
    final i = reading.bookletIndex;
    if (i != null && i < exam.booklets.length) {
      booklet = exam.booklets[i].code;
      source = BookletSource.marked;
    } else {
      // Öğrenci kitapçığı işaretlememiş: hangi kitapçığın anahtarıyla en
      // çok doğru çıkıyorsa o. Fark azsa öğretmen onaylayacak.
      booklet = const ScoringEngine().guessBooklet(exam, marks).code;
      source = BookletSource.guessed;
    }
  } else if (exam.booklets.isNotEmpty) {
    booklet = exam.booklets.first.code;
  }

  return StudentSheet(
    id: id,
    examId: exam.id,
    createdAt: now,
    studentNumber: reading.studentNumber,
    bookletCode: booklet,
    bookletSource: source,
    choiceMarks: marks,
    openScores: {for (final q in exam.openQuestions) q.number: null},
    needsReview: reading.unsureQuestions.toSet(),
    openImageCount: reading.openAnswers.length,
  );
}
