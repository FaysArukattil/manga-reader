import 'package:shared_preferences/shared_preferences.dart';

class CategoryStore {
  CategoryStore._();

  static const String _key = 'shelfmark_custom_categories_v1';
  static const List<String> defaultCategories = [
    'Favorites',
  ];

  static Future<List<String>> getCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key);
      if (list != null && list.isNotEmpty) {
        return List<String>.from(list);
      }
    } catch (_) {}
    return List<String>.from(defaultCategories);
  }

  static Future<void> saveCategories(List<String> categories) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, categories);
    } catch (_) {}
  }

  static Future<List<String>> addCategory(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return getCategories();
    final current = await getCategories();
    if (!current.contains(clean)) {
      current.add(clean);
      await saveCategories(current);
    }
    return current;
  }

  static Future<List<String>> removeCategory(String name) async {
    if (name.toLowerCase() == 'favorites' || name.toLowerCase() == 'favourite') {
      return getCategories();
    }
    final current = await getCategories();
    current.remove(name);
    await saveCategories(current);
    return current;
  }

  static Future<List<String>> renameCategory(
      String oldName, String newName) async {
    if (oldName.toLowerCase() == 'favorites' || oldName.toLowerCase() == 'favourite') {
      return getCategories();
    }
    final clean = newName.trim();
    if (clean.isEmpty) return getCategories();
    final current = await getCategories();
    final idx = current.indexOf(oldName);
    if (idx >= 0) {
      current[idx] = clean;
      await saveCategories(current);
    }
    return current;
  }
}
