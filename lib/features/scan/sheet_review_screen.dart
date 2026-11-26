import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/ai/ai_grader.dart';
import '../../core/models/booklet.dart';
import '../../core/models/exam.dart';
import '../../core/models/question.dart';
import '../../core/models/student_sheet.dart';
import '../../core/util/format.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/exam_not_found.dart';
import '../../shared/widgets/option_card.dart';

/// Bir öğrenci kâğıdını gözden geçirme: okunan işaretleri düzeltme,
/// açık uçlu sorulara puan verme ve onaylama.
class SheetReviewScreen extends ConsumerWidget {
  const SheetReviewScreen({
    required this.examId,
    required this.sheetId,
    super.key,
  });

  final String examId;
  final String sheetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exam = ref.watch(examByIdProvider(examId)).value;
    final sheets = ref.watch(sheetsProvider(examId));
    if (exam == null || sheets.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final list = sheets.value ?? const <StudentSheet>[];
    final sheet = list.where((s) => s.id == sheetId).firstOrNull;
    if (sheet == null) return const ExamNotFound();
    return _Review(key: ValueKey(sheet.id), exam: exam, initial: sheet);
  }
}

class _Review extends ConsumerStatefulWidget {
  const _Review({required this.exam, required this.initial, super.key});

  final Exam exam;
  final StudentSheet initial;

  @override
  ConsumerState<_Review> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<_Review> {
  late StudentSheet _sheet = widget.initial;
  late final _number = TextEditingController(text: _sheet.studentNumber);
  late final _name = TextEditingController(text: _sheet.studentName);
  Future<void> _saving = Future.value();

  Exam get exam => widget.exam;

  bool get _openPending =>
      exam.openQuestions.any((q) => _sheet.openScores[q.number] == null);

  /// Okumadan kaynaklanan, öğretmenin bakması gereken sorunlar.
  List<String> get _readIssues => [
    for (final i in _sheet.issues(exam))
      if (!i.startsWith('Açık uçlu')) i,
  ];

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  void _update(StudentSheet next) {
    setState(() => _sheet = next);
    final notifier = ref.read(sheetsProvider(exam.id).notifier);
    _saving = _saving.then((_) => notifier.save(next));
  }

  Booklet get _booklet =>
      (_sheet.bookletCode == null
          ? null
          : exam.bookletByCode(_sheet.bookletCode!)) ??
      Booklet.master(exam.choiceCount);

  void _toggleMark(int bookletNumber, int option) {
    final marks = {..._sheet.choiceMarks};
    final set = {...?marks[bookletNumber]};
    if (!set.remove(option)) set.add(option);
    if (set.isEmpty) {
      marks.remove(bookletNumber);
    } else {
      marks[bookletNumber] = set;
    }
    _update(
      _sheet.copyWith(
        choiceMarks: marks,
        needsReview: {..._sheet.needsReview}..remove(bookletNumber),
      ),
    );
  }

  void _setOpen(int number, double? score) {
    _update(_sheet.copyWith(openScores: {..._sheet.openScores, number: score}));
  }

  Future<void> _approve() async {
    _update(
      _sheet.copyWith(
        reviewed: true,
        needsReview: {},
        studentNumber: _number.text.trim(),
        studentName: _name.text.trim(),
      ),
    );
    await _saving;
    if (!mounted) return;
    // Kontrol bekleyen bir sonraki kâğıda geç.
    final sheets = ref.read(sheetsProvider(exam.id)).value ?? const [];
    final next = sheets
        .where(
          (s) => !s.reviewed && s.id != _sheet.id && s.issues(exam).isNotEmpty,
        )
        .firstOrNull;
    if (next != null) {
      context.pushReplacement('/sinav/${exam.id}/kagit/${next.id}');
    } else {
      showInfo(context, 'Kâğıt onaylandı.');
      if (context.canPop()) context.pop();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kâğıt silinsin mi?'),
        content: const Text(
          'Bu öğrencinin okunan cevapları ve puanı silinir. '
          'Kâğıdı tekrar okutabilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(sheetsProvider(exam.id).notifier).delete(_sheet);
    if (mounted && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = _sheet.score(exam);
    final images =
        ref.watch(sheetImagesProvider(_sheet.id)).value ?? const <Uint8List>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kâğıt'),
        actions: [
          IconButton(
            tooltip: 'Kâğıdı sil',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        children: [
          PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScoreHeader(exam: exam, sheet: _sheet),
                const SizedBox(height: 16),
                if (!_sheet.reviewed && _readIssues.isNotEmpty) ...[
                  InfoBox(
                    warning: true,
                    text:
                        'Kontrol edin: ${_readIssues.join(', ').toLowerCase()}.',
                  ),
                  const SizedBox(height: 16),
                ] else if (_openPending) ...[
                  const InfoBox(
                    text: 'Test soruları okundu. Açık uçlu sorulara puan verip onaylayın.',
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _number,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Öğrenci no',
                        ),
                        onChanged: (v) =>
                            _update(_sheet.copyWith(studentNumber: v.trim())),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Adı (isteğe bağlı)',
                        ),
                        onChanged: (v) =>
                            _update(_sheet.copyWith(studentName: v.trim())),
                      ),
                    ),
                  ],
                ),
                if (exam.usesBooklets) ...[
                  const SizedBox(height: 20),
                  Text('Kitapçık', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      for (final b in exam.booklets)
                        ButtonSegment(value: b.code, label: Text(b.code)),
                    ],
                    selected: {?_sheet.bookletCode},
                    emptySelectionAllowed: true,
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      _update(
                        _sheet.copyWith(
                          bookletCode: () => s.first,
                          bookletSource: BookletSource.manual,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _sheet.bookletSource.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                for (final (i, q) in exam.openQuestions.indexed) ...[
                  const SizedBox(height: 24),
                  _OpenScoreCard(
                    question: q,
                    image: i < images.length ? images[i] : null,
                    score: _sheet.openScores[q.number],
                    onChanged: (v) => _setOpen(q.number, v),
                    subject: exam.subject,
                  ),
                ],
                if (exam.choiceCount > 0) ...[
                  const SizedBox(height: 24),
                  Text('Test cevapları', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Yanlış okunan bir işaret varsa yuvarlağa dokunarak düzeltin.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _Legend(),
                  const SizedBox(height: 8),
                  for (var n = 1; n <= exam.choiceCount; n++)
                    _AnswerRow(
                      number: n,
                      question:
                          exam.choiceQuestions[_booklet.masterNumberOf(n) - 1],
                      booklet: _booklet,
                      optionCount: exam.optionCount,
                      marked: _sheet.choiceMarks[n] ?? const {},
                      review: _sheet.needsReview.contains(n),
                      onTap: (o) => _toggleMark(n, o),
                    ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Toplam: ${fmtNum(score.total)} / ${fmtNum(exam.rules.totalPoints)}',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
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
            onPressed: _approve,
            icon: const Icon(Icons.check_rounded),
            label: Text(_sheet.reviewed ? 'Kaydet' : 'Onayla'),
          ),
        ),
      ),
    );
  }
}

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({required this.exam, required this.sheet});

  final Exam exam;
  final StudentSheet sheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = sheet.score(exam);
    Widget stat(String label, String value, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              fmtNum(s.total, maxDecimals: 1),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onPrimaryContainer,
              ),
            ),
            Text(
              s.isFinal
                  ? 'puan'
                  : 'puan (${s.openPending} açık uçlu soru bekliyor)',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            if (exam.choiceCount > 0) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  stat('Doğru', '${s.correct}', Colors.green.shade700),
                  stat('Yanlış', '${s.wrong}', scheme.error),
                  stat('Boş', '${s.blank}', scheme.onSurfaceVariant),
                  if (exam.rules.wrongPenaltyDivisor != null)
                    stat('Net', fmtNum(s.net), scheme.primary),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    Widget item(Color fill, Color border, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 2),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: style),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(Colors.green.shade600, Colors.green.shade600, 'Doğru işaret'),
        item(Colors.red.shade600, Colors.red.shade600, 'Yanlış işaret'),
        item(Colors.transparent, Colors.green.shade600, 'Doğru cevap'),
      ],
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.number,
    required this.question,
    required this.booklet,
    required this.optionCount,
    required this.marked,
    required this.review,
    required this.onTap,
  });

