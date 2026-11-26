import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../page_frame.dart';

/// Adresteki sınav yoksa (silinmiş ya da yanlış bağlantı) gösterilir.
class ExamNotFound extends StatelessWidget {
  const ExamNotFound({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: PageFrame(
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Icon(Icons.search_off_rounded, size: 56),
            const SizedBox(height: 12),
            const Text('Bu sınav bulunamadı. Silinmiş olabilir.'),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('Ana ekrana dön'),
            ),
          ],
        ),
      ),
    );
  }
}
