// lib/sketch/sketch_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;
import '../ble/ble_manager.dart';
import '../ble/ble_packet.dart';
import 'sketch_constants.dart';
import 'sketch_painter.dart';
import 'sketch_dialogs.dart';
import 'sketch_pdf_export.dart';
import 'sketch_widgets.dart';
import 'sketch_object.dart';


enum SketchMode { draw, select }

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
  Offset? _cursorWorld;
  bool _isDraggingLastPoint = false;
  bool _dragOccurred = false;
  bool _isMultiTouch = false;
  int _activePointIndex = -1;
  bool _isDraggingActivePoint = false;
  int? _snapTargetIndex;
  final List<List<Offset>> _undoStack = [];
  final List<List<Offset>> _redoStack = [];
  final List<bool> _undoClosedStack = [];
  final List<bool> _redoClosedStack = [];
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
  
  double? _pendingBleMm;
  bool _waitingForBle = false;
  List<SketchObject> _objects = [];
  int _activeObjIndex = 0;
  SketchMode _mode = SketchMode.draw;

  // ── PROXY GETTERS & SETTERS ──────────────────────────────────────────
  // These trick your existing gesture code into modifying the active room
  List<Offset> get _points => _objects.isNotEmpty ? _objects[_activeObjIndex].points : [];
  set _points(List<Offset> v) { if (_objects.isNotEmpty) _objects[_activeObjIndex].points = v; }

  bool get _isClosed => _objects.isNotEmpty ? _objects[_activeObjIndex].isClosed : false;
  set _isClosed(bool v) { if (_objects.isNotEmpty) _objects[_activeObjIndex].isClosed = v; }

  Map<int, double> get _wallRealMm => _objects.isNotEmpty ? _objects[_activeObjIndex].wallRealMm : {};
  // ───────────────────────────────────────────────────────────────────

  // ── Mixin contract — expose private state via public getters ─────────────
  @override List<Offset> get sketchPoints => _points;
  @override bool get sketchIsClosed => _isClosed;
  @override double? get sketchCurrentAngleDeg => _currentAngleDeg;
  @override double? get sketchSnappedAngle => _snappedAngle;
  @override Map<int, double> get sketchWallRealMm => _wallRealMm;
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
    _objects.add(SketchObject(id: '1', label: 'Room 1', points: []));

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
    if (_points.isEmpty || _isClosed) return false;
    if (_activePointIndex >= 0) return false;
    return (screenPos - worldToScreen(_points.last)).distance < lastPointGlowRadius;
  }

  int _findNearPoint(Offset screenPos,
      {int excludeIndex = -1,
      double radius = pointSelectRadiusScreen}) {
    for (int i = 0; i < _points.length; i++) {
      if (i == excludeIndex) continue;
      if ((screenPos - worldToScreen(_points[i])).distance < radius) return i;
    }
    return -1;
  }

  // ── Undo / redo ──────────────────────────────────────────────────────────
  void _saveUndo() {
    _undoStack.add(List<Offset>.of(_points));
    _undoClosedStack.add(_isClosed);
    _redoStack.clear();
    _redoClosedStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List<Offset>.of(_points));
    _redoClosedStack.add(_isClosed);
    setState(() {
      _points = _undoStack.removeLast();
      _isClosed = _undoClosedStack.removeLast();
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
    if (_redoStack.isEmpty) return;
    _undoStack.add(List<Offset>.of(_points));
    _undoClosedStack.add(_isClosed);
    setState(() {
      _points = _redoStack.removeLast();
      _isClosed = _redoClosedStack.removeLast();
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
      _points.clear();
      _isClosed = false;
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
        ? _points[idx - 1]
        : (_isClosed && _points.length > 1 ? _points.last : null);
    Offset? nextPt = idx < _points.length - 1
        ? _points[idx + 1]
        : (_isClosed && _points.length > 1 ? _points[0] : null);

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
    final Offset a = _points[wallIndex];
    final Offset b = _points[(wallIndex + 1) % _points.length];
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  int _findNearWall(Offset screenPos) {
    if (_points.length < 2) return -1;
    const double hitThresh = 18.0;
    final sp = _points.map(worldToScreen).toList();
    final int n = sp.length;
    final int wallCount = _isClosed ? n : n - 1;
    for (int i = 0; i < wallCount; i++) {
      if (_pointToSegmentDist(screenPos, sp[i], sp[(i + 1) % n]) < hitThresh) {
        return i;
      }
    }
    return -1;
  }

  double _pointToSegmentDist(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return (p - a).distance;
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final proj = Offset(a.dx + t.clamp(0, 1) * dx, a.dy + t.clamp(0, 1) * dy);
    return (p - proj).distance;
  }

  void _applyRealMeasurement(int wallIndex, double realMm) {
    final double pixelLen = _wallLengthWorld(wallIndex);
    if (pixelLen < 1e-6) return;
    final double ratio = (realMm / mmPerUnit) / pixelLen;
    if (ratio <= 0) return;
    _saveUndo();
    final Offset anchor = _points[wallIndex];
    setState(() {
      _points = _points.map((pt) {
        final dx = pt.dx - anchor.dx, dy = pt.dy - anchor.dy;
        return Offset(anchor.dx + dx * ratio, anchor.dy + dy * ratio);
      }).toList();
      _wallRealMm[wallIndex] = realMm;
      _selectedWallIndex = -1;
      _activePointIndex = -1;
    });
  }

  // ── Geometry calculations ────────────────────────────────────────────────
  double _totalPerimeter() {
    if (_points.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < _points.length - 1; i++) {
      final dx = _points[i + 1].dx - _points[i].dx;
      final dy = _points[i + 1].dy - _points[i].dy;
      total += math.sqrt(dx * dx + dy * dy);
    }
    if (_isClosed) {
      final dx = _points.first.dx - _points.last.dx;
      final dy = _points.first.dy - _points.last.dy;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }

  double _totalArea() {
    if (!_isClosed || _points.length < 3) return 0;
    double area = 0;
    final n = _points.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += _points[i].dx * _points[j].dy;
      area -= _points[j].dx * _points[i].dy;
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

    if (_isClosed) {
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
              worldToScreen(_points[_activePointIndex]))
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

    if (_points.isNotEmpty && _isNearLastPoint(event.localPosition)) {
      _isDraggingLastPoint = true;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isClosed) {
      if (_isDraggingActivePoint && _activePointIndex >= 0) {
        _dragOccurred = true;
        final raw = screenToWorld(event.localPosition);
        final snapIdx = _findNearPoint(event.localPosition,
            excludeIndex: _activePointIndex,
            radius: pointSnapRadiusScreen);
        final Offset pos = snapIdx >= 0
            ? _points[snapIdx]
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
          _points[_activePointIndex] = pos;
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
          ? _points[snapIdx]
          : _updateMiddlePointAngles(_activePointIndex, raw);
      if (snapIdx >= 0) {
        _prevWallAngle = null;
        _nextWallAngle = null;
        _prevWallSnapped = false;
        _nextWallSnapped = false;
      }
      setState(() {
        _snapTargetIndex = snapIdx >= 0 ? snapIdx : null;
        _points[_activePointIndex] = pos;
        _cursorWorld = null;
      });
      return;
    }

    if (_isDraggingLastPoint && _points.isNotEmpty) {
      _dragOccurred = true;
      final raw = screenToWorld(event.localPosition);
      final snapIdx = _findNearPoint(event.localPosition,
          excludeIndex: _points.length - 1,
          radius: pointSnapRadiusScreen);
      Offset newPos;
      if (snapIdx >= 0) {
        newPos = _points[snapIdx];
        _currentAngleDeg = null;
        _nearestSnapAngleDeg = null;
        _snapDiffDeg = null;
        _snappedAngle = null;
        _isAngleSnapped = false;
      } else if (_points.length >= 2) {
        newPos = _computeAngle(_points[_points.length - 2], raw);
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
        _points[_points.length - 1] = newPos;
        _cursorWorld = null;
      });
      return;
    }

    if (_points.isNotEmpty && _activePointIndex < 0) {
      final raw = snapToGrid(screenToWorld(event.localPosition));
      setState(() => _cursorWorld = _computeAngle(_points.last, raw));
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_isDraggingLastPoint &&
        _snapTargetIndex == 0 &&
        _points.length >= 3) {
      _saveUndo();
      setState(() {
        _isClosed = true;
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
    } else {
      if (_isDraggingActivePoint && _dragOccurred) _saveUndo();
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
    if (_isClosed || _points.isEmpty || _activePointIndex >= 0) return;
    final raw = snapToGrid(screenToWorld(event.localPosition));
    setState(() => _cursorWorld = _computeAngle(_points.last, raw));
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
    if (_isDraggingLastPoint || _isDraggingActivePoint) return;
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

  void _onTapDown(TapDownDetails details) {
    if (_isMultiTouch) return;
    if (_dragOccurred) { _dragOccurred = false; return; }

    if (_isClosed) {
      final wallIdx = _findNearWall(details.localPosition);
      if (wallIdx >= 0) {
        setState(() {
          _activePointIndex = -1;
          _selectedWallIndex = wallIdx;
        });
        showSketchWallEditDialog(wallIdx);   // ← mixin method
        return;
      }
      setState(() {
        _activePointIndex = _findNearPoint(details.localPosition,
            radius: pointSelectRadiusScreen);
        _selectedWallIndex = -1;
      });
      return;
    }

    if (_points.length >= 3) {
      final dist = (details.localPosition - worldToScreen(_points.first))
          .distance;
      if (dist < pointSelectRadiusScreen) {
        _saveUndo();
        setState(() {
          _isClosed = true;
          _cursorWorld = null;
          _currentAngleDeg = null;
          _nearestSnapAngleDeg = null;
          _snapDiffDeg = null;
          _snappedAngle = null;
          _isAngleSnapped = false;
          _activePointIndex = -1;
        });
        return;
      }
    }

    final existingIdx = _findNearPoint(details.localPosition,
        excludeIndex: _points.isEmpty ? -1 : _points.length - 1,
        radius: pointSelectRadiusScreen);
    if (existingIdx >= 0 && _points.length > 1) {
      setState(() => _activePointIndex = existingIdx);
      return;
    }

    if (_activePointIndex >= 0) {
      final dist = (details.localPosition -
              worldToScreen(_points[_activePointIndex]))
          .distance;
      if (dist > pointSelectRadiusScreen) {
        setState(() => _activePointIndex = -1);
      }
      return;
    }

    if (_points.isNotEmpty && _isNearLastPoint(details.localPosition)) return;

    _pendingTap = details;
    _tapCancelled = false;
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_tapCancelled || _pendingTap == null) return;
      _commitTap(_pendingTap!);
      _pendingTap = null;
    });
  }

  void _commitTap(TapDownDetails details) {
    if (_isClosed || _isMultiTouch) return;
    final raw = snapToGrid(screenToWorld(details.localPosition));
    final pos = _points.isNotEmpty ? _computeAngle(_points.last, raw) : raw;
    if (_points.isNotEmpty &&
        (pos - _points.last).distance < minPointDistance) return;
    _saveUndo();
    setState(() {
      _points.add(pos);
      _cursorWorld = null;
      _currentAngleDeg = null;
      _nearestSnapAngleDeg = null;
      _snapDiffDeg = null;
      _snappedAngle = null;
      _isAngleSnapped = false;
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    Offset? angleRefWorld;
    Offset? angleTargetWorld;
    if (_isDraggingLastPoint && _points.length >= 2) {
      angleRefWorld = _points[_points.length - 2];
      angleTargetWorld = _points.last;
    } else if (!_isDraggingLastPoint &&
        _activePointIndex < 0 &&
        _points.isNotEmpty &&
        _cursorWorld != null) {
      angleRefWorld = _points.last;
      angleTargetWorld = _cursorWorld;
    }

    double? liveDistance;
    if (!_isClosed && _points.isNotEmpty && _activePointIndex < 0) {
      final t = _cursorWorld;
      if (t != null) {
        final dx = t.dx - _points.last.dx, dy = t.dy - _points.last.dy;
        liveDistance = math.sqrt(dx * dx + dy * dy);
      }
    }

    final bool showAngleStrip = _currentAngleDeg != null &&
        _activePointIndex < 0 &&
        _points.length >= 2 &&
        !_isClosed;

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
              child: CustomPaint(
                painter: SketchPainter(
                  objects: _objects,
                  activeObjIndex: _activeObjIndex,
                  panOffset: _panOffset,
                  scale: _scale,
                  minorGrid: minorGrid,
                  majorGrid: majorGrid,
                  points: _points,
                  isClosed: _isClosed,
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
                  wallRealMm: _wallRealMm,
                ),
                child: const SizedBox.expand(),
              ),
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
                        _isClosed
                            ? _selectedWallIndex >= 0
                                ? 'Wall ${_selectedWallIndex + 1} selected — enter real measurement'
                                : _activePointIndex >= 0
                                    ? 'Drag point ${_activePointIndex + 1} to reposition'
                                    : _waitingForBle
                                        ? 'Point device at wall → press BOOT button'
                                        : 'Tap a wall to edit its length'
                            : _points.isEmpty
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
              !_isClosed &&
              _points.isNotEmpty &&
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
                                value: _isClosed
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
                                  value: '${_points.length}'),
                              if (_isClosed && _points.length >= 2) ...[
                                const SizedBox(width: 8),
                                StatusItem(
                                  label: 'PERIM',
                                  value: formatLength(_totalPerimeter()),
                                ),
                              ],
                              if (_isClosed && _points.length >= 3) ...[
                                const SizedBox(width: 8),
                                StatusItem(
                                  label: 'AREA',
                                  value: formatArea(_totalArea()),
                                ),
                              ],
                              if (_activePointIndex >= 0 &&
                                  _activePointIndex < _points.length) ...[
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
                        onPressed: _undoStack.isEmpty ? null : _undo,
                        color: const Color(0xFFFFAA00),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Undo',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo, size: 18),
                        onPressed: _redoStack.isEmpty ? null : _redo,
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
                        onPressed: _points.isEmpty ? null : _clear,
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
                        onPressed: _points.length >= 2
                            ? () => exportSketchPdf(
                                  context: context,
                                  points: _points,
                                  isClosed: _isClosed,
                                  wallRealMm: _wallRealMm,
                                  totalPerimeter: _totalPerimeter(),
                                  totalArea: _totalArea(),
                                )
                            : null,
                        color: const Color(0xFFFF4488),
                        disabledColor: const Color(0xFF555555),
                        tooltip: 'Export PDF',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 36, minHeight: 36),
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