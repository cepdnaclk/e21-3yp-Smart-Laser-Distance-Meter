// lib/sketch/sketch_model.dart

import 'package:flutter/material.dart';
import 'room_object.dart';

class SharedWall {
  final int otherShapeIndex;
  final int myWallIndex;
  final int otherWallIndex;
  SharedWall({
    required this.otherShapeIndex,
    required this.myWallIndex,
    required this.otherWallIndex,
  });
}

class SketchShape {
  List<Offset> points;
  bool isClosed;
  String label;
  Map<int, double> wallRealMm;
  List<RoomObject> roomObjects;
  List<SharedWall> sharedWalls;

  SketchShape({
    List<Offset>? points,
    this.isClosed = false,
    this.label = '',
    Map<int, double>? wallRealMm,
    List<RoomObject>? roomObjects,
    List<SharedWall>? sharedWalls,
    
  })  : points = points ?? [],
        wallRealMm = wallRealMm ?? {},
      roomObjects = roomObjects ?? [],
      sharedWalls = sharedWalls ?? [];

  // Creates a fresh empty room
  factory SketchShape.empty() => SketchShape();

  // Total number of walls
  int get wallCount => isClosed ? points.length : (points.length - 1).clamp(0, 999);
}