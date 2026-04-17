// lib/sketch/sketch_object.dart
//
// A single drawable polygon object in the sketch canvas.
// The canvas holds a List<SketchObject> — one per room / furniture / obstacle.

import 'package:flutter/material.dart';

class SketchObject {
  /// Unique id for this object (used for selection, deletion)
  final String id;

  /// Display label shown near the centroid (e.g. "Room 1", "Bathroom")
  String label;

  /// Polygon vertices in world-space units
  List<Offset> points;

  /// Whether the polygon ring is closed (first == last edge exists)
  bool isClosed;

  /// Real-world measurements per wall index (mm)
  Map<int, double> wallRealMm;

  /// Colour used to draw this object's fill and stroke
  Color color;

  SketchObject({
    required this.id,
    required this.label,
    required this.points,
    this.isClosed = false,
    Map<int, double>? wallRealMm,
    this.color = const Color(0xFF00AAFF),
  }) : wallRealMm = wallRealMm ?? {};

  // ── Geometry helpers ────────────────────────────────────────────────────

  int get wallCount => isClosed ? points.length : (points.length - 1).clamp(0, 999);

  double get perimeter {
    double total = 0;
    for (int i = 0; i < wallCount; i++) {
      total += (points[(i + 1) % points.length] - points[i]).distance;
    }
    return total;
  }

  double get area {
    if (points.length < 3 || !isClosed) return 0;
    double a = 0;
    final int n = points.length;
    for (int i = 0; i < n; i++) {
      final Offset p = points[i];
      final Offset q = points[(i + 1) % n];
      a += p.dx * q.dy - q.dx * p.dy;
    }
    return a.abs() / 2.0;
  }

  Offset get centroid {
    if (points.isEmpty) return Offset.zero;
    double cx = 0, cy = 0;
    for (final p in points) {
      cx += p.dx;
      cy += p.dy;
    }
    return Offset(cx / points.length, cy / points.length);
  }

  // ── Move the entire object by a world-space delta ────────────────────────
  void translate(Offset delta) {
    points = points.map((p) => p + delta).toList();
  }

  // ── Hit-test: is world-space point inside the polygon? ──────────────────
  bool containsPoint(Offset worldPt) {
    if (points.length < 3 || !isClosed) return false;
    bool inside = false;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      final Offset pi = points[i];
      final Offset pj = points[j];
      if (((pi.dy > worldPt.dy) != (pj.dy > worldPt.dy)) &&
          (worldPt.dx < (pj.dx - pi.dx) * (worldPt.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  // ── Deep copy ───────────────────────────────────────────────────────────
  SketchObject copyWith({
    String? label,
    List<Offset>? points,
    bool? isClosed,
    Map<int, double>? wallRealMm,
    Color? color,
  }) {
    return SketchObject(
      id: id,
      label: label ?? this.label,
      points: points ?? List<Offset>.from(this.points),
      isClosed: isClosed ?? this.isClosed,
      wallRealMm: wallRealMm ?? Map<int, double>.from(this.wallRealMm),
      color: color ?? this.color,
    );
  }
}

// ── Palette of colours cycled through as new objects are added ────────────
const List<Color> kObjectPalette = [
  Color(0xFF00AAFF), // blue
  Color(0xFF00E5A0), // teal
  Color(0xFFFFAA00), // amber
  Color(0xFFFF5577), // rose
  Color(0xFFAA88FF), // violet
  Color(0xFF55DDDD), // cyan
  Color(0xFFFFDD55), // yellow
];
