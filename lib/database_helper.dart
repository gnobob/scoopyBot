import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('scoopy_logs.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT NOT NULL,
        status TEXT NOT NULL,
        image BLOB
      )
    ''');
  }

  Future<void> insertLog(String status, Uint8List? imageBytes) async {
    final db = await instance.database;
    await db.insert('logs', {
      'time': DateTime.now().toString(),
      'status': status,
      'image': imageBytes,
    });
  }

  Future<List<Map<String, dynamic>>> fetchLogsByDate(DateTime date) async {
    final db = await instance.database;
    String dateStr = date.toString().split(' ')[0]; // YYYY-MM-DD
    return await db.query(
      'logs',
      where: "time LIKE ?",
      whereArgs: ['$dateStr%'],
      orderBy: "time DESC",
    );
  }
}