/// Sınav soruları: çoktan seçmeli ve açık uçlu.
library;

/// Şık harfleri. Sınavlar 4 (A-D) ya da 5 (A-E) şıklı olabilir.
const optionLetters = ['A', 'B', 'C', 'D', 'E'];

/// Ana (A) kitapçığa göre numaralanmış çoktan seçmeli soru.
class ChoiceQuestion {
  const ChoiceQuestion({
    required this.number,
    this.correctOptions = const {},
    this.points,
    this.cancelled = false,
  });

  /// Ana kitapçıktaki soru numarası, 1'den başlar.
  final int number;

  /// Doğru kabul edilen şıkların indeksleri (0 = A). Birden fazla olabilir.
  final Set<int> correctOptions;

  /// Öğretmenin elle verdiği puan. `null` ise puan eşit dağıtılır.
  final double? points;

  final bool cancelled;

  bool get hasAnswer => correctOptions.isNotEmpty;

  ChoiceQuestion copyWith({
    Set<int>? correctOptions,
    double? Function()? points,
    bool? cancelled,
  }) {
    return ChoiceQuestion(
      number: number,
      correctOptions: correctOptions ?? this.correctOptions,
      points: points != null ? points() : this.points,
      cancelled: cancelled ?? this.cancelled,
    );
  }

  Map<String, Object?> toJson() => {
    'number': number,
    'correctOptions': correctOptions.toList()..sort(),
    'points': points,
    'cancelled': cancelled,
  };

  factory ChoiceQuestion.fromJson(Map<String, Object?> json) => ChoiceQuestion(
    number: json['number'] as int,
    correctOptions: (json['correctOptions'] as List<Object?>)
        .cast<int>()
        .toSet(),
    points: (json['points'] as num?)?.toDouble(),
    cancelled: json['cancelled'] as bool? ?? false,
  );
}

/// Açık uçlu sorunun puanlama ölçütü (dereceli puanlama anahtarının bir satırı).
class RubricCriterion {
  const RubricCriterion({required this.title, required this.weightPercent});

  final String title;

  /// Bu ölçütün sorunun puanındaki payı, yüzde olarak.
  final double weightPercent;

  Map<String, Object?> toJson() => {
    'title': title,
    'weightPercent': weightPercent,
  };

  factory RubricCriterion.fromJson(Map<String, Object?> json) =>
      RubricCriterion(
        title: json['title'] as String,
        weightPercent: (json['weightPercent'] as num).toDouble(),
      );
}

class OpenQuestion {
  const OpenQuestion({
    required this.number,
    required this.maxPoints,
    this.prompt = '',
    this.referenceAnswer = '',
    this.rubric = const [],
    this.answerLines = 4,
  });

  /// Açık uçlu sorular kendi içinde 1'den numaralanır.
  final int number;
  final double maxPoints;
  final String prompt;
  final String referenceAnswer;
  final List<RubricCriterion> rubric;

  /// Formda bu soruya ayrılacak satır sayısı; cevap kutusunun yüksekliğini belirler.
  final int answerLines;

  double get rubricTotal => rubric.fold(0, (sum, c) => sum + c.weightPercent);

  bool get rubricIsComplete =>
      rubric.isNotEmpty && (rubricTotal - 100).abs() < 0.01;

  OpenQuestion copyWith({
    double? maxPoints,
    String? prompt,
    String? referenceAnswer,
    List<RubricCriterion>? rubric,
    int? answerLines,
  }) {
    return OpenQuestion(
      number: number,
      maxPoints: maxPoints ?? this.maxPoints,
      prompt: prompt ?? this.prompt,
      referenceAnswer: referenceAnswer ?? this.referenceAnswer,
      rubric: rubric ?? this.rubric,
      answerLines: answerLines ?? this.answerLines,
    );
  }

  Map<String, Object?> toJson() => {
    'number': number,
    'maxPoints': maxPoints,
    'prompt': prompt,
    'referenceAnswer': referenceAnswer,
    'rubric': [for (final c in rubric) c.toJson()],
    'answerLines': answerLines,
  };

  factory OpenQuestion.fromJson(Map<String, Object?> json) => OpenQuestion(
    number: json['number'] as int,
    maxPoints: (json['maxPoints'] as num).toDouble(),
    prompt: json['prompt'] as String? ?? '',
    referenceAnswer: json['referenceAnswer'] as String? ?? '',
    rubric: [
      for (final c in (json['rubric'] as List<Object?>? ?? const []))
        RubricCriterion.fromJson((c! as Map).cast<String, Object?>()),
    ],
    answerLines: json['answerLines'] as int? ?? 4,
  );
}
