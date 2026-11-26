/// Çoktan seçmeli ve açık uçlu cevaplardan puan hesaplayan saf Dart motoru.
///
/// Arayüzden bağımsızdır; bu sayede birim testleriyle tamamen denetlenebilir
/// ve kural değişince bütün kâğıtlar saniyeler içinde yeniden puanlanabilir.
library;

import 'dart:math' as math;

import '../models/booklet.dart';
import '../models/exam.dart';
import '../models/question.dart';
import '../models/scoring_rules.dart';

/// Bir öğrencinin bir sınavdaki cevapları, kâğıtta göründüğü haliyle.
class StudentResponse {
  const StudentResponse({
    this.bookletCode,
    this.choiceMarks = const {},
    this.openScores = const {},
  });

  /// Öğrencinin kodladığı ya da QR'dan okunan kitapçık. `null` ise ana kitapçık varsayılır.
  final String? bookletCode;

  /// Kitapçıktaki soru numarası → işaretlenen şık indeksleri (0 = A).
  final Map<int, Set<int>> choiceMarks;

  /// Açık uçlu soru numarası → öğretmenin onayladığı puan.
  /// Değer `null` ya da anahtar yoksa soru henüz puanlanmamıştır.
  final Map<int, double?> openScores;
}

enum QuestionOutcome {
  correct,
  wrong,
  blank,
  cancelled;

  String get label => switch (this) {
    QuestionOutcome.correct => 'Doğru',
    QuestionOutcome.wrong => 'Yanlış',
    QuestionOutcome.blank => 'Boş',
    QuestionOutcome.cancelled => 'İptal',
  };
}

class QuestionResult {
  const QuestionResult({
    required this.masterNumber,
    required this.outcome,
    required this.markedOptions,
    required this.points,
    required this.earned,
    this.multiMarked = false,
  });

  /// Ana kitapçığa göre soru numarası.
  final int masterNumber;
  final QuestionOutcome outcome;

  /// Ana kitapçık şıklarına çevrilmiş işaretler.
  final Set<int> markedOptions;

  /// Sorunun değeri (iptal ve dağıtım kuralları uygulanmış).
  final double points;

  /// Yanlış cezası düşülmeden önce kazanılan puan.
  final double earned;

  /// Birden fazla şık işaretlenmiş mi (öğretmene uyarı için).
  final bool multiMarked;
}

class ScoreResult {
  const ScoreResult({
    required this.bookletCode,
    required this.questions,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.cancelled,
    required this.net,
    required this.choiceScore,
    required this.openScore,
    required this.openPending,
    required this.total,
  });

  final String bookletCode;
  final List<QuestionResult> questions;
  final int correct;
  final int wrong;
  final int blank;
  final int cancelled;

  /// Doğru − Yanlış / bölen. Yanlış götürmüyorsa doğru sayısına eşittir.
  final double net;
  final double choiceScore;
  final double openScore;

  /// Puanlanmamış açık uçlu soru sayısı. 0 değilse sonuç kesin değildir.
  final int openPending;

  /// Yuvarlanmış ve 0 ile tam puan arasına sınırlanmış toplam.
  final double total;

  bool get isFinal => openPending == 0;
}

class ScoringEngine {
  const ScoringEngine();

  /// Her çoktan seçmeli sorunun puan değerini hesaplar.
  ///
  /// Elle puan verilmemiş sorular kalan puanı eşit paylaşır. İptal edilen
  /// sorular "hesaptan çıkar" kuralındaysa puanları diğer sorulara orantılı dağıtılır.
  Map<int, double> questionPoints(Exam exam) {
    final budget = exam.choicePointsTotal;
    final questions = exam.choiceQuestions;
    if (questions.isEmpty) return {};

    final manualSum = questions
        .where((q) => q.points != null)
        .fold<double>(0, (s, q) => s + q.points!);
    final autoCount = questions.where((q) => q.points == null).length;
    final share = autoCount == 0
        ? 0.0
        : math.max(0, budget - manualSum) / autoCount;

    final raw = {for (final q in questions) q.number: q.points ?? share};

    if (exam.rules.cancelPolicy == CancelPolicy.exclude) {
      final activeSum = questions
          .where((q) => !q.cancelled)
          .fold<double>(0, (s, q) => s + raw[q.number]!);
      final allSum = raw.values.fold<double>(0, (s, v) => s + v);
      final scale = activeSum == 0 ? 0 : allSum / activeSum;
      return {
        for (final q in questions)
          q.number: q.cancelled ? 0 : raw[q.number]! * scale,
      };
    }
    return raw;
  }

