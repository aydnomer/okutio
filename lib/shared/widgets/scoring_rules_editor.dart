import 'package:material_ui/material_ui.dart';

import '../../core/models/scoring_rules.dart';

/// Boş, çift işaret, iptal, yanlış götürme ve yuvarlama kuralları.
///
/// Hem sınav oluşturma sihirbazında hem de sonradan "Puanlama kuralları"
/// ekranında aynı haliyle kullanılır.
class ScoringRulesEditor extends StatelessWidget {
  const ScoringRulesEditor({
    required this.rules,
    required this.onChanged,
    super.key,
  });

  final ScoringRules rules;
  final ValueChanged<ScoringRules> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String text, String help) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            help,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final style = SegmentedButton.styleFrom(minimumSize: const Size(0, 52));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(
          'Yanlışlar doğruyu götürsün mü?',
          'Boş bırakılan soru puan getirmez ama doğruyu da götürmez.',
        ),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Hayır')),
            ButtonSegment(value: 3, label: Text('3 yanlış 1 doğru')),
            ButtonSegment(value: 4, label: Text('4 yanlış 1 doğru')),
          ],
          selected: {rules.wrongPenaltyDivisor ?? 0},
          showSelectedIcon: false,
          style: style,
          onSelectionChanged: (s) => onChanged(
            rules.copyWith(
              wrongPenaltyDivisor: () => s.first == 0 ? null : s.first,
            ),
          ),
        ),
        label(
          'Bir soruda birden fazla şık işaretlenirse',
          'Bu kâğıtlar okutunca size ayrıca gösterilir; iyi silinmemiş '
              'bir işaretse tek dokunuşla düzeltebilirsiniz.',
        ),
        SegmentedButton<MultiMarkPolicy>(
          segments: [
            for (final p in MultiMarkPolicy.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {rules.multiMarkPolicy},
          showSelectedIcon: false,
          style: style,
          onSelectionChanged: (s) =>
              onChanged(rules.copyWith(multiMarkPolicy: s.first)),
        ),
        label(
          'İptal ettiğiniz sorular',
          rules.cancelPolicy == CancelPolicy.countAsCorrect
              ? 'Sorunun puanı herkese verilir.'
              : 'Soru yok sayılır, puanı diğer sorulara paylaştırılır.',
        ),
        SegmentedButton<CancelPolicy>(
          segments: [
            for (final p in CancelPolicy.values)
              ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {rules.cancelPolicy},
          showSelectedIcon: false,
          style: style,
          onSelectionChanged: (s) =>
              onChanged(rules.copyWith(cancelPolicy: s.first)),
        ),
        label(
          'Puanlar nasıl yuvarlansın?',
          'Örneğin 72,4 puan tam sayıya yuvarlanınca 72 olur.',
        ),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Tam sayıya')),
            ButtonSegment(value: 0.5, label: Text('Yarım puana')),
            ButtonSegment(value: 0, label: Text('Yuvarlama')),
          ],
          selected: {rules.roundingStep},
          showSelectedIcon: false,
          style: style,
          onSelectionChanged: (s) =>
              onChanged(rules.copyWith(roundingStep: s.first)),
        ),
      ],
    );
  }
}
