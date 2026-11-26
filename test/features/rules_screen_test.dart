import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:okutio/core/exam_factory.dart';
import 'package:okutio/core/models/scoring_rules.dart';
import 'package:okutio/data/exam_repository.dart';
import 'package:okutio/data/providers.dart';
import 'package:okutio/data/sheet_repository.dart';
import 'package:okutio/features/rules/rules_screen.dart';

void main() {
  Future<InMemoryExamRepository> pump(WidgetTester tester) async {
    final repo = InMemoryExamRepository();
    await repo.save(
      ExamDraft(openCount: 0).build(id: 'e1', now: DateTime(2026)),
    );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          examRepositoryProvider.overrideWithValue(repo),
          sheetRepositoryProvider.overrideWithValue(InMemorySheetRepository()),
        ],
        child: const MaterialApp(home: RulesScreen(examId: 'e1')),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('mikrofon yoksa komut yazılarak da uygulanır', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byTooltip('Sesli komut'));
    await tester.pumpAndSettle();
    expect(find.text('Sesli komut'), findsOne);

    await tester.enterText(
      find.widgetWithText(TextField, 'Komut'),
      '5. soruyu iptal et ve çift işaretleri boş say',
    );
    await tester.pumpAndSettle();
    expect(find.text('5. soru iptal edildi: herkese doğru say.'), findsOne);
    expect(find.text('Çift işaretli sorular boş sayılacak.'), findsOne);

    await tester.tap(find.text('2 değişikliği uygula'));
    await tester.pumpAndSettle();
    final stored = (await repo.loadAll()).single;
    expect(stored.choiceQuestions[4].cancelled, isTrue);
    expect(stored.rules.multiMarkPolicy, MultiMarkPolicy.blank);
    expect(find.text('Geri al'), findsOne);
  });

  testWidgets('soru iptal edilir ve kural sonradan değiştirilir', (
    tester,
  ) async {
    final repo = InMemoryExamRepository();
    await repo.save(
      ExamDraft(openCount: 0).build(id: 'e1', now: DateTime(2026)),
    );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          examRepositoryProvider.overrideWithValue(repo),
          sheetRepositoryProvider.overrideWithValue(InMemorySheetRepository()),
        ],
        child: const MaterialApp(home: RulesScreen(examId: 'e1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('İptal edilen soru yok.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '3'));
    await tester.pumpAndSettle();
    var stored = (await repo.loadAll()).single;
    expect(stored.choiceQuestions[2].cancelled, isTrue);
    expect(find.textContaining('1 soru iptal: herkese doğru say'), findsOne);

    await tester.tap(find.text('Hesaptan çıkar'));
    await tester.pumpAndSettle();
    stored = (await repo.loadAll()).single;
    expect(stored.rules.cancelPolicy, CancelPolicy.exclude);

    await tester.tap(find.text('Boş say'));
    await tester.pumpAndSettle();
    stored = (await repo.loadAll()).single;
    expect(stored.rules.multiMarkPolicy, MultiMarkPolicy.blank);
  });
}
