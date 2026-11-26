import 'booklet.dart';
import 'question.dart';
import 'scoring_rules.dart';

/// Öğretmenin seçebileceği hazır sınav şablonları.
enum ExamTemplate {
  schoolWritten,
  lgsPractice,
  tytPractice,
  quiz;

  String get title => switch (this) {
    ExamTemplate.schoolWritten => 'Okul yazılısı',
    ExamTemplate.lgsPractice => 'LGS tarzı deneme',
    ExamTemplate.tytPractice => 'TYT / KPSS tarzı deneme',
    ExamTemplate.quiz => 'Kısa sınav (quiz)',
  };

  String get description => switch (this) {
    ExamTemplate.schoolWritten =>
      '100 puan üzerinden, çoktan seçmeli ve açık uçlu sorular birlikte.',
    ExamTemplate.lgsPractice =>
      'Çoktan seçmeli, 4 şık, 3 yanlış 1 doğruyu götürür.',
    ExamTemplate.tytPractice =>
      'Çoktan seçmeli, 5 şık, 4 yanlış 1 doğruyu götürür.',
    ExamTemplate.quiz => 'Az soruyla hızlı kontrol, tek kitapçık.',
  };

  int get defaultChoiceCount => switch (this) {
    ExamTemplate.schoolWritten => 10,
    ExamTemplate.lgsPractice => 20,
    ExamTemplate.tytPractice => 40,
    ExamTemplate.quiz => 10,
  };

  int get defaultOpenCount => switch (this) {
    ExamTemplate.schoolWritten => 4,
    _ => 0,
  };

  int get defaultOptionCount => switch (this) {
    ExamTemplate.tytPractice => 5,
    _ => 4,
  };

  ScoringRules get defaultRules => switch (this) {
    ExamTemplate.lgsPractice => const ScoringRules(wrongPenaltyDivisor: 3),
    ExamTemplate.tytPractice => const ScoringRules(wrongPenaltyDivisor: 4),
    _ => const ScoringRules(),
  };
}

class Exam {
  const Exam({
    required this.id,
    required this.title,
    required this.createdAt,
    this.subject = '',
    this.classGroup = '',
    this.template = ExamTemplate.schoolWritten,
    this.optionCount = 4,
    this.choiceQuestions = const [],
    this.openQuestions = const [],
    this.booklets = const [],
    this.rules = const ScoringRules(),
  });

  final String id;
  final String title;
  final String subject;

  /// Sınıf ve şube, ör. "9-A".
  final String classGroup;
  final DateTime createdAt;
  final ExamTemplate template;

  /// Her çoktan seçmeli sorudaki şık sayısı (4 ya da 5).
  final int optionCount;
  final List<ChoiceQuestion> choiceQuestions;
  final List<OpenQuestion> openQuestions;

  /// İlk eleman her zaman ana kitapçıktır.
  final List<Booklet> booklets;
  final ScoringRules rules;

  int get choiceCount => choiceQuestions.length;
  int get openCount => openQuestions.length;
  bool get usesBooklets => booklets.length > 1;

  double get openPointsTotal =>
      openQuestions.fold(0, (sum, q) => sum + q.maxPoints);

  /// Çoktan seçmeli bölüme kalan puan.
  double get choicePointsTotal =>
      (rules.totalPoints - openPointsTotal).clamp(0, rules.totalPoints);

  bool get answerKeyComplete =>
      choiceQuestions.every((q) => q.hasAnswer || q.cancelled);

  int get missingAnswerCount =>
      choiceQuestions.where((q) => !q.hasAnswer && !q.cancelled).length;

  Booklet? bookletByCode(String code) {
    for (final b in booklets) {
      if (b.code == code) return b;
    }
    return null;
  }

  Exam copyWith({
    String? title,
    String? subject,
    String? classGroup,
    ExamTemplate? template,
    int? optionCount,
    List<ChoiceQuestion>? choiceQuestions,
    List<OpenQuestion>? openQuestions,
    List<Booklet>? booklets,
    ScoringRules? rules,
  }) {
    return Exam(
      id: id,
      createdAt: createdAt,
      title: title ?? this.title,
      subject: subject ?? this.subject,
      classGroup: classGroup ?? this.classGroup,
      template: template ?? this.template,
      optionCount: optionCount ?? this.optionCount,
      choiceQuestions: choiceQuestions ?? this.choiceQuestions,
      openQuestions: openQuestions ?? this.openQuestions,
      booklets: booklets ?? this.booklets,
      rules: rules ?? this.rules,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'subject': subject,
    'classGroup': classGroup,
    'createdAt': createdAt.toIso8601String(),
    'template': template.name,
    'optionCount': optionCount,
    'choiceQuestions': [for (final q in choiceQuestions) q.toJson()],
    'openQuestions': [for (final q in openQuestions) q.toJson()],
    'booklets': [for (final b in booklets) b.toJson()],
    'rules': rules.toJson(),
  };

  factory Exam.fromJson(Map<String, Object?> json) {
    List<Map<String, Object?>> list(String key) => [
      for (final e in (json[key] as List<Object?>? ?? const []))
        (e! as Map).cast<String, Object?>(),
    ];
    return Exam(
      id: json['id'] as String,
      title: json['title'] as String,
      subject: json['subject'] as String? ?? '',
      classGroup: json['classGroup'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      template: ExamTemplate.values.byName(json['template'] as String),
      optionCount: json['optionCount'] as int? ?? 4,
      choiceQuestions: list('choiceQuestions')
          .map(ChoiceQuestion.fromJson)
          .toList(),
      openQuestions: list('openQuestions').map(OpenQuestion.fromJson).toList(),
      booklets: list('booklets').map(Booklet.fromJson).toList(),
      rules: ScoringRules.fromJson(
        (json['rules']! as Map).cast<String, Object?>(),
      ),
    );
  }
}
