import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/exam_factory.dart';
import '../../core/models/exam.dart';
import '../../data/providers.dart';
import '../../core/util/format.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/number_stepper.dart';
import '../../shared/widgets/option_card.dart';
import '../../shared/widgets/scoring_rules_editor.dart';

/// Adım adım sınav oluşturma. Her ekranda tek bir soru sorulur.
class ExamWizardScreen extends ConsumerStatefulWidget {
  const ExamWizardScreen({super.key});

  @override
  ConsumerState<ExamWizardScreen> createState() => _ExamWizardScreenState();
}

enum _Step { template, info, choice, open, booklets, rules, summary }

class _ExamWizardScreenState extends ConsumerState<ExamWizardScreen> {
  final _draft = ExamDraft();
  var _index = 0;
  var _saving = false;

  final _title = TextEditingController();
  final _subject = TextEditingController();
  final _classGroup = TextEditingController();

  /// Sınavda çoktan seçmeli soru yoksa kitapçık ve kural adımları atlanır.
  List<_Step> get _steps => [
    _Step.template,
    _Step.info,
    _Step.choice,
    _Step.open,
    if (_draft.choiceCount > 0) _Step.booklets,
    if (_draft.choiceCount > 0) _Step.rules,
    _Step.summary,
  ];

  _Step get _step => _steps[_index];
  bool get _isLast => _index == _steps.length - 1;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _classGroup.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) => setState(change);

  String? get _blocker => switch (_step) {
    _Step.open || _Step.summary => _draft.pointsProblem,
    _ => null,
  };

  Future<void> _next() async {
    if (_blocker != null) return;
    if (!_isLast) {
      setState(() => _index++);
      return;
    }
    setState(() => _saving = true);
    _draft
      ..title = _title.text
      ..subject = _subject.text
      ..classGroup = _classGroup.text;
    final exam = _draft.build();
    await ref.read(examListProvider.notifier).save(exam);
    if (!mounted) return;
    context.pushReplacement('/sinav/${exam.id}');
  }

  void _back() {
    if (_index == 0) {
      context.pop();
    } else {
      setState(() => _index--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Yeni sınav'),
          leading: IconButton(
            tooltip: 'Kapat',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => context.pop(),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: PageFrame(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Adım ${_index + 1} / ${steps.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_index + 1) / steps.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          child: PageFrame(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: switch (_step) {
              _Step.template => _templateStep(),
              _Step.info => _infoStep(),
              _Step.choice => _choiceStep(),
              _Step.open => _openStep(),
              _Step.booklets => _bookletStep(),
              _Step.rules => _rulesStep(),
              _Step.summary => _summaryStep(),
            },
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: PageFrame(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                if (_index > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _back,
                      child: const Text('Geri'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving || _blocker != null ? null : _next,
                    child: Text(_isLast ? 'Sınavı oluştur' : 'Devam'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Adımlar ----

  Widget _templateStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const StepHeader(
        title: 'Nasıl bir sınav?',
        help: 'Size en yakın olanı seçin. Ayarları sonraki adımlarda değiştirebilirsiniz.',
      ),
      for (final t in ExamTemplate.values) ...[
        OptionCard(
          title: t.title,
          subtitle: t.description,
          icon: switch (t) {
            ExamTemplate.schoolWritten => Icons.edit_document,
            ExamTemplate.lgsPractice => Icons.school_rounded,
            ExamTemplate.tytPractice => Icons.workspace_premium_rounded,
            ExamTemplate.quiz => Icons.bolt_rounded,
          },
          selected: _draft.template == t,
          onTap: () => _update(() => _draft.applyTemplate(t)),
        ),
        const SizedBox(height: 10),
      ],
    ],
  );

  Widget _infoStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const StepHeader(
        title: 'Sınavın adı ne olsun?',
        help: 'Bu bilgiler formun üstüne yazılır. Boş bırakabilirsiniz.',
      ),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'Sınav adı',
          hintText: 'Ör. ${_draft.template.title} - 1. dönem',
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _subject,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Ders',
          hintText: 'Ör. Matematik',
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _classGroup,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Sınıf / şube',
          hintText: 'Ör. 9-A',
        ),
      ),
    ],
  );

  Widget _choiceStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const StepHeader(
        title: 'Kaç tane test (çoktan seçmeli) soru var?',
        help: 'Test sorusu yoksa 0 seçin.',
      ),
      NumberStepper(
        value: _draft.choiceCount,
        max: 120,
        quickPicks: const [0, 10, 20, 25, 40],
        onChanged: (v) => _update(() => _draft.choiceCount = v),
      ),
      if (_draft.choiceCount > 0) ...[
        const SizedBox(height: 32),
        Text(
          'Her soruda kaç şık var?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 4, label: Text('4 şık (A-D)')),
            ButtonSegment(value: 5, label: Text('5 şık (A-E)')),
          ],
          selected: {_draft.optionCount},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(minimumSize: const Size(0, 52)),
          onSelectionChanged: (s) =>
              _update(() => _draft.optionCount = s.first),
        ),
      ],
    ],
  );

  Widget _openStep() {
    final problem = _draft.pointsProblem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeader(
          title: 'Kaç tane açık uçlu soru var?',
          help: 'Öğrencinin cevabı yazarak verdiği sorular. Yoksa 0 seçin.',
        ),
        NumberStepper(
          value: _draft.openCount,
          max: 30,
          quickPicks: const [0, 2, 4, 5, 10],
          onChanged: (v) => _update(() => _draft.openCount = v),
        ),
        if (_draft.openCount > 0) ...[
          const SizedBox(height: 32),
          Text(
            'Her açık uçlu soru kaç puan?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('Soruların puanlarını sonra tek tek değiştirebilirsiniz.'),
          const SizedBox(height: 12),
          NumberStepper(
            value: _draft.openPointsEach.round(),
            min: 1,
            max: 100,
            unit: 'puan',
            quickPicks: const [5, 10, 15, 20, 25],
            onChanged: (v) =>
                _update(() => _draft.openPointsEach = v.toDouble()),
          ),
        ],
        const SizedBox(height: 24),
        if (problem != null)
          InfoBox(text: problem, warning: true)
        else
          InfoBox(text: _pointsSummary()),
      ],
    );
  }

  String _pointsSummary() {
    final parts = <String>[];
    if (_draft.choiceCount > 0) {
      parts.add(
        'Test soruları ${_draft.choiceCount} × ${fmtNum(_draft.choicePointsEach)} puan',
      );
    }
    if (_draft.openCount > 0) {
      parts.add(
        'açık uçlu sorular ${_draft.openCount} × ${fmtNum(_draft.openPointsEach)} puan',
      );
    }
    return '${parts.join(', ')}. Toplam ${fmtNum(_draft.rules.totalPoints)} puan.';
  }

  Widget _bookletStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const StepHeader(
        title: 'Kaç farklı kitapçık olacak?',
        help:
            'Kopyayı önlemek için soruların sırası kitapçıklarda farklı olur. '
            'Siz yalnızca A kitapçığının cevap anahtarını girersiniz; '
            'diğerlerini uygulama hazırlar.',
      ),
      for (final (count, title, sub) in const [
        (1, 'Tek kitapçık', 'Herkes aynı sırayla çözer.'),
        (2, 'A ve B', 'Yan yana oturanlar farklı kitapçık alır.'),
        (4, 'A, B, C ve D', 'Kalabalık salonlar için.'),
      ]) ...[
        OptionCard(
          title: title,
          subtitle: sub,
          selected: _draft.bookletCount == count,
          onTap: () => _update(() => _draft.bookletCount = count),
        ),
        const SizedBox(height: 10),
      ],
      if (_draft.bookletCount > 1) ...[
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _draft.shuffleOptions,
          onChanged: (v) => _update(() => _draft.shuffleOptions = v),
          title: const Text('Şıkların yerini de karıştır'),
          subtitle: const Text(
            'Daha güvenli, ama soru kâğıtlarını her kitapçık için ayrı hazırlamanız gerekir.',
          ),
        ),
      ],
    ],
  );

  Widget _rulesStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const StepHeader(
        title: 'Puanlama kuralları',
        help:
            'Seçtiğiniz sınav türüne göre dolduruldu. Sınavdan sonra da '
            'değiştirebilirsiniz; puanlar kendiliğinden yeniden hesaplanır.',
      ),
      ScoringRulesEditor(
        rules: _draft.rules,
        onChanged: (r) => _update(() => _draft.rules = r),
      ),
    ],
  );

  Widget _summaryStep() {
    final d = _draft;
    final problem = d.pointsProblem;
    final rows = <(String, String)>[
      ('Sınav türü', d.template.title),
      if (_title.text.trim().isNotEmpty) ('Ad', _title.text.trim()),
      if (_subject.text.trim().isNotEmpty) ('Ders', _subject.text.trim()),
      if (_classGroup.text.trim().isNotEmpty)
        ('Sınıf / şube', _classGroup.text.trim()),
      if (d.choiceCount > 0)
        (
          'Test soruları',
          '${d.choiceCount} soru, ${d.optionCount} şık, '
              'her biri ${fmtNum(d.choicePointsEach)} puan',
        ),
      if (d.openCount > 0)
        (
          'Açık uçlu sorular',
          '${d.openCount} soru, her biri ${fmtNum(d.openPointsEach)} puan',
        ),
      if (d.choiceCount > 0)
        (
          'Kitapçık',
          d.bookletCount == 1
              ? 'Tek kitapçık'
              : '${d.bookletCount} kitapçık'
                    '${d.shuffleOptions ? ', şıklar da karışık' : ''}',
        ),
      if (d.choiceCount > 0) ('Yanlışlar', d.rules.penaltyLabel),
      ('Tam puan', fmtNum(d.rules.totalPoints)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeader(
          title: 'Her şey doğru mu?',
          help: 'Sınavı oluşturduktan sonra cevap anahtarını girip formu yazdıracaksınız.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final (k, v) in rows)
                  ListTile(
                    title: Text(
                      k,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      v,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (problem != null) ...[
          const SizedBox(height: 16),
          InfoBox(text: problem, warning: true),
        ],
      ],
    );
  }
}
