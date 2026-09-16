// lib/ar/ar_polygon_math.dart
//
// AR-3: Converts a list of detected wall planes into an ordered 2D room
// polygon whose coordinates are in millimetres (ARCore metres × 1000).
//
// Algorithm:
//  1. Project each wall plane to the floor (XZ plane, Y = 0).
//  2. Sort walls by the angle of their centre from the overall centroid so
//     they appear in cyclic order around the room.
//  3. For each consecutive wall pair, compute the 2D line intersection →
//     that intersection is one room corner.
//  4. Scale from metres to mm and return the ordered polygon.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class WallPlane {
  final Vector3 position; // a point on the wall, ARCore metres (Y-up)
  final Vector3 normal;   // unit outward normal of the wall

  WallPlane({required this.position, required this.normal});
}

/// Converts detected wall planes to an ordered 2D polygon in mm.
/// Returns an empty list when geometry is degenerate or fewer than 3 walls.
List<Offset> wallPlanesToPolygonMm(List<WallPlane> walls) {
  if (walls.length < 3) return [];

  // Project each wall to the XZ floor plane.
  // A wall in 2D is described by a point (x, z) and a unit normal (nx, nz).
  final walls2d = <({Offset pos, Offset nor})>[];
  for (final w in walls) {
    final nx = w.normal.x;
    final nz = w.normal.z;
    final len = math.sqrt(nx * nx + nz * nz);
    if (len < 0.001) continue; // floor / ceiling — skip
    walls2d.add((
      pos: Offset(w.position.x, w.position.z),
      nor: Offset(nx / len, nz / len),
    ));
  }
  if (walls2d.length < 3) return [];

  // Sort walls by the angle of their position from the centroid.
  // This puts them in cyclic room order regardless of capture sequence.
  final centX = walls2d.fold(0.0, (s, w) => s + w.pos.dx) / walls2d.length;
  final centZ = walls2d.fold(0.0, (s, w) => s + w.pos.dy) / walls2d.length;
  final sorted = [...walls2d]
    ..sort((a, b) {
      final aa = math.atan2(a.pos.dy - centZ, a.pos.dx - centX);
      final ab = math.atan2(b.pos.dy - centZ, b.pos.dx - centX);
      return aa.compareTo(ab);
    });

  // Find corners: intersection of each consecutive wall pair.
  final corners = <Offset>[];
  final n = sorted.length;
  for (int i = 0; i < n; i++) {
    final w1 = sorted[i];
    final w2 = sorted[(i + 1) % n];
    final c = _intersect2D(w1.pos, w1.nor, w2.pos, w2.nor);
    if (c != null) corners.add(c);
  }
  if (corners.length < 3) return [];

  // Convert ARCore metres → mm.
  return corners.map((c) => Offset(c.dx * 1000, c.dy * 1000)).toList();
}

/// 2D intersection of two lines, each defined by a point [p] and outward
/// unit normal [n]:  n·(x − p) = 0  →  n.x·x + n.y·y = d
///
/// Returns null when the lines are parallel (walls facing same direction).
Offset? _intersect2D(Offset p1, Offset n1, Offset p2, Offset n2) {
  final d1 = n1.dx * p1.dx + n1.dy * p1.dy;
  final d2 = n2.dx * p2.dx + n2.dy * p2.dy;
  final det = n1.dx * n2.dy - n1.dy * n2.dx;
  if (det.abs() < 1e-6) return null; // parallel walls
  return Offset(
    (d1 * n2.dy - d2 * n1.dy) / det,
    (n1.dx * d2 - n2.dx * d1) / det,
  );
}
