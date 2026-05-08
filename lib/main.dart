import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DiandiNotesApp());
}

class DiandiColors {
  static const bg = Color(0xFF08080F);
  static const red = Color(0xFFCC2A2A);
  static const blue = Color(0xFF1A4FD6);
  static const deepBlue = Color(0xFF0D1F6E);
  static const panel = Color(0xFF11111B);
}

class Note {
  Note({
    this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String content;
  final DateTime updatedAt;

  Note copyWith({
    int? id,
    String? title,
    String? content,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static Note fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as int,
      title: map['title'] as String,
      content: map['content'] as String,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

class NotesRepository {
  Database? _db;
  bool _memoryMode = kIsWeb;
  int _memoryId = 0;
  final List<Note> _memoryNotes = [];

  Future<void> init() async {
    if (_memoryMode) {
      return;
    }

    try {
      final path = p.join(await getDatabasesPath(), 'diandi_notes.db');
      _db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE notes(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      );
    } on MissingPluginException {
      _memoryMode = true;
    } catch (_) {
      _memoryMode = true;
    }
  }

  Future<List<Note>> getAllNotes() async {
    if (_memoryMode) {
      final copy = [..._memoryNotes];
      copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return copy;
    }

    final db = _db;
    if (db == null) {
      return [];
    }

    final rows = await db.query('notes', orderBy: 'updated_at DESC');
    return rows.map(Note.fromMap).toList();
  }

  Future<Note> saveNote(Note note) async {
    final now = DateTime.now();
    final normalized = note.copyWith(
      updatedAt: now,
      title: note.title.trim(),
      content: note.content.trim(),
    );

    if (_memoryMode) {
      if (normalized.id == null) {
        final created = normalized.copyWith(id: ++_memoryId);
        _memoryNotes.add(created);
        return created;
      }

      final index = _memoryNotes.indexWhere((n) => n.id == normalized.id);
      if (index >= 0) {
        _memoryNotes[index] = normalized;
      }
      return normalized;
    }

    final db = _db;
    if (db == null) {
      return normalized;
    }

    if (normalized.id == null) {
      final id = await db.insert('notes', normalized.toMap()..remove('id'));
      return normalized.copyWith(id: id);
    }

    await db.update(
      'notes',
      normalized.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [normalized.id],
    );
    return normalized;
  }

  Future<void> deleteNote(int id) async {
    if (_memoryMode) {
      _memoryNotes.removeWhere((n) => n.id == id);
      return;
    }

    final db = _db;
    if (db == null) {
      return;
    }
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}

class DiandiNotesApp extends StatelessWidget {
  const DiandiNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Diandi Notes',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: DiandiColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: DiandiColors.blue,
          secondary: DiandiColors.red,
          surface: DiandiColors.panel,
        ),
      ),
      home: const NotesHomePage(),
    );
  }
}

class NotesHomePage extends StatefulWidget {
  const NotesHomePage({super.key});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final NotesRepository _repository = NotesRepository();
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String _search = '';
  List<Note> _notes = [];

  @override
  void initState() {
    super.initState();
    _boot();
    _searchController.addListener(() {
      setState(() {
        _search = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _repository.init();
    await _loadNotes();
  }

  Future<void> _loadNotes() async {
    final notes = await _repository.getAllNotes();
    if (!mounted) {
      return;
    }
    setState(() {
      _notes = notes;
      _isLoading = false;
    });
  }

  List<Note> get _filteredNotes {
    if (_search.isEmpty) {
      return _notes;
    }
    return _notes
        .where(
          (note) => note.title.toLowerCase().contains(_search) || note.content.toLowerCase().contains(_search),
        )
        .toList();
  }

  Future<void> _openEditor({Note? note}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DiandiColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                note == null ? 'Nouvelle note' : 'Modifier la note',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Titre',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contentController,
                maxLines: 7,
                minLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Contenu',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (titleController.text.trim().isEmpty && contentController.text.trim().isEmpty) {
                          return;
                        }
                        await _repository.saveNote(
                          Note(
                            id: note?.id,
                            title: titleController.text.trim().isEmpty ? 'Sans titre' : titleController.text.trim(),
                            content: contentController.text,
                            updatedAt: DateTime.now(),
                          ),
                        );
                        if (!context.mounted) {
                          return;
                        }
                        Navigator.pop(context, true);
                      },
                      child: const Text('Enregistrer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    titleController.dispose();
    contentController.dispose();

    if (saved == true) {
      await _loadNotes();
    }
  }

  Future<void> _delete(Note note) async {
    if (note.id == null) {
      return;
    }
    await _repository.deleteNote(note.id!);
    await _loadNotes();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note supprimée')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diandi Notes'),
        backgroundColor: DiandiColors.bg,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une note...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: DiandiColors.panel,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _filteredNotes.isEmpty
                        ? const Center(
                            child: Text(
                              'Aucune note pour le moment',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _filteredNotes.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final note = _filteredNotes[index];
                              return Container(
                                decoration: BoxDecoration(
                                  color: DiandiColors.panel,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: DiandiColors.deepBlue, width: 1),
                                ),
                                child: ListTile(
                                  onTap: () => _openEditor(note: note),
                                  title: Text(
                                    note.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        note.content,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white70),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _dateFormat.format(note.updatedAt),
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    onPressed: () => _delete(note),
                                    icon: const Icon(Icons.delete_outline, color: DiandiColors.red),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: DiandiColors.blue,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Nouvelle note'),
      ),
    );
  }
}
