import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('FoodLog', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Deine Küche. Dein Essen. Dein Plan.'),
          const SizedBox(height: 28),
          Text('Was essen wir heute?', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome, size: 36),
              const SizedBox(height: 12),
              const Text('Hier erscheinen später passende Rezeptvorschläge aus euren Vorräten.'),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: () => context.go('/recipes'), icon: const Icon(Icons.menu_book), label: const Text('Rezepte ansehen')),
            ]),
          )),
          const SizedBox(height: 20),
          Text('Schnellzugriff', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Card(child: ListTile(leading: const Icon(Icons.kitchen_outlined), title: const Text('Mein Vorrat'), trailing: const Icon(Icons.chevron_right), onTap: () => context.go('/pantry'))),
          Card(child: ListTile(leading: const Icon(Icons.shopping_cart_outlined), title: const Text('Einkaufsliste'), trailing: const Icon(Icons.chevron_right), onTap: () => context.go('/shopping'))),
        ],
      );
}
