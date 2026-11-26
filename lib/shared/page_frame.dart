import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';

/// Web ve tablette içeriği okunabilir genişlikte ortalar, telefonda tam genişlik kullanır.
class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Kısa, sade bilgi mesajı gösterir.
void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
