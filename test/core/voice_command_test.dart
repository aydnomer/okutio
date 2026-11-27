import 'package:flutter_test/flutter_test.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/models/scoring_rules.dart';
import 'package:okutio/core/voice/voice_command.dart';

void main() {
  final exam = ExamDraft(
    choiceCount: 20,
    openCount: 0,
  ).build(id: 'e', now: DateTime(2026));
  const v = VoiceCommands();

  test('rakamla soru iptali, varsayılan kural', () {
    final r = v.apply(exam, '5. soruyu iptal et');
    expect(r.exam.choiceQuestions[4].cancelled, isTrue);
    expect(r.done.single, '5. soru iptal edildi: herkese doğru say.');
    expect(r.notUnderstood, isEmpty);
  });

  test('sözle söylenen sıra sayısı ve iptal kuralı', () {
    final r = v.apply(exam, 'On ikinci soruyu iptal et hesaptan çıkar');
    expect(r.exam.choiceQuestions[11].cancelled, isTrue);
    expect(r.exam.rules.cancelPolicy, CancelPolicy.exclude);
  });

  test('bir cümlede birden fazla komut', () {
    final r = v.apply(
      exam,
      'Üçüncü soruyu iptal et, çift işaretleri boş say ve '
      '4 yanlış 1 doğruyu götürsün',
    );
    expect(r.exam.choiceQuestions[2].cancelled, isTrue);
    expect(r.exam.rules.multiMarkPolicy, MultiMarkPolicy.blank);
    expect(r.exam.rules.wrongPenaltyDivisor, 4);
    expect(r.done, hasLength(3));
  });

  test('iptali kaldırma', () {
    final cancelled = v.apply(exam, '7. soruyu iptal et').exam;
    final r = v.apply(cancelled, '7. sorunun iptalini kaldır');
    expect(r.exam.choiceQuestions[6].cancelled, isFalse);
  });

  test('yanlış götürmeyi kapatma ve yuvarlama', () {
    final pen = v.apply(exam, '3 yanlış 1 doğruyu götürsün').exam;
    expect(pen.rules.wrongPenaltyDivisor, 3);
    final r = v.apply(pen, 'yanlışlar doğruyu götürmesin. yarım puana yuvarla');
    expect(r.exam.rules.wrongPenaltyDivisor, isNull);
    expect(r.exam.rules.roundingStep, 0.5);
  });

  test('cevap anahtarı değiştirme', () {
    final r = v.apply(exam, '3. sorunun cevabı C');
    expect(r.exam.choiceQuestions[2].correctOptions, {2});
    expect(r.done.single, '3. sorunun cevabı C yapıldı.');
    final r2 = v.apply(exam, 'yirmi birinci sorunun cevabı A');
    expect(r2.changed, isFalse, reason: '21. soru yok');
  });

  test('anlaşılmayan cümle değişiklik yapmaz', () {
    final r = v.apply(exam, 'bugün hava çok güzel');
    expect(r.changed, isFalse);
    expect(r.notUnderstood, isNotEmpty);
    expect(identical(r.exam, exam), isTrue);
  });

  test('"numaralı soru" ifadesi', () {
    expect(
      v
          .apply(exam, 'beş numaralı soruyu iptal et')
          .exam
          .choiceQuestions[4]
          .cancelled,
      isTrue,
    );
    expect(
      v
          .apply(exam, '8 numaralı soruyu iptal et')
          .exam
          .choiceQuestions[7]
          .cancelled,
      isTrue,
    );
  });
}
