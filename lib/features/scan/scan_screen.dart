import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/exam.dart';
import '../../core/models/student_sheet.dart';
import '../../core/scan/scan_service.dart';
import '../../core/scan/sheet_import.dart';
import '../../core/util/format.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/action_card.dart';
import '../../shared/widgets/exam_not_found.dart';
import '../../shared/widgets/option_card.dart';
import 'marked_photo.dart';

/// Kâğıt okutma: fotoğraf çek ya da galeriden toplu seç.
class ScanScreen extends ConsumerWidget {
  const ScanScreen({required this.examId, super.key});

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

class _Failure {
  const _Failure(this.name, this.message);

  final String name;
  final String message;
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.exam});

  final Exam exam;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _picker = ImagePicker();
  int _total = 0;
  int _done = 0;
  final _failures = <_Failure>[];
  final _sessionIds = <String>[];

  bool get _busy => _done < _total;

  Future<void> _camera() async {
    final XFile? photo;
    try {
      photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
      );
    } on Object {
      if (mounted) {
        showInfo(
          context,
          'Kamera açılamadı. "Fotoğraflardan seç" ile deneyin.',
        );
      }
      return;
    }
    if (photo == null) return;
    await _process([photo]);
    // Öğretmen arka arkaya çekebilsin: kâğıt okunduysa kamerayı yeniden öner.
    if (mounted && _failures.isEmpty) {
      final again = await showModalBottomSheet<bool>(
        context: context,
        builder: (_) => const _NextSheetPrompt(),
      );
      if (again ?? false) await _camera();
    }
  }

  Future<void> _gallery() async {
    final List<XFile> files;
    try {
      files = await _picker.pickMultiImage(
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
      );
    } on Object {
      if (mounted) showInfo(context, 'Fotoğraflar açılamadı.');
      return;
    }
    if (files.isEmpty) return;
    await _process(files);
  }

  Future<void> _process(List<XFile> files) async {
    final exam = widget.exam;
    final notifier = ref.read(sheetsProvider(exam.id).notifier);
    setState(() {
      _failures.clear();
      _total = files.length;
      _done = 0;
    });
    for (final (i, file) in files.indexed) {
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } on Object {
        _failures.add(_Failure('${i + 1}. fotoğraf', 'Dosya okunamadı.'));
        setState(() => _done++);
        continue;
      }
      final outcome = await readSheetPhoto(exam, bytes);
      final reading = outcome.reading;
      if (reading == null) {
        _failures.add(_Failure('${i + 1}. fotoğraf', outcome.error!));
      } else {
        final sheet = sheetFromReading(
          exam: exam,
          reading: reading,
          id: const Uuid().v4(),
          now: DateTime.now(),
        );
        await notifier.save(sheet, images: imagesToStore(reading));
        _sessionIds.add(sheet.id);
      }
      if (mounted) setState(() => _done++);
    }
    if (!mounted) return;
    final ok = files.length - _failures.length;
    showInfo(
      context,
      _failures.isEmpty
          ? '$ok kâğıt okundu.'
          : '$ok kâğıt okundu, ${_failures.length} fotoğraf okunamadı.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exam = widget.exam;
    final sheets = ref.watch(sheetsProvider(exam.id)).value ?? const [];
    final recent = [
      for (final id in _sessionIds.reversed) ...sheets.where((s) => s.id == id),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kâğıt okut'),
        actions: [
          if (sheets.isNotEmpty)
            TextButton(
              onPressed: () => context.push('/sinav/${exam.id}/sonuclar'),
              child: Text('Sonuçlar (${sheets.length})'),
            ),
        ],
      ),
      body: ListView(
        children: [
          PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StepHeader(
                  title: exam.title,
                  help: sheets.isEmpty
                      ? 'Kâğıtları fotoğraflayın; puanlar hemen hesaplanır.'
                      : 'Bu sınavda ${sheets.length} kâğıt okundu.',
                ),
                ActionCard(
                  primary: true,
                  icon: Icons.photo_camera_rounded,
                  title: 'Fotoğraf çek',
                  subtitle: 'Kâğıtları tek tek çekin, her biri hemen okunur.',
                  onTap: _busy ? () {} : _camera,
                ),
                const SizedBox(height: 10),
                ActionCard(
                  icon: Icons.photo_library_rounded,
                  title: 'Fotoğraflardan seç',
                  subtitle:
                      'Önceden çektiğiniz ya da tarattığınız kâğıtları '
                      'toplu seçin. Bir sınıfın tamamı tek seferde okunur.',
                  onTap: _busy ? () {} : _gallery,
                ),
                const SizedBox(height: 16),
                if (_total > 0) _ProgressCard(done: _done, total: _total),
                for (final f in _failures)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InfoBox(
                      warning: true,
                      text: '${f.name}: ${f.message}',
                    ),
                  ),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Yeni okunanlar', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final s in recent)
                    SheetTile(
                      exam: exam,
                      sheet: s,
                      onTap: () =>
                          context.push('/sinav/${exam.id}/kagit/${s.id}'),
                    ),
                ],
                const SizedBox(height: 24),
                const _Tips(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = done >= total;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              finished
                  ? '$total fotoğraf işlendi'
                  : '${done + 1} / $total kâğıt okunuyor…',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 10,
              borderRadius: BorderRadius.circular(10),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextSheetPrompt extends StatelessWidget {
  const _NextSheetPrompt();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Kâğıt okundu',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Sıradaki kâğıdı çekmek ister misiniz?'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.photo_camera_rounded),
              label: const Text('Sıradaki kâğıt'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Şimdilik bu kadar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tips = [
      (Icons.crop_free_rounded, 'Dört köşedeki siyah kareler kadraja girsin.'),
      (Icons.wb_incandescent_outlined, 'Loş ışık sorun değil; flaş gerekmez.'),
      (
        Icons.screen_rotation_rounded,
        'Kâğıt yan ya da ters olabilir, fark etmez.',
      ),
      (Icons.layers_clear_rounded, 'Kâğıdı düz bir yere koyun, katlı olmasın.'),
      (
        Icons.auto_fix_off_rounded,
        'İyi silinmemiş işaretler çift işaret sayılabilir; size gösterilir.',
      ),
    ];
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('İyi bir fotoğraf için', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final (icon, text) in tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(text, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Öğrenci kâğıdının liste satırı: numara, puan ve öğretmene düşen işler.
class SheetTile extends StatelessWidget {
  const SheetTile({
    required this.exam,
    required this.sheet,
    required this.onTap,
    super.key,
  });

  final Exam exam;
  final StudentSheet sheet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = sheet.score(exam);
    final issues = sheet.issues(exam);
    final name = sheet.studentName.isNotEmpty
        ? sheet.studentName
        : sheet.studentNumber.isEmpty
        ? 'Numara okunamadı'
        : 'No ${sheet.studentNumber}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      exam.choiceCount > 0
                          ? '${score.correct} D · ${score.wrong} Y · '
                                '${score.blank} B'
                                '${sheet.bookletCode != null && exam.usesBooklets ? ' · ${sheet.bookletCode} kitapçığı' : ''}'
                          : 'Açık uçlu',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (issues.isNotEmpty && !sheet.reviewed) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final i in issues)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                i,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  Text(
                    fmtNum(score.total, maxDecimals: 1),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: score.isFinal ? scheme.primary : scheme.outline,
                    ),
                  ),
                  Text(
                    score.isFinal ? 'puan' : 'şimdilik',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
