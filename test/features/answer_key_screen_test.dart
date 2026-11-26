import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/models/exam.dart';
import 'package:okutio/data/exam_repository.dart';
import 'package:okutio/data/providers.dart';
import 'package:okutio/features/answer_key/answer_key_screen.dart';

void main() {
  late InMemoryExamRepository repo;
  late Exam exam;

  setUp(() async {
    repo = InMemoryExamRepository();
    // 10 soruluk, 4 şıklı, anahtarı boş bir sınav.
    exam = ExamDraft(openCount: 0).build(id: 'e1', now: DateTime(2026));
    await repo.save(exam);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [examRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: AnswerKeyScreen(examId: 'e1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Exam> stored() async =>
      (await repo.loadAll()).firstWhere((e) => e.id == 'e1');

  testWidgets('şıkka dokunmak cevabı kaydeder, tekrar dokunmak kaldırır', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('0 / 10 soru girildi'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('1. soru C şıkkı'));
    await tester.pumpAndSettle();
    expect((await stored()).choiceQuestions.first.correctOptions, {2});
    expect(find.text('1 / 10 soru girildi'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('1. soru C şıkkı'));
    await tester.pumpAndSettle();
    expect((await stored()).choiceQuestions.first.correctOptions, isEmpty);
  });

  testWidgets('yazarak giriş anahtarı doldurur', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Cevapları yazarak gir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ABCDA BCDAB');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();

    final saved = await stored();
    expect(saved.answerKeyComplete, isTrue);
    expect(saved.choiceQuestions[4].correctOptions, {0});
    expect(find.text('Tüm sorular tamam'), findsOneWidget);
    expect(find.text('Bitti'), findsOneWidget);
  });

  testWidgets('soru iptal edilebilir ve çoklu doğru seçilebilir', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byTooltip('2. soru seçenekleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soruyu iptal et'));
    await tester.pumpAndSettle();
    expect((await stored()).choiceQuestions[1].cancelled, isTrue);
    expect(find.text('İptal edildi'), findsOneWidget);

    await tester.tap(find.byTooltip('3. soru seçenekleri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Birden fazla doğru cevap var'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('3. soru A şıkkı'));
    await tester.tap(find.bySemanticsLabel('3. soru D şıkkı'));
    await tester.pumpAndSettle();
    expect((await stored()).choiceQuestions[2].correctOptions, {0, 3});
  });
}
