import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/exam.dart';
import '../../core/scoring/answer_key.dart';
import '../../core/scoring/scoring_engine.dart';
import '../../core/util/format.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/exam_not_found.dart';

/// Bir sınavın özeti ve öğretmenin sıradaki adımları.
class ExamDetailScreen extends ConsumerWidget {
  const ExamDetailScreen({required this.examId, super.key});

  final String examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examByIdProvider(examId));
    return exam.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const ExamNotFound(),
      data: (e) => e == null ? const ExamNotFound() : _Body(exam: e),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.exam});

  final Exam exam;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(examListProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final copy = exam;
    await notifier.delete(exam.id);
    if (context.mounted) context.go('/');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"${copy.title}" silindi.'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () => notifier.save(copy),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final details = [
      if (exam.subject.isNotEmpty) exam.subject,
      if (exam.classGroup.isNotEmpty) exam.classGroup,
      if (exam.title != exam.template.title) exam.template.title,
    ].join(' · ');
    final keyDone = exam.answerKeyComplete;
    final openDone =
        exam.openQuestions.isNotEmpty &&
        exam.openQuestions.every((q) => q.rubricIsComplete);
    final steps = <_Step>[
      if (exam.choiceCount > 0)
        _Step(
          title: 'Cevap anahtarını girin',
          subtitle: keyDone
              ? 'Tamamlandı. Değiştirmek için dokunun.'
              : '${exam.missingAnswerCount} sorunun cevabı eksik.',
          done: keyDone,
          onTap: () => context.push('/sinav/${exam.id}/anahtar'),
        ),
      if (exam.openCount > 0)
        _Step(
          title: 'Açık uçlu soruları hazırlayın',
          subtitle: openDone
              ? 'Puanlar ve ölçütler hazır.'
              : 'Puan, beklenen cevap ve ölçütler (isteğe bağlı).',
          done: openDone,
          onTap: () => context.push('/sinav/${exam.id}/acik'),
        ),
      _Step(
        title: 'Optik formu yazdırın',
        subtitle: 'Her öğrenci için QR kodlu form hazırlanır.',
        enabled: keyDone,
        disabledHint: 'Önce cevap anahtarını tamamlayın.',
        onTap: () => context.push('/sinav/${exam.id}/form'),
      ),
      _Step(
        title: 'Kâğıtları tarayın',
        subtitle: 'Sınavdan sonra kâğıtları okutup puanları görün.',
        enabled: false,
        disabledHint: 'Tarama bir sonraki sürümde geliyor.',
        onTap: () {},
      ),
    ];
    final points = const ScoringEngine().questionPoints(exam);
    final choiceEach = points.isEmpty ? 0.0 : points.values.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sınav'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Diğer işlemler',
            onSelected: (v) {
              if (v == 'delete') _delete(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Sınavı sil'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: PageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(exam.title, style: theme.textTheme.headlineSmall),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  details,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (exam.choiceCount > 0)
                    _Fact(
                      '${exam.choiceCount} test sorusu'
                      '${exam.choiceQuestions.every((q) => q.points == null) ? ' × ${fmtNum(choiceEach)} puan' : ''}',
                    ),
                  if (exam.openCount > 0)
                    _Fact(
                      '${exam.openCount} açık uçlu '
                      '(${fmtNum(exam.openPointsTotal)} puan)',
                    ),
                  if (exam.usesBooklets)
                    _Fact('${exam.booklets.length} kitapçık'),
                  if (exam.choiceCount > 0) _Fact(exam.rules.penaltyLabel),
                ],
              ),
              const SizedBox(height: 28),
              Text('Sıradaki adımlar', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final (i, step) in steps.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                _StepCard(
                  number: i + 1,
                  title: step.title,
                  subtitle: step.subtitle,
                  done: step.done,
                  enabled: step.enabled,
                  disabledHint: step.disabledHint,
                  onTap: step.onTap,
                ),
              ],
              if (exam.usesBooklets && keyDone) ...[
                const SizedBox(height: 28),
                Text('Kitapçık anahtarları', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'A kitapçığından otomatik hazırlandı.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _BookletKeys(exam: exam),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Step {
  const _Step({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.done = false,
    this.enabled = true,
    this.disabledHint,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool done;
  final bool enabled;
  final String? disabledHint;
}

class _Fact extends StatelessWidget {
  const _Fact(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Chip(label: Text(text));
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onTap,
    this.enabled = true,
    this.disabledHint,
  });

  final int number;
  final String title;
  final String subtitle;
  final bool done;
  final bool enabled;
  final String? disabledHint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = !enabled;
    return Opacity(
      opacity: muted ? 0.6 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (enabled) {
              onTap();
            } else if (disabledHint != null) {
              showInfo(context, disabledHint!);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: done
                      ? scheme.secondaryContainer
                      : scheme.primaryContainer,
                  child: done
                      ? Icon(Icons.check_rounded, color: scheme.secondary)
                      : Text(
                          '$number',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        muted && disabledHint != null
                            ? disabledHint!
                            : subtitle,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled
                      ? Icons.chevron_right_rounded
                      : Icons.lock_outline_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookletKeys extends StatelessWidget {
  const _BookletKeys({required this.exam});

  final Exam exam;

  @override
  Widget build(BuildContext context) {
    const builder = AnswerKeyBuilder();
    final keys = {
      for (final b in exam.booklets) b.code: builder.keyFor(exam, b),
    };
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 40,
          columnSpacing: 20,
          columns: [
            const DataColumn(label: Text('Soru')),
            for (final code in keys.keys)
              DataColumn(
                label: Text(
                  code,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
          ],
          rows: [
            for (var i = 1; i <= exam.choiceCount; i++)
              DataRow(
                cells: [
                  DataCell(Text('$i')),
                  for (final key in keys.values)
                    DataCell(
                      Text(
                        key[i] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
