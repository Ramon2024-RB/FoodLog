import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

class _IngredientEntry {
  _IngredientEntry(this.amount, this.unit, this.name);
  final String id =
      DateTime.now().microsecondsSinceEpoch.toString() +
      _nextEntryId().toString();
  String amount;
  String unit;
  String name;

  static int _counter = 0;
  static int _nextEntryId() => _counter++;

  factory _IngredientEntry.fromText(String text) {
    final match = RegExp(
      r'^([0-9]+(?:[.,][0-9]+)?(?:/[0-9]+)?)\s*(g|kg|mg|ml|l|EL|TL|Stk|Stück|Prise|Prisen|Dose|Dosen|Pck|Päckchen)?\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (match == null) return _IngredientEntry('', '', text);
    return _IngredientEntry(
      match.group(1)!,
      match.group(2) ?? '',
      match.group(3)!,
    );
  }

  String get storedText => [
    amount.trim(),
    unit.trim(),
    name.trim(),
  ].where((part) => part.isNotEmpty).join(' ');
}

class _StepEntry {
  _StepEntry(this.text);
  final String id = '${DateTime.now().microsecondsSinceEpoch}_${_nextId()}';
  String text;
  static int _counter = 0;
  static int _nextId() => _counter++;
}

String _scaledIngredient(String text, int original, int target) {
  if (original == target || original <= 0) return text;
  final match = RegExp(r'^([0-9]+(?:[.,][0-9]+)?|[0-9]+/[0-9]+)(.*)$')
      .firstMatch(text.trim());
  if (match == null) return text;
  final raw = match.group(1)!.replaceAll(',', '.');
  final parts = raw.split('/');
  final amount = parts.length == 2
      ? (double.tryParse(parts[1]) ?? 0) == 0
            ? null
            : (double.tryParse(parts[0]) ?? 0) / double.parse(parts[1])
      : double.tryParse(raw);
  if (amount == null || !amount.isFinite) return text;
  final scaled = amount * target / original;
  final formatted = scaled == scaled.roundToDouble()
      ? scaled.toInt().toString()
      : scaled
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '')
            .replaceAll('.', ',');
  return '$formatted${match.group(2)}';
}

class RecipePhoto {
  RecipePhoto({
    required this.id,
    required this.recipeId,
    required this.path,
    required this.stepIndex,
    required this.position,
  });
  final String id;
  final String recipeId;
  final String path;
  final int? stepIndex; // null = gallery; -1 = cover
  final int position;
}

