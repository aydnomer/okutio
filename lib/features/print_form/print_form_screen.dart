import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';

import '../../core/form/form_layout.dart';
import '../../core/form/form_pdf.dart';
import '../../core/models/exam.dart';
import '../../data/providers.dart';
import '../../shared/page_frame.dart';
import '../../shared/widgets/exam_not_found.dart';
import '../../shared/widgets/number_stepper.dart';
import '../../shared/widgets/option_card.dart';
import 'form_preview.dart';

/// PDF'e gömülecek yazı tipleri; bir kez yüklenir.
final formFontsProvider = FutureProvider<FormFonts>((ref) async {
  final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
  final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
  return FormFonts.fromBytes(regular: regular, bold: bold);
});

/// Her işletim sisteminde sorunsuz açılan, Türkçe harfleri sadeleştirilmiş dosya adı.
String pdfFileName(String title) {
  const map = {
    'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', //
    'Ç': 'C', 'Ğ': 'G', 'İ': 'I', 'Ö': 'O', 'Ş': 'S', 'Ü': 'U',
  };
  final ascii = title.split('').map((c) => map[c] ?? c).join();
  final safe = ascii
      .replaceAll(RegExp(r'[^A-Za-z0-9 -]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-')
      .toLowerCase();
  return 'okutio-${safe.isEmpty ? 'form' : safe}.pdf';
}

class PrintFormScreen extends ConsumerWidget {
  const PrintFormScreen({required this.examId, super.key});

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

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.exam});

  final Exam exam;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late final FormLayout _layout = FormLayout.compute(widget.exam);
  int _copies = 1;
  int _page = 0;
  bool _busy = false;

  String get _fileName => pdfFileName(widget.exam.title);

  Future<Uint8List> _bytes() async {
    final fonts = await ref.read(formFontsProvider.future);
    return FormPdf(_layout, fonts).build(copies: _copies);
  }

  Future<void> _run(Future<void> Function(Uint8List bytes) action) async {
    setState(() => _busy = true);
    try {
      await action(await _bytes());
    } on Exception catch (e) {
      if (mounted) showInfo(context, 'Form hazırlanamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _print() => _run(
    (bytes) => Printing.layoutPdf(
      name: _fileName,
      format: PdfPageFormat.a4,
      onLayout: (_) async => bytes,
    ),
  );

  void _share() =>
      _run((bytes) => Printing.sharePdf(bytes: bytes, filename: _fileName));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = _layout.pages;
    final sheets = pages.length * _copies;
    return Scaffold(
      appBar: AppBar(title: const Text('Optik form')),
      body: ListView(
        children: [
          PageFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StepHeader(
                  title: 'Form hazır',
                  help: pages.length == 1
                      ? 'Her öğrenciye bir sayfa. Bir tane yazdırıp fotokopiyle çoğaltabilirsiniz.'
                      : 'Her öğrenciye ${pages.length} sayfa. Sayfaları zımbalamanız yeterli.',
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: FormPreview(page: pages[_page]),
                  ),
                ),
                if (pages.length > 1) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < pages.length; i++)
                          ButtonSegment(
                            value: i,
                            label: Text('Sayfa ${i + 1}'),
                          ),
                      ],
                      selected: {_page},
                      onSelectionChanged: (s) =>
                          setState(() => _page = s.first),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Text('Kaç kopya?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                NumberStepper(
                  value: _copies,
                  min: 1,
                  max: 200,
                  unit: 'kopya',
                  quickPicks: const [1, 20, 30, 40],
                  onChanged: (v) => setState(() => _copies = v),
                ),
                const SizedBox(height: 8),
                Text(
                  _copies == 1
                      ? 'Fotokopi için bir kopya yeterli.'
                      : 'Toplam $sheets sayfa yazdırılacak.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                const InfoBox(
                  text:
                      'Yazdırırken ölçeği "Gerçek boyut" ya da "%100" seçin. '
                      'Köşedeki siyah kareler ve QR kod kesilmemeli; kâğıdı '
                      'okuturken bunlarla hizalanır.',
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
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('İndir'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _print,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.print_rounded),
                  label: const Text('Yazdır'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
