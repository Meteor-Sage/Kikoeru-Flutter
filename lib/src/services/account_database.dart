import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/account.dart';

class AccountDatabase {
  static final AccountDatabase instance = AccountDatabase._init();
  static Database? _database;

  AccountDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('accounts.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Initialize FFI for desktop platforms
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String dbPath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // For desktop platforms, use application documents directory
      final appDocDir = await getApplicationDocumentsDirectory();
      dbPath = join(appDocDir.path, 'KikoFlu');
      // Create directory if it doesn't exist
      await Directory(dbPath).create(recursive: true);
    } else {
      // For mobile platforms, use default path
      dbPath = await getDatabasesPath();
    }
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        host TEXT NOT NULL,
        isActive INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT,
        lastUsedAt TEXT
      )
    ''');
  }

  Future<Account> createAccount(Account account) async {
    final db = await database;

    // Deactivate all other accounts if this one is active
    if (account.isActive) {
      await db.update(
        'accounts',
        {'isActive': 0},
        where: 'isActive = ?',
        whereArgs: [1],
      );
    }

    final id = await db.insert('accounts', account.toMap());
    return account.copyWith(id: id);
  }

  Future<Account?> getAccount(int id) async {
    final db = await database;

    final maps = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Account.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final maps = await db.query('accounts', orderBy: 'lastUsedAt DESC');
    return maps.map((map) => Account.fromMap(map)).toList();
  }

  Future<Account?> getActiveAccount() async {
    final db = await database;

    final maps = await db.query(
      'accounts',
      where: 'isActive = ?',
      whereArgs: [1],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return Account.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateAccount(Account account) async {
    final db = await database;

    // If setting this account as active, deactivate others
    if (account.isActive) {
      await db.update(
        'accounts',
        {'isActive': 0},
        where: 'isActive = ? AND id != ?',
        whereArgs: [1, account.id],
      );
    }

    return await db.update(
      'accounts',
      account.toMap(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    return await db.delete(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> setActiveAccount(int id) async {
    final db = await database;

    // Deactivate all accounts
    await db.update('accounts', {'isActive': 0});

    // Activate the selected account and update lastUsedAt
    return await db.update(
      'accounts',
      {
        'isActive': 1,
        'lastUsedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
