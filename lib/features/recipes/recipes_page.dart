import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class Recipe {
  Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.ingredients,
    required this.steps,
    required this.minutes,
    required this.servings,
    required this.folderIds,
    required this.favorite,
  });

  final String id;
  final String title;
  final String description;
  final List<String> ingredients;
  final List<String> steps;
  final int minutes;
  final int servings;
  final List<String> folderIds;
  final bool favorite;
}

class RecipeFolder {
  RecipeFolder({required this.id, required this.name, required this.parentId});

  final String id;
  final String name;
  final String? parentId;
}

class RecipeStorage {
  sqlite.Database? _database;

  Future<void> initialize() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = p.join(directory.path, 'foodlog_recipes.db');

    _database = sqlite.sqlite3.open(file);

    _database!.execute('''
      CREATE TABLE IF NOT EXISTS recipe_folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT
      )
    ''');

    _database!.execute('''
      CREATE TABLE IF NOT EXISTS recipes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        ingredients TEXT NOT NULL,
        steps TEXT NOT NULL,
        minutes INTEGER NOT NULL,
        servings INTEGER NOT NULL,
        folder_ids TEXT NOT NULL,
        favorite INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  sqlite.Database get db {
    final database = _database;
    if (database == null) {
      throw StateError('Die Rezeptdatenbank ist nicht geöffnet.');
    }
    return database;
  }

  List<RecipeFolder> getFolders() {
    return db
        .select('SELECT * FROM recipe_folders ORDER BY name COLLATE NOCASE')
        .map((row) {
          return RecipeFolder(
            id: row['id'] as String,
            name: row['name'] as String,
            parentId: row['parent_id'] as String?,
          );
        })
        .toList();
  }

  List<Recipe> getRecipes() {
    return db.select('SELECT * FROM recipes ORDER BY title COLLATE NOCASE').map(
      (row) {
        return Recipe(
          id: row['id'] as String,
          title: row['title'] as String,
          description: row['description'] as String,
          ingredients: List<String>.from(
            jsonDecode(row['ingredients'] as String) as List,
          ),
          steps: List<String>.from(jsonDecode(row['steps'] as String) as List),
          minutes: row['minutes'] as int,
          servings: row['servings'] as int,
          folderIds: List<String>.from(
            jsonDecode(row['folder_ids'] as String) as List,
          ),
          favorite: (row['favorite'] as int) == 1,
        );
      },
    ).toList();
  }

  void saveFolder(RecipeFolder folder) {
    db.execute(
      '''
      INSERT OR REPLACE INTO recipe_folders
      (id, name, parent_id)
      VALUES (?, ?, ?)
      ''',
      [folder.id, folder.name, folder.parentId],
    );
  }

  void saveRecipe(Recipe recipe) {
    db.execute(
      '''
      INSERT OR REPLACE INTO recipes
      (id, title, description, ingredients, steps,
       minutes, servings, folder_ids, favorite)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        recipe.id,
        recipe.title,
        recipe.description,
        jsonEncode(recipe.ingredients),
        jsonEncode(recipe.steps),
        recipe.minutes,
        recipe.servings,
        jsonEncode(recipe.folderIds),
        recipe.favorite ? 1 : 0,
      ],
    );
  }

  void deleteRecipe(String id) {
    db.execute('DELETE FROM recipes WHERE id = ?', [id]);
  }

  void dispose() {
    _database?.close();
    _database = null;
  }
}

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  final RecipeStorage storage = RecipeStorage();

  List<Recipe> recipes = [];
  List<RecipeFolder> folders = [];

  bool loading = true;
  String? error;
  int selected = 0;
  String? activeFolderId;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    storage.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await storage.initialize();
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  void _refresh() {
    setState(() {
      recipes = storage.getRecipes();
      folders = storage.getFolders();
      loading = false;
    });
  }

  String _newId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  Future<void> _createFolder() async {
    String folderName = '';
    String? parentId = activeFolderId;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Neuer Ordner'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                autofocus: true,
                initialValue: folderName,
                onChanged: (value) => folderName = value,
                decoration: const InputDecoration(
                  labelText: 'Ordnername',
                  hintText: 'z. B. Kuchen',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: parentId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Übergeordneter Ordner',
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Keiner – Hauptordner'),
                  ),
                  ...folders.map(
                    (folder) => DropdownMenuItem(
                      value: folder.id,
                      child: Text(folder.name),
                    ),
                  ),
                ],
                onChanged: (value) => updateDialog(() {
                  parentId = value == null || value.isEmpty ? null : value;
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () {
                if (folderName.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (result == true) {
      storage.saveFolder(
        RecipeFolder(id: _newId(), name: folderName.trim(), parentId: parentId),
      );
      _refresh();
    }
  }

  Future<void> _editRecipe([Recipe? existing]) async {
    String title = existing?.title ?? '';
    String description = existing?.description ?? '';
    String ingredients = existing?.ingredients.join('\n') ?? '';
    String steps = existing?.steps.join('\n') ?? '';
    String minutes = '${existing?.minutes ?? 30}';
    String servings = '${existing?.servings ?? 2}';

    final selectedFolders = <String>{
      ...?existing?.folderIds,
      if (existing == null && activeFolderId != null) activeFolderId!,
    };
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => FractionallySizedBox(
          heightFactor: 0.95,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 20,
            ),
            child: Form(
              key: formKey,
              child: ListView(
                children: [
                  Text(
                    existing == null ? 'Neues Rezept' : 'Rezept bearbeiten',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    initialValue: title,
                    onChanged: (value) => title = value,
                    decoration: const InputDecoration(
                      labelText: 'Rezeptname *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Bitte einen Namen eingeben'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: description,
                    onChanged: (value) => description = value,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: minutes,
                          onChanged: (value) => minutes = value,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minuten',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final number = int.tryParse(value ?? '');
                            return number == null || number < 0
                                ? 'Ungültige Zeit'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: servings,
                          onChanged: (value) => servings = value,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Portionen',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final number = int.tryParse(value ?? '');
                            return number == null || number < 1
                                ? 'Mindestens 1'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Zutaten',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('Eine Zutat pro Zeile, z. B. 250 g Mehl'),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: ingredients,
                    onChanged: (value) => ingredients = value,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: '250 g Mehl\n2 Eier\n100 ml Milch',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Zubereitung',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('Ein Arbeitsschritt pro Zeile'),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: steps,
                    onChanged: (value) => steps = value,
                    minLines: 4,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      hintText: 'Backofen vorheizen\nZutaten vermischen\n30 Minuten backen',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ordner',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (folders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Noch keine Ordner angelegt. '
                        'Du kannst das Rezept trotzdem speichern.',
                      ),
                    ),
                  ...folders.map(
                    (folder) => CheckboxListTile(
                      title: Text(folder.name),
                      value: selectedFolders.contains(folder.id),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (checked) => updateSheet(() {
                        if (checked == true) {
                          selectedFolders.add(folder.id);
                        } else {
                          selectedFolders.remove(folder.id);
                        }
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      storage.saveRecipe(
                        Recipe(
                          id: existing?.id ?? _newId(),
                          title: title.trim(),
                          description: description.trim(),
                          ingredients: ingredients
                              .split('\n')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList(),
                          steps: steps
                              .split('\n')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList(),
                          minutes: int.parse(minutes),
                          servings: int.parse(servings),
                          folderIds: selectedFolders.toList(),
                          favorite: existing?.favorite ?? false,
                        ),
                      );
                      Navigator.pop(sheetContext, true);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Rezept speichern'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!mounted) return;
    if (result == true) _refresh();
  }

  void _toggleFavorite(Recipe recipe) {
    storage.saveRecipe(
      Recipe(
        id: recipe.id,
        title: recipe.title,
        description: recipe.description,
        ingredients: recipe.ingredients,
        steps: recipe.steps,
        minutes: recipe.minutes,
        servings: recipe.servings,
        folderIds: recipe.folderIds,
        favorite: !recipe.favorite,
      ),
    );
    _refresh();
  }

  Future<void> _deleteRecipe(Recipe recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rezept löschen?'),
        content: Text('Möchtest du „${recipe.title}“ wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      storage.deleteRecipe(recipe.id);
      _refresh();
    }
  }

  void _showRecipe(Recipe recipe) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.9,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    recipe.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _editRecipe(recipe);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _deleteRecipe(recipe);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recipe.description.isNotEmpty) Text(recipe.description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                Chip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text('${recipe.minutes} Min.'),
                ),
                Chip(
                  avatar: const Icon(Icons.people_outline, size: 18),
                  label: Text('${recipe.servings} Portionen'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Zutaten', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (recipe.ingredients.isEmpty)
              const Text('Keine Zutaten eingetragen'),
            ...recipe.ingredients.map(
              (ingredient) => ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(ingredient),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 20),
            Text('Zubereitung', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (recipe.steps.isEmpty)
              const Text('Keine Zubereitungsschritte eingetragen'),
            ...recipe.steps.asMap().entries.map(
              (entry) => ListTile(
                leading: CircleAvatar(
                  radius: 15,
                  child: Text('${entry.key + 1}'),
                ),
                title: Text(entry.value),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recipeCard(Recipe recipe) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: const CircleAvatar(child: Icon(Icons.restaurant_menu)),
        title: Text(
          recipe.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${recipe.minutes} Min. · ${recipe.servings} Portionen'),
        trailing: IconButton(
          icon: Icon(
            recipe.favorite ? Icons.favorite : Icons.favorite_border,
            color: recipe.favorite ? Colors.red : null,
          ),
          onPressed: () => _toggleFavorite(recipe),
        ),
        onTap: () => _showRecipe(recipe),
      ),
    );
  }

  Widget _folderCard(RecipeFolder folder) {
    final count = recipes
        .where((recipe) => recipe.folderIds.contains(folder.id))
        .length;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() => activeFolderId = folder.id);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_outlined, size: 32),
              const SizedBox(height: 10),
              Text(
                folder.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '$count Rezepte',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('Datenbankfehler:\n$error'),
        ),
      );
    }

    final activeFolder = activeFolderId == null
        ? null
        : folders.where((f) => f.id == activeFolderId).firstOrNull;

    final visibleFolders = folders
        .where((folder) => folder.parentId == activeFolderId)
        .toList();

    final visibleRecipes = recipes.where((recipe) {
      if (selected == 2 && !recipe.favorite) return false;
      if (selected == 0 && activeFolderId != null) {
        return recipe.folderIds.contains(activeFolderId);
      }
      return true;
    }).toList();

    return Scaffold(
      floatingActionButton: selected == 0
          ? FloatingActionButton.extended(
              onPressed: () => _editRecipe(),
              icon: const Icon(Icons.add),
              label: const Text('Rezept'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        children: [
          Text(
            'Rezepte',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Meine')),
              ButtonSegment(value: 1, label: Text('Entdecken')),
              ButtonSegment(value: 2, label: Text('Favoriten')),
            ],
            selected: {selected},
            onSelectionChanged: (value) {
              setState(() => selected = value.first);
            },
          ),
          const SizedBox(height: 22),
          if (selected == 1)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('Neue Rezepte entdecken – folgt später.'),
              ),
            )
          else ...[
            if (selected == 0) ...[
              if (activeFolder != null)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      activeFolderId = activeFolder.parentId;
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: Text('Zurück aus ${activeFolder.name}'),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      activeFolder?.name ?? 'Meine Ordner',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ordner erstellen',
                    onPressed: _createFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (visibleFolders.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.45,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: visibleFolders.length,
                  itemBuilder: (context, index) =>
                      _folderCard(visibleFolders[index]),
                ),
              const SizedBox(height: 18),
            ],
            Text(
              selected == 2 ? 'Meine Favoriten' : 'Meine Rezepte',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (visibleRecipes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: Text(
                    selected == 2
                        ? 'Noch keine Favoriten vorhanden.'
                        : 'Hier erscheinen deine Rezepte.',
                  ),
                ),
              ),
            ...visibleRecipes.map(_recipeCard),
          ],
        ],
      ),
    );
  }
}
