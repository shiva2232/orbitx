import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'orbitx.db');

    if (!await File(path).exists()) {
      await _copyDatabase(path);
    }

    _db = await openDatabase(path);
    return _db!;
  }

  static Future<void> _copyDatabase(String path) async {
    final data = await rootBundle.load(
      'assets/db/orbitx.db',
    );

    final bytes = data.buffer.asUint8List();

    await File(path).writeAsBytes(
      bytes,
      flush: true,
    );
  }
}