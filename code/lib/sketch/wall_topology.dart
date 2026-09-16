import 'package:flutter/material.dart';
import 'sketch_model.dart';

class WallSource {
  final String shapeId;
  final int wallIndex;
  final double tStart;
  final double tEnd;

  WallSource({
    required this.shapeId,
    required this.wallIndex,
    required this.tStart,
    required this.tEnd,
  });
}

class Wall {
  final String id;
  final Offset a;
  final Offset b;
  final List<WallSource> sources;

  Wall({required this.id, required this.a, required this.b, required this.sources});

  bool get isShared => sources.length > 1;
}

({Offset start, Offset end, Offset oStart, Offset oEnd})? wallOverlapSegment(
    Offset mA, Offset mB, Offset oA, Offset oB,
    {double perpThresh = 3.0, double parallelThresh = 0.08}) {
  final mDir = mB - mA;
  final mLen = mDir.distance;
  final oDir = oB - oA;
  final oLen = oDir.distance;
  if (mLen < 1 || oLen < 1) return null;

  final mUnit = mDir / mLen;
  final oUnit = oDir / oLen;

  final dot = (mUnit.dx * oUnit.dx + mUnit.dy * oUnit.dy).abs();
  if (dot < 1.0 - parallelThresh) return null;

  final cross = (oA - mA).dx * mUnit.dy - (oA - mA).dy * mUnit.dx;
  if (cross.abs() > perpThresh) return null;

  final tOA = (oA - mA).dx * mUnit.dx + (oA - mA).dy * mUnit.dy;
  final tOB = (oB - mA).dx * mUnit.dx + (oB - mA).dy * mUnit.dy;

  final tStart = tOA < tOB ? tOA : tOB;
  final tEnd = tOA < tOB ? tOB : tOA;
  final overlapStart = tStart.clamp(0.0, mLen);
  final overlapEnd = tEnd.clamp(0.0, mLen);
  if (overlapEnd - overlapStart < 4.0) return null;

  final sharedStart = mA + mUnit * overlapStart;
  final sharedEnd = mA + mUnit * overlapEnd;

  final oUnitSigned = dot > 0 ? oUnit : -oUnit;
  final oBase = dot > 0 ? oA : oB;
  final tOnOStart =
      (sharedStart - oBase).dx * oUnitSigned.dx + (sharedStart - oBase).dy * oUnitSigned.dy;
  final tOnOEnd =
      (sharedEnd - oBase).dx * oUnitSigned.dx + (sharedEnd - oBase).dy * oUnitSigned.dy;
  final oSharedStart = oBase + oUnitSigned * tOnOStart.clamp(0.0, oLen);
  final oSharedEnd = oBase + oUnitSigned * tOnOEnd.clamp(0.0, oLen);

  return (start: sharedStart, end: sharedEnd, oStart: oSharedStart, oEnd: oSharedEnd);
}

double _tAlong(Offset p1, Offset p2, Offset p) {
  final d = p2 - p1;
  final len2 = d.dx * d.dx + d.dy * d.dy;
  if (len2 < 1e-9) return 0;
  return ((p.dx - p1.dx) * d.dx + (p.dy - p1.dy) * d.dy) / len2;
}

List<(double, double)> _subtractRanges(List<(double, double)> covered) {
  if (covered.isEmpty) return [(0.0, 1.0)];
  final sorted = [...covered]..sort((a, b) => a.$1.compareTo(b.$1));
  final result = <(double, double)>[];
  double cursor = 0.0;
  for (final r in sorted) {
    final start = r.$1.clamp(0.0, 1.0);
    final end = r.$2.clamp(0.0, 1.0);
    if (start > cursor) result.add((cursor, start));
    if (end > cursor) cursor = end;
  }
  if (cursor < 1.0) result.add((cursor, 1.0));
  return result;
}

List<Wall> buildWalls(List<SketchShape> shapes) {
  final walls = <Wall>[];
  final covered = <String, Map<int, List<(double, double)>>>{};

  void markCovered(String shapeId, int wallIndex, double t0, double t1) {
    covered.putIfAbsent(shapeId, () => {});
    covered[shapeId]!.putIfAbsent(wallIndex, () => []);
    covered[shapeId]![wallIndex]!.add((t0, t1));
  }

  for (int si = 0; si < shapes.length; si++) {
    final shapeA = shapes[si];
    if (!shapeA.isClosed) continue;
    final na = shapeA.points.length;
    for (int ai = 0; ai < na; ai++) {
      final mA = shapeA.points[ai];
      final mB = shapeA.points[(ai + 1) % na];

      for (int sj = si + 1; sj < shapes.length; sj++) {
        final shapeB = shapes[sj];
        if (!shapeB.isClosed) continue;
        final nb = shapeB.points.length;
        for (int bi = 0; bi < nb; bi++) {
          final oA = shapeB.points[bi];
          final oB = shapeB.points[(bi + 1) % nb];
          final overlap = wallOverlapSegment(mA, mB, oA, oB);
          if (overlap == null) continue;

          final tA0 = _tAlong(mA, mB, overlap.start);
          final tA1 = _tAlong(mA, mB, overlap.end);
          final tB0 = _tAlong(oA, oB, overlap.oStart);
          final tB1 = _tAlong(oA, oB, overlap.oEnd);

          walls.add(Wall(
            id: 'w_${shapeA.id}_${ai}_${shapeB.id}_$bi',
            a: overlap.start,
            b: overlap.end,
            sources: [
              WallSource(shapeId: shapeA.id, wallIndex: ai, tStart: tA0, tEnd: tA1),
              WallSource(shapeId: shapeB.id, wallIndex: bi, tStart: tB0, tEnd: tB1),
            ],
          ));

          markCovered(shapeA.id, ai, tA0 < tA1 ? tA0 : tA1, tA0 < tA1 ? tA1 : tA0);
          markCovered(shapeB.id, bi, tB0 < tB1 ? tB0 : tB1, tB0 < tB1 ? tB1 : tB0);
        }
      }
    }
  }

  for (final shape in shapes) {
    if (!shape.isClosed) continue;
    final n = shape.points.length;
    for (int i = 0; i < n; i++) {
      final a = shape.points[i];
      final b = shape.points[(i + 1) % n];
      final ranges = covered[shape.id]?[i] ?? const [];
      for (final free in _subtractRanges(ranges)) {
        if (free.$2 - free.$1 < 0.01) continue;
        walls.add(Wall(
          id: 'w_${shape.id}_${i}_${free.$1.toStringAsFixed(3)}',
          a: a + (b - a) * free.$1,
          b: a + (b - a) * free.$2,
          sources: [
            WallSource(shapeId: shape.id, wallIndex: i, tStart: free.$1, tEnd: free.$2),
          ],
        ));
      }
    }
  }

  return walls;
}
