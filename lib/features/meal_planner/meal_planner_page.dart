import 'package:flutter/material.dart';
class MealPlannerPage extends StatelessWidget {
  const MealPlannerPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [Text('Essensplan', style: Theme.of(context).textTheme.headlineLarge), const SizedBox(height: 60), Icon(Icons.calendar_month_outlined, size: 70, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), const Text('Hier planst du später eure Mahlzeiten.', textAlign: TextAlign.center)]);
}
