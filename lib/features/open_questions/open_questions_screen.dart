import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/exam.dart';
import '../../core/models/question.dart';
import '../../core/scoring/scoring_engine.dart';
import '../../core/util/format.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/exam_not_found.dart';
import '../../shared/widgets/number_stepper.dart';
import '../../shared/widgets/option_card.dart';

/// Hazır puanlama ölçütleri: öğretmen boş sayfayla başlamasın.
const rubricPresets = <String, List<RubricCriterion>>{
  'Problem çözme': [
    RubricCriterion(title: 'Doğru yöntem / işlem', weightPercent: 50),
    RubricCriterion(title: 'Doğru sonuç', weightPercent: 30),
    RubricCriterion(title: 'Birim ve gösterim', weightPercent: 20),
  ],
  'Açıklama / yorum': [
    RubricCriterion(title: 'Kavramı doğru açıklama', weightPercent: 50),
    RubricCriterion(title: 'Örnek ya da gerekçe', weightPercent: 30),
    RubricCriterion(title: 'Açık ve düzenli anlatım', weightPercent: 20),
  ],
  'İki örnek isteyen soru': [
    RubricCriterion(title: 'Birinci doğru örnek', weightPercent: 50),
    RubricCriterion(title: 'İkinci doğru örnek', weightPercent: 50),
  ],
  'Kısa cevap': [RubricCriterion(title: 'Doğru cevap', weightPercent: 100)],
};

/// Açık uçlu soruların puanı, beklenen cevabı ve puanlama ölçütleri.
class OpenQuestionsScreen extends ConsumerWidget {
  const OpenQuestionsScreen({required this.examId, super.key});

  final String examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examByIdProvider(examId));
    return exam.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const ExamNotFound(),
      data: (e) => e == null ? const ExamNotFound() : _Editor(initial: e),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.initial});

  final Exam initial;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late Exam _exam = widget.initial;
  Future<void> _saving = Future.value();
  Timer? _debounce;

  @override
  void dispose() {
    // Ekrandan çıkarken bekleyen yazıyı kaybetme.
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _persist();
    }
    super.dispose();
  }

  void _persist() {
    final snapshot = _exam;
    final notifier = ref.read(examListProvider.notifier);
    _saving = _saving.then((_) => notifier.save(snapshot));
  }

  void _replace(OpenQuestion q, {bool typing = false}) {
    setState(() {
      _exam = _exam.copyWith(
        openQuestions: [
          for (final old in _exam.openQuestions)
            old.number == q.number ? q : old,
        ],
      );
    });
    _debounce?.cancel();
    if (typing) {
      _debounce = Timer(const Duration(milliseconds: 500), _persist);
    } else {
      _persist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = _exam.openPointsTotal;
    final total = _exam.rules.totalPoints;
    final choiceBudget = total - open;
    final points = const ScoringEngine().questionPoints(_exam);
    final choiceEach = points.isEmpty ? 0.0 : points.values.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Açık uçlu sorular')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          PageFrame(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Her soru için puanı ve neye puan vereceğinizi belirleyin. '
                  'Kâğıtları okurken bu ölçütler size yardımcı olur; '
                  'son puanı her zaman siz onaylarsınız.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (choiceBudget < 0)
                  InfoBox(
                    warning: true,
                    text:
                        'Açık uçlu soruların toplamı ${fmtNum(open)} puan; '
                        'sınavın tam puanı olan ${fmtNum(total)} puanı aşıyor.',
                  )
                else
                  InfoBox(
                    text: _exam.choiceCount == 0
                        ? 'Açık uçlu sorular toplam ${fmtNum(open)} puan.'
                        : 'Açık uçlu: ${fmtNum(open)} puan. Kalan '
                              '${fmtNum(choiceBudget)} puan ${_exam.choiceCount} test '
                              'sorusuna dağıtılır (her biri ${fmtNum(choiceEach)} puan).',
                    warning: _exam.choiceCount == 0 && open != total,
                  ),
              ],
            ),
          ),
          for (final q in _exam.openQuestions)
            PageFrame(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _QuestionCard(
                key: ValueKey(q.number),
                question: q,
                onChanged: _replace,
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: PageFrame(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go('/sinav/${_exam.id}'),
            child: const Text('Bitti'),
          ),
        ),
      ),
    );
  }
}

