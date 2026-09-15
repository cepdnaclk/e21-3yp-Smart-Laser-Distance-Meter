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
