import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';

GoRouter buildRouter() => GoRouter(
  routes: [GoRoute(path: '/', builder: (context, state) => const HomeScreen())],
);
