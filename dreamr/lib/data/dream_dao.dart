// data/dream_dao.dart
import 'dart:async';
import 'package:dreamr/models/dream.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DreamDao {
  static final DreamDao _instance = DreamDao._internal();
  factory DreamDao() => _instance;
  DreamDao._internal();

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'dreamr.db');
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE dreams (
            id INTEGER PRIMARY KEY,
            user_id INTEGER,
            text TEXT,
            analysis TEXT,
            summary TEXT,
            tone TEXT,
            image_prompt TEXT,
            hidden INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            image_file TEXT,
            image_tile TEXT,
            interpreter_id INTEGER,
            interpreter_name TEXT,
            interpreter_icon TEXT
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_dreams_created_at ON dreams(created_at DESC)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_dreams_hidden ON dreams(hidden)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE dreams ADD COLUMN interpreter_id INTEGER');
          await db.execute('ALTER TABLE dreams ADD COLUMN interpreter_name TEXT');
          await db.execute('ALTER TABLE dreams ADD COLUMN interpreter_icon TEXT');
        }
      },
    );
    return _db!;
  }

  Map<String, Object?> _toMap(Dream d) => {
    'id': d.id,
    'user_id': d.userId,
    'text': d.text,
    'analysis': d.analysis,
    'summary': d.summary,
    'tone': d.tone,
    'image_prompt': d.imagePrompt,
    'hidden': d.hidden ? 1 : 0,
    'created_at': d.createdAt.toIso8601String(),
    'image_file': d.imageFile,
    'image_tile': d.imageTile,
    'interpreter_id': d.interpreterId,
    'interpreter_name': d.interpreterName,
    'interpreter_icon': d.interpreterIcon,
  };

  Dream _fromMap(Map<String, Object?> m) {
    return Dream(
      id: (m['id'] as num).toInt(),
      userId: (m['user_id'] as num?)?.toInt() ?? 0,
      text: (m['text'] as String?) ?? '',
      analysis: (m['analysis'] as String?) ?? '',
      summary: (m['summary'] as String?) ?? '',
      tone: (m['tone'] as String?) ?? '',
      imagePrompt: (m['image_prompt'] as String?) ?? '',
      hidden: (m['hidden'] as int? ?? 0) == 1,
      createdAt: DateTime.parse((m['created_at'] as String)),
      imageFile: m['image_file'] as String?,
      imageTile: m['image_tile'] as String?,
      interpreterId: (m['interpreter_id'] as num?)?.toInt(),
      interpreterName: m['interpreter_name'] as String?,
      interpreterIcon: m['interpreter_icon'] as String?,
    );
  }

  Future<void> upsertMany(List<Dream> dreams) async {
    final db = await _open();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final d in dreams) {
        batch.insert(
          'dreams',
          _toMap(d),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsert(Dream d) async {
    final db = await _open();
    await db.insert(
      'dreams',
      _toMap(d),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Dream>> getAll({bool includeHidden = false}) async {
    final db = await _open();
    final rows = await db.query(
      'dreams',
      where: includeHidden ? null : 'hidden = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromMap).toList();
  }

  Future<void> deleteAll() async {
    final db = await _open();
    await db.delete('dreams');
  }
}
