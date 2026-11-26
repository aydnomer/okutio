import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/exam_factory.dart';
import '../../core/models/exam.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/action_card.dart';

/// Ana ekran: iki büyük iş (yeni sınav, kâğıt tara) ve sınav listesi.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(examListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.fact_check_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text('Okutio', style: theme.textTheme.titleLarge),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: PageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Hoş geldiniz', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Ne yapmak istiyorsunuz?',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ActionCard(
                icon: Icons.add_circle_rounded,
                title: 'Yeni sınav oluştur',
                subtitle: 'Soru sayısını seçin, formu yazdırın.',
                primary: true,
                onTap: () => context.push('/sinav/yeni'),
              ),
              const SizedBox(height: 12),
              ActionCard(
                icon: Icons.document_scanner_rounded,
                title: 'Kâğıt tara',
                subtitle: 'Sınav kâğıtlarını okutup puanlayın.',
                onTap: () => showInfo(
                  context,
                  'Tarama bir sonraki sürümde geliyor. '
                  'Şimdilik sınav oluşturup formu yazdırabilirsiniz.',
                ),
              ),
              const SizedBox(height: 32),
              Text('Sınavlarım', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              exams.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => const _Message(
                  icon: Icons.error_outline_rounded,
                  text: 'Sınavlar yüklenemedi. Uygulamayı kapatıp açmayı deneyin.',
                ),
                data: (list) => list.isEmpty
                    ? const _EmptyExams()
                    : Column(
                        children: [
                          for (final exam in list) ...[
                            _ExamTile(exam: exam),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamTile extends StatelessWidget {
  const _ExamTile({required this.exam});

  final Exam exam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      if (exam.classGroup.isNotEmpty) exam.classGroup,
      if (exam.choiceCount > 0) '${exam.choiceCount} test',
      if (exam.openCount > 0) '${exam.openCount} açık uçlu',
      if (exam.usesBooklets) '${exam.booklets.length} kitapçık',
    ].join(' · ');
    final ready = exam.answerKeyComplete;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/sinav/${exam.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exam.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _StatusChip(
                      ok: ready,
                      text: ready
                          ? 'Formu yazdırmaya hazır'
                          : 'Cevap anahtarı eksik '
                                '(${exam.missingAnswerCount} soru)',
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DateFormat('d MMM', 'tr').format(exam.createdAt),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 18),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = ok ? scheme.secondaryContainer : scheme.tertiaryContainer;
    final fg = ok ? scheme.onSecondaryContainer : scheme.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.edit_note_rounded,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyExams extends ConsumerWidget {
  const _EmptyExams();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Henüz sınavınız yok.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Uygulamayı denemek için hazır bir örnek sınav ekleyebilirsiniz. '
              'İstediğiniz zaman silebilirsiniz.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(examListProvider.notifier).save(buildSampleExam()),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Örnek sınavla dene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
