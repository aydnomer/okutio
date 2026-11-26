/// Bir sınavın puanlama kuralları.
///
/// Öğretmen bu kuralları sınav oluştururken seçer. Kurallar değişirse
/// kâğıtlar yeniden taranmadan tüm puanlar yeniden hesaplanabilir.
library;

/// Aynı soruda birden fazla şık işaretlenmişse ne yapılacağı.
enum MultiMarkPolicy {
  /// Yanlış sayılır (ÖSYM ve çoğu deneme sınavı böyle yapar).
  wrong,

  /// Boş sayılır.
  blank;

  String get label => switch (this) {
    MultiMarkPolicy.wrong => 'Yanlış say',
    MultiMarkPolicy.blank => 'Boş say',
  };
}

/// İptal edilen bir sorunun nasıl değerlendirileceği.
enum CancelPolicy {
  /// Herkese doğru sayılır, puanı herkese verilir.
  countAsCorrect,

  /// Hesaptan çıkarılır; puanı diğer sorulara dağıtılır.
  exclude;

  String get label => switch (this) {
    CancelPolicy.countAsCorrect => 'Herkese doğru say',
    CancelPolicy.exclude => 'Hesaptan çıkar',
  };
}

class ScoringRules {
  const ScoringRules({
    this.wrongPenaltyDivisor,
    this.multiMarkPolicy = MultiMarkPolicy.wrong,
    this.cancelPolicy = CancelPolicy.countAsCorrect,
    this.totalPoints = 100,
    this.roundingStep = 1,
  });

  /// Kaç yanlışın bir doğruyu götürdüğü. `null` ise yanlış götürmez.
  /// LGS tarzı için 3, TYT/KPSS tarzı için 4.
  final int? wrongPenaltyDivisor;

  final MultiMarkPolicy multiMarkPolicy;
  final CancelPolicy cancelPolicy;

  /// Sınavın tam puanı (çoğunlukla 100).
  final double totalPoints;

  /// Son puanın yuvarlanacağı adım: 1 tam sayıya, 0.5 yarım puana yuvarlar.
  /// 0 ise yuvarlama yapılmaz.
  final double roundingStep;

  bool get hasPenalty => wrongPenaltyDivisor != null;

  String get penaltyLabel => switch (wrongPenaltyDivisor) {
    null => 'Yanlış doğruyu götürmez',
    final d => '$d yanlış 1 doğruyu götürür',
  };

  ScoringRules copyWith({
    int? Function()? wrongPenaltyDivisor,
    MultiMarkPolicy? multiMarkPolicy,
    CancelPolicy? cancelPolicy,
    double? totalPoints,
    double? roundingStep,
  }) {
    return ScoringRules(
      wrongPenaltyDivisor: wrongPenaltyDivisor != null
          ? wrongPenaltyDivisor()
          : this.wrongPenaltyDivisor,
      multiMarkPolicy: multiMarkPolicy ?? this.multiMarkPolicy,
      cancelPolicy: cancelPolicy ?? this.cancelPolicy,
      totalPoints: totalPoints ?? this.totalPoints,
      roundingStep: roundingStep ?? this.roundingStep,
    );
  }

  Map<String, Object?> toJson() => {
    'wrongPenaltyDivisor': wrongPenaltyDivisor,
    'multiMarkPolicy': multiMarkPolicy.name,
    'cancelPolicy': cancelPolicy.name,
    'totalPoints': totalPoints,
    'roundingStep': roundingStep,
  };

  factory ScoringRules.fromJson(Map<String, Object?> json) => ScoringRules(
    wrongPenaltyDivisor: json['wrongPenaltyDivisor'] as int?,
    multiMarkPolicy: MultiMarkPolicy.values.byName(
      json['multiMarkPolicy'] as String,
    ),
    cancelPolicy: CancelPolicy.values.byName(json['cancelPolicy'] as String),
    totalPoints: (json['totalPoints'] as num).toDouble(),
    roundingStep: (json['roundingStep'] as num).toDouble(),
  );
}
