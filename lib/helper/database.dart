import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:orbitx/models/automation_model.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final instance = DatabaseHelper._();

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


  Future<Database> initialize() async {
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
    final data = await rootBundle.load('assets/db/orbitx.db');

    final bytes = data.buffer.asUint8List();

    await File(path).writeAsBytes(bytes, flush: true);
  }

  Database get db {
    if (_db == null) {
      throw Exception("Repository not initialized");
    }

    return _db!;
  }

  Future<int> saveRule({
    required String name,
    required bool enabled,
    required DateTime startAt,
    required String periodicity,
    required Map<String, dynamic> rule,
  }) async {
    final now = DateTime.now().toIso8601String();

    return await db.insert("automation_rules", {
      "name": name,
      "enabled": enabled ? 1 : 0,
      "start_at": startAt.toIso8601String(),
      "periodicity": periodicity,
      "rule_json": jsonEncode(rule),
      "created_at": now,
      "updated_at": now,
    });
  }

  Future<int> updateRule({
    required int id,
    required String name,
    required bool enabled,
    required DateTime startAt,
    required String periodicity,
    required Map<String, dynamic> rule,
  }) async {
    return await db.update(
      "automation_rules",
      {
        "name": name,
        "enabled": enabled ? 1 : 0,
        "start_at": startAt.toIso8601String(),
        "periodicity": periodicity,
        "rule_json": jsonEncode(rule),
        "updated_at": DateTime.now().toIso8601String(),
      },
      where: "id = ?",
      whereArgs: [id],
    );
  }

  Future<void> deleteRule(int id) async {
    await db.delete("automation_rules", where: "id = ?", whereArgs: [id]);
  }

  Future<List<AutomationRule>> loadAll() async {
    final result = await db.query("automation_rules", orderBy: "id DESC");
  return result
      .map(
        (e) => AutomationRule.fromMap(
          {
            ...e,
            "rule_json": jsonDecode(
              e["rule_json"]
                  as String,
            ),
          },
        ),
      )
      .toList();
  }

  Future<Map<String, dynamic>?> loadRule(int id) async {
    final result = await db.query(
      "automation_rules",
      where: "id = ?",
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return {
      ...result.first,
      "rule_json": jsonDecode(result.first["rule_json"] as String),
    };
  }

  Future<void> logExecution({
    required int ruleId,
    required String status,
    String? message,
  }) async {
    await db.insert("automation_logs", {
      "rule_id": ruleId,
      "status": status,
      "message": message,
      "executed_at": DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> loadLogs(int ruleId) async {
    return await db.query(
      "automation_logs",
      where: "rule_id = ?",
      whereArgs: [ruleId],
      orderBy: "executed_at DESC",
    );
  }
}