typedef _OnChanged = void Function(OpenQuestion q, {bool typing});

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    required this.question,
    required this.onChanged,
    super.key,
  });

  final OpenQuestion question;
  final _OnChanged onChanged;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  late final _prompt = TextEditingController(text: widget.question.prompt);
  late final _reference = TextEditingController(
    text: widget.question.referenceAnswer,
  );

  /// Ölçüt satırlarının kimlikleri; satır silinince doğru yazı kutusu silinsin.
  late List<int> _rowIds = [
    for (var i = 0; i < widget.question.rubric.length; i++) i,
  ];
  late int _nextId = _rowIds.length;

  OpenQuestion get q => widget.question;

  @override
  void dispose() {
    _prompt.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _setRubric(List<RubricCriterion> rubric, List<int> ids) {
    setState(() => _rowIds = ids);
    widget.onChanged(q.copyWith(rubric: rubric));
  }

  void _addCriterion() {
    final remaining = (100 - q.rubricTotal).clamp(0, 100).toDouble();
    _setRubric(
      [...q.rubric, RubricCriterion(title: '', weightPercent: remaining)],
      [..._rowIds, _nextId++],
    );
  }

  void _usePreset(List<RubricCriterion> preset) {
    _setRubric(preset, [for (final _ in preset) _nextId++]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasRubric = q.rubric.isNotEmpty;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${q.number}. açık uçlu soru',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (hasRubric)
                  Icon(
                    q.rubricIsComplete
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: q.rubricIsComplete ? scheme.primary : scheme.error,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Puanı', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            NumberStepper(
              value: q.maxPoints.round(),
              min: 1,
              max: 100,
              unit: 'puan',
              quickPicks: const [5, 10, 15, 20, 25],
              onChanged: (v) =>
                  widget.onChanged(q.copyWith(maxPoints: v.toDouble())),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _prompt,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Soru metni (isteğe bağlı)',
                helperText:
                    'Yazarsanız formda cevap kutusunun üstünde görünür.',
              ),
              onChanged: (v) =>
                  widget.onChanged(q.copyWith(prompt: v), typing: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reference,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Beklenen cevap (isteğe bağlı)',
                helperText: 'Kâğıt okurken size hatırlatılır, öğrenci görmez.',
              ),
              onChanged: (v) => widget.onChanged(
                q.copyWith(referenceAnswer: v),
                typing: true,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Puanlama ölçütleri',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Hazır ölçüt seç',
                  onSelected: (k) => _usePreset(rubricPresets[k]!),
                  itemBuilder: (_) => [
                    for (final name in rubricPresets.keys)
                      PopupMenuItem(value: name, child: Text(name)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Hazır ölçüt',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Text(
              hasRubric
                  ? 'Her ölçüt sorunun puanının bir yüzdesidir. Kısmi puan verirken bunlara bakarsınız.'
                  : 'İsteğe bağlı. Kısmi puanı adil ve tutarlı vermek için önerilir.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < q.rubric.length; i++)
              _CriterionRow(
                key: ValueKey(_rowIds[i]),
                criterion: q.rubric[i],
                maxPoints: q.maxPoints,
                onChanged: (c, {typing = false}) {
                  final list = [...q.rubric]..[i] = c;
                  widget.onChanged(q.copyWith(rubric: list), typing: typing);
                },
                onDelete: () => _setRubric(
                  [...q.rubric]..removeAt(i),
                  [..._rowIds]..removeAt(i),
                ),
              ),
            if (hasRubric) ...[
              const SizedBox(height: 4),
              _RubricTotal(total: q.rubricTotal),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addCriterion,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Ölçüt ekle'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Formdaki cevap alanı', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            NumberStepper(
              value: q.answerLines,
              min: 2,
              max: 20,
              unit: 'satır',
              quickPicks: const [3, 5, 8, 12],
              onChanged: (v) => widget.onChanged(q.copyWith(answerLines: v)),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _OnCriterion = void Function(RubricCriterion c, {bool typing});

class _CriterionRow extends StatefulWidget {
  const _CriterionRow({
    required this.criterion,
    required this.maxPoints,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });

  final RubricCriterion criterion;
  final double maxPoints;
  final _OnCriterion onChanged;
  final VoidCallback onDelete;

  @override
  State<_CriterionRow> createState() => _CriterionRowState();
}

class _CriterionRowState extends State<_CriterionRow> {
  late final _title = TextEditingController(text: widget.criterion.title);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _setPercent(double p) => widget.onChanged(
    RubricCriterion(title: widget.criterion.title, weightPercent: p),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.criterion;
    final pts = widget.maxPoints * c.weightPercent / 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    hintText: 'Ölçüt, ör. "Doğru sonuç"',
                  ),
                  onChanged: (v) => widget.onChanged(
                    RubricCriterion(title: v, weightPercent: c.weightPercent),
                    typing: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Ölçütü sil',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Yüzdeyi azalt',
                icon: const Icon(Icons.remove_rounded),
                onPressed: c.weightPercent >= 5
                    ? () => _setPercent(c.weightPercent - 5)
                    : null,
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '%${fmtNum(c.weightPercent)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Yüzdeyi artır',
                icon: const Icon(Icons.add_rounded),
                onPressed: c.weightPercent <= 95
                    ? () => _setPercent(c.weightPercent + 5)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '= ${fmtNum(pts)} puan',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RubricTotal extends StatelessWidget {
  const _RubricTotal({required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    final ok = (total - 100).abs() < 0.01;
    if (ok) {
      return Text(
        'Toplam %100',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return InfoBox(
      warning: true,
      text: total < 100
          ? 'Ölçütlerin toplamı %${fmtNum(total)}. %${fmtNum(100 - total)} eksik.'
          : 'Ölçütlerin toplamı %${fmtNum(total)}. %${fmtNum(total - 100)} fazla.',
    );
  }
}
