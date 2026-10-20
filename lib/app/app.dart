import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import '../features/home/home_page.dart';
import '../features/recipes/recipes_page.dart';
import '../features/pantry/pantry_page.dart';
import '../features/shopping/shopping_page.dart';
import '../features/meal_planner/meal_planner_page.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => FoodLogShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomePage()),
        GoRoute(path: '/recipes', builder: (_, _) => const RecipesPage()),
        GoRoute(path: '/pantry', builder: (_, _) => const PantryPage()),
        GoRoute(path: '/shopping', builder: (_, _) => const ShoppingPage()),
        GoRoute(path: '/plan', builder: (_, _) => const MealPlannerPage()),
      ],
    ),
  ],
);

class FoodLogApp extends StatelessWidget {
  const FoodLogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'FoodLog',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      );
}

class FoodLogShell extends StatelessWidget {
  const FoodLogShell({super.key, required this.child});
  final Widget child;

  static const _paths = ['/', '/recipes', '/pantry', '/shopping', '/plan'];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _paths.indexOf(location);
    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) => context.go(_paths[i]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Start'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Rezepte'),
          NavigationDestination(icon: Icon(Icons.kitchen_outlined), selectedIcon: Icon(Icons.kitchen), label: 'Vorrat'),
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: 'Einkauf'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Plan'),
        ],
      ),
    );
  }
}
