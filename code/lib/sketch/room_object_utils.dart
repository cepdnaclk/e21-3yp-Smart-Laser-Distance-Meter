// lib/sketch/room_object_utils.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'room_object.dart';

class WallHitResult {
  final int wallIndex;
  final double positionAlong; // 0.0 – 1.0
  final Offset snapPoint;     // world coords of snap position

  const WallHitResult({
    required this.wallIndex,
    required this.positionAlong,
    required this.snapPoint,
  });
}

/// Find the nearest wall to a screen position.
/// Returns null if no wall is within [hitThreshold] screen pixels.
WallHitResult? findNearestWall({
  required Offset screenPos,
  required List<Offset> points,
  required bool isClosed,
  required Offset Function(Offset) worldToScreen,
  required Offset Function(Offset) screenToWorld,
  double hitThreshold = 30.0,
}) {
  if (points.length < 2) return null;
  final int n = points.length;
  final int wallCount = isClosed ? n : n - 1;

  double bestDist = hitThreshold;
  int bestWall = -1;
  double bestT = 0.5;
  Offset bestSnap = Offset.zero;

  for (int i = 0; i < wallCount; i++) {
    final Offset aWorld = points[i];
    final Offset bWorld = points[(i + 1) % n];
    final Offset aScreen = worldToScreen(aWorld);
    final Offset bScreen = worldToScreen(bWorld);

    final dx = bScreen.dx - aScreen.dx;
    final dy = bScreen.dy - aScreen.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1) continue;

    final t = ((screenPos.dx - aScreen.dx) * dx +
               (screenPos.dy - aScreen.dy) * dy) / lenSq;
    final tClamped = t.clamp(0.05, 0.95); // keep off the corners

    final projScreen = Offset(
      aScreen.dx + tClamped * dx,
      aScreen.dy + tClamped * dy,
    );
    final dist = (screenPos - projScreen).distance;

    if (dist < bestDist) {
      bestDist = dist;
      bestWall = i;
      bestT = tClamped;
      bestSnap = screenToWorld(projScreen);
    }
  }

  if (bestWall < 0) return null;
  return WallHitResult(
    wallIndex: bestWall,
    positionAlong: bestT,
    snapPoint: bestSnap,
  );
}

/// Convert a RoomObject's positionAlong into its world-coordinate centre point.
Offset objectCentreWorld({
  required RoomObject obj,
  required List<Offset> points,
  int? wallCount,
}) {
  final int n = points.length;
  final int wc = wallCount ?? n;
  if (obj.wallIndex >= wc) return points[0];
  final Offset a = points[obj.wallIndex];
  final Offset b = points[(obj.wallIndex + 1) % n];
  return Offset(
    a.dx + obj.positionAlong * (b.dx - a.dx),
    a.dy + obj.positionAlong * (b.dy - a.dy),
  );
}

/// Compute the wall direction unit vector (screen space) for drawing.
Offset wallDirectionScreen({
  required int wallIndex,
  required List<Offset> points,
  required Offset Function(Offset) worldToScreen,
}) {
  final int n = points.length;
  final Offset aScreen = worldToScreen(points[wallIndex]);
  final Offset bScreen = worldToScreen(points[(wallIndex + 1) % n]);
  final dx = bScreen.dx - aScreen.dx;
  final dy = bScreen.dy - aScreen.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < 1) return const Offset(1, 0);
  return Offset(dx / len, dy / len);
}