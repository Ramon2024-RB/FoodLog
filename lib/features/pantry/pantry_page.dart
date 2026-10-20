import 'package:flutter/material.dart';
class PantryPage extends StatelessWidget {
  const PantryPage({super.key});
  @override
  Widget build(BuildContext context) => const _EmptyPage(title: 'Vorrat', icon: Icons.kitchen_outlined, description: 'Hier verwaltest du bald Lebensmittel, Mengen und Haltbarkeit.');
}
class _EmptyPage extends StatelessWidget {
  const _EmptyPage({required this.title, required this.icon, required this.description});
  final String title;
  final IconData icon;
  final String description;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [Text(title, style: Theme.of(context).textTheme.headlineLarge), const SizedBox(height: 60), Icon(icon, size: 70, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), Text(description, textAlign: TextAlign.center)]);
}
