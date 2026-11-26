import 'package:flutter_test/flutter_test.dart';
import 'package:okutio/core/models/booklet.dart';
import 'package:okutio/core/models/exam.dart';
import 'package:okutio/core/models/question.dart';
import 'package:okutio/core/models/scoring_rules.dart';
import 'package:okutio/core/scoring/answer_key.dart';
import 'package:okutio/core/scoring/booklet_generator.dart';
import 'package:okutio/core/scoring/scoring_engine.dart';

const a = 0, b = 1, c = 2, d = 3;

Exam makeExam({
  List<int> key = const [a, b, c, d, a, b, c, d, a, b],
  List<OpenQuestion> open = const [],
  ScoringRules rules = const ScoringRules(),
  List<Booklet> booklets = const [],
}) {
  return Exam(
    id: 'test',
    title: 'Deneme',
    createdAt: DateTime(2026, 11, 26),
    choiceQuestions: [
      for (var i = 0; i < key.length; i++)
        ChoiceQuestion(number: i + 1, correctOptions: {key[i]}),
    ],
    openQuestions: open,
    booklets: booklets,
    rules: rules,
  );
}

Map<int, Set<int>> marks(List<int?> answers) => {
  for (var i = 0; i < answers.length; i++)
    if (answers[i] != null) i + 1: {answers[i]!},
};

