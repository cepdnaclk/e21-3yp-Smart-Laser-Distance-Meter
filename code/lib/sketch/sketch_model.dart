// lib/sketch/sketch_model.dart

import 'package:flutter/material.dart';

class SketchShape {
  List<Offset> points;
  bool isClosed;
  String label;
  Map<int, double> wallRealMm;

  SketchShape({
    List<Offset>? points,
    this.isClosed = false,
    this.label = '',
    Map<int, double>? wallRealMm,
  })  : points = points ?? [],
        wallRealMm = wallRealMm ?? {};

  // Creates a fresh empty room
  factory SketchShape.empty() => SketchShape();

  // Total number of walls
  int get wallCount => isClosed ? points.length : (points.length - 1).clamp(0, 999);
}