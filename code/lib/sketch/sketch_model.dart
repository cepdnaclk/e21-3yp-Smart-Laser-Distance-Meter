// lib/sketch/sketch_model.dart

import 'package:flutter/material.dart';
import 'furniture_item.dart';
import 'room_object.dart';

int _shapeIdCounter = 0;

String generateShapeId() {
  _shapeIdCounter++;
  return '${DateTime.now().microsecondsSinceEpoch}_$_shapeIdCounter';
}

class SharedWall {
  final String otherShapeId;
  final int myWallIndex;
  final int otherWallIndex;
  final double tStart; // 0.0-1.0 along myWallIndex segment
  final double tEnd; // 0.0-1.0 along myWallIndex segment

  SharedWall({
    required this.otherShapeId,
    required this.myWallIndex,
    required this.otherWallIndex,
    required this.tStart,
    required this.tEnd,
  });
}

class SketchShape {
  final String id;
  List<Offset> points;
  bool isClosed;
  String label;
  Map<int, double> wallRealMm;
  List<RoomObject> roomObjects;
  List<SharedWall> sharedWalls;

  List<FurnitureItem> furnitureItems;
  double heightMm;

  SketchShape({
    String? id,
    List<Offset>? points,
    this.isClosed = false,
    this.label = '',
    Map<int, double>? wallRealMm,
    List<RoomObject>? roomObjects,
    List<SharedWall>? sharedWalls,
    List<FurnitureItem>? furnitureItems,
    this.heightMm = 2400,
    })  : id = id ?? generateShapeId(),
      points = points ?? [],
        wallRealMm = wallRealMm ?? {},
        roomObjects = roomObjects ?? [],
        sharedWalls = sharedWalls ?? [],
        furnitureItems = furnitureItems ?? [];

  // Creates a fresh empty room
  factory SketchShape.empty() => SketchShape();

  // Total number of walls
  int get wallCount => isClosed ? points.length : (points.length - 1).clamp(0, 999);
}