void main() {
  const engine = ScoringEngine();

  group('temel puanlama', () {
    test('tamamı doğru 100 puan alır', () {
      final exam = makeExam();
      final r = engine.score(
        exam,
        StudentResponse(choiceMarks: marks([a, b, c, d, a, b, c, d, a, b])),
      );
      expect(r.correct, 10);
      expect(r.total, 100);
      expect(r.isFinal, isTrue);
    });

    test('doğru, yanlış ve boş ayrı sayılır', () {
      final exam = makeExam();
      final r = engine.score(
        exam,
        StudentResponse(
          choiceMarks: marks([a, b, c, d, a, b, c, a, null, null]),
        ),
      );
      expect(r.correct, 7);
      expect(r.wrong, 1);
      expect(r.blank, 2);
      expect(r.total, 70);
    });
  });

  group('yanlış götürme', () {
    test('4 yanlış 1 doğruyu götürür: net ve puan', () {
      // 40 soru, 30 doğru, 8 yanlış, 2 boş → 28 net.
      final key = List.filled(40, a);
      final answers = <int?>[
        ...List.filled(30, a),
        ...List.filled(8, b),
        null,
        null,
      ];
      final exam = makeExam(
        key: key,
        rules: const ScoringRules(wrongPenaltyDivisor: 4),
      );
      final r = engine.score(
        exam,
        StudentResponse(choiceMarks: marks(answers)),
      );
      expect(r.net, 28);
      expect(r.total, 70); // 28 net × 2,5 puan
    });

    test('puan sıfırın altına inmez', () {
      final exam = makeExam(
        key: List.filled(4, a),
        rules: const ScoringRules(wrongPenaltyDivisor: 3),
      );
      final r = engine.score(
        exam,
        StudentResponse(choiceMarks: marks([b, b, b, b])),
      );
      expect(r.net, lessThan(0));
      expect(r.total, 0);
    });
  });

  group('çift işaretleme', () {
    test('varsayılan olarak yanlış sayılır ve işaretlenir', () {
      final exam = makeExam();
      final r = engine.score(
        exam,
        const StudentResponse(
          choiceMarks: {
            1: {a, b},
          },
        ),
      );
      expect(r.wrong, 1);
      expect(r.questions.first.multiMarked, isTrue);
    });

    test('"boş say" kuralında boş sayılır', () {
      final exam = makeExam(
        rules: const ScoringRules(multiMarkPolicy: MultiMarkPolicy.blank),
      );
      final r = engine.score(
        exam,
        const StudentResponse(
          choiceMarks: {
            1: {a, b},
          },
        ),
      );
      expect(r.wrong, 0);
      expect(r.blank, 10);
    });
  });

  group('iptal edilen soru', () {
    Exam cancelledExam(CancelPolicy policy) {
      final base = makeExam(rules: ScoringRules(cancelPolicy: policy));
      return base.copyWith(
        choiceQuestions: [
          base.choiceQuestions.first.copyWith(cancelled: true),
          ...base.choiceQuestions.skip(1),
        ],
      );
    }

    test('herkese doğru sayılır', () {
      final exam = cancelledExam(CancelPolicy.countAsCorrect);
      final r = engine.score(exam, const StudentResponse());
      expect(r.correct, 1);
      expect(r.total, 10);
    });

    test('hesaptan çıkarılırsa puanı diğer sorulara dağıtılır', () {
      final exam = cancelledExam(CancelPolicy.exclude);
      final points = engine.questionPoints(exam);
      expect(points[1], 0);
      expect(points[2], closeTo(100 / 9, 1e-9));
      final r = engine.score(
        exam,
        StudentResponse(choiceMarks: marks([null, b, c, d, a, b, c, d, a, b])),
      );
      expect(r.total, 100);
    });
  });

  group('soru puanları', () {
    test('elle verilen puanlar korunur, kalan eşit dağıtılır', () {
      final base = makeExam(key: [a, a, a]);
      final exam = base.copyWith(
        choiceQuestions: [
          base.choiceQuestions[0].copyWith(points: () => 50),
          base.choiceQuestions[1],
          base.choiceQuestions[2],
        ],
      );
      final p = engine.questionPoints(exam);
      expect(p[1], 50);
      expect(p[2], 25);
      expect(p[3], 25);
    });

    test('açık uçlu puanlar çoktan seçmeli bütçesinden düşülür', () {
      final exam = makeExam(
        open: const [
          OpenQuestion(number: 1, maxPoints: 20),
          OpenQuestion(number: 2, maxPoints: 30),
        ],
      );
      expect(exam.choicePointsTotal, 50);
      final r = engine.score(
        exam,
        StudentResponse(
          choiceMarks: marks([a, b, c, d, a, b, c, d, a, b]),
          openScores: const {1: 15, 2: null},
        ),
      );
      expect(r.choiceScore, 50);
      expect(r.openScore, 15);
      expect(r.openPending, 1);
      expect(r.isFinal, isFalse);
      expect(r.total, 65);
    });

    test('açık uçlu puan sorunun tam puanını geçemez', () {
      final exam = makeExam(
        key: const [],
        open: const [OpenQuestion(number: 1, maxPoints: 10)],
      );
      final r = engine.score(exam, const StudentResponse(openScores: {1: 14}));
      expect(r.openScore, 10);
    });
  });

  group('yuvarlama', () {
    test('yarım puana yuvarlar', () {
      expect(ScoringEngine.roundTo(72.3, 0.5), 72.5);
      expect(ScoringEngine.roundTo(72.2, 0.5), 72);
      expect(ScoringEngine.roundTo(72.5, 1), 73);
      expect(ScoringEngine.roundTo(72.37, 0), 72.37);
    });
  });

  group('kitapçıklar', () {
    // B kitapçığı: soru sırası ters, 1. sorunun şıkları da karışık.
    final bookletB = Booklet(
      code: 'B',
      questionOrder: [for (var i = 10; i >= 1; i--) i],
      optionMaps: const {
        1: [d, c, b, a],
      },
    );
    final exam = makeExam(booklets: [Booklet.master(10), bookletB]);

    test('B kitapçığı cevapları ana kitapçığa çevrilerek puanlanır', () {
      // Ana anahtar: 1-A 2-B ... 10-B. B'de 1. soru ana 10. soru (B).
      // B'de 10. soru ana 1. soru; ana A şıkkı B'de D şıkkıdır.
      final answers = List<int?>.filled(10, null);
      answers[0] = b; // B'nin 1. sorusu = ana 10 → doğru cevap B
      answers[9] = d; // B'nin 10. sorusu = ana 1 → ana A = B'de D
      final r = engine.score(
        exam,
        StudentResponse(bookletCode: 'B', choiceMarks: marks(answers)),
      );
      expect(r.correct, 2);
      expect(r.bookletCode, 'B');
    });

    test('B kitapçığının anahtarı otomatik üretilir', () {
      final key = const AnswerKeyBuilder().keyFor(exam, bookletB);
      expect(key[1], 'B'); // ana 10
      expect(key[10], 'D'); // ana 1, A → D
      expect(key[2], 'A'); // ana 9
    });

    test('kodlanmamış kitapçık doğru tahmin edilir', () {
      // B kitapçığına göre tamamen doğru cevaplar.
      final key = const AnswerKeyBuilder().keyFor(exam, bookletB);
      final answers = <int, Set<int>>{
        for (final e in key.entries) e.key: {optionLetters.indexOf(e.value)},
      };
      final guess = engine.guessBooklet(exam, answers);
      expect(guess.code, 'B');
      expect(guess.confident, isTrue);
    });

    test('bilinmeyen kitapçık kodu ana kitapçığa düşer', () {
      final r = engine.score(
        exam,
        StudentResponse(
          bookletCode: 'Z',
          choiceMarks: marks([a, b, c, d, a, b, c, d, a, b]),
        ),
      );
      expect(r.bookletCode, 'A');
      expect(r.correct, 10);
    });
  });

  group('kitapçık üretici', () {
    const gen = BookletGenerator();

    test('aynı girdiyle hep aynı kitapçığı üretir', () {
      Booklet make() => gen.generate(
        examId: 'x',
        code: 'B',
        questionCount: 30,
        optionCount: 4,
        shuffleOptions: true,
      );
      expect(make().questionOrder, make().questionOrder);
      expect(make().optionMaps[5], make().optionMaps[5]);
    });

    test('üretilen kitapçık geçerli bir karıştırmadır', () {
      final booklet = gen.generate(
        examId: 'x',
        code: 'C',
        questionCount: 40,
        optionCount: 5,
        shuffleOptions: true,
      );
      expect(booklet.validate(optionCount: 5), isEmpty);
      expect(booklet.isIdentity, isFalse);
    });

    test('hatalı harita yakalanır', () {
      const broken = Booklet(
        code: 'B',
        questionOrder: [1, 1, 3],
        optionMaps: {
          2: [0, 0, 1, 2],
        },
      );
      expect(broken.validate(optionCount: 4), hasLength(2));
    });
  });

  group('JSON', () {
    test('sınav kaydedilip geri okunabilir', () {
      final exam = makeExam(
        open: const [
          OpenQuestion(
            number: 1,
            maxPoints: 10,
            rubric: [RubricCriterion(title: 'Tanım', weightPercent: 100)],
          ),
        ],
        rules: const ScoringRules(wrongPenaltyDivisor: 4),
        booklets: [
          Booklet.master(10),
          const BookletGenerator().generate(
            examId: 't',
            code: 'B',
            questionCount: 10,
            optionCount: 4,
            shuffleOptions: true,
          ),
        ],
      );
      final copy = Exam.fromJson(exam.toJson());
      expect(copy.toJson(), exam.toJson());
      expect(copy.openQuestions.first.rubricIsComplete, isTrue);
    });
  });
}