  ScoreResult score(Exam exam, StudentResponse response) {
    final booklet = _resolveBooklet(exam, response.bookletCode);
    final rules = exam.rules;
    final points = questionPoints(exam);

    // Öğrencinin işaretlerini ana kitapçık numaralarına çevir.
    final masterMarks = <int, Set<int>>{};
    response.choiceMarks.forEach((bookletNumber, marks) {
      if (bookletNumber < 1 || bookletNumber > booklet.questionCount) return;
      final master = booklet.masterNumberOf(bookletNumber);
      masterMarks[master] = {
        for (final m in marks) booklet.masterOptionOf(master, m),
      };
    });

    var correct = 0, wrong = 0, blank = 0, cancelled = 0;
    var earnedSum = 0.0, wrongPoints = 0.0;
    final results = <QuestionResult>[];

    for (final q in exam.choiceQuestions) {
      final marks = masterMarks[q.number] ?? const <int>{};
      final value = points[q.number] ?? 0;
      final outcome = _outcomeFor(q, marks, rules);
      var earned = 0.0;
      switch (outcome) {
        case QuestionOutcome.correct:
          correct++;
          earned = value;
        case QuestionOutcome.wrong:
          wrong++;
          wrongPoints += value;
        case QuestionOutcome.blank:
          blank++;
        case QuestionOutcome.cancelled:
          cancelled++;
          if (rules.cancelPolicy == CancelPolicy.countAsCorrect) {
            correct++;
            earned = value;
          }
      }
      earnedSum += earned;
      results.add(
        QuestionResult(
          masterNumber: q.number,
          outcome: outcome,
          markedOptions: marks,
          points: value,
          earned: earned,
          multiMarked: marks.length > 1,
        ),
      );
    }

    final divisor = rules.wrongPenaltyDivisor;
    final net = divisor == null
        ? correct.toDouble()
        : correct - wrong / divisor;
    final penalty = divisor == null ? 0.0 : wrongPoints / divisor;
    final choiceScore = math.max(0.0, earnedSum - penalty);

    var openScore = 0.0, openPending = 0;
    for (final q in exam.openQuestions) {
      final s = response.openScores[q.number];
      if (s == null) {
        openPending++;
      } else {
        openScore += s.clamp(0, q.maxPoints);
      }
    }

    final total = roundTo(
      (choiceScore + openScore).clamp(0, rules.totalPoints).toDouble(),
      rules.roundingStep,
    );

    return ScoreResult(
      bookletCode: booklet.code,
      questions: results,
      correct: correct,
      wrong: wrong,
      blank: blank,
      cancelled: cancelled,
      net: net,
      choiceScore: choiceScore,
      openScore: openScore,
      openPending: openPending,
      total: total,
    );
  }

  QuestionOutcome _outcomeFor(
    ChoiceQuestion q,
    Set<int> marks,
    ScoringRules rules,
  ) {
    if (q.cancelled) return QuestionOutcome.cancelled;
    if (marks.isEmpty) return QuestionOutcome.blank;
    if (marks.length > 1) {
      return rules.multiMarkPolicy == MultiMarkPolicy.blank
          ? QuestionOutcome.blank
          : QuestionOutcome.wrong;
    }
    return q.correctOptions.contains(marks.first)
        ? QuestionOutcome.correct
        : QuestionOutcome.wrong;
  }

  Booklet _resolveBooklet(Exam exam, String? code) {
    if (exam.booklets.isEmpty) return Booklet.master(exam.choiceCount);
    if (code == null) return exam.booklets.first;
    return exam.bookletByCode(code) ?? exam.booklets.first;
  }

  /// Kitapçık kodlanmamış ya da şüpheli olduğunda, cevapları her kitapçığın
  /// anahtarıyla puanlayıp en olası kitapçığı önerir.
  BookletGuess guessBooklet(Exam exam, Map<int, Set<int>> choiceMarks) {
    final candidates = exam.booklets.isEmpty
        ? [Booklet.master(exam.choiceCount)]
        : exam.booklets;
    final scores = <String, int>{
      for (final b in candidates)
        b.code: score(
          exam,
          StudentResponse(bookletCode: b.code, choiceMarks: choiceMarks),
        ).correct,
    };
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final runnerUp = ranked.length > 1 ? ranked[1].value : 0;
    // Fark sorunun %10'undan ve 3 sorudan büyükse güvenli öneri sayılır.
    final threshold = math.max(3, (exam.choiceCount * 0.1).ceil());
    return BookletGuess(
      code: best.key,
      correctByBooklet: scores,
      confident: ranked.length == 1 || best.value - runnerUp >= threshold,
    );
  }

  static double roundTo(double value, double step) {
    if (step <= 0) return value;
    return (value / step).round() * step;
  }
}

class BookletGuess {
  const BookletGuess({
    required this.code,
    required this.correctByBooklet,
    required this.confident,
  });

  final String code;
  final Map<String, int> correctByBooklet;

  /// `false` ise fark küçüktür; kâğıt öğretmenin onayına düşmelidir.
  final bool confident;
}
