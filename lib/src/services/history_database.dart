import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/history_record.dart';

class HistoryDatabase {
  static final HistoryDatabase instance = HistoryDatabase._init();
  static Database? _database;

  HistoryDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final String dbPath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final appDocDir = await getApplicationDocumentsDirectory();
      dbPath = join(appDocDir.path, 'KikoFlu');
      await Directory(dbPath).create(recursive: true);
    } else {
      dbPath = await getDatabasesPath();
    }
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE history (
        work_id INTEGER PRIMARY KEY,
        work_json TEXT NOT NULL,
        last_played_time INTEGER NOT NULL,
        last_track_json TEXT,
        last_position_ms INTEGER DEFAULT 0,
        playlist_index INTEGER DEFAULT 0,
        playlist_total INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Version 2: Add playlist_index and playlist_total
      // Since we are in dev, we can just drop and recreate or alter table
      // But to be safe and simple for now, let's try adding columns if they don't exist
      // Or just drop table if it's easier for dev environment
      // Given the previous code dropped table for version < 2, let's stick with that pattern for now
      // or implement proper migration.

      // Let's try to add columns instead of dropping to preserve history if possible
      try {
        await db.execute(
            'ALTER TABLE history ADD COLUMN playlist_index INTEGER DEFAULT 0');
        await db.execute(
            'ALTER TABLE history ADD COLUMN playlist_total INTEGER DEFAULT 0');
      } catch (e) {
        // If columns already exist or error, ignore (or handle appropriately)
        print('Migration error (ignored): $e');
      }
    }
  }

  Future<void> addOrUpdate(HistoryRecord record) async {
    final db = await instance.database;
    await db.insert(
      'history',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HistoryRecord>> getAllHistory() async {
    final db = await instance.database;
    final result = await db.query('history', orderBy: 'last_played_time DESC');
    return result.map((json) => HistoryRecord.fromMap(json)).toList();
  }

  Future<void> delete(int workId) async {
    final db = await instance.database;
    await db.delete(
      'history',
      where: 'work_id = ?',
      whereArgs: [workId],
    );
  }

  Future<void> clear() async {
    final db = await instance.database;
    await db.delete('history');
  }
}
