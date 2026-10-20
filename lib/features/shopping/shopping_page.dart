import 'package:flutter/material.dart';
class ShoppingPage extends StatelessWidget {
  const ShoppingPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [Text('Einkauf', style: Theme.of(context).textTheme.headlineLarge), const SizedBox(height: 60), Icon(Icons.shopping_cart_outlined, size: 70, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), const Text('Deine Einkaufsliste wird hier erscheinen.', textAlign: TextAlign.center)]);
}
