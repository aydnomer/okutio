import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/models/exam.dart';
import 'package:okutio/data/exam_repository.dart';
import 'package:okutio/data/providers.dart';
import 'package:okutio/features/open_questions/open_questions_screen.dart';

void main() {
  late InMemoryExamRepository repo;

  setUp(() async {
    repo = InMemoryExamRepository();
    // 10 test + 2 açık uçlu × 10 puan.
    await repo.save(
      ExamDraft(
        choiceCount: 10,
        openCount: 2,
      ).build(id: 'e1', now: DateTime(2026)),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [examRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: OpenQuestionsScreen(examId: 'e1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Exam> stored() async =>
      (await repo.loadAll()).firstWhere((e) => e.id == 'e1');

  testWidgets('puan değişince test sorularının puanı yeniden dağıtılır', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining('her biri 8 puan'), findsOneWidget);

    // İlk sorunun puanını 20 yap.
    await tester.tap(find.text('20').first);
    await tester.pumpAndSettle();

    expect((await stored()).openQuestions.first.maxPoints, 20);
    expect(find.textContaining('her biri 7 puan'), findsOneWidget);
  });

  testWidgets('hazır ölçüt seçilir, eksik yüzde uyarılır', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Hazır ölçüt seç').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Problem çözme'));
    await tester.pumpAndSettle();

    var q = (await stored()).openQuestions.first;
    expect(q.rubric, hasLength(3));
    expect(q.rubricIsComplete, isTrue);
    expect(find.text('Toplam %100'), findsOneWidget);

    await tester.tap(find.byTooltip('Ölçütü sil').first);
    await tester.pumpAndSettle();
    q = (await stored()).openQuestions.first;
    expect(q.rubric, hasLength(2));
    expect(find.textContaining('%50 eksik'), findsOneWidget);

    await tester.tap(find.text('Ölçüt ekle').first);
    await tester.pumpAndSettle();
    q = (await stored()).openQuestions.first;
    expect(q.rubric.last.weightPercent, 50);
    expect(q.rubricIsComplete, isTrue);
  });

  testWidgets('yazılan beklenen cevap kaydedilir', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Beklenen cevap (isteğe bağlı)').first,
      'Fotosentez',
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect((await stored()).openQuestions.first.referenceAnswer, 'Fotosentez');
  });
}
