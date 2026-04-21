import 'package:flutter/material.dart';

/// One room polygon — the central data model for the multi-room feature.
/// Every room on the canvas is represented by exactly one [SketchShape].
class SketchShape {
  /// Unique identifier (used to distinguish shapes in undo snapshots).
  final String id;

  /// Corner points in world coordinates.
  List<Offset> points;

  /// Whether the polygon has been closed (last point connected to first).
  bool isClosed;

  /// Optional room label shown at the centroid (Phase 5 — set to null for now).
  String? label;

  /// Per-wall real measurements entered by the user or received over BLE.
  /// Key = wall index (0-based), value = real length in mm.
  Map<int, double> wallRealMm;

  SketchShape({
    required this.id,
    List<Offset>? points,
    this.isClosed = false,
    this.label,
    Map<int, double>? wallRealMm,
  })  : points = points ?? [],
        wallRealMm = wallRealMm ?? {};

  /// Deep-copy constructor — used by the undo system.
  SketchShape.copy(SketchShape source)
      : id = source.id,
        points = List<Offset>.from(source.points),
        isClosed = source.isClosed,
        label = source.label,
        wallRealMm = Map<int, double>.from(source.wallRealMm);
}