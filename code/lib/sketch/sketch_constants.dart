// lib/sketch/sketch_constants.dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

const double mmPerUnit = 5.0;
const double unitsPerMeter = 200.0;

const double panThreshold = 6.0;
const double minorGrid = 20.0;
const double majorGrid = 100.0;
const double snapRadiusWorld = 15.0;
const double minPointDistance = 8.0;
const double lastPointGlowRadius = 28.0;
const double lastPointRingRadius = 14.0;
const double pointSnapRadiusScreen = 30.0;
const double pointSelectRadiusScreen = 22.0;
const double snapThresholdDeg = 3.0;
const double minAngleDistance = 10.0;
const double wallThickness = 10.0;

List<Offset> thickWallRect(Offset a, Offset b, double thickness) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len == 0) return [];
  final px = -dy / len * (thickness / 2);
  final py = dx / len * (thickness / 2);
  return [
    Offset(a.dx + px, a.dy + py),
    Offset(b.dx + px, b.dy + py),
    Offset(b.dx - px, b.dy - py),
    Offset(a.dx - px, a.dy - py),
  ];
}// world units (~50mm real)

const List<double> snapAngles = [
  0, 30, 45, 60, 75, 90, 105, 120, 135, 150,
  180, 210, 225, 240, 255, 270, 285, 300, 315, 330,
];

// ── Formatters used across all sketch files ──────────────────────────────
String formatLength(double worldUnits) {
  final double mm = worldUnits * mmPerUnit;
  if (mm >= 1000) {
    return '${(mm / 1000.0).toStringAsFixed(2)} m';
  }
  return '${mm.toStringAsFixed(0)} mm';
}

String formatArea(double worldUnitsSquared) {
  final double mm2 = worldUnitsSquared * mmPerUnit * mmPerUnit;
  final double m2 = mm2 / 1000000.0;
  if (m2 >= 0.01) return '${m2.toStringAsFixed(2)} m²';
  return '${mm2.toStringAsFixed(0)} mm²';
}

Offset? lineIntersect(Offset p1, Offset d1, Offset p2, Offset d2) {
  final cross = d1.dx * d2.dy - d1.dy * d2.dx;
  if (cross.abs() < 1e-6) return null; // parallel
  final t = ((p2.dx - p1.dx) * d2.dy - (p2.dy - p1.dy) * d2.dx) / cross;
  return Offset(p1.dx + t * d1.dx, p1.dy + t * d1.dy);
}