import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/models/exam.dart';
import '../../core/voice/voice_command.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';

/// Uygulama çubuğundaki mikrofon düğmesi: sesli komut penceresini açar.
class VoiceCommandButton extends ConsumerWidget {
  const VoiceCommandButton({required this.exam, super.key});

  final Exam exam;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: 'Sesli komut',
    icon: const Icon(Icons.mic_rounded),
    onPressed: () => showVoiceCommandSheet(context, ref, exam),
  );
}

Future<void> showVoiceCommandSheet(
  BuildContext context,
  WidgetRef ref,
  Exam exam,
) async {
  final result = await showModalBottomSheet<VoiceResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VoiceSheet(exam: exam),
  );
  if (result == null || !result.changed || !context.mounted) return;
  final notifier = ref.read(examListProvider.notifier);
  await notifier.save(result.exam);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(result.done.join(' ')),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () => notifier.save(exam),
        ),
      ),
    );
}

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet({required this.exam});

  final Exam exam;

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _speech = SpeechToText();
  final _text = TextEditingController();
  bool _ready = false;
  bool _listening = false;
  String? _micProblem;

  static const _unavailable =
      'Bu cihazda sesli komut kullanılamıyor. Komutu aşağıya yazabilirsiniz.';

  VoiceResult get _preview =>
      const VoiceCommands().apply(widget.exam, _text.text);

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          setState(() => _listening = s == SpeechToText.listeningStatus);
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _micProblem = e.errorMsg.contains('permission')
                ? 'Mikrofon izni verilmedi. Komutu aşağıya yazabilirsiniz.'
                : 'Ses anlaşılamadı. Tekrar deneyin ya da komutu yazın.';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _ready = ok;
        if (!ok) _micProblem = _unavailable;
      });
      if (ok) await _listen();
    } on Object {
      if (!mounted) return;
      setState(() => _micProblem = _unavailable);
    }
  }

  Future<void> _listen() async {
    setState(() => _micProblem = null);
    await _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        localeId: 'tr_TR',
        partialResults: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
      ),
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!mounted) return;
    setState(() {
      _text.text = r.recognizedWords;
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    });
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    final hasText = _text.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: PageFrame(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Sesli komut', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Yapmak istediğinizi söyleyin. Uygulamadan önce ne '
                  'yapılacağını burada görürsünüz.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: _MicButton(
                    listening: _listening,
                    enabled: _ready,
                    onTap: () => _listening
                        ? unawaited(_speech.stop())
                        : unawaited(_listen()),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _listening
                      ? 'Dinliyorum…'
                      : _ready
                      ? 'Konuşmak için mikrofona dokunun'
                      : _micProblem ?? 'Mikrofon hazırlanıyor…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                if (_micProblem != null && _ready) ...[
                  const SizedBox(height: 4),
                  Text(
                    _micProblem!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Komut',
                    hintText: 'Örn. 5. soruyu iptal et',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                if (hasText) ...[
                  for (final d in preview.done)
                    _Line(icon: Icons.check_circle_rounded, text: d, ok: true),
                  for (final m in preview.notUnderstood)
                    _Line(
                      icon: Icons.help_outline_rounded,
                      text: 'Anlaşılmadı: "$m"',
                      ok: false,
                    ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed: preview.changed
                      ? () => Navigator.pop(context, preview)
                      : null,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    preview.done.length > 1
                        ? '${preview.done.length} değişikliği uygula'
                        : 'Uygula',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Söyleyebilecekleriniz',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in VoiceCommands.examples)
                      ActionChip(
                        label: Text(e),
                        onPressed: () => setState(() => _text.text = e),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.enabled,
    required this.onTap,
  });

  final bool listening;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: listening ? 'Dinlemeyi durdur' : 'Konuşmaya başla',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: !enabled
              ? scheme.surfaceContainerHighest
              : listening
              ? scheme.error
              : scheme.primary,
          boxShadow: [
            if (listening)
              BoxShadow(
                color: scheme.error.withValues(alpha: 0.35),
                blurRadius: 24,
                spreadRadius: 6,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: Icon(
              listening ? Icons.stop_rounded : Icons.mic_rounded,
              size: 40,
              color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, required this.ok});

  final IconData icon;
  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 22,
            color: ok ? Colors.green.shade700 : scheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
