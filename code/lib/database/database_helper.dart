// lib/database/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/material.dart';
import '../sketch/room_object.dart';
import '../sketch/furniture_item.dart';

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
      version: 3,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
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

    await db.execute('''
      CREATE TABLE furniture_items (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id    INTEGER NOT NULL,
        shape_index   INTEGER NOT NULL,
        furniture_id  TEXT NOT NULL,
        type          TEXT NOT NULL,
        position_x    REAL NOT NULL,
        position_y    REAL NOT NULL,
        rotation_deg  REAL NOT NULL,
        width_mm      REAL NOT NULL,
        depth_mm      REAL NOT NULL,
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_uploads (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id    INTEGER NOT NULL,
        payload       TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        attempts      INTEGER NOT NULL DEFAULT 0,
        last_attempt  TEXT,
        status        TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_uploads (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          project_id    INTEGER NOT NULL,
          payload       TEXT NOT NULL,
          created_at    TEXT NOT NULL,
          attempts      INTEGER NOT NULL DEFAULT 0,
          last_attempt  TEXT,
          status        TEXT NOT NULL DEFAULT 'pending'
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS furniture_items (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          project_id    INTEGER NOT NULL,
          shape_index   INTEGER NOT NULL,
          furniture_id  TEXT NOT NULL,
          type          TEXT NOT NULL,
          position_x    REAL NOT NULL,
          position_y    REAL NOT NULL,
          rotation_deg  REAL NOT NULL,
          width_mm      REAL NOT NULL,
          depth_mm      REAL NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
        )
      ''');
    }
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
    List<List<FurnitureItem>>? furniturePerShape,
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

      // 4. Save furniture items per shape
      final furnitureSource = furniturePerShape ??
          shapes.map<List<FurnitureItem>>(
            (s) => List<FurnitureItem>.from(s.furnitureItems as List),
          ).toList();
      for (int s = 0; s < furnitureSource.length; s++) {
        for (final f in furnitureSource[s]) {
          await txn.insert('furniture_items', {
            'project_id': projectId,
            'shape_index': s,
            'furniture_id': f.id,
            'type': f.type.name,
            'position_x': f.position.dx,
            'position_y': f.position.dy,
            'rotation_deg': f.rotationDeg,
            'width_mm': f.widthMm,
            'depth_mm': f.depthMm,
          });
        }
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

    // Furniture items
    final furnitureRows = await db.query(
      'furniture_items',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'shape_index ASC',
    );

    return {
      'project': projects.first,
      'shapes': shapesData,
      'room_objects': objects,
      'furniture_items': furnitureRows,
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

  // Add an item to the upload queue
  Future<void> queueUpload({
    required int projectId,
    required String payloadJson,
  }) async {
    final db = await database;
    await db.insert('pending_uploads', {
      'project_id': projectId,
      'payload': payloadJson,
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    });
  }

  // Get the oldest pending item
  Future<Map<String, dynamic>?> getNextPendingUpload() async {
    final db = await database;
    final rows = await db.query(
      'pending_uploads',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // Remove a successfully uploaded item
  Future<void> deletePendingUpload(int id) async {
    final db = await database;
    await db.delete('pending_uploads', where: 'id = ?', whereArgs: [id]);
  }

  // Mark an item as conflicted (do not retry automatically)
  Future<void> markUploadConflict(int id) async {
    final db = await database;
    await db.update(
      'pending_uploads',
      {'status': 'conflict', 'last_attempt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Increment attempt count on network failure
  Future<void> markUploadAttempted(int id) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE pending_uploads
      SET attempts = attempts + 1,
          last_attempt = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), id]);
  }

  // Count how many items are waiting
  Future<int> pendingUploadCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as c FROM pending_uploads WHERE status = 'pending'"
    );
    return result.first['c'] as int;
  }
}