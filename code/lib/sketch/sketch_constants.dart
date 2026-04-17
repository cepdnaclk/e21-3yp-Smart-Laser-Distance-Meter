// lib/sketch/sketch_constants.dart

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