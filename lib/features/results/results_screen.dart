import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../../core/models/exam.dart';
import '../../core/models/student_sheet.dart';
import '../../core/results/class_report.dart';
import '../../core/util/format.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/exam_not_found.dart';
import '../../shared/widgets/option_card.dart';
import '../print_form/print_form_screen.dart';
import '../rules/rules_screen.dart';
import '../scan/scan_screen.dart';
import '../voice/voice_command_sheet.dart';

/// Sınıfın sonuçları: özet, en zor sorular, öğrenci listesi.
class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({required this.examId, super.key});

  final String examId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examByIdProvider(examId)).value;
    final sheets = ref.watch(sheetsProvider(examId));
    if (ref.watch(examByIdProvider(examId)).isLoading || sheets.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (exam == null) return const ExamNotFound();
    return _Body(exam: exam, sheets: sheets.value ?? const []);
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.exam, required this.sheets});

  final Exam exam;
  final List<StudentSheet> sheets;

  Future<void> _downloadPdf(BuildContext context, WidgetRef ref) async {
    try {
      final fonts = await ref.read(formFontsProvider.future);
      final bytes = await ClassReport(exam, sheets).pdf(fonts);
      await Printing.sharePdf(
        bytes: bytes,
        filename: pdfFileName('${exam.title} sonuclar'),
      );
    } on Object catch (e) {
      if (context.mounted) showInfo(context, 'Liste hazırlanamadı: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final report = ClassReport(exam, sheets);
    final hardest = report.hardest();
    final cancelledCount = exam.choiceQuestions
        .where((q) => q.cancelled)
        .length;
    final pending = sheets
        .where((s) => !s.reviewed && s.issues(exam).isNotEmpty)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sonuçlar'),
        actions: [
          VoiceCommandButton(exam: exam),
          if (sheets.isNotEmpty)
            IconButton(
              tooltip: 'Listeyi PDF olarak indir',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => _downloadPdf(context, ref),
            ),
        ],
      ),
      body: ListView(
        children: [
          PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StepHeader(title: exam.title),
                if (sheets.isEmpty)
                  const InfoBox(
                    text:
                        'Henüz kâğıt okutulmadı. Aşağıdaki düğmeyle başlayın.',
                  )
                else ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _Stat('Kâğıt', '${report.count}'),
                      _Stat('Ortalama', fmtNum(report.average, maxDecimals: 1)),
                      _Stat('En yüksek', fmtNum(report.highest)),
                      _Stat('En düşük', fmtNum(report.lowest)),
                    ],
                  ),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      color: theme.colorScheme.tertiaryContainer,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        leading: const Icon(Icons.fact_check_outlined),
                        title: Text(
                          '${pending.length} kâğıt kontrolünüzü bekliyor',
                        ),
                        subtitle: const Text(
                          'Silik işaret, okunamayan numara ya da açık uçlu puan',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(
                          '/sinav/${exam.id}/kagit/${pending.first.id}',
                        ),
                      ),
                    ),
                  ],
                  if (cancelledCount > 0) ...[
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.block_rounded),
                        title: Text(
                          '$cancelledCount soru iptal: '
                          '${exam.rules.cancelPolicy.label.toLowerCase()}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/sinav/${exam.id}/kurallar'),
                      ),
                    ),
                  ],
                  if (hardest.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'En çok zorlanılan sorular',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ders tekrarında üzerinde durmak isteyebilirsiniz.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final q in hardest)
                      _HardQuestion(
                        stat: q,
                        onTap: () => showCancelQuestionSheet(
                          context,
                          ref,
                          exam,
                          q.number,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Hatalı bir soru varsa üzerine dokunup iptal edebilirsiniz.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Öğrenciler', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final s in sheets)
                    SheetTile(
                      exam: exam,
                      sheet: s,
                      onTap: () =>
                          context.push('/sinav/${exam.id}/kagit/${s.id}'),
                    ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: PageFrame(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: () => context.push('/sinav/${exam.id}/tara'),
            icon: const Icon(Icons.document_scanner_rounded),
            label: Text(
              sheets.isEmpty ? 'Kâğıt okut' : 'Daha fazla kâğıt okut',
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(label, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _HardQuestion extends StatelessWidget {
  const _HardQuestion({required this.stat, required this.onTap});

  final QuestionStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (stat.correctRate * 100).round();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                '${stat.number}. soru',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: LinearProgressIndicator(
                value: stat.correctRate,
                minHeight: 12,
                borderRadius: BorderRadius.circular(8),
                color: pct < 30 ? theme.colorScheme.error : null,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: Text('%$pct doğru', style: theme.textTheme.bodyMedium),
            ),
            const Icon(Icons.more_vert_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}
