import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

class NoteService {
  static const String _notesKey = 'bible_notes';
  final Map<String, Note> _notesCache = {};
  bool _isLoaded = false;

  // Singleton pattern
  static NoteService? _instance;
  static NoteService get instance {
    _instance ??= NoteService._internal();
    return _instance!;
  }

  NoteService._internal();

  String _noteKey(String bookName, int chapter, int verse) =>
      '${bookName}_${chapter}_$verse';

  Future<void> loadNotes() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = prefs.getString(_notesKey);

      if (notesJson != null) {
        final decoded = json.decode(notesJson) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          final note = Note.fromJson(value as Map<String, dynamic>);
          _notesCache[note.key] = note;
        });
      }
      _isLoaded = true;
    } catch (e) {
      throw Exception('Failed to load notes: $e');
    }
  }

  Future<Note?> getNote(String bookName, int chapter, int verse) async {
    await loadNotes();
    final key = _noteKey(bookName, chapter, verse);
    return _notesCache[key];
  }

  Future<void> saveNote(
    String bookName,
    int chapter,
    int verse,
    String text,
  ) async {
    await loadNotes();
    final key = _noteKey(bookName, chapter, verse);
    final now = DateTime.now();

    final note =
        _notesCache[key]?.copyWith(text: text, updatedAt: now) ??
        Note(
          bookName: bookName,
          chapter: chapter,
          verse: verse,
          text: text,
          createdAt: now,
          updatedAt: now,
        );

    _notesCache[key] = note;
    await _persistNotes();
  }

  Future<void> deleteNote(String bookName, int chapter, int verse) async {
    await loadNotes();
    final key = _noteKey(bookName, chapter, verse);
    _notesCache.remove(key);
    await _persistNotes();
  }

  bool hasNote(String bookName, int chapter, int verse) {
    final key = _noteKey(bookName, chapter, verse);
    return _notesCache.containsKey(key) &&
        _notesCache[key]!.text.trim().isNotEmpty;
  }

  bool hasAnyNotes() {
    return _notesCache.values.any((note) => note.text.trim().isNotEmpty);
  }

  Future<void> _persistNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = <String, dynamic>{};
      _notesCache.forEach((key, note) {
        notesJson[key] = note.toJson();
      });
      await prefs.setString(_notesKey, json.encode(notesJson));
    } catch (e) {
      throw Exception('Failed to save notes: $e');
    }
  }

  List<Note> getAllNotes() {
    return _notesCache.values.toList()..sort((a, b) {
      final aKey = '${a.bookName}_${a.chapter}_${a.verse}';
      final bKey = '${b.bookName}_${b.chapter}_${b.verse}';
      return aKey.compareTo(bKey);
    });
  }
}
