// lib/database/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/material.dart';
import '../sketch/room_object.dart';

class DatabaseHelper {
  // Singleton — only one instance ever exists in the app
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  // Every time you need the database, call this getter
  // First call opens/creates it, every call after just returns it
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('smartmeasure.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
    );
  }

  // Runs once on fresh install — creates all tables
  Future _createTables(Database db, int version) async {

    // One row per project (a project can have multiple rooms)
    await db.execute('''
      CREATE TABLE projects (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL,
        created_at  TEXT NOT NULL,
        updated_at  TEXT NOT NULL
      )
    ''');

    // One row per room/shape
    // shape_index = position in your shapes list (0, 1, 2...)
    await db.execute('''
      CREATE TABLE shapes (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id   INTEGER NOT NULL,
        shape_index  INTEGER NOT NULL,
        is_closed    INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    // Every Offset in the points list
    await db.execute('''
      CREATE TABLE shape_points (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        shape_id     INTEGER NOT NULL,
        order_index  INTEGER NOT NULL,
        x            REAL NOT NULL,
        y            REAL NOT NULL,
        FOREIGN KEY (shape_id) REFERENCES shapes(id) ON DELETE CASCADE
      )
    ''');

    // Wall real measurements — your wallRealMm map
    await db.execute('''
      CREATE TABLE wall_real_mm (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        shape_id    INTEGER NOT NULL,
        wall_index  INTEGER NOT NULL,
        real_mm     REAL NOT NULL,
        FOREIGN KEY (shape_id) REFERENCES shapes(id) ON DELETE CASCADE
      )
    ''');

    // Wall angles list
    await db.execute('''
      CREATE TABLE wall_angles (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        shape_id     INTEGER NOT NULL,
        order_index  INTEGER NOT NULL,
        angle        REAL NOT NULL,
        FOREIGN KEY (shape_id) REFERENCES shapes(id) ON DELETE CASCADE
      )
    ''');

    // Wall drawn lengths list
    await db.execute('''
      CREATE TABLE wall_lengths (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        shape_id     INTEGER NOT NULL,
        order_index  INTEGER NOT NULL,
        length       REAL NOT NULL,
        FOREIGN KEY (shape_id) REFERENCES shapes(id) ON DELETE CASCADE
      )
    ''');

    // Doors and windows
    await db.execute('''
      CREATE TABLE room_objects (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id      INTEGER NOT NULL,
        object_id       TEXT NOT NULL,
        type            TEXT NOT NULL,
        wall_index      INTEGER NOT NULL,
        position_along  REAL NOT NULL,
        width_mm        REAL NOT NULL,
        height_mm       REAL NOT NULL,
        elevation_mm    REAL NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');
  }

  // ── CREATE ────────────────────────────────────────────────────────────────

  // Call this when user taps Save
  // Pass in everything from your SketchScreenState
  Future<int> saveProject({
    required String name,
    required List<dynamic> shapes,       // your List<SketchShape>
    required List<RoomObject> roomObjects,
    required List<double> wallAngles,
    required List<double> wallDrawnLengths,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // transaction = all-or-nothing, if anything fails nothing is saved
    return await db.transaction((txn) async {

      // 1. Insert project row
      final projectId = await txn.insert('projects', {
        'name': name,
        'created_at': now,
        'updated_at': now,
      });

      // 2. Loop through each shape and save it
      for (int s = 0; s < shapes.length; s++) {
        final shape = shapes[s];

        final shapeId = await txn.insert('shapes', {
          'project_id': projectId,
          'shape_index': s,
          'is_closed': shape.isClosed ? 1 : 0,
        });

        // Save each point in order
        for (int i = 0; i < shape.points.length; i++) {
          await txn.insert('shape_points', {
            'shape_id': shapeId,
            'order_index': i,
            'x': shape.points[i].dx,
            'y': shape.points[i].dy,
          });
        }

        // Save wallRealMm map entries
        for (final entry in shape.wallRealMm.entries) {
          await txn.insert('wall_real_mm', {
            'shape_id': shapeId,
            'wall_index': entry.key,
            'real_mm': entry.value,
          });
        }

        // Save wall angles
        for (int i = 0; i < wallAngles.length; i++) {
          await txn.insert('wall_angles', {
            'shape_id': shapeId,
            'order_index': i,
            'angle': wallAngles[i],
          });
        }

        // Save wall drawn lengths
        for (int i = 0; i < wallDrawnLengths.length; i++) {
          await txn.insert('wall_lengths', {
            'shape_id': shapeId,
            'order_index': i,
            'length': wallDrawnLengths[i],
          });
        }
      }

      // 3. Save all room objects (doors/windows)
      for (final obj in roomObjects) {
        await txn.insert('room_objects', {
          'project_id': projectId,
          'object_id': obj.id,
          'type': obj.type.name,
          'wall_index': obj.wallIndex,
          'position_along': obj.positionAlong,
          'width_mm': obj.widthMm,
          'height_mm': obj.heightMm,
          'elevation_mm': obj.elevationMm,
        });
      }

      return projectId;
    });
  }

  // ── READ ──────────────────────────────────────────────────────────────────

  // Returns all projects for the project list screen
  Future<List<Map<String, dynamic>>> getAllProjects() async {
    final db = await database;
    return await db.query('projects', orderBy: 'updated_at DESC');
  }

  // Loads everything for one project — returns a map with all data
  Future<Map<String, dynamic>?> loadProject(int projectId) async {
    final db = await database;

    // Get the project row
    final projects = await db.query(
      'projects', where: 'id = ?', whereArgs: [projectId],
    );
    if (projects.isEmpty) return null;

    // Get all shapes for this project in order
    final shapeRows = await db.query(
      'shapes',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'shape_index ASC',
    );

    List<Map<String, dynamic>> shapesData = [];

    for (final shapeRow in shapeRows) {
      final shapeId = shapeRow['id'] as int;

      // Points in order
      final points = await db.query(
        'shape_points',
        where: 'shape_id = ?',
        whereArgs: [shapeId],
        orderBy: 'order_index ASC',
      );

      // wallRealMm
      final wallMm = await db.query(
        'wall_real_mm',
        where: 'shape_id = ?',
        whereArgs: [shapeId],
      );

      // wall angles
      final angles = await db.query(
        'wall_angles',
        where: 'shape_id = ?',
        whereArgs: [shapeId],
        orderBy: 'order_index ASC',
      );

      // wall lengths
      final lengths = await db.query(
        'wall_lengths',
        where: 'shape_id = ?',
        whereArgs: [shapeId],
        orderBy: 'order_index ASC',
      );

      shapesData.add({
        'is_closed': shapeRow['is_closed'],
        'points': points,
        'wall_real_mm': wallMm,
        'wall_angles': angles,
        'wall_lengths': lengths,
      });
    }

    // Room objects
    final objects = await db.query(
      'room_objects',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );

    return {
      'project': projects.first,
      'shapes': shapesData,
      'room_objects': objects,
    };
  }

  // ── DELETE ────────────────────────────────────────────────────────────────

  Future<void> deleteProject(int projectId) async {
    final db = await database;
    await db.delete(
      'projects', where: 'id = ?', whereArgs: [projectId],
    );
    // CASCADE in the table definition automatically deletes
    // all shapes, points, objects linked to this project
  }
}