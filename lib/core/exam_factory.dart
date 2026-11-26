import 'package:uuid/uuid.dart';

import 'util/format.dart';

import 'models/booklet.dart';
import 'models/exam.dart';
import 'models/question.dart';
import 'models/scoring_rules.dart';
import 'scoring/booklet_generator.dart';

/// Sihirbazda toplanan bilgilerden yeni bir sınav oluşturur.
class ExamDraft {
  ExamDraft({
    this.template = ExamTemplate.schoolWritten,
    this.title = '',
    this.subject = '',
    this.classGroup = '',
    int? choiceCount,
    int? openCount,
    int? optionCount,
    this.bookletCount = 1,
    this.shuffleOptions = false,
    double? openPointsEach,
    ScoringRules? rules,
  }) : choiceCount = choiceCount ?? template.defaultChoiceCount,
       openCount = openCount ?? template.defaultOpenCount,
       optionCount = optionCount ?? template.defaultOptionCount,
       openPointsEach = openPointsEach ?? 10,
       rules = rules ?? template.defaultRules;

  ExamTemplate template;
  String title;
  String subject;
  String classGroup;
  int choiceCount;
  int openCount;
  int optionCount;
  int bookletCount;
  bool shuffleOptions;
  double openPointsEach;
  ScoringRules rules;

  /// Şablon değişince ona bağlı varsayılanları da günceller.
  void applyTemplate(ExamTemplate t) {
    template = t;
    choiceCount = t.defaultChoiceCount;
    openCount = t.defaultOpenCount;
    optionCount = t.defaultOptionCount;
    rules = t.defaultRules;
    bookletCount = 1;
  }

  double get openTotal => openCount * openPointsEach;

  /// Açık uçlu puanlar toplam puanı aşıyorsa uyarı metni, yoksa `null`.
  String? get pointsProblem {
    if (openTotal > rules.totalPoints) {
      return 'Açık uçlu soruların toplamı (${fmtNum(openTotal)}) '
          'sınavın tam puanını (${fmtNum(rules.totalPoints)}) aşıyor.';
    }
    if (choiceCount == 0 && openCount == 0) {
      return 'Sınavda en az bir soru olmalı.';
    }
    if (choiceCount == 0 && openTotal != rules.totalPoints) {
      return 'Açık uçlu soruların toplamı ${fmtNum(openTotal)}; '
          '${fmtNum(rules.totalPoints)} olmalı.';
    }
    return null;
  }

  double get choicePointsEach => choiceCount == 0
      ? 0
      : (rules.totalPoints - openTotal).clamp(0, rules.totalPoints) /
            choiceCount;

  Exam build({String? id, DateTime? now}) {
    final examId = id ?? const Uuid().v4();
    var exam = Exam(
      id: examId,
      title: title.trim().isEmpty ? template.title : title.trim(),
      subject: subject.trim(),
      classGroup: classGroup.trim(),
      createdAt: now ?? DateTime.now(),
      template: template,
      optionCount: optionCount,
      choiceQuestions: [
        for (var i = 1; i <= choiceCount; i++) ChoiceQuestion(number: i),
      ],
      openQuestions: [
        for (var i = 1; i <= openCount; i++)
          OpenQuestion(number: i, maxPoints: openPointsEach),
      ],
      rules: rules,
    );
    exam = exam.copyWith(
      booklets: bookletCount <= 1
          ? [Booklet.master(choiceCount)]
          : const BookletGenerator().generateAll(
              exam,
              count: bookletCount,
              shuffleOptions: shuffleOptions,
            ),
    );
    return exam;
  }
}

/// Öğretmenin hiçbir şey girmeden uygulamayı deneyebilmesi için hazır örnek sınav.
Exam buildSampleExam({DateTime? now}) {
  final draft = ExamDraft(
    title: 'Örnek sınav: Fen Bilimleri 1. yazılı',
    subject: 'Fen Bilimleri',
    classGroup: '7-A',
    choiceCount: 10,
    openCount: 2,
    openPointsEach: 25,
    bookletCount: 2,
  );
  final exam = draft.build(now: now);
  const key = [0, 2, 1, 3, 0, 1, 2, 3, 1, 0];
  return exam.copyWith(
    choiceQuestions: [
      for (final q in exam.choiceQuestions)
        q.copyWith(correctOptions: {key[q.number - 1]}),
    ],
    openQuestions: [
      exam.openQuestions[0].copyWith(
        prompt: 'Fotosentezi tanımlayınız.',
        referenceAnswer:
            'Bitkilerin ışık enerjisini kullanarak karbondioksit ve sudan '
            'besin (glikoz) ve oksijen üretmesidir.',
        rubric: const [
          RubricCriterion(
            title: 'Işık enerjisinin kullanıldığı',
            weightPercent: 40,
          ),
          RubricCriterion(
            title: 'Girdiler: karbondioksit ve su',
            weightPercent: 30,
          ),
          RubricCriterion(
            title: 'Çıktılar: besin ve oksijen',
            weightPercent: 30,
          ),
        ],
      ),
      exam.openQuestions[1].copyWith(
        prompt: 'Maddenin hâl değişimlerinden iki örnek veriniz.',
        referenceAnswer: 'Erime (buzun suya dönüşmesi), buharlaşma (suyun buhara dönüşmesi).',
        rubric: const [
          RubricCriterion(title: 'Birinci doğru örnek', weightPercent: 50),
          RubricCriterion(title: 'İkinci doğru örnek', weightPercent: 50),
        ],
      ),
    ],
  );
}