  final int number;
  final ChoiceQuestion question;
  final Booklet booklet;
  final int optionCount;
  final Set<int> marked;
  final bool review;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final master = question.number;
    final correct = {
      for (final o in question.correctOptions)
        booklet.bookletOptionOf(master, o),
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: review ? scheme.tertiaryContainer : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$number.',
              textAlign: TextAlign.right,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          for (var o = 0; o < optionCount; o++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _Dot(
                letter: optionLetters[o],
                marked: marked.contains(o),
                correct: correct.contains(o),
                cancelled: question.cancelled,
                label: '$number. soru ${optionLetters[o]} şıkkı',
                onTap: () => onTap(o),
              ),
            ),
          const Spacer(),
          if (question.cancelled)
            Text('İptal', style: theme.textTheme.labelMedium)
          else if (review)
            Text(
              'Silik',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.letter,
    required this.marked,
    required this.correct,
    required this.cancelled,
    required this.label,
    required this.onTap,
  });

  final String letter;
  final bool marked;
  final bool correct;
  final bool cancelled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final green = Colors.green.shade600;
    final red = Colors.red.shade600;
    final Color fill;
    final Color border;
    if (cancelled) {
      fill = marked ? scheme.outline : Colors.transparent;
      border = scheme.outline;
    } else if (marked) {
      fill = correct ? green : red;
      border = fill;
    } else {
      fill = Colors.transparent;
      border = correct ? green : scheme.outlineVariant;
    }
    return Semantics(
      button: true,
      selected: marked,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: correct ? 3 : 1.5),
          ),
          child: Text(
            letter,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: marked ? Colors.white : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Açık uçlu soru: öğrencinin cevabının fotoğrafı ve puan seçimi.
class _OpenScoreCard extends StatefulWidget {
  const _OpenScoreCard({
    required this.question,
    required this.image,
    required this.score,
    required this.onChanged,
    this.subject = '',
  });

  final OpenQuestion question;
  final Uint8List? image;
  final double? score;
  final ValueChanged<double?> onChanged;
  final String subject;

  @override
  State<_OpenScoreCard> createState() => _OpenScoreCardState();
}

class _OpenScoreCardState extends State<_OpenScoreCard> {
  AiSuggestion? _ai;
  String? _aiError;
  bool _aiBusy = false;

  OpenQuestion get question => widget.question;
  Uint8List? get image => widget.image;
  double? get score => widget.score;
  ValueChanged<double?> get onChanged => widget.onChanged;

  Future<void> _askAi() async {
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final s = await AiGrader().grade(
        jpeg: image!,
        question: question,
        subject: widget.subject,
      );
      if (mounted) setState(() => _ai = s);
    } on AiGraderException catch (e) {
      if (mounted) setState(() => _aiError = e.message);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = question;
    final max = q.maxPoints;
    final quick = <(String, double)>[
      ('0', 0),
      ('Çeyrek', max / 4),
      ('Yarım', max / 2),
      ('¾', max * 3 / 4),
      ('Tam', max),
    ];
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
                Text(
                  score == null
                      ? '— / ${fmtNum(max)}'
                      : '${fmtNum(score!)} / ${fmtNum(max)}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: score == null ? scheme.outline : scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (q.prompt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(q.prompt, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: InteractiveViewer(
                  maxScale: 4,
                  child: Image.memory(
                    image!,
                    fit: BoxFit.fitWidth,
                    semanticLabel: 'Öğrencinin cevabı',
                  ),
                ),
              )
            else
              const InfoBox(
                text: 'Cevabın fotoğrafı bu cihazda yok. Kâğıda bakarak puan verin.',
              ),
            if (aiGraderConfigured && image != null) ...[
              const SizedBox(height: 12),
              if (_ai == null)
                OutlinedButton.icon(
                  onPressed: _aiBusy ? null : _askAi,
                  icon: _aiBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(
                    _aiBusy
                        ? 'Yazı okunuyor…'
                        : 'Yapay zekâ okusun, puan önersin',
                  ),
                )
              else
                _AiSuggestionCard(
                  suggestion: _ai!,
                  max: max,
                  onApply: () => onChanged(_ai!.suggestedScore),
                ),
              if (_aiError != null) ...[
                const SizedBox(height: 8),
                InfoBox(warning: true, text: _aiError!),
              ],
            ],
            if (q.referenceAnswer.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Beklenen: ${q.referenceAnswer}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (q.rubric.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Ölçütler', style: theme.textTheme.titleSmall),
              for (final c in q.rubric)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.check_box_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(c.title.isEmpty ? 'Ölçüt' : c.title),
                      ),
                      Text('${fmtNum(max * c.weightPercent / 100)} puan'),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, v) in quick)
                  ChoiceChip(
                    label: Text('$label (${fmtNum(v)})'),
                    selected: score != null && (score! - v).abs() < 0.001,
                    onSelected: (_) => onChanged(v),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: '1 puan azalt',
                  onPressed: (score ?? 0) >= 1
                      ? () => onChanged((score ?? 0) - 1)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Slider(
                    value: (score ?? 0).clamp(0, max),
                    max: max,
                    divisions: (max * 2).round().clamp(1, 400),
                    label: fmtNum(score ?? 0),
                    onChanged: onChanged,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '1 puan artır',
                  onPressed: (score ?? 0) + 1 <= max
                      ? () => onChanged((score ?? 0) + 1)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AiSuggestionCard extends StatelessWidget {
  const _AiSuggestionCard({
    required this.suggestion,
    required this.max,
    required this.onApply,
  });

  final AiSuggestion suggestion;
  final double max;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = suggestion;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Öneri: ${fmtNum(s.suggestedScore)} / ${fmtNum(max)}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(s.confidenceLabel, style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 10),
          Text('Öğrencinin yazdığı', style: theme.textTheme.labelLarge),
          const SizedBox(height: 2),
          Text(
            s.transcription.isEmpty ? '(boş)' : s.transcription,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
          if (!s.legible)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Yazı büyük ölçüde okunamadı; kâğıda bakarak puanlayın.',
                style: TextStyle(color: scheme.error),
              ),
            ),
          const SizedBox(height: 10),
          for (final c in s.criteria)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '• ${c.title}: ${fmtNum(c.points)} puan. ${c.reason}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (s.feedback.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Öğrenciye not: ${s.feedback}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: onApply,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Öneriyi uygula'),
          ),
          const SizedBox(height: 4),
          Text(
            'Son karar sizin: puanı aşağıdan değiştirebilirsiniz.',
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
