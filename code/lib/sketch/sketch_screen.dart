// lib/sketch/sketch_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;
import '../ble/ble_manager.dart';
import '../ble/ble_packet.dart';
import 'sketch_constants.dart';
import 'sketch_model.dart';
import 'sketch_painter.dart';
import 'sketch_dialogs.dart';
import 'sketch_pdf_export.dart';
import 'sketch_widgets.dart';
import 'room_object.dart';
import 'room_object_utils.dart';
import 'room_3d_screen.dart';


class SketchScreen extends StatefulWidget {
  final BleManager? bleManager;
  const SketchScreen({super.key, this.bleManager});

  @override
  State<SketchScreen> createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen>
    with SketchDialogsMixin<SketchScreen> {

  // ── State fields ─────────────────────────────────────────────────────────
  Offset _panOffset = Offset.zero;
  double _scale = 1.0;
  double _scaleStart = 1.0;
  List<SketchShape> shapes = [SketchShape.empty()];
  int activeIndex = 0;
  Offset? _cursorWorld;
  bool _isDraggingLastPoint = false;
  bool _dragOccurred = false;
  bool _isMultiTouch = false;
  int _activePointIndex = -1;
  bool _isDraggingActivePoint = false;
  int? _snapTargetIndex;
  // full-canvas undo snapshots (all shapes + activeIndex)
  final List<List<List<Offset>>> _undoAllPointsStack = [];
  final List<List<bool>> _undoAllClosedStack = [];
  final List<List<List<RoomObject>>> _undoAllObjectsStack = [];
  final List<List<Map<int, double>>> _undoAllRealMmStack = [];
  final List<int> _undoActiveIndexStack = [];

  final List<List<List<Offset>>> _redoAllPointsStack = [];
  final List<List<bool>> _redoAllClosedStack = [];
  final List<List<List<RoomObject>>> _redoAllObjectsStack = [];
  final List<List<Map<int, double>>> _redoAllRealMmStack = [];
  final List<int> _redoActiveIndexStack = [];
  TapDownDetails? _pendingTap;
  bool _tapCancelled = false;
  double? _snappedAngle;
  bool _isAngleSnapped = false;
  double? _currentAngleDeg;
  double? _prevWallAngle;
  double? _nextWallAngle;
  bool _prevWallSnapped = false;
  bool _nextWallSnapped = false;
  Offset? _panStartPosition;
  bool _panConfirmed = false;
  double? _nearestSnapAngleDeg;
  double? _snapDiffDeg;
  int _selectedWallIndex = -1;
  final List<({Rect rect, int wallIndex, int shapeIndex})> _labelHitRects = [];
  double? _pendingBleMm;
  bool _waitingForBle = false;
  SketchShape get activeShape => shapes[activeIndex];
  // ── From Venuka — object placement ──────────────────────────
  RoomObjectType? _draggingObjectType;  
  String? _selectedObjectId;            
  Offset? _dragObjectScreenPos;         
  WallHitResult? _dragWallHit;          
  int _objectCounter = 0;  
  // ── From Venuka — wall vector chain ─────────────────────────
  final List<double> _wallAngles = [];
  final List<double> _wallDrawnLengths = [];
  final List<List<double>> _undoWallAnglesStack = [];
  final List<List<double>> _undoWallLengthsStack = [];
  final List<List<double>> _redoWallAnglesStack = [];
  final List<List<double>> _redoWallLengthsStack = [];
            

  String? _movingObjectId;        
  Offset? _moveStartScreenPos;    
  bool _objectMoveOccurred = false;

  // ── Room move mode ───────────────────────────────────────────
  bool _isMoveMode = false;
  int _movingShapeIndex = -1;
  Offset? _moveStartWorld;
  int _snapCandidateShape = -1; // shape index whose wall is highlighted
  int _snapCandidateWall = -1; // wall index on that shape

  // ── Mixin contract — expose private state via public getters ─────────────
  @override List<Offset> get sketchPoints => activeShape.points;
  @override bool get sketchIsClosed => activeShape.isClosed;
  @override double? get sketchCurrentAngleDeg => _currentAngleDeg;
  @override double? get sketchSnappedAngle => _snappedAngle;
  @override Map<int, double> get sketchWallRealMm => activeShape.wallRealMm;
  @override bool get sketchWaitingForBle => _waitingForBle;
  @override dynamic get sketchBleManager => widget.bleManager;

  @override void sketchSetSnappedAngle(double? v) => _snappedAngle = v;
  @override void sketchSetCursorWorld(Offset? v) => _cursorWorld = v;
  @override void sketchSetCurrentAngleDeg(double? v) => _currentAngleDeg = v;
  @override void sketchSetIsAngleSnapped(bool v) => _isAngleSnapped = v;
  @override void sketchSetSelectedWallIndex(int v) => _selectedWallIndex = v;
  @override void sketchSetWaitingForBle(bool v) => _waitingForBle = v;
  @override void sketchSaveUndo() => _saveUndo();
  @override void sketchApplyRealMeasurement(int i, double mm) =>
      _applyRealMeasurement(i, mm);
  @override double sketchWallLengthWorld(int i) => _wallLengthWorld(i);

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    widget.bleManager?.packetStream.listen((BlePacket packet) {
      if (_waitingForBle && _selectedWallIndex >= 0) {
        setState(() {
          _waitingForBle = false;
          _pendingBleMm = packet.distanceMm;
        });
        _applyRealMeasurement(_selectedWallIndex, packet.distanceMm);
      }
    });
  }

  @override
  void dispose() {
    widget.bleManager?.disconnect();
    super.dispose();
  }

  void _showRoomNameDialog() {
    final controller = TextEditingController(text: activeShape.label);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Room Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Bedroom, Kitchen...'),
          onSubmitted: (_) => Navigator.pop(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () {
              setState(() => activeShape.label = controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ── Coordinate helpers ───────────────────────────────────────────────────
  Offset worldToScreen(Offset world) => world * _scale + _panOffset;
  Offset screenToWorld(Offset screen) => (screen - _panOffset) / _scale;

  Offset snapToGrid(Offset worldPos) {
    final double snappedX =
        (worldPos.dx / minorGrid).round() * minorGrid;
    final double snappedY =
        (worldPos.dy / minorGrid).round() * minorGrid;
    return Offset(snappedX, snappedY);
  }

  // ── Point helpers ────────────────────────────────────────────────────────
  bool _isNearLastPoint(Offset screenPos) {
    if (activeShape.points.isEmpty || activeShape.isClosed) return false;
    if (_activePointIndex >= 0) return false;
    return (screenPos - worldToScreen(activeShape.points.last)).distance < lastPointGlowRadius;
  }

  int _findNearPoint(Offset screenPos,
      {int excludeIndex = -1,
      double radius = pointSelectRadiusScreen}) {
    for (int i = 0; i < activeShape.points.length; i++) {
      if (i == excludeIndex) continue;
      if ((screenPos - worldToScreen(activeShape.points[i])).distance < radius) return i;
    }
    return -1;
  }

  Offset? _findSnapPointAcrossShapes(Offset screenPos,
      {double radius = pointSnapRadiusScreen}) {
    for (int s = 0; s < shapes.length; s++) {
      if (s == activeIndex) continue; // skip active shape, handled separately
      if (!shapes[s].isClosed) continue;
      for (final pt in shapes[s].points) {
        if ((screenPos - worldToScreen(pt)).distance < radius) return pt;
      }
    }
    return null;
  }

  void _addNewRoom() {
    _saveUndo();
    setState(() {
      shapes.add(SketchShape.empty());
      activeIndex = shapes.length - 1;
    });
  }
  // ── Undo / redo ──────────────────────────────────────────────────────────
  void _saveUndo() {
    _undoAllPointsStack.add(shapes.map((s) => List<Offset>.of(s.points)).toList());
    _undoAllClosedStack.add(shapes.map((s) => s.isClosed).toList());
    _undoAllObjectsStack
        .add(shapes.map((s) => List<RoomObject>.of(s.roomObjects)).toList());
    _undoAllRealMmStack
        .add(shapes.map((s) => Map<int, double>.of(s.wallRealMm)).toList());
    _undoActiveIndexStack.add(activeIndex);
    _undoWallAnglesStack.add(List<double>.of(_wallAngles));
    _undoWallLengthsStack.add(List<double>.of(_wallDrawnLengths));

    _redoAllPointsStack.clear();
    _redoAllClosedStack.clear();
    _redoAllObjectsStack.clear();
    _redoAllRealMmStack.clear();
    _redoActiveIndexStack.clear();
    _redoWallAnglesStack.clear();
    _redoWallLengthsStack.clear();
  }

  void _undo() {
    if (_undoAllPointsStack.isEmpty) return;

    // save current state to redo
    _redoAllPointsStack.add(shapes.map((s) => List<Offset>.of(s.points)).toList());
    _redoAllClosedStack.add(shapes.map((s) => s.isClosed).toList());
    _redoAllObjectsStack
        .add(shapes.map((s) => List<RoomObject>.of(s.roomObjects)).toList());
    _redoAllRealMmStack
        .add(shapes.map((s) => Map<int, double>.of(s.wallRealMm)).toList());
    _redoActiveIndexStack.add(activeIndex);
    _redoWallAnglesStack.add(List<double>.of(_wallAngles));
    _redoWallLengthsStack.add(List<double>.of(_wallDrawnLengths));

    // restore snapshot
    final pts = _undoAllPointsStack.removeLast();
    final closed = _undoAllClosedStack.removeLast();
    final objs = _undoAllObjectsStack.removeLast();
    final mm = _undoAllRealMmStack.removeLast();
    final idx = _undoActiveIndexStack.removeLast();

    setState(() {
      // rebuild the shapes list from the snapshot
      shapes = List.generate(pts.length, (i) {
        final s = SketchShape.empty();
        s.points = pts[i];
        s.isClosed = closed[i];
        s.roomObjects..clear()..addAll(objs[i]);
        s.wallRealMm..clear()..addAll(mm[i]);
        return s;
      });
      activeIndex = idx;

      if (_undoWallAnglesStack.isNotEmpty) {
        _wallAngles..clear()..addAll(_undoWallAnglesStack.removeLast());
        _wallDrawnLengths..clear()..addAll(_undoWallLengthsStack.removeLast());
      }

      _activePointIndex = -1;
      _cursorWorld = null;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
    });
  }

  void _redo() {
    if (_redoAllPointsStack.isEmpty) return;

    _undoAllPointsStack.add(shapes.map((s) => List<Offset>.of(s.points)).toList());
    _undoAllClosedStack.add(shapes.map((s) => s.isClosed).toList());
    _undoAllObjectsStack
        .add(shapes.map((s) => List<RoomObject>.of(s.roomObjects)).toList());
    _undoAllRealMmStack
        .add(shapes.map((s) => Map<int, double>.of(s.wallRealMm)).toList());
    _undoActiveIndexStack.add(activeIndex);
    _undoWallAnglesStack.add(List<double>.of(_wallAngles));
    _undoWallLengthsStack.add(List<double>.of(_wallDrawnLengths));

    final pts = _redoAllPointsStack.removeLast();
    final closed = _redoAllClosedStack.removeLast();
    final objs = _redoAllObjectsStack.removeLast();
    final mm = _redoAllRealMmStack.removeLast();
    final idx = _redoActiveIndexStack.removeLast();

    setState(() {
      shapes = List.generate(pts.length, (i) {
        final s = SketchShape.empty();
        s.points = pts[i];
        s.isClosed = closed[i];
        s.roomObjects..clear()..addAll(objs[i]);
        s.wallRealMm..clear()..addAll(mm[i]);
        return s;
      });
      activeIndex = idx;

      if (_redoWallAnglesStack.isNotEmpty) {
        _wallAngles..clear()..addAll(_redoWallAnglesStack.removeLast());
        _wallDrawnLengths..clear()..addAll(_redoWallLengthsStack.removeLast());
      }

      _activePointIndex = -1;
      _cursorWorld = null;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
    });
  }

  void _clear() {
    _saveUndo();
    setState(() {
      activeShape.points.clear();
      activeShape.isClosed = false;
      activeShape.roomObjects.clear();
      _wallAngles.clear();
      _wallDrawnLengths.clear();
      activeShape.wallRealMm.clear();
      
      _cursorWorld = null;
      _isDraggingLastPoint = false;
      _dragOccurred = false;
      _isMultiTouch = false;
      _pendingTap = null;
      _tapCancelled = false;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
      _activePointIndex = -1;
      _isDraggingActivePoint = false;
      _snapTargetIndex = null;
      _prevWallAngle = null;
      _nextWallAngle = null;
    });
  }

  // ── Angle math ───────────────────────────────────────────────────────────
  double _computeAngleDeg(Offset from, Offset to) {
    final dx = to.dx - from.dx;
    final dy = -(to.dy - from.dy);
    double a = math.atan2(dy, dx) * 180 / math.pi;
    if (a < 0) a += 360;
    return a;
  }

  (double, double) _nearestSnapAngle(double angleDeg) {
    double nearest = snapAngles.first;
    double minDiff = double.infinity;
    for (final a in snapAngles) {
      double diff = (angleDeg - a).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff < minDiff) { minDiff = diff; nearest = a; }
    }
    return (nearest, minDiff);
  }

  Offset _computeAngle(Offset fromWorld, Offset toWorld) {
    final dx = toWorld.dx - fromWorld.dx;
    final dy = toWorld.dy - fromWorld.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance < minAngleDistance) {
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
      return toWorld;
    }
    final angleDeg = _computeAngleDeg(fromWorld, toWorld);
    _currentAngleDeg = angleDeg;
    final (nearest, minDiff) = _nearestSnapAngle(angleDeg);
    _nearestSnapAngleDeg = nearest;
    _snapDiffDeg = minDiff;
    _snappedAngle = nearest;
    if (minDiff <= snapThresholdDeg) {
      _isAngleSnapped = true;
      final rad = nearest * math.pi / 180;
      return Offset(
        fromWorld.dx + distance * math.cos(rad),
        fromWorld.dy - distance * math.sin(rad),
      );
    }
    _isAngleSnapped = false;
    return toWorld;
  }

  Offset? _rayIntersection(
      Offset oA, double degA, Offset oB, double degB) {
    final rA = degA * math.pi / 180;
    final rB = degB * math.pi / 180;
    final dAx = math.cos(rA), dAy = -math.sin(rA);
    final dBx = math.cos(rB), dBy = -math.sin(rB);
    final det = dAx * (-dBy) - dAy * (-dBx);
    if (det.abs() < 1e-10) return null;
    final dx = oB.dx - oA.dx, dy = oB.dy - oA.dy;
    final t = (dx * (-dBy) - dy * (-dBx)) / det;
    return Offset(oA.dx + t * dAx, oA.dy + t * dAy);
  }

  (double?, bool) _trySnap(double angleDeg) {
    final (nearest, diff) = _nearestSnapAngle(angleDeg);
    return diff <= snapThresholdDeg ? (nearest, true) : (nearest, false);
  }

  Offset _updateMiddlePointAngles(int idx, Offset rawPos) {
    _prevWallAngle = null;
    _nextWallAngle = null;
    _prevWallSnapped = false;
    _nextWallSnapped = false;

    Offset? prevPt = idx > 0
        ? activeShape.points[idx - 1]
        : (activeShape.isClosed && activeShape.points.length > 1 ? activeShape.points.last : null);
    Offset? nextPt = idx < activeShape.points.length - 1
        ? activeShape.points[idx + 1]
        : (activeShape.isClosed && activeShape.points.length > 1 ? activeShape.points[0] : null);

    double? prevSnapAngle;
    Offset? prevSnappedPos;
    if (prevPt != null) {
      final dx = rawPos.dx - prevPt.dx, dy = rawPos.dy - prevPt.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist >= minAngleDistance) {
        final rawAngle = _computeAngleDeg(prevPt, rawPos);
        _prevWallAngle = rawAngle;
        final (nearest, snapped) = _trySnap(rawAngle);
        if (snapped) {
          _prevWallSnapped = true;
          prevSnapAngle = nearest;
          _prevWallAngle = nearest;
          final rad = nearest! * math.pi / 180;
          prevSnappedPos = Offset(
            prevPt.dx + dist * math.cos(rad),
            prevPt.dy - dist * math.sin(rad),
          );
        }
      }
    }

    double? nextSnapAngle;
    Offset? nextSnappedPos;
    if (nextPt != null) {
      final dx = nextPt.dx - rawPos.dx, dy = nextPt.dy - rawPos.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist >= minAngleDistance) {
        final rawAngle = _computeAngleDeg(rawPos, nextPt);
        _nextWallAngle = rawAngle;
        final (nearest, snapped) = _trySnap(rawAngle);
        if (snapped) {
          _nextWallSnapped = true;
          nextSnapAngle = nearest;
          _nextWallAngle = nearest;
          final reverseAngle = (nearest! + 180) % 360;
          final rad = reverseAngle * math.pi / 180;
          nextSnappedPos = Offset(
            nextPt.dx + dist * math.cos(rad),
            nextPt.dy - dist * math.sin(rad),
          );
        }
      }
    }

    if (_prevWallSnapped && _nextWallSnapped &&
        prevPt != null && nextPt != null &&
        prevSnapAngle != null && nextSnapAngle != null) {
      final reverseNext = (nextSnapAngle + 180) % 360;
      final intersection =
          _rayIntersection(prevPt, prevSnapAngle, nextPt, reverseNext);
      if (intersection != null) {
        _prevWallAngle = prevSnapAngle;
        _nextWallAngle = nextSnapAngle;
        return intersection;
      }
      return prevSnappedPos ?? rawPos;
    }
    if (_prevWallSnapped) return prevSnappedPos ?? rawPos;
    if (_nextWallSnapped) return nextSnappedPos ?? rawPos;
    return rawPos;
  }

  // ── Wall helpers ─────────────────────────────────────────────────────────
  double _wallLengthWorld(int wallIndex) {
    final Offset a = activeShape.points[wallIndex];
    final Offset b = activeShape.points[(wallIndex + 1) % activeShape.points.length];
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  int _findNearWall(Offset screenPos) {
    if (activeShape.points.length < 2) return -1;
    const double hitThresh = 18.0;
    final sp = activeShape.points.map(worldToScreen).toList();
    final int n = sp.length;
    final int wallCount = activeShape.isClosed ? n : n - 1;
    for (int i = 0; i < wallCount; i++) {
      if (_pointToSegmentDist(screenPos, sp[i], sp[(i + 1) % n]) < hitThresh) {
        return i;
      }
    }
    return -1;
  }

  /// Inserts a new point on wall [wallIndex] at the screen position,
  /// then immediately enters drag mode on the new point.
  void _insertPointOnWall(int wallIndex, Offset screenPos) {
    _saveUndo();
    final Offset a = activeShape.points[wallIndex];
    final Offset b = activeShape.points[(wallIndex + 1) % activeShape.points.length];

    // Project screenPos onto the wall to get exact world position
    final aS = worldToScreen(a);
    final bS = worldToScreen(b);
    final ab = bS - aS;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = len2 == 0
        ? 0.5
        : ((screenPos - aS).dx * ab.dx + (screenPos - aS).dy * ab.dy) / len2;
    final tC = t.clamp(0.05, 0.95);
    final newWorld = Offset(a.dx + tC * (b.dx - a.dx), a.dy + tC * (b.dy - a.dy));

    setState(() {
      // Insert after wallIndex
      activeShape.points.insert(wallIndex + 1, newWorld);
      // Invalidate wallRealMm for affected walls
      activeShape.wallRealMm.remove(wallIndex);
      // Shift keys above insertion point
      final newMm = <int, double>{};
      activeShape.wallRealMm.forEach((k, v) {
        newMm[k <= wallIndex ? k : k + 1] = v;
      });
      activeShape.wallRealMm
        ..clear()
        ..addAll(newMm);
      // Enter drag mode on the new point
      _activePointIndex = wallIndex + 1;
      _isDraggingActivePoint = true;
    });
    _syncWallDefinitions();
  }

  bool _pointInsidePolygon(Offset screenPos, List<Offset> worldPoints) {
    final pts = worldPoints.map(worldToScreen).toList();
    bool inside = false;
    int j = pts.length - 1;
    for (int i = 0; i < pts.length; i++) {
      if (((pts[i].dy > screenPos.dy) != (pts[j].dy > screenPos.dy)) &&
          (screenPos.dx < (pts[j].dx - pts[i].dx) *
              (screenPos.dy - pts[i].dy) /
              (pts[j].dy - pts[i].dy) + pts[i].dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  double _pointToSegmentDist(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final proj = Offset(a.dx + t.clamp(0, 1) * dx, a.dy + t.clamp(0, 1) * dy);
    return (p - proj).distance;
  }

  /// Projects point [p] onto segment [a→b], returns the clamped parameter t ∈ [0,1]
  /// and the projected point.
  (double, Offset) _projectPointOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (0.0, a);
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    final tc = t.clamp(0.0, 1.0);
    return (tc, a + ab * tc);
  }

  double _tAlong(Offset base, Offset vec, double len, Offset pt) {
    if (len == 0) return 0.0;
    return ((pt - base).dx * vec.dx + (pt - base).dy * vec.dy) /
        (len * len);
  }

  /// Returns the overlapping sub-segment between wall [mA→mB] and wall [oA→oB]
  /// when they are parallel, collinear (within [perpThresh]), and overlap.
  /// Returns null if no overlap or not collinear.
  ({Offset start, Offset end, Offset oStart, Offset oEnd})? _wallOverlapSegment(
      Offset mA, Offset mB, Offset oA, Offset oB,
      {double perpThresh = 14.0, double parallelThresh = 0.08}) {
    final mDir = mB - mA;
    final mLen = mDir.distance;
    final oDir = oB - oA;
    final oLen = oDir.distance;
    if (mLen < 1 || oLen < 1) return null;

    final mUnit = mDir / mLen;
    final oUnit = oDir / oLen;

    // Must be parallel (dot product of unit vectors ≈ ±1)
    final dot = (mUnit.dx * oUnit.dx + mUnit.dy * oUnit.dy).abs();
    if (dot < 1.0 - parallelThresh) return null;

    // Must be collinear — perpendicular distance from oA to line mA→mB must be small
    final cross = (oA - mA).dx * mUnit.dy - (oA - mA).dy * mUnit.dx;
    if (cross.abs() > perpThresh) return null;

    // Project oA and oB onto the mA→mB axis
    final tOA = (oA - mA).dx * mUnit.dx + (oA - mA).dy * mUnit.dy;
    final tOB = (oB - mA).dx * mUnit.dx + (oB - mA).dy * mUnit.dy;

    // Overlap along the axis
    final tStart = tOA < tOB ? tOA : tOB;
    final tEnd = tOA < tOB ? tOB : tOA;
    final overlapStart = tStart.clamp(0.0, mLen);
    final overlapEnd = tEnd.clamp(0.0, mLen);
    if (overlapEnd - overlapStart < 4.0) return null; // too short, ignore

    final sharedStart = mA + mUnit * overlapStart;
    final sharedEnd = mA + mUnit * overlapEnd;

    // Corresponding points on the other wall
    final oUnitSigned = dot > 0 ? oUnit : -oUnit; // match direction
    final oBase = dot > 0 ? oA : oB;
    final tOnO_start =
        (sharedStart - oBase).dx * oUnitSigned.dx + (sharedStart - oBase).dy * oUnitSigned.dy;
    final tOnO_end =
        (sharedEnd - oBase).dx * oUnitSigned.dx + (sharedEnd - oBase).dy * oUnitSigned.dy;
    final oSharedStart = oBase + oUnitSigned * tOnO_start.clamp(0.0, oLen);
    final oSharedEnd = oBase + oUnitSigned * tOnO_end.clamp(0.0, oLen);

    return (
      start: sharedStart,
      end: sharedEnd,
      oStart: oSharedStart,
      oEnd: oSharedEnd,
    );
  }

  /// Finds the best wall pair between movingShape and all other closed shapes.
  /// Returns (myWallIndex, otherShapeIndex, otherWallIndex, overlapData) or null.
  ({
    int mw,
    int os,
    int ow,
    Offset sharedStart,
    Offset sharedEnd,
    Offset oSharedStart,
    Offset oSharedEnd
  })? _findWallSnapCandidate(SketchShape movingShape) {
    final int n = movingShape.points.length;
    for (int mi = 0; mi < n; mi++) {
      final Offset mA = movingShape.points[mi];
      final Offset mB = movingShape.points[(mi + 1) % n];

      for (int s = 0; s < shapes.length; s++) {
        if (s == _movingShapeIndex) continue;
        if (!shapes[s].isClosed) continue;
        final other = shapes[s];
        final int on = other.points.length;
        for (int oi = 0; oi < on; oi++) {
          final Offset oA = other.points[oi];
          final Offset oB = other.points[(oi + 1) % on];
          final overlap = _wallOverlapSegment(mA, mB, oA, oB);
          if (overlap != null) {
            return (
              mw: mi,
              os: s,
              ow: oi,
              sharedStart: overlap.start,
              sharedEnd: overlap.end,
              oSharedStart: overlap.oStart,
              oSharedEnd: overlap.oEnd,
            );
          }
        }
      }
    }
    return null;
  }

  /// Returns (myPointIndex, otherShapeIndex, otherPointIndex) or null
  ({int mp, int os, int op})? _findVertexSnapCandidate(SketchShape movingShape) {
    for (int mi = 0; mi < movingShape.points.length; mi++) {
      final Offset mp = movingShape.points[mi];
      for (int s = 0; s < shapes.length; s++) {
        if (s == _movingShapeIndex) continue;
        if (!shapes[s].isClosed) continue;
        for (int oi = 0; oi < shapes[s].points.length; oi++) {
          final Offset op = shapes[s].points[oi];
          if ((mp - op).distance < wallSnapThresholdWorld) {
            return (mp: mi, os: s, op: oi);
          }
        }
      }
    }
    return null;
  }

  void _syncWallDefinitions() {
    _wallAngles.clear();
    _wallDrawnLengths.clear();
    final pts = activeShape.points;
    final n = pts.length;
    if (n < 2) return;
    for (int i = 0; i < n - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final dx = b.dx - a.dx, dy = b.dy - a.dy;
      _wallAngles.add(math.atan2(dy, dx));
      _wallDrawnLengths.add(math.sqrt(dx * dx + dy * dy));
    }
  }

  void _rebuildPointsFromChain() {
    if (_wallAngles.isEmpty || activeShape.points.isEmpty) return;
    final pts = [activeShape.points[0]];
    for (int i = 0; i < _wallAngles.length; i++) {
      final len = activeShape.wallRealMm.containsKey(i)
          ? activeShape.wallRealMm[i]! / mmPerUnit
          : _wallDrawnLengths[i];
      pts.add(Offset(
        pts.last.dx + len * math.cos(_wallAngles[i]),
        pts.last.dy + len * math.sin(_wallAngles[i]),
      ));
    }
    activeShape.points
      ..clear()
      ..addAll(pts);
  }

  void _applyRealMeasurement(int wallIndex, double realMm) {
    if (wallIndex >= _wallAngles.length) return;
    if (_wallLengthWorld(wallIndex) < 1e-6) return;
    _saveUndo();
    setState(() {
      activeShape.wallRealMm[wallIndex] = realMm;
      _rebuildPointsFromChain();
      _selectedWallIndex = -1;
      _activePointIndex = -1;
    });
  }

  
  // ── Geometry calculations ────────────────────────────────────────────────
  double _totalPerimeter() {
    if (activeShape.points.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < activeShape.points.length - 1; i++) {
      final dx = activeShape.points[i + 1].dx - activeShape.points[i].dx;
      final dy = activeShape.points[i + 1].dy - activeShape.points[i].dy;
      total += math.sqrt(dx * dx + dy * dy);
    }
    if (activeShape.isClosed) {
      final dx = activeShape.points.first.dx - activeShape.points.last.dx;
      final dy = activeShape.points.first.dy - activeShape.points.last.dy;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }

  double _totalArea() {
    if (!activeShape.isClosed || activeShape.points.length < 3) return 0;
    double area = 0;
    final n = activeShape.points.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += activeShape.points[i].dx * activeShape.points[j].dy;
      area -= activeShape.points[j].dx * activeShape.points[i].dy;
    }
    return area.abs() / 2.0;
  }

  // ── Label helper ─────────────────────────────────────────────────────────
  String _angleLabel() {
    if (_currentAngleDeg == null) return '';
    if (_isAngleSnapped && _snappedAngle != null) {
      return '${_snappedAngle!.toStringAsFixed(0)}°';
    }
    return '${_currentAngleDeg!.toStringAsFixed(1)}°';
  }

  // ── Gesture handlers ─────────────────────────────────────────────────────
  void _onPointerDown(PointerDownEvent event) {
    _dragOccurred = false;
    _panStartPosition = event.localPosition;
    _panConfirmed = false;
    _snapTargetIndex = null;
    _prevWallAngle = null;
    _nextWallAngle = null;

    // ── MOVE MODE ──────────────────────────────────────────────
    if (_isMoveMode) {
      for (int s = 0; s < shapes.length; s++) {
        if (!shapes[s].isClosed) continue;
        if (_pointInsidePolygon(event.localPosition, shapes[s].points)) {
          _saveUndo();
          setState(() {
            _movingShapeIndex = s;
            activeIndex = s;
            _moveStartWorld = screenToWorld(event.localPosition);
            _activePointIndex = -1;
          });
          return;
        }
      }
      return; // move mode but not on any shape -> do nothing
    }
    // ── end move mode ──────────────────────────────────────────

    if (activeShape.isClosed) {
      final idx = _findNearPoint(event.localPosition,
          radius: pointSelectRadiusScreen);
      setState(() {
        _activePointIndex = idx;
        _isDraggingActivePoint = idx >= 0;
      });
      return;
    }

    if (_activePointIndex >= 0) {
      final dist = (event.localPosition -
              worldToScreen(activeShape.points[_activePointIndex]))
          .distance;
      if (dist < lastPointGlowRadius) {
        _isDraggingActivePoint = true;
        return;
      }
      final idx = _findNearPoint(event.localPosition,
          excludeIndex: _activePointIndex,
          radius: pointSelectRadiusScreen);
      if (idx >= 0) {
        setState(() {
          _activePointIndex = idx;
          _isDraggingActivePoint = true;
        });
        return;
      }
      setState(() {
        _activePointIndex = -1;
        _isDraggingActivePoint = false;
      });
    }

    if (activeShape.points.isNotEmpty && _isNearLastPoint(event.localPosition)) {
      _isDraggingLastPoint = true;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    // ── MOVE MODE ──────────────────────────────────────────────
    if (_movingShapeIndex >= 0 && _moveStartWorld != null) {
      // Clear stale shared walls every frame during move - prevents ghost walls
      for (final sw in shapes[_movingShapeIndex].sharedWalls) {
        if (sw.otherShapeIndex < shapes.length) {
          shapes[sw.otherShapeIndex]
              .sharedWalls
              .removeWhere((s) => s.otherShapeIndex == _movingShapeIndex);
        }
      }
      shapes[_movingShapeIndex].sharedWalls.clear();

      _dragOccurred = true;
      final currentWorld = screenToWorld(event.localPosition);
      final delta = currentWorld - _moveStartWorld!;
      setState(() {
        final shape = shapes[_movingShapeIndex];
        shape.points = shape.points.map((p) => p + delta).toList();
        _moveStartWorld = currentWorld;
      });

      // Check for wall snap candidate during drag
      final movingShape = shapes[_movingShapeIndex];
      if (movingShape.isClosed) {
        final candidate = _findWallSnapCandidate(movingShape);
        setState(() {
          _snapCandidateShape = candidate?.os ?? -1;
          _snapCandidateWall = candidate?.ow ?? -1;
        });
      }
      return;
    }
    // ── end move mode ──────────────────────────────────────────

    if (activeShape.isClosed) {
      if (_isDraggingActivePoint && _activePointIndex >= 0) {
        _dragOccurred = true;
        final raw = screenToWorld(event.localPosition);
        final snapIdx = _findNearPoint(event.localPosition,
            excludeIndex: _activePointIndex,
            radius: pointSnapRadiusScreen);
        final Offset pos = snapIdx >= 0
            ? activeShape.points[snapIdx]
            : _updateMiddlePointAngles(_activePointIndex, raw);
        if (snapIdx < 0) {
          // angles already updated inside _updateMiddlePointAngles
        } else {
          _prevWallAngle = null;
          _nextWallAngle = null;
          _prevWallSnapped = false;
          _nextWallSnapped = false;
        }
        setState(() {
          _snapTargetIndex = snapIdx >= 0 ? snapIdx : null;
          activeShape.points[_activePointIndex] = pos;
        });
      }
      return;
    }

    if (_isDraggingActivePoint && _activePointIndex >= 0) {
      _dragOccurred = true;
      final raw = screenToWorld(event.localPosition);
      final snapIdx = _findNearPoint(event.localPosition,
          excludeIndex: _activePointIndex,
          radius: pointSnapRadiusScreen);
      final Offset pos = snapIdx >= 0
          ? activeShape.points[snapIdx]
          : _updateMiddlePointAngles(_activePointIndex, raw);
      if (snapIdx >= 0) {
        _prevWallAngle = null;
        _nextWallAngle = null;
        _prevWallSnapped = false;
        _nextWallSnapped = false;
      }
      setState(() {
        _snapTargetIndex = snapIdx >= 0 ? snapIdx : null;
        activeShape.points[_activePointIndex] = pos;
        _cursorWorld = null;
      });
      return;
    }

    if (_isDraggingLastPoint && activeShape.points.isNotEmpty) {
      _dragOccurred = true;
      final raw = screenToWorld(event.localPosition);
      final snapIdx = _findNearPoint(event.localPosition,
          excludeIndex: activeShape.points.length - 1,
          radius: pointSnapRadiusScreen);
      Offset newPos;
      if (snapIdx >= 0) {
        newPos = activeShape.points[snapIdx];
        _currentAngleDeg = null;
        _nearestSnapAngleDeg = null;
        _snapDiffDeg = null;
        _snappedAngle = null;
        _isAngleSnapped = false;
      } else if (activeShape.points.length >= 2) {
        newPos = _computeAngle(activeShape.points[activeShape.points.length - 2], raw);
      } else {
        newPos = raw;
        _currentAngleDeg = null;
        _nearestSnapAngleDeg = null;
        _snapDiffDeg = null;
        _snappedAngle = null;
        _isAngleSnapped = false;
      }
      setState(() {
        _snapTargetIndex = snapIdx >= 0 ? snapIdx : null;
        activeShape.points[activeShape.points.length - 1] = newPos;
        _cursorWorld = null;
      });
      return;
    }

    if (activeShape.points.isNotEmpty && _activePointIndex < 0) {
      final raw = snapToGrid(screenToWorld(event.localPosition));
      final crossSnap = _findSnapPointAcrossShapes(event.localPosition);
      setState(() => _cursorWorld = crossSnap ?? _computeAngle(activeShape.points.last, raw));
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    // ── MOVE MODE ──────────────────────────────────────────────
    if (_movingShapeIndex >= 0) {
      if (_movingShapeIndex >= 0) {
        final movingShape = shapes[_movingShapeIndex];
        if (movingShape.isClosed) {
          final candidate = _findWallSnapCandidate(movingShape);
          if (candidate != null) {
            final other = shapes[candidate.os];
            // Snap: translate moving shape so its shared segment aligns to the other
            final myMid = Offset((candidate.sharedStart.dx + candidate.sharedEnd.dx) / 2,
                (candidate.sharedStart.dy + candidate.sharedEnd.dy) / 2);
            final oMid = Offset((candidate.oSharedStart.dx + candidate.oSharedEnd.dx) / 2,
                (candidate.oSharedStart.dy + candidate.oSharedEnd.dy) / 2);
            final delta = oMid - myMid;
            movingShape.points = movingShape.points.map((p) => p + delta).toList();

            // Recalculate overlap after snapping
            final mA = movingShape.points[candidate.mw];
            final mB =
                movingShape.points[(candidate.mw + 1) % movingShape.points.length];
            final oA = other.points[candidate.ow];
            final oB = other.points[(candidate.ow + 1) % other.points.length];
            final finalOverlap = _wallOverlapSegment(mA, mB, oA, oB);
            if (finalOverlap != null) {
              // Remove any existing shared wall for these indices
              movingShape.sharedWalls.removeWhere((sw) => sw.myWallIndex == candidate.mw);
              other.sharedWalls.removeWhere((sw) =>
                  sw.otherShapeIndex == _movingShapeIndex && sw.myWallIndex == candidate.ow);

              // Compute parametric t-values along each wall
              final mVec = mB - mA;
              final mLen = mVec.distance;
              final oVec = oB - oA;
              final oLen = oVec.distance;

              final tMS =
                  _tAlong(mA, mVec, mLen, finalOverlap.start).clamp(0.0, 1.0);
              final tME = _tAlong(mA, mVec, mLen, finalOverlap.end).clamp(0.0, 1.0);
              final tOS =
                  _tAlong(oA, oVec, oLen, finalOverlap.oStart).clamp(0.0, 1.0);
              final tOE = _tAlong(oA, oVec, oLen, finalOverlap.oEnd).clamp(0.0, 1.0);

              movingShape.sharedWalls.add(SharedWall(
                otherShapeIndex: candidate.os,
                myWallIndex: candidate.mw,
                otherWallIndex: candidate.ow,
                tStart: tMS,
                tEnd: tME,
              ));
              other.sharedWalls.add(SharedWall(
                otherShapeIndex: _movingShapeIndex,
                myWallIndex: candidate.ow,
                otherWallIndex: candidate.mw,
                tStart: tOS,
                tEnd: tOE,
              ));
            }
          }

          // Vertex-to-vertex snap
          final vertexCandidate = _findVertexSnapCandidate(movingShape);
          if (vertexCandidate != null) {
            final Offset myPt = movingShape.points[vertexCandidate.mp];
            final Offset otherPt = shapes[vertexCandidate.os].points[vertexCandidate.op];
            final Offset delta = otherPt - myPt;
            // Translate entire moving shape so the two vertices meet exactly
            movingShape.points = movingShape.points.map((p) => p + delta).toList();
          }
        }
      }
      setState(() {
        _snapCandidateShape = -1;
        _snapCandidateWall = -1;
      });

      setState(() {
        _movingShapeIndex = -1;
        _moveStartWorld = null;
      });
      _isDraggingLastPoint = false;
      _isDraggingActivePoint = false;
      _panStartPosition = null;
      _panConfirmed = false;
      return;
    }
    // ── end move mode ──────────────────────────────────────────

    if (_isDraggingLastPoint &&
        _snapTargetIndex == 0 &&
        activeShape.points.length >= 3) {
      _saveUndo();
      setState(() {
        activeShape.isClosed = true;
        _cursorWorld = null;
        _currentAngleDeg = null;
        _nearestSnapAngleDeg = null;
        _snapDiffDeg = null;
        _snappedAngle = null;
        _isAngleSnapped = false;
        _snapTargetIndex = null;
        _prevWallAngle = null;
        _nextWallAngle = null;
      });
      _syncWallDefinitions();
      _showRoomNameDialog();
    } else {
      if (_isDraggingActivePoint && _dragOccurred) {
        if (_activePointIndex > 0) activeShape.wallRealMm.remove(_activePointIndex - 1);
        if (_activePointIndex < _wallAngles.length) activeShape.wallRealMm.remove(_activePointIndex);
        _saveUndo();
        _syncWallDefinitions();
      }
      _syncWallDefinitions();
      setState(() {
        _snapTargetIndex = null;
        _prevWallAngle = null;
        _nextWallAngle = null;
      });
    }
    _isDraggingLastPoint = false;
    _isDraggingActivePoint = false;
    _panStartPosition = null;
    _panConfirmed = false;
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (activeShape.isClosed || activeShape.points.isEmpty || _activePointIndex >= 0) return;
    final raw = snapToGrid(screenToWorld(event.localPosition));
    setState(() => _cursorWorld = _computeAngle(activeShape.points.last, raw));
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      setState(() {
        final factor = event.scrollDelta.dy > 0 ? 0.92 : 1.08;
        final focalWorld = screenToWorld(event.position);
        _scale = (_scale * factor).clamp(0.05, 50.0);
        _panOffset = event.position - focalWorld * _scale;
      });
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _scaleStart = _scale;
    _panConfirmed = false;
    if (d.pointerCount >= 2) {
      _isMultiTouch = true;
      _tapCancelled = true;
      _pendingTap = null;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_isDraggingLastPoint || _isDraggingActivePoint || _movingShapeIndex >= 0) return;
    if (d.pointerCount >= 2) {
      _isMultiTouch = true;
      _tapCancelled = true;
      _pendingTap = null;
      _panConfirmed = true;
      setState(() {
        final focalWorld = screenToWorld(d.focalPoint);
        _scale = (_scaleStart * d.scale).clamp(0.05, 50.0);
        _panOffset = d.focalPoint - focalWorld * _scale;
      });
      return;
    }
    if (!_panConfirmed && _panStartPosition != null) {
      if ((d.focalPoint - _panStartPosition!).distance > panThreshold) {
        _panConfirmed = true;
      }
    }
    if (_panConfirmed) setState(() => _panOffset += d.focalPointDelta);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _panConfirmed = false;
    Future.delayed(const Duration(milliseconds: 150), () {
      _isMultiTouch = false;
      _tapCancelled = false;
    });
  }

  void _onLongPress(LongPressStartDetails details) {
    // Only works on a closed active shape
    if (!activeShape.isClosed) return;
    if (_isMoveMode) return;

    // Make sure tap is not on an existing point
    final nearPt = _findNearPoint(details.localPosition, radius: pointSelectRadiusScreen);
    if (nearPt >= 0) return;

    final wallIdx = _findNearWall(details.localPosition);
    if (wallIdx < 0) return;

    _insertPointOnWall(wallIdx, details.localPosition);
  }

  void _onTapDown(TapDownDetails details) {
    if (_isMultiTouch) return;
    if (_isMoveMode) return; // taps handled by pointer down/up in move mode

    // Prioritize direct wall taps over label hit-rect taps
    if (activeShape.isClosed) {
      final wallIdx = _findNearWall(details.localPosition);
      if (wallIdx >= 0) {
        setState(() {
          _activePointIndex = -1;
          _selectedWallIndex = wallIdx;
        });
        return;
      }
    }

    // Tap on dimension label -> edit that wall
    for (final hit in _labelHitRects) {
      if (hit.rect.contains(details.localPosition)) {
        setState(() {
          activeIndex = hit.shapeIndex;
          _selectedWallIndex = hit.wallIndex;
          _activePointIndex = -1;
        });
        showSketchWallEditDialog(hit.wallIndex);
        return;
      }
    }
    if (_dragOccurred) { _dragOccurred = false; return; }

    // Check if tap is inside a different closed shape -> switch active
    for (int s = 0; s < shapes.length; s++) {
      if (s == activeIndex) continue;
      if (!shapes[s].isClosed) continue;
      if (_pointInsidePolygon(details.localPosition, shapes[s].points)) {
        setState(() {
          activeIndex = s;
          _activePointIndex = -1;
          _selectedWallIndex = -1;
          _cursorWorld = null;
        });
        return;
      }
    }

    if (activeShape.isClosed) {
      setState(() {
        _activePointIndex = _findNearPoint(details.localPosition,
            radius: pointSelectRadiusScreen);
        _selectedWallIndex = -1;
      });
      return;
    }

    if (activeShape.points.length >= 3) {
      final dist = (details.localPosition - worldToScreen(activeShape.points.first))
          .distance;
      if (dist < pointSelectRadiusScreen) {
        _saveUndo();
        setState(() {
          activeShape.isClosed = true;
          _cursorWorld = null;
          _currentAngleDeg = null;
          _nearestSnapAngleDeg = null;
          _snapDiffDeg = null;
          _snappedAngle = null;
          _isAngleSnapped = false;
          _activePointIndex = -1;
        });
        _syncWallDefinitions();
        _showRoomNameDialog();
        return;
      }
    }

    final existingIdx = _findNearPoint(details.localPosition,
        excludeIndex: activeShape.points.isEmpty ? -1 : activeShape.points.length - 1,
        radius: pointSelectRadiusScreen);
    if (existingIdx >= 0 && activeShape.points.length > 1) {
      setState(() => _activePointIndex = existingIdx);
      return;
    }

    if (_activePointIndex >= 0) {
      final dist = (details.localPosition -
              worldToScreen(activeShape.points[_activePointIndex]))
          .distance;
      if (dist > pointSelectRadiusScreen) {
        setState(() => _activePointIndex = -1);
      }
      return;
    }

    if (activeShape.points.isNotEmpty && _isNearLastPoint(details.localPosition)) return;

    _pendingTap = details;
    _tapCancelled = false;
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_tapCancelled || _pendingTap == null) return;
      _commitTap(_pendingTap!);
      _pendingTap = null;
    });
  }

  void _commitTap(TapDownDetails details) {
    if (activeShape.isClosed || _isMultiTouch) return;
    final raw = snapToGrid(screenToWorld(details.localPosition));
    final crossSnap = _findSnapPointAcrossShapes(details.localPosition);
    final pos = crossSnap ??
      (activeShape.points.isNotEmpty
        ? _computeAngle(activeShape.points.last, raw)
        : raw);
    if (activeShape.points.isNotEmpty &&
        (pos - activeShape.points.last).distance < minPointDistance) return;
    _saveUndo();
    setState(() {
      activeShape.points.add(pos);
      _cursorWorld = null;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
    });
    _syncWallDefinitions();
  }
  
  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {

    // Called when user drags an object from the panel and releases it
    void _onObjectDropped(Offset screenPos) {
      if (_draggingObjectType == null || !activeShape.isClosed) return;
      
      // Check if they dropped it near a wall
      final hit = findNearestWall(
        screenPos: screenPos,
        points: activeShape.points,     
        isClosed: activeShape.isClosed, 
        worldToScreen: worldToScreen,
        screenToWorld: screenToWorld,
      );
      
      if (hit == null) {
        setState(() {
          _draggingObjectType = null;
          _dragObjectScreenPos = null;
          _dragWallHit = null;
        });
        return;
      }
      
      _saveUndo();
      setState(() {
        _objectCounter++;
        activeShape.roomObjects.add(RoomObject(
          id: 'obj_$_objectCounter',
          type: _draggingObjectType!,
          wallIndex: hit.wallIndex,
          positionAlong: hit.positionAlong,
          widthMm: _draggingObjectType == RoomObjectType.door ? 900 : 1200,
          heightMm: _draggingObjectType == RoomObjectType.door ? 2100 : 1200,
          elevationMm: _draggingObjectType == RoomObjectType.door ? 0 : 900,
        ));
        _draggingObjectType = null;
        _dragObjectScreenPos = null;
        _dragWallHit = null;
      });
    }

    // Called when user taps a placed object to edit/delete it
    void _onObjectTapped(String id) {
      final obj = activeShape.roomObjects.firstWhere((o) => o.id == id);
      showDialog(
        context: context,
        builder: (ctx) => ObjectMeasurementDialog(
          roomObject: obj,
          onSave: (updatedObj) {
            setState(() {
              final idx = activeShape.roomObjects.indexWhere((o) => o.id == id);
              if (idx >= 0) activeShape.roomObjects[idx] = updatedObj;
            });
          },
          onDelete: () {
            _saveUndo();
            setState(() {
              activeShape.roomObjects.removeWhere((o) => o.id == id);
              _selectedObjectId = null;
            });
          },
        ),
      );
    }
    final topPadding = MediaQuery.of(context).padding.top;

    Offset? angleRefWorld;
    Offset? angleTargetWorld;
    if (_isDraggingLastPoint && activeShape.points.length >= 2) {
      angleRefWorld = activeShape.points[activeShape.points.length - 2];
      angleTargetWorld = activeShape.points.last;
    } else if (!_isDraggingLastPoint &&
        _activePointIndex < 0 &&
        activeShape.points.isNotEmpty &&
        _cursorWorld != null) {
      angleRefWorld = activeShape.points.last;
      angleTargetWorld = _cursorWorld;
    }

    double? liveDistance;
    if (!activeShape.isClosed && activeShape.points.isNotEmpty && _activePointIndex < 0) {
      final t = _cursorWorld;
      if (t != null) {
        final dx = t.dx - activeShape.points.last.dx, dy = t.dy - activeShape.points.last.dy;
        liveDistance = math.sqrt(dx * dx + dy * dy);
      }
    }

    final bool showAngleStrip = _currentAngleDeg != null &&
        _activePointIndex < 0 &&
        activeShape.points.length >= 2 &&
        !activeShape.isClosed;

    _labelHitRects.clear();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          // ── Canvas ───────────────────────────────────────────────────
          Listener(
            onPointerSignal: _onPointerSignal,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerHover: _onPointerHover,
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapDown: _onTapDown,
              onLongPressStart: _onLongPress,
              child: CustomPaint(
                painter: SketchPainter(
                  panOffset: _panOffset,
                  scale: _scale,
                  minorGrid: minorGrid,
                  majorGrid: majorGrid,
                  cursorWorld: _cursorWorld,
                  snapRadiusWorld: snapRadiusWorld,
                  isDraggingLastPoint: _isDraggingLastPoint,
                  lastPointGlowRadius: lastPointGlowRadius,
                  lastPointRingRadius: lastPointRingRadius,
                  snappedAngle: _snappedAngle,
                  isAngleSnapped: _isAngleSnapped,
                  currentAngleDeg: _currentAngleDeg,
                  nearestSnapAngleDeg: _nearestSnapAngleDeg,
                  snapDiffDeg: _snapDiffDeg,
                  angleRefWorld: angleRefWorld,
                  angleTargetWorld: angleTargetWorld,
                  snapAngles: snapAngles,
                  activePointIndex: _activePointIndex,
                  snapTargetIndex: _snapTargetIndex,
                  prevWallAngle: _prevWallAngle,
                  nextWallAngle: _nextWallAngle,
                  prevWallSnapped: _prevWallSnapped,
                  nextWallSnapped: _nextWallSnapped,
                  selectedWallIndex: _selectedWallIndex,
                  snapCandidateShape: _snapCandidateShape,
                  snapCandidateWall: _snapCandidateWall,
                  labelHitRects: _labelHitRects,
                  shapes: shapes,
                  activeIndex: activeIndex,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // ── Object panel (right side) — only shown when room is closed ───────────
          if (activeShape.isClosed)
            Positioned(
              right: 8,
              top: 80,
              child: Column(
                children: [
                  _ObjectPanelButton(
                    icon: Icons.door_front_door,
                    label: 'Door',
                    onDragStarted: () => setState(() =>
                        _draggingObjectType = RoomObjectType.door),
                    onDragEnd: (details) => _onObjectDropped(details.offset),
                  ),
                  const SizedBox(height: 8),
                  _ObjectPanelButton(
                    icon: Icons.window,
                    label: 'Window',
                    onDragStarted: () => setState(() =>
                        _draggingObjectType = RoomObjectType.window),
                    onDragEnd: (details) => _onObjectDropped(details.offset),
                  ),
                ],
              ),
            ),

          // ── 3D View button ────────────────────────────────────────────────────────
          if (activeShape.isClosed && activeShape.points.length >= 3)
            Positioned(
              right: 8,
              bottom: 62,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.view_in_ar, size: 16),
                label: const Text('3D View',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B2FBE),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Room3DScreen(
                        points: activeShape.points,
                        roomObjects: activeShape.roomObjects,
                        wallRealMm: activeShape.wallRealMm,
                        bleManager: widget.bleManager,
                      ),
                    ),
                  );
                },
              ),
            ),

          
          // ── Top toolbar ──────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.only(top: topPadding),
              color: const Color(0xFF2D2D2D),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Icon(Icons.straighten,
                        color: Color(0xFF00AAFF), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        activeShape.isClosed
                            ? _selectedWallIndex >= 0
                                ? 'Wall ${_selectedWallIndex + 1} selected — enter real measurement'
                                : _activePointIndex >= 0
                                    ? 'Drag point ${_activePointIndex + 1} to reposition'
                                    : _waitingForBle
                                        ? 'Point device at wall → press BOOT button'
                                        : 'Tap a wall to edit its length'
                            : activeShape.points.isEmpty
                                ? 'Tap to place first corner'
                                : _isDraggingLastPoint
                                    ? 'Drag | ${_angleLabel()}'
                                    : _activePointIndex >= 0
                                        ? 'Drag point ${_activePointIndex + 1} to reposition'
                                        : _isAngleSnapped
                                            ? 'Snapped: ${_angleLabel()}'
                                            : 'Tap next corner | Drag orange to adjust',
                        style: TextStyle(
                          color: _activePointIndex >= 0
                              ? const Color(0xFFFFAA00)
                              : _isAngleSnapped
                                  ? const Color(0xFF00CC44)
                                  : const Color(0xFFCCCCCC),
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF555555)),
                      ),
                      child: const Text('1div=100mm',
                          style: TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 10,
                              fontFamily: 'monospace')),
                    ),
                    const SizedBox(width: 6),
                    Text('${(_scale * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 12,
                            fontFamily: 'monospace')),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: Color(0xFFAAAAAA), size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Polar tracking HUD ───────────────────────────────────────
          if (_currentAngleDeg != null &&
              _activePointIndex < 0 &&
              !activeShape.isClosed &&
              activeShape.points.isNotEmpty &&
              _cursorWorld != null)
            Positioned(
              bottom: showAngleStrip ? 86 : 60,
              left: 0, right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isAngleSnapped
                        ? const Color(0xFF003311).withOpacity(0.95)
                        : const Color(0xFF1A1A2E).withOpacity(0.92),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isAngleSnapped
                          ? const Color(0xFF00CC44)
                          : const Color(0xFF334466),
                      width: _isAngleSnapped ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('ANGLE',
                            style: TextStyle(
                                color: Color(0xFF556677),
                                fontSize: 9,
                                fontFamily: 'monospace')),
                        Text('${_currentAngleDeg!.toStringAsFixed(1)}°',
                            style: TextStyle(
                              color: _isAngleSnapped
                                  ? const Color(0xFF00CC44)
                                  : const Color(0xFF88AACC),
                              fontSize: 18,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            )),
                      ]),
                      if (liveDistance != null) ...[
                        const SizedBox(width: 16),
                        Container(
                            width: 1,
                            height: 36,
                            color: const Color(0xFF334466)),
                        const SizedBox(width: 16),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('LENGTH',
                              style: TextStyle(
                                  color: Color(0xFF556677),
                                  fontSize: 9,
                                  fontFamily: 'monospace')),
                          Text(formatLength(liveDistance),
                              style: const TextStyle(
                                color: Color(0xFF0099FF),
                                fontSize: 18,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              )),
                        ]),
                      ],
                      if (_nearestSnapAngleDeg != null) ...[
                        const SizedBox(width: 16),
                        Container(
                            width: 1,
                            height: 36,
                            color: const Color(0xFF334466)),
                        const SizedBox(width: 16),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            _isAngleSnapped ? 'SNAPPED' : 'NEAREST',
                            style: TextStyle(
                                color: _isAngleSnapped
                                    ? const Color(0xFF00CC44)
                                    : const Color(0xFF556677),
                                fontSize: 9,
                                fontFamily: 'monospace'),
                          ),
                          Text('${_nearestSnapAngleDeg!.toStringAsFixed(0)}°',
                              style: TextStyle(
                                color: _isAngleSnapped
                                    ? const Color(0xFF00FF55)
                                    : const Color(0xFFFFAA33),
                                fontSize: 18,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              )),
                        ]),
                        if (!_isAngleSnapped) ...[
                          const SizedBox(width: 12),
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text('delta',
                                style: TextStyle(
                                    color: Color(0xFF556677),
                                    fontSize: 9,
                                    fontFamily: 'monospace')),
                            Text(
                              '${(_snapDiffDeg ?? 0).toStringAsFixed(1)}°',
                              style: TextStyle(
                                color: (_snapDiffDeg ?? 99) < 1.5
                                    ? const Color(0xFFFFCC44)
                                    : const Color(0xFF556677),
                                fontSize: 14,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ]),
                        ],
                      ],
                      if (_isAngleSnapped) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.lock,
                            color: Color(0xFF00CC44), size: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // ── Bottom toolbar ───────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showAngleStrip)
                  GestureDetector(
                    onTap: showSketchAngleEditor,  // ← mixin method
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isAngleSnapped
                            ? const Color(0xFF003A1A)
                            : const Color(0xFF363636),
                        border: Border(
                          top: BorderSide(
                            color: _isAngleSnapped
                                ? const Color(0xFF00CC44)
                                : const Color(0xFF555555),
                            width: _isAngleSnapped ? 1.5 : 1.0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_isAngleSnapped)
                            const Icon(Icons.lock,
                                size: 13, color: Color(0xFF00CC44))
                          else
                            const Icon(Icons.rotate_90_degrees_ccw,
                                size: 13, color: Color(0xFF888888)),
                          const SizedBox(width: 6),
                          Text('ANGLE',
                              style: TextStyle(
                                color: _isAngleSnapped
                                    ? const Color(0xFF00CC44)
                                    : const Color(0xFF888888),
                                fontSize: 10,
                                fontFamily: 'monospace',
                                letterSpacing: 1.0,
                              )),
                          const SizedBox(width: 8),
                          Text(_angleLabel(),
                              style: TextStyle(
                                color: _isAngleSnapped
                                    ? const Color(0xFF00FF66)
                                    : const Color(0xFFEEEEEE),
                                fontSize: 20,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              )),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isAngleSnapped
                                  ? const Color(0xFF005522)
                                  : const Color(0xFF4A4A4A),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _isAngleSnapped
                                    ? const Color(0xFF00CC44)
                                    : const Color(0xFF666666),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.edit,
                                    size: 11, color: Color(0xFFAAAAAA)),
                                SizedBox(width: 4),
                                Text('EDIT',
                                    style: TextStyle(
                                      color: Color(0xFFCCCCCC),
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Container(
                  height: 52,
                  color: const Color(0xFF2D2D2D),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StatusItem(
                                label: 'MODE',
                                value: activeShape.isClosed
                                    ? _activePointIndex >= 0 ? 'EDIT' : 'DONE'
                                    : _isDraggingLastPoint
                                        ? 'DRAG'
                                        : _activePointIndex >= 0
                                            ? 'EDIT'
                                            : 'DRAW',
                              ),
                              const SizedBox(width: 8),
                              StatusItem(
                                  label: 'PTS',
                                  value: '${activeShape.points.length}'),
                              if (activeShape.isClosed && activeShape.points.length >= 2) ...[
                                const SizedBox(width: 8),
                                StatusItem(
                                  label: 'PERIM',
                                  value: formatLength(_totalPerimeter()),
                                ),
                              ],
                              if (activeShape.isClosed && activeShape.points.length >= 3) ...[
                                const SizedBox(width: 8),
                                StatusItem(
                                  label: 'AREA',
                                  value: formatArea(_totalArea()),
                                ),
                              ],
                              if (_activePointIndex >= 0 &&
                                  _activePointIndex < activeShape.points.length) ...[
                                const SizedBox(width: 8),
                                StatusItem(
                                  label: 'PT',
                                  value: '${_activePointIndex + 1}',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.undo, size: 18),
                        onPressed: _undoAllPointsStack.isEmpty ? null : _undo,
                        color: const Color(0xFFFFAA00),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Undo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo, size: 18),
                        onPressed: _redoAllPointsStack.isEmpty ? null : _redo,
                        color: const Color(0xFFFFAA00),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Redo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: activeShape.points.isEmpty ? null : _clear,
                        color: const Color(0xFFFF4444),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Clear',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        onPressed: activeShape.points.length >= 2
                            ? () => exportSketchPdf(
                                  context: context,
                                  shapes: shapes,
                                  totalPerimeter: _totalPerimeter(),
                                  totalArea: _totalArea(),
                                  roomObjects: activeShape.roomObjects,
                                )
                            : null,
                        color: const Color(0xFFFF4488),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Export PDF',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_box_outlined, size: 18),
                        onPressed: _addNewRoom,
                        color: const Color(0xFF00AAFF),
                        tooltip: 'Add Room',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.open_with,
                          size: 18,
                          color: _isMoveMode
                              ? const Color(0xFF00FF99)
                              : const Color(0xFF00AAFF),
                        ),
                        onPressed: () => setState(() {
                          _isMoveMode = !_isMoveMode;
                          _movingShapeIndex = -1;
                          _moveStartWorld = null;
                          _activePointIndex = -1;
                        }),
                        tooltip: _isMoveMode ? 'Move Mode ON' : 'Move Mode OFF',
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ObjectPanelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onDragStarted;
  final void Function(DraggableDetails) onDragEnd;

  const _ObjectPanelButton({
    required this.icon,
    required this.label,
    required this.onDragStarted,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: label,
      onDragStarted: onDragStarted,
      onDragEnd: onDragEnd,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF00AAFF),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 8)
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2A3A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334466)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF00AAFF), size: 20),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF778899),
                    fontSize: 9,
                    fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}