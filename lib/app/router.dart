import 'package:go_router/go_router.dart';

import '../features/exam_detail/exam_detail_screen.dart';
import '../features/exam_wizard/exam_wizard_screen.dart';
import '../features/home/home_screen.dart';

GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/sinav/yeni',
      builder: (context, state) => const ExamWizardScreen(),
    ),
    GoRoute(
      path: '/sinav/:id',
      builder: (context, state) =>
          ExamDetailScreen(examId: state.pathParameters['id']!),
    ),
  ],
);
