/// Okutulmuş (ya da elle girilmiş) bir öğrenci kâğıdı.
library;

import '../scoring/scoring_engine.dart';
import 'exam.dart';

/// Kitapçığın nereden geldiği; öğretmene ne kadar güvenebileceğini söyler.
enum BookletSource {
  marked('Öğrenci işaretledi'),
  guessed('Cevaplara göre tahmin edildi'),
  manual('Öğretmen seçti'),
  single('Tek kitapçık');

  const BookletSource(this.label);
  final String label;
}

class StudentSheet {
  const StudentSheet({
    required this.id,
    required this.examId,
    required this.createdAt,
    this.studentNumber = '',
    this.studentName = '',
    this.bookletCode,
    this.bookletSource = BookletSource.single,
    this.choiceMarks = const {},
    this.openScores = const {},
    this.needsReview = const {},
    this.reviewed = false,
    this.openImageCount = 0,
  });

  final String id;
  final String examId;
  final DateTime createdAt;
  final String studentNumber;
  final String studentName;
  final String? bookletCode;
  final BookletSource bookletSource;

  /// Kitapçıktaki soru numarası → işaretlenen şıklar.
  final Map<int, Set<int>> choiceMarks;

  /// Açık uçlu soru → öğretmenin verdiği puan (`null`: henüz puanlanmadı).
  final Map<int, double?> openScores;

  /// Öğretmenin bakması gereken test soruları (silik işaret vb.).
  final Set<int> needsReview;

  /// Öğretmen kâğıdı gözden geçirip onayladı mı?
  final bool reviewed;

  /// Saklanan açık uçlu cevap görüntüsü sayısı.
  final int openImageCount;

  /// Öğretmene sorulacak bir şey var mı?
  List<String> issues(Exam exam) => [
    if (studentNumber.isEmpty || studentNumber.contains('?'))
      'Öğrenci numarası okunamadı',
    if (needsReview.isNotEmpty) '${needsReview.length} soruda silik işaret',
    if (bookletSource == BookletSource.guessed) 'Kitapçık tahmin edildi',
    if (exam.openQuestions.any((q) => openScores[q.number] == null))
      'Açık uçlu puan bekliyor',
  ];

  StudentResponse toResponse() => StudentResponse(
    bookletCode: bookletCode,
    choiceMarks: choiceMarks,
    openScores: openScores,
  );

  ScoreResult score(Exam exam) =>
      const ScoringEngine().score(exam, toResponse());

  StudentSheet copyWith({
    String? studentNumber,
    String? studentName,
    String? Function()? bookletCode,
    BookletSource? bookletSource,
    Map<int, Set<int>>? choiceMarks,
    Map<int, double?>? openScores,
    Set<int>? needsReview,
    bool? reviewed,
    int? openImageCount,
  }) => StudentSheet(
    id: id,
    examId: examId,
    createdAt: createdAt,
    studentNumber: studentNumber ?? this.studentNumber,
    studentName: studentName ?? this.studentName,
    bookletCode: bookletCode != null ? bookletCode() : this.bookletCode,
    bookletSource: bookletSource ?? this.bookletSource,
    choiceMarks: choiceMarks ?? this.choiceMarks,
    openScores: openScores ?? this.openScores,
    needsReview: needsReview ?? this.needsReview,
    reviewed: reviewed ?? this.reviewed,
    openImageCount: openImageCount ?? this.openImageCount,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'examId': examId,
    'createdAt': createdAt.toIso8601String(),
    'studentNumber': studentNumber,
    'studentName': studentName,
    'bookletCode': bookletCode,
    'bookletSource': bookletSource.name,
    'choiceMarks': {
      for (final e in choiceMarks.entries) '${e.key}': e.value.toList()..sort(),
    },
    'openScores': {for (final e in openScores.entries) '${e.key}': e.value},
    'needsReview': needsReview.toList()..sort(),
    'reviewed': reviewed,
    'openImageCount': openImageCount,
  };

  factory StudentSheet.fromJson(Map<String, Object?> j) => StudentSheet(
    id: j['id']! as String,
    examId: j['examId']! as String,
    createdAt: DateTime.parse(j['createdAt']! as String),
    studentNumber: j['studentNumber'] as String? ?? '',
    studentName: j['studentName'] as String? ?? '',
    bookletCode: j['bookletCode'] as String?,
    bookletSource: BookletSource.values.byName(
      j['bookletSource'] as String? ?? 'single',
    ),
    choiceMarks: {
      for (final e in (j['choiceMarks'] as Map? ?? const {}).entries)
        int.parse(e.key as String): (e.value as List<Object?>)
            .cast<int>()
            .toSet(),
    },
    openScores: {
      for (final e in (j['openScores'] as Map? ?? const {}).entries)
        int.parse(e.key as String): (e.value as num?)?.toDouble(),
    },
    needsReview: (j['needsReview'] as List<Object?>? ?? const [])
        .cast<int>()
        .toSet(),
    reviewed: j['reviewed'] as bool? ?? false,
    openImageCount: j['openImageCount'] as int? ?? 0,
  );
}