Widget _photoPreview(String path, {double height = 120}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.file(
      File(path),
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        height: height,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined),
      ),
    ),
  );
}

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
    _database!.execute(
      'CREATE TABLE IF NOT EXISTS recipe_photos (id TEXT PRIMARY KEY, recipe_id TEXT NOT NULL, file_path TEXT NOT NULL, step_index INTEGER, position INTEGER NOT NULL DEFAULT 0)',
    );
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

  List<RecipePhoto> getPhotos(String recipeId) {
    return db
        .select(
          'SELECT * FROM recipe_photos WHERE recipe_id = ? ORDER BY position',
          [recipeId],
        )
        .map(
          (row) => RecipePhoto(
            id: row['id'] as String,
            recipeId: row['recipe_id'] as String,
            path: row['file_path'] as String,
            stepIndex: row['step_index'] as int?,
            position: row['position'] as int,
          ),
        )
        .toList();
  }

  void savePhotos(String recipeId, List<RecipePhoto> photos) {
    db.execute('BEGIN TRANSACTION');
    try {
      db.execute('DELETE FROM recipe_photos WHERE recipe_id = ?', [recipeId]);
      for (var i = 0; i < photos.length; i++) {
        final photo = photos[i];
        db.execute(
          'INSERT INTO recipe_photos (id, recipe_id, file_path, step_index, position) VALUES (?, ?, ?, ?, ?)',
          [photo.id, recipeId, photo.path, photo.stepIndex, i],
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteRecipe(String id) {
    db.execute('DELETE FROM recipe_photos WHERE recipe_id = ?', [id]);
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

  Future<String?> _pickAndStorePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (picked == null) return null;
    final directory = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(directory.path, 'recipe_photos'));
    await photosDir.create(recursive: true);
    final extension = p.extension(picked.path).toLowerCase();
    final safeExtension =
        ['.jpg', '.jpeg', '.png', '.heic', '.webp'].contains(extension)
        ? extension
        : '.jpg';
    final destination = p.join(photosDir.path, '${_newId()}$safeExtension');
    await File(picked.path).copy(destination);
    return destination;
  }

  Future<void> _editRecipe([Recipe? existing]) async {
    String title = existing?.title ?? '';
    String description = existing?.description ?? '';
    String minutes = '${existing?.minutes ?? 30}';
    String servings = '${existing?.servings ?? 2}';
    final ingredients = (existing?.ingredients ?? <String>[])
        .map(_IngredientEntry.fromText)
        .toList();
    final steps = (existing?.steps ?? <String>[]).map(_StepEntry.new).toList();
    if (ingredients.isEmpty) ingredients.add(_IngredientEntry('', '', ''));
    if (steps.isEmpty) steps.add(_StepEntry(''));
    final selectedFolders = <String>{
      ...?existing?.folderIds,
      if (existing == null && activeFolderId != null) activeFolderId!,
    };
    final formKey = GlobalKey<FormState>();
    final recipeId = existing?.id ?? _newId();
    final photos = existing == null
        ? <RecipePhoto>[]
        : storage.getPhotos(existing.id);
    Future<void> addPhoto(int? stepIndex, StateSetter updateSheet) async {
      try {
        final path = await _pickAndStorePhoto();
        if (path == null || !mounted) return;
        updateSheet(() {
          if (stepIndex == -1) {
            photos.removeWhere((photo) => photo.stepIndex == -1);
          }
          photos.add(
            RecipePhoto(
              id: _newId(),
              recipeId: recipeId,
              path: path,
              stepIndex: stepIndex,
              position: photos.length,
            ),
          );
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Foto konnte nicht hinzugefügt werden: $e')),
        );
      }
    }

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
              16,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: Form(
              key: formKey,
              child: ListView(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          existing == null
                              ? 'Neues Rezept'
                              : 'Rezept bearbeiten',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Schließen',
                        onPressed: () => Navigator.pop(sheetContext, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
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
                            final n = int.tryParse(value ?? '');
                            return n == null || n < 0 ? 'Ungültige Zeit' : null;
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
                            final n = int.tryParse(value ?? '');
                            return n == null || n < 1 ? 'Mindestens 1' : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Rezeptbilder',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Fotos sind optional und werden offline gespeichert.',
                  ),
                  const SizedBox(height: 12),
                  ...photos
                      .where((photo) => photo.stepIndex == -1)
                      .map(
                        (photo) => Column(
                          children: [
                            _photoPreview(photo.path, height: 170),
                            TextButton.icon(
                              onPressed: () =>
                                  updateSheet(() => photos.remove(photo)),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Titelbild entfernen'),
                            ),
                          ],
                        ),
                      ),
                  OutlinedButton.icon(
                    onPressed: () => addPhoto(-1, updateSheet),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Titelbild auswählen'),
                  ),
                  const SizedBox(height: 10),
                  ...photos
                      .where((photo) => photo.stepIndex == null)
                      .map(
                        (photo) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _photoPreview(photo.path, height: 95),
                              ),
                              IconButton(
                                tooltip: 'Foto entfernen',
                                onPressed: () =>
                                    updateSheet(() => photos.remove(photo)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                  OutlinedButton.icon(
                    onPressed: () => addPhoto(null, updateSheet),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Weiteres Foto hinzufügen'),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Zutaten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text('Menge, Einheit und Zutat getrennt eintragen.'),
                  const SizedBox(height: 12),
                  ...ingredients.map(
                    (ingredient) => Padding(
                      key: ValueKey(ingredient.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: ingredient.amount,
                                  onChanged: (v) => ingredient.amount = v,
                                  decoration: const InputDecoration(
                                    labelText: 'Menge',
                                    hintText: '250',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  initialValue: ingredient.unit,
                                  onChanged: (v) => ingredient.unit = v,
                                  decoration: const InputDecoration(
                                    labelText: 'Einheit',
                                    hintText: 'g',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Zutat entfernen',
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () => updateSheet(
                                  () => ingredients.remove(ingredient),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: ingredient.name,
                            onChanged: (v) => ingredient.name = v,
                            decoration: const InputDecoration(
                              labelText: 'Zutat',
                              hintText: 'Mehl',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => updateSheet(
                      () => ingredients.add(_IngredientEntry('', '', '')),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Zutat hinzufügen'),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Zubereitung',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  ...steps.asMap().entries.map(
                    (entry) => Padding(
                      key: ValueKey(entry.value.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  right: 10,
                                ),
                                child: CircleAvatar(
                                  radius: 15,
                                  child: Text('${entry.key + 1}'),
                                ),
                              ),
                              Expanded(
                                child: TextFormField(
                                  initialValue: entry.value.text,
                                  onChanged: (value) =>
                                      entry.value.text = value,
                                  minLines: 2,
                                  maxLines: 5,
                                  decoration: const InputDecoration(
                                    labelText: 'Arbeitsschritt',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Schritt entfernen',
                                onPressed: () => updateSheet(() {
                                  final removedIndex = entry.key;
                                  steps.remove(entry.value);
                                  photos.removeWhere(
                                    (photo) => photo.stepIndex == removedIndex,
                                  );
                                  for (var i = 0; i < photos.length; i++) {
                                    final photo = photos[i];
                                    if (photo.stepIndex != null &&
                                        photo.stepIndex! > removedIndex) {
                                      photos[i] = RecipePhoto(
                                        id: photo.id,
                                        recipeId: photo.recipeId,
                                        path: photo.path,
                                        stepIndex: photo.stepIndex! - 1,
                                        position: photo.position,
                                      );
                                    }
                                  }
                                }),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            ],
                          ),
                          ...photos
                              .where((photo) => photo.stepIndex == entry.key)
                              .map(
                                (photo) => Row(
                                  children: [
                                    Expanded(
                                      child: _photoPreview(
                                        photo.path,
                                        height: 110,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Schrittfoto entfernen',
                                      onPressed: () => updateSheet(
                                        () => photos.remove(photo),
                                      ),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => addPhoto(entry.key, updateSheet),
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: const Text('Foto zu diesem Schritt'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        updateSheet(() => steps.add(_StepEntry(''))),
                    icon: const Icon(Icons.add),
                    label: const Text('Schritt hinzufügen'),
                  ),
                  const SizedBox(height: 22),
                  Text('Ordner', style: Theme.of(context).textTheme.titleLarge),
                  if (folders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Noch keine Ordner vorhanden. Das Rezept kann trotzdem gespeichert werden.',
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
                          id: recipeId,
                          title: title.trim(),
                          description: description.trim(),
                          ingredients: ingredients
                              .where((e) => e.name.trim().isNotEmpty)
                              .map((e) => e.storedText)
                              .toList(),
                          steps: steps
                              .map((e) => e.text.trim())
                              .where((e) => e.isNotEmpty)
                              .toList(),
                          minutes: int.parse(minutes),
                          servings: int.parse(servings),
                          folderIds: selectedFolders.toList(),
                          favorite: existing?.favorite ?? false,
                        ),
                      );
                      storage.savePhotos(recipeId, photos);
                      Navigator.pop(sheetContext, true);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Rezept speichern'),
                  ),
                  const SizedBox(height: 12),
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
    int displayedServings = recipe.servings;
    final photos = storage.getPhotos(recipe.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => FractionallySizedBox(
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
                    tooltip: 'Bearbeiten',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _editRecipe(recipe);
                    },
                  ),
                  IconButton(
                    tooltip: 'Löschen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _deleteRecipe(recipe);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...photos
                  .where((photo) => photo.stepIndex == -1)
                  .map((photo) => _photoPreview(photo.path, height: 230)),
              if (recipe.description.isNotEmpty) Text(recipe.description),
              const SizedBox(height: 12),
              Chip(
                avatar: const Icon(Icons.schedule, size: 18),
                label: Text('${recipe.minutes} Min.'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Portionen',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Weniger Portionen',
                    onPressed: displayedServings > 1
                        ? () => updateSheet(() => displayedServings--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '$displayedServings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    tooltip: 'Mehr Portionen',
                    onPressed: () => updateSheet(() => displayedServings++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const Text(
                'Die Zutatenmengen werden für die gewählte Portionszahl angepasst.',
              ),
              const SizedBox(height: 20),
              Text('Zutaten', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (recipe.ingredients.isEmpty)
                const Text('Keine Zutaten eingetragen'),
              ...recipe.ingredients.map(
                (ingredient) => ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(
                    _scaledIngredient(
                      ingredient,
                      recipe.servings,
                      displayedServings,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (photos.any((photo) => photo.stepIndex == null)) ...[
                const SizedBox(height: 16),
                Text(
                  'Weitere Bilder',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...photos
                    .where((photo) => photo.stepIndex == null)
                    .map(
                      (photo) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _photoPreview(photo.path, height: 200),
                      ),
                    ),
              ],
              const SizedBox(height: 20),
              Text(
                'Zubereitung',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (recipe.steps.isEmpty)
                const Text('Keine Zubereitungsschritte eingetragen'),
              ...recipe.steps.asMap().entries.map(
                (entry) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        radius: 15,
                        child: Text('${entry.key + 1}'),
                      ),
                      title: Text(entry.value),
                      contentPadding: EdgeInsets.zero,
                    ),
                    ...photos
                        .where((photo) => photo.stepIndex == entry.key)
                        .map(
                          (photo) => Padding(
                            padding: const EdgeInsets.only(
                              left: 40,
                              bottom: 10,
                            ),
                            child: _photoPreview(photo.path, height: 170),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recipeCard(Recipe recipe) {
    final cover = storage
        .getPhotos(recipe.id)
        .where((photo) => photo.stepIndex == -1)
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: cover == null
            ? const CircleAvatar(child: Icon(Icons.restaurant_menu))
            : SizedBox(
                width: 56,
                height: 56,
                child: _photoPreview(cover.path, height: 56),
              ),
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
