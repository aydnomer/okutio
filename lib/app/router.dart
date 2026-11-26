import 'package:go_router/go_router.dart';

import '../features/answer_key/answer_key_screen.dart';
import '../features/exam_detail/exam_detail_screen.dart';
import '../features/exam_wizard/exam_wizard_screen.dart';
import '../features/home/home_screen.dart';
import '../features/open_questions/open_questions_screen.dart';
import '../features/print_form/print_form_screen.dart';

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
      routes: [
        GoRoute(
          path: 'anahtar',
          builder: (context, state) =>
              AnswerKeyScreen(examId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'acik',
          builder: (context, state) =>
              OpenQuestionsScreen(examId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'form',
          builder: (context, state) =>
              PrintFormScreen(examId: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);
