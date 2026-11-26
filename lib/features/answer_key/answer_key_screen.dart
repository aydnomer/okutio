import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/exam.dart';
import '../../core/models/question.dart';
import '../../core/scoring/answer_input.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/exam_not_found.dart';
import '../../shared/widgets/option_card.dart';

/// Çoktan seçmeli soruların cevap anahtarı (ana kitapçık).
///
/// Her dokunuş hemen kaydedilir; öğretmenin "kaydet" düğmesi aramasına gerek yok.
class AnswerKeyScreen extends ConsumerWidget {
  const AnswerKeyScreen({required this.examId, super.key});

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

  /// Birden fazla doğru şık kabul edilen sorular.
  late final Set<int> _multi = {
    for (final q in widget.initial.choiceQuestions)
      if (q.correctOptions.length > 1) q.number,
  };

  Future<void> _saving = Future.value();
  bool _saved = true;

  int get _done => _exam.choiceCount - _exam.missingAnswerCount;

  void _update(Exam next) {
    setState(() {
      _exam = next;
      _saved = false;
    });
    final notifier = ref.read(examListProvider.notifier);
    // Kayıtları sırayla yap ki hızlı dokunuşlarda eski hâl yenisinin üstüne yazılmasın.
    _saving = _saving.then((_) => notifier.save(next)).then((_) {
      if (mounted && identical(_exam, next)) setState(() => _saved = true);
    });
  }

  void _replaceQuestion(ChoiceQuestion q) {
    _update(
      _exam.copyWith(
        choiceQuestions: [
          for (final old in _exam.choiceQuestions)
            old.number == q.number ? q : old,
        ],
      ),
    );
  }

  /// Ekrandaki satır eski kalmış olabilir; her zaman güncel soruyu kullan.
  ChoiceQuestion _current(int number) =>
      _exam.choiceQuestions.firstWhere((q) => q.number == number);

  void _tapOption(int number, int option) {
    final q = _current(number);
    if (q.cancelled) {
      showInfo(
        context,
        '${q.number}. soru iptal edildi. İptali kaldırmak için sağdaki menüyü kullanın.',
      );
      return;
    }
    final Set<int> next;
    if (_multi.contains(q.number)) {
      next = {...q.correctOptions};
      if (!next.remove(option)) next.add(option);
    } else {
      next = q.correctOptions.length == 1 && q.correctOptions.contains(option)
          ? {}
          : {option};
    }
    _replaceQuestion(q.copyWith(correctOptions: next));
  }

  void _menu(int number, _RowAction action) {
    final q = _current(number);
    switch (action) {
      case _RowAction.toggleMulti:
        setState(() {
          if (!_multi.remove(q.number)) _multi.add(q.number);
        });
        if (!_multi.contains(q.number) && q.correctOptions.length > 1) {
          final first = (q.correctOptions.toList()..sort()).first;
          _replaceQuestion(q.copyWith(correctOptions: {first}));
        }
      case _RowAction.toggleCancel:
        _replaceQuestion(q.copyWith(cancelled: !q.cancelled));
        showInfo(
          context,
          q.cancelled
              ? '${q.number}. sorunun iptali kaldırıldı.'
              : '${q.number}. soru iptal edildi: ${_exam.rules.cancelPolicy.label.toLowerCase()}.',
        );
      case _RowAction.clear:
        _replaceQuestion(q.copyWith(correctOptions: {}));
    }
  }

  Future<void> _typeAnswers() async {
    final answers = await showDialog<List<int?>>(
      context: context,
      builder: (_) => _TypeAnswersDialog(exam: _exam),
    );
    if (answers == null) return;
    final questions = [..._exam.choiceQuestions];
    for (var i = 0; i < answers.length; i++) {
      final q = questions[i];
      final a = answers[i];
      questions[i] = q.copyWith(correctOptions: a == null ? {} : {a});
      _multi.remove(q.number);
    }
    _update(_exam.copyWith(choiceQuestions: questions));
    final filled = answers.whereType<int>().length;
    if (mounted) {
      showInfo(context, '$filled sorunun cevabı girildi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _exam.choiceCount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cevap anahtarı'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _SaveState(saved: _saved),
          ),
        ],
      ),
      body: total == 0
          ? const PageFrame(
              child: InfoBox(
                text: 'Bu sınavda test sorusu yok. Açık uçlu soruların puanlarını sınav ekranından düzenleyebilirsiniz.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                PageFrame(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _exam.usesBooklets
                            ? 'A kitapçığının doğru cevaplarına dokunun. Diğer kitapçıklar otomatik hazırlanır.'
                            : 'Her sorunun doğru cevabına dokunun. Yanlış dokunursanız tekrar dokunarak kaldırabilirsiniz.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _Progress(done: _done, total: total),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _typeAnswers,
                        icon: const Icon(Icons.keyboard_alt_outlined),
                        label: const Text('Cevapları yazarak gir'),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                for (final q in _exam.choiceQuestions)
                  PageFrame(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _QuestionRow(
                      question: q,
                      optionCount: _exam.optionCount,
                      multi: _multi.contains(q.number),
                      onTap: (o) => _tapOption(q.number, o),
                      onAction: (a) => _menu(q.number, a),
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
            child: Text(
              _exam.answerKeyComplete
                  ? 'Bitti'
                  : 'Şimdilik bu kadar (${_exam.missingAnswerCount} eksik)',
            ),
          ),
        ),
      ),
    );
  }
}

class _SaveState extends StatelessWidget {
  const _SaveState({required this.saved});

  final bool saved;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          saved ? Icons.cloud_done_outlined : Icons.sync_rounded,
          size: 20,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          saved ? 'Kaydedildi' : 'Kaydediliyor',
          style: TextStyle(color: color),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = done == total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                complete ? 'Tüm sorular tamam' : '$done / $total soru girildi',
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (complete)
              Icon(
                Icons.check_circle_rounded,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: total == 0 ? 0 : done / total,
          minHeight: 10,
          borderRadius: BorderRadius.circular(10),
        ),
      ],
    );
  }
}

enum _RowAction { toggleMulti, toggleCancel, clear }

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.question,
    required this.optionCount,
    required this.multi,
    required this.onTap,
    required this.onAction,
  });

  final ChoiceQuestion question;
  final int optionCount;
  final bool multi;
  final ValueChanged<int> onTap;
  final ValueChanged<_RowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = question;
    final scheme = theme.colorScheme;
    final missing = !q.hasAnswer && !q.cancelled;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
      decoration: BoxDecoration(
        color: q.cancelled
            ? scheme.surfaceContainerHighest
            : missing
            ? null
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '${q.number}.',
              textAlign: TextAlign.right,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var o = 0; o < optionCount; o++)
                      _Bubble(
                        letter: optionLetters[o],
                        selected: q.correctOptions.contains(o),
                        dimmed: q.cancelled,
                        semantics:
                            '${q.number}. soru ${optionLetters[o]} şıkkı',
                        onTap: () => onTap(o),
                      ),
                  ],
                ),
                if (q.cancelled || multi)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      q.cancelled
                          ? 'İptal edildi'
                          : 'Birden fazla doğru seçilebilir',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: q.cancelled ? scheme.error : scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<_RowAction>(
            tooltip: '${q.number}. soru seçenekleri',
            onSelected: onAction,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _RowAction.toggleMulti,
                child: Text(
                  multi
                      ? 'Tek doğru cevaba dön'
                      : 'Birden fazla doğru cevap var',
                ),
              ),
              PopupMenuItem(
                value: _RowAction.toggleCancel,
                child: Text(q.cancelled ? 'İptali kaldır' : 'Soruyu iptal et'),
              ),
              if (q.hasAnswer)
                const PopupMenuItem(
                  value: _RowAction.clear,
                  child: Text('Cevabı temizle'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.letter,
    required this.selected,
    required this.dimmed,
    required this.semantics,
    required this.onTap,
  });

  final String letter;
  final bool selected;
  final bool dimmed;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = selected
        ? (dimmed ? scheme.outline : scheme.primary)
        : Colors.transparent;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      selected: selected,
      label: semantics,
      child: Material(
        color: fill,
        shape: CircleBorder(
          side: BorderSide(color: selected ? fill : scheme.outline, width: 1.5),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: dimmed && !selected
                      ? scheme.onSurface.withValues(alpha: 0.4)
                      : fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeAnswersDialog extends StatefulWidget {
  const _TypeAnswersDialog({required this.exam});

  final Exam exam;

  @override
  State<_TypeAnswersDialog> createState() => _TypeAnswersDialogState();
}

class _TypeAnswersDialogState extends State<_TypeAnswersDialog> {
  // Var olan anahtar seçili gelir: öğretmen yazmaya başlayınca tamamen değişir.
  late final _controller = () {
    final text = widget.exam.missingAnswerCount == widget.exam.choiceCount
        ? ''
        : AnswerInput.format(widget.exam.choiceQuestions);
    return TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }();

  AnswerInputResult get _result => AnswerInput.parse(
    _controller.text,
    optionCount: widget.exam.optionCount,
    questionCount: widget.exam.choiceCount,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final last = optionLetters[widget.exam.optionCount - 1];
    return AlertDialog(
      title: const Text('Cevapları yazarak girin'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cevapları sırayla yazın, örneğin "ABCDA BDCA". '
              'Boşluklar önemsizdir. Boş bırakmak için "-" yazın. '
              'Harfler A-$last arası olmalı.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontSize: 22,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'ABCD…',
                errorText: r.error,
                errorMaxLines: 3,
                helperText:
                    '${r.answers.length} / ${widget.exam.choiceCount} soru',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (r.ok && r.answers.isNotEmpty) {
                  Navigator.of(context).pop(r.answers);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: r.ok && r.answers.isNotEmpty
              ? () => Navigator.of(context).pop(r.answers)
              : null,
          child: const Text('Uygula'),
        ),
      ],
    );
  }
}
