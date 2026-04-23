// lib/sketch/room_object.dart

enum RoomObjectType { door, window }

class RoomObject {
  final String id;
  final RoomObjectType type;
  int wallIndex;          // which wall it sits on
  double positionAlong;   // 0.0 = wall start, 1.0 = wall end
  double widthMm;         // real-world width in mm
  double heightMm;        // real-world height in mm (for 3D)
  double elevationMm;     // mm from floor (windows only, doors = 0)
  final bool swingFlipped;  // flips door arc to other side of wall

  RoomObject({
    required this.id,
    required this.type,
    required this.wallIndex,
    this.positionAlong = 0.5,
    this.widthMm = 900,
    this.heightMm = 2100,
    this.elevationMm = 0,
    this.swingFlipped = false,
  });

  bool get isDoor => type == RoomObjectType.door;
  bool get isWindow => type == RoomObjectType.window;

  RoomObject copyWith({
    int? wallIndex,
    double? positionAlong,
    double? widthMm,
    double? heightMm,
    double? elevationMm,
    bool? swingFlipped,
  }) {
    return RoomObject(
      id: id,
      type: type,
      wallIndex: wallIndex ?? this.wallIndex,
      positionAlong: positionAlong ?? this.positionAlong,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      elevationMm: elevationMm ?? this.elevationMm,
      swingFlipped: swingFlipped ?? this.swingFlipped,
    );
  }
}