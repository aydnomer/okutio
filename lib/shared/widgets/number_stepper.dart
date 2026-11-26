import 'package:material_ui/material_ui.dart';

/// Büyük eksi/artı düğmeli sayı seçici. Klavye açmadan sayı girmeyi sağlar.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    required this.value,
    required this.onChanged,
    super.key,
    this.min = 0,
    this.max = 200,
    this.step = 1,
    this.quickPicks = const [],
    this.unit = '',
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;
  final List<int> quickPicks;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _RoundButton(
              icon: Icons.remove_rounded,
              tooltip: 'Azalt',
              onPressed: value - step >= min
                  ? () => onChanged(value - step)
                  : null,
            ),
            Expanded(
              child: Text(
                unit.isEmpty ? '$value' : '$value $unit',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _RoundButton(
              icon: Icons.add_rounded,
              tooltip: 'Artır',
              onPressed: value + step <= max
                  ? () => onChanged(value + step)
                  : null,
            ),
          ],
        ),
        if (quickPicks.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final v in quickPicks)
                ChoiceChip(
                  label: Text('$v'),
                  selected: v == value,
                  onSelected: (_) => onChanged(v),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 32,
      style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
      icon: Icon(icon),
    );
  }
}
