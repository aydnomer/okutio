import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/exam.dart';
import '../../core/models/scoring_rules.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/exam_not_found.dart';
import '../../shared/widgets/option_card.dart';
import '../../shared/widgets/scoring_rules_editor.dart';
import '../voice/voice_command_sheet.dart';

/// Sınavdan sonra da değiştirilebilen puanlama kuralları ve soru iptali.
class RulesScreen extends ConsumerWidget {
  const RulesScreen({required this.examId, super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sheetCount = ref.watch(sheetsProvider(exam.id)).value?.length ?? 0;
    final save = ref.read(examListProvider.notifier).save;
    final cancelled = exam.choiceQuestions.where((q) => q.cancelled).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Puanlama kuralları'),
        actions: [VoiceCommandButton(exam: exam)],
      ),
      body: SingleChildScrollView(
        child: PageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StepHeader(
                title: exam.title,
                help: sheetCount == 0
                    ? 'Değişiklikler hemen kaydedilir.'
                    : 'Değişiklikler hemen kaydedilir ve okunan $sheetCount '
                          'kâğıdın puanı kendiliğinden yeniden hesaplanır.',
              ),
              if (exam.choiceCount > 0) ...[
                Text('Soru iptali', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Hatalı ya da iki cevaplı bir soruyu iptal etmek için '
                  'numarasına dokunun. Tekrar dokunursanız iptal kalkar.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final q in exam.choiceQuestions)
                      FilterChip(
                        label: Text('${q.number}'),
                        selected: q.cancelled,
                        showCheckmark: false,
                        avatar: q.cancelled
                            ? const Icon(Icons.block_rounded, size: 18)
                            : null,
                        tooltip: q.cancelled
                            ? '${q.number}. soru iptal, kaldırmak için dokunun'
                            : '${q.number}. soruyu iptal et',
                        onSelected: (v) => save(
                          exam.copyWith(
                            choiceQuestions: [
                              for (final o in exam.choiceQuestions)
                                o.number == q.number
                                    ? o.copyWith(cancelled: v)
                                    : o,
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                InfoBox(
                  text: cancelled == 0
                      ? 'İptal edilen soru yok.'
                      : '$cancelled soru iptal: '
                            '${exam.rules.cancelPolicy.label.toLowerCase()}. '
                            'Bunu aşağıdan değiştirebilirsiniz.',
                ),
              ],
              ScoringRulesEditor(
                rules: exam.rules,
                onChanged: (r) => save(exam.copyWith(rules: r)),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sonuçlar ekranından tek soruyu hızlıca iptal etmek için alt pencere.
Future<void> showCancelQuestionSheet(
  BuildContext context,
  WidgetRef ref,
  Exam exam,
  int number,
) async {
  final q = exam.choiceQuestions.firstWhere((q) => q.number == number);
  final otherCancelled = exam.choiceQuestions.any(
    (o) => o.cancelled && o.number != number,
  );
  final choice = await showModalBottomSheet<CancelPolicy?>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                q.cancelled
                    ? '$number. soru iptal edilmiş'
                    : '$number. soruyu iptal edin',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                q.cancelled
                    ? 'İptali kaldırırsanız soru cevap anahtarına göre '
                          'yeniden puanlanır.'
                    : 'Soruda hata varsa iptal edin, bütün kâğıtların '
                          'puanı hemen yeniden hesaplanır.',
                style: theme.textTheme.bodyMedium,
              ),
              if (!q.cancelled && otherCancelled) ...[
                const SizedBox(height: 6),
                Text(
                  'Seçiminiz iptal edilen diğer sorulara da uygulanır.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              if (q.cancelled)
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('İptali kaldır'),
                )
              else ...[
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, CancelPolicy.countAsCorrect),
                  child: const Text('Herkese doğru say'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, CancelPolicy.exclude),
                  child: const Text('Hesaptan çıkar, puanını dağıt'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  // Pencere dışına dokunup kapatmak da null döner; iptal edilmemiş soruda
  // bu "vazgeç" demektir.
  if (!q.cancelled && choice == null) return;
  if (!context.mounted) return;
  final updated = exam.copyWith(
    choiceQuestions: [
      for (final o in exam.choiceQuestions)
        o.number == number ? o.copyWith(cancelled: !q.cancelled) : o,
    ],
    rules: choice == null ? null : exam.rules.copyWith(cancelPolicy: choice),
  );
  await ref.read(examListProvider.notifier).save(updated);
  if (context.mounted) {
    showInfo(
      context,
      q.cancelled
          ? '$number. sorunun iptali kaldırıldı.'
          : '$number. soru iptal edildi: ${choice!.label.toLowerCase()}.',
    );
  }
}
