import 'wall_topology.dart';
import 'sketch_model.dart';
import 'room_object.dart';
import 'sketch_constants.dart';

class ResolvedOpening {
  final RoomObject source;
  final double positionAlong;

  ResolvedOpening({required this.source, required this.positionAlong});
}

class WallOpenings {
  final List<ResolvedOpening> openings;
  final bool hasConflict;

  WallOpenings(this.openings, this.hasConflict);
}

WallOpenings openingsForWall(Wall wall, List<SketchShape> shapes) {
  final resolved = <ResolvedOpening>[];

  for (final src in wall.sources) {
    SketchShape? shape;
    for (final s in shapes) {
      if (s.id == src.shapeId) {
        shape = s;
        break;
      }
    }
    if (shape == null) continue;

    final lo = src.tStart < src.tEnd ? src.tStart : src.tEnd;
    final hi = src.tStart < src.tEnd ? src.tEnd : src.tStart;

    for (final obj in shape.roomObjects) {
      if (obj.wallIndex != src.wallIndex) continue;
      if (obj.positionAlong < lo - 1e-6 || obj.positionAlong > hi + 1e-6) continue;

      final span = src.tEnd - src.tStart;
      final localT = span.abs() < 1e-9
          ? 0.0
          : ((obj.positionAlong - src.tStart) / span).clamp(0.0, 1.0);

      resolved.add(ResolvedOpening(source: obj, positionAlong: localT));
    }
  }

  bool conflict = false;
  final wallLen = (wall.b - wall.a).distance;
  for (int i = 0; i < resolved.length; i++) {
    for (int j = i + 1; j < resolved.length; j++) {
      final a = resolved[i];
      final b = resolved[j];
      if (a.source.ownerShapeId == b.source.ownerShapeId) continue;
      if (wallLen < 1) continue;

      final halfA = (a.source.widthMm / mmPerUnit / 2) / wallLen;
      final halfB = (b.source.widthMm / mmPerUnit / 2) / wallLen;
      final aLo = a.positionAlong - halfA;
      final aHi = a.positionAlong + halfA;
      final bLo = b.positionAlong - halfB;
      final bHi = b.positionAlong + halfB;
      if (aLo < bHi && bLo < aHi) conflict = true;
    }
  }

  return WallOpenings(resolved, conflict);
}

Wall? findWallForObject(RoomObject obj, SketchShape owner, List<Wall> walls) {
  for (final wall in walls) {
    for (final src in wall.sources) {
      if (src.shapeId != owner.id || src.wallIndex != obj.wallIndex) continue;
      final lo = src.tStart < src.tEnd ? src.tStart : src.tEnd;
      final hi = src.tStart < src.tEnd ? src.tEnd : src.tStart;
      if (obj.positionAlong >= lo - 1e-6 && obj.positionAlong <= hi + 1e-6) {
        return wall;
      }
    }
  }
  return null;
}

bool wouldConflict(
    RoomObject candidate, SketchShape owner, List<SketchShape> shapes, List<Wall> walls) {
  final wall = findWallForObject(candidate, owner, walls);
  if (wall == null || !wall.isShared) return false;

  WallSource? mySource;
  for (final source in wall.sources) {
    if (source.shapeId == owner.id && source.wallIndex == candidate.wallIndex) {
      mySource = source;
      break;
    }
  }
  if (mySource == null) return false;

  final wallLen = (wall.b - wall.a).distance;
  if (wallLen < 1) return false;

  final span = mySource.tEnd - mySource.tStart;
  final localT = span.abs() < 1e-9
      ? 0.0
      : ((candidate.positionAlong - mySource.tStart) / span).clamp(0.0, 1.0);
  final halfC = (candidate.widthMm / mmPerUnit / 2) / wallLen;
  final cLo = localT - halfC;
  final cHi = localT + halfC;

  for (final other in openingsForWall(wall, shapes).openings) {
    if (other.source.ownerShapeId == owner.id) continue;
    final halfO = (other.source.widthMm / mmPerUnit / 2) / wallLen;
    final oLo = other.positionAlong - halfO;
    final oHi = other.positionAlong + halfO;
    if (cLo < oHi && oLo < cHi) return true;
  }
  return false;
}
