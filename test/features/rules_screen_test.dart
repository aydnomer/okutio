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
