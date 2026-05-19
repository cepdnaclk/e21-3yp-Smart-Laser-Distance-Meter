// lib/sketch/room_3d_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:math' as math;
import 'room_object.dart';
import 'furniture_item.dart';
import 'sketch_constants.dart';
import '../ble/ble_manager.dart';

class Room3DScreen extends StatefulWidget {
  final List<Offset> points;
  final List<RoomObject> roomObjects;
  final Map<int, double> wallRealMm;
  final List<FurnitureItem> furnitureItems;
  final BleManager? bleManager;

  final void Function(int wallIndex, double mm)? onWallMeasured;
  final double initialHeightMm;
  final void Function(double heightMm)? onHeightChanged;

  const Room3DScreen({
    super.key,
    required this.points,
    required this.roomObjects,
    required this.wallRealMm,
    this.furnitureItems = const [],
    this.bleManager,
    this.onWallMeasured,
    this.initialHeightMm = 2400,
    this.onHeightChanged,
  });

  @override
  State<Room3DScreen> createState() => _Room3DScreenState();
}

class _Room3DScreenState extends State<Room3DScreen> {
  // ── Painter view state ─────────────────────────────────────────────────────
  double _rotX = 1.1;
  double _rotY = 0.6;
  double _zoom = 0.7;
  Offset _panOffset = Offset.zero;
  double _lastZoom = 0.7;

  int? _selectedWallIndex;
  bool _waitingForBle = false;

  final List<List<Offset>> _wallPolygons = [];

  bool _showCeiling = false;
  bool _showDimensions = true;

  late double _wallHeightMm;
  static const double _mmScale = 0.10;

  // ── WebView state ──────────────────────────────────────────────────────────
  bool _use3D = true;   // true = WebView, false = legacy painter
  late WebViewController _webController;
  bool _webLoaded = false;

  @override
  void initState() {
    super.initState();
    _wallHeightMm = widget.initialHeightMm;
    _initWebView();
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _webLoaded = true;
          _sendRoomData();
        },
      ));
    _loadInlinedHtml();
  }

  // Reads three.min.js and the HTML template from assets, injects Three.js
  // inline, then loads the combined string via loadHtmlString.
  // This avoids ALL external file requests from file:// which Android WebView
  // blocks via CORS even for same-directory assets.
  Future<void> _loadInlinedHtml() async {
    final threeJs = await rootBundle.loadString('assets/3d/three.min.js');
    final template = await rootBundle.loadString('assets/3d/three_room.html');
    final html = template.replaceFirst(
      '<!--THREE_JS-->',
      '<script>$threeJs</script>',
    );
    await _webController.loadHtmlString(html);
  }

  // ── JSON contract: sketch world-units → Three.js metres ───────────────────
  Map<String, dynamic> _buildRoomJson() {
    const double toM = mmPerUnit / 1000.0; // 5mm per unit → metres

    return {
      'points': widget.points
          .map((p) => {'x': p.dx * toM, 'z': p.dy * toM})
          .toList(),
      'wallHeightM': _wallHeightMm / 1000.0,
      'wallThicknessM': 0.2,
      'roomObjects': widget.roomObjects
          .map((obj) => {
                'wallIndex': obj.wallIndex,
                'positionAlong': obj.positionAlong,
                'widthM': obj.widthMm / 1000.0,
                'heightM': obj.heightMm / 1000.0,
                'elevationM': obj.elevationMm / 1000.0,
                'isDoor': obj.isDoor,
              })
          .toList(),
      'furnitureItems': widget.furnitureItems.map((item) {
        // toARGB32() gives 0xFFRRGGBB — drop alpha byte for CSS hex
        final argb = item.type.color.toARGB32();
        final hex = '#${argb.toRadixString(16).padLeft(8, '0').substring(2)}';
        return {
          'type': item.type.name,
          'x': item.position.dx * toM,
          'z': item.position.dy * toM,
          'rotationDeg': item.rotationDeg,
          'widthM': item.widthMm / 1000.0,
          'depthM': item.depthMm / 1000.0,
          'heightM': item.type.heightMm / 1000.0,
          'colorHex': hex,
        };
      }).toList(),
    };
  }

  void _sendRoomData() {
    if (!_webLoaded) return;
    final data = _buildRoomJson();
    // Embed the JSON literal directly as a JS argument — no string escaping needed.
    _webController.runJavaScript('window.initRoom(${jsonEncode(data)})');
  }

  // ── JS → Flutter messages ──────────────────────────────────────────────────
  void _onJsMessage(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      switch (data['type'] as String) {
        case 'ready':
          // Three.js finished loading — send the current room data
          _sendRoomData();
          break;
        case 'wallTap':
          final idx = (data['index'] as num).toInt();
          setState(() =>
              _selectedWallIndex = _selectedWallIndex == idx ? null : idx);
          // Mirror highlight back into JS
          _webController.runJavaScript(
              'window.highlightWall(${_selectedWallIndex ?? -1})');
          break;
        case 'furnitureTap':
          // Future: show info panel
          break;
        case 'screenshot':
          _handleScreenshot(data['data'] as String);
          break;
      }
    } catch (_) {}
  }

  void _handleScreenshot(String dataUrl) {
    // dataUrl = 'data:image/png;base64,...'
    // Decoded bytes can be shared via share_plus in Phase 3D-5.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Screenshot ready — share in Phase 3D-5',
            style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
        backgroundColor: Color(0xFF003311),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ── Re-send when props change (new furniture dropped, room edited, etc.) ───
  @override
  void didUpdateWidget(Room3DScreen old) {
    super.didUpdateWidget(old);
    if (_use3D && _webLoaded) {
      if (old.furnitureItems.length != widget.furnitureItems.length ||
          old.roomObjects.length != widget.roomObjects.length ||
          old.points.length != widget.points.length ||
          old.wallRealMm.length != widget.wallRealMm.length) {
        _sendRoomData();
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: const Color(0xFFCCDDEE),
        title: Text(
          _use3D ? '3D Room (WebView)' : '3D Room (Painter)',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
        actions: [
          // Height input
          GestureDetector(
            onTap: _editHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.height, color: Color(0xFF00AA66), size: 16),
                  const SizedBox(width: 3),
                  Text(
                    '${(_wallHeightMm / 1000).toStringAsFixed(2)}m',
                    style: const TextStyle(
                        color: Color(0xFF00AA66),
                        fontFamily: 'monospace',
                        fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          // Screenshot (WebView only)
          if (_use3D)
            IconButton(
              icon: const Icon(Icons.camera_alt,
                  color: Color(0xFF556677), size: 20),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Screenshot',
              onPressed: () =>
                  _webController.runJavaScript('window.captureScreenshot()'),
            ),

          // Reset camera
          IconButton(
            icon: const Icon(Icons.center_focus_strong,
                color: Color(0xFF556677), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Reset view',
            onPressed: _resetView,
          ),

          // Ceiling toggle (painter only)
          if (!_use3D)
            IconButton(
              icon: Icon(
                _showCeiling ? Icons.roofing : Icons.roofing_outlined,
                color: _showCeiling
                    ? const Color(0xFF00AAFF)
                    : const Color(0xFF556677),
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: _showCeiling ? 'Hide ceiling' : 'Show ceiling',
              onPressed: () => setState(() => _showCeiling = !_showCeiling),
            ),

          // Dimensions toggle (painter only)
          if (!_use3D)
            IconButton(
              icon: Icon(
                Icons.straighten,
                color: _showDimensions
                    ? const Color(0xFF00AAFF)
                    : const Color(0xFF556677),
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: _showDimensions ? 'Hide dimensions' : 'Show dimensions',
              onPressed: () =>
                  setState(() => _showDimensions = !_showDimensions),
            ),

          // 3D / Painter toggle
          IconButton(
            icon: Icon(
              _use3D ? Icons.view_in_ar : Icons.layers,
              color: _use3D
                  ? const Color(0xFF00AAFF)
                  : const Color(0xFF556677),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: _use3D ? 'Switch to Painter' : 'Switch to Three.js',
            onPressed: () => setState(() => _use3D = !_use3D),
          ),

          const SizedBox(width: 4),
        ],
      ),
      body: Stack(children: [
        // ── Main view ─────────────────────────────────────────────────────
        if (_use3D)
          WebViewWidget(controller: _webController)
        else
          _buildPainterView(),

        // ── Bottom info / BLE bar ─────────────────────────────────────────
        Positioned(
          bottom: 16,
          left: 12,
          right: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: _selectedWallIndex == null
                ? Text(
                    _use3D
                        ? 'Pinch/drag to orbit & zoom  •  tap wall to select'
                        : '1 finger = rotate  •  2 fingers = zoom/pan  •  tap wall to select',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF778899),
                        fontFamily: 'monospace',
                        fontSize: 11),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Wall ${_selectedWallIndex! + 1} selected',
                        style: const TextStyle(
                            color: Color(0xFF00AAFF),
                            fontFamily: 'monospace',
                            fontSize: 11),
                      ),
                      if (widget.bleManager != null)
                        _waitingForBle
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF00AAFF))),
                                  SizedBox(width: 6),
                                  Text('Measuring…',
                                      style: TextStyle(
                                          color: Color(0xFF00AAFF),
                                          fontFamily: 'monospace',
                                          fontSize: 11)),
                                ],
                              )
                            : GestureDetector(
                                onTap: _triggerBleMeasurement,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bluetooth,
                                        color: Color(0xFF00AAFF), size: 14),
                                    SizedBox(width: 4),
                                    Text('Measure',
                                        style: TextStyle(
                                            color: Color(0xFF00AAFF),
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight.bold)),
                                  ],
                                ),
                              ),
                    ],
                  ),
          ),
        ),

        // ── Object legend (top-left, painter mode only) ────────────────────
        if (!_use3D && widget.roomObjects.isNotEmpty)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22).withOpacity(0.9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legendDot(const Color(0xFF8B4513), 'Door'),
                  const SizedBox(height: 4),
                  _legendDot(const Color(0xFF4FC3F7), 'Window'),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  // ── Painter view (legacy fallback) ─────────────────────────────────────────
  Widget _buildPainterView() {
    return GestureDetector(
      onTapUp: (details) {
        bool hit = false;
        for (int i = 0; i < _wallPolygons.length; i++) {
          if (_pointInPolygon(details.localPosition, _wallPolygons[i])) {
            setState(
                () => _selectedWallIndex = _selectedWallIndex == i ? null : i);
            hit = true;
            break;
          }
        }
        if (!hit) setState(() => _selectedWallIndex = null);
      },
      onScaleStart: (_) {
        _lastZoom = _zoom;
      },
      onScaleUpdate: (d) {
        setState(() {
          if (d.pointerCount == 1) {
            _rotY += d.focalPointDelta.dx * 0.01;
            _rotX = (_rotX - d.focalPointDelta.dy * 0.008)
                .clamp(0.05, math.pi / 2);
          } else {
            _zoom = (_lastZoom * d.scale).clamp(0.3, 5.0);
            _panOffset += d.focalPointDelta;
          }
        });
      },
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _Room3DPainter(
            points: widget.points,
            roomObjects: widget.roomObjects,
            wallRealMm: widget.wallRealMm,
            furnitureItems: widget.furnitureItems,
            rotX: _rotX,
            rotY: _rotY,
            zoom: _zoom,
            panOffset: _panOffset,
            selectedWallIndex: _selectedWallIndex,
            wallHeightMm: _wallHeightMm,
            mmScale: _mmScale,
            wallPolygons: _wallPolygons,
            showCeiling: _showCeiling,
            showDimensions: _showDimensions,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  void _resetView() {
    if (_use3D) {
      _webController.runJavaScript('window.resetCamera()');
    } else {
      setState(() {
        _rotX = 1.1;
        _rotY = 0.6;
        _zoom = 0.7;
        _panOffset = Offset.zero;
      });
    }
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF778899),
                fontFamily: 'monospace',
                fontSize: 10)),
      ],
    );
  }

  bool _pointInPolygon(Offset p, List<Offset> poly) {
    bool inside = false;
    int j = poly.length - 1;
    for (int i = 0; i < poly.length; i++) {
      if (((poly[i].dy > p.dy) != (poly[j].dy > p.dy)) &&
          (p.dx <
              (poly[j].dx - poly[i].dx) *
                      (p.dy - poly[i].dy) /
                      (poly[j].dy - poly[i].dy) +
                  poly[i].dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  Future<void> _editHeight() async {
    final ctrl = TextEditingController(
      text: (_wallHeightMm / 1000).toStringAsFixed(3),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A3A),
        title: const Text(
          'Room height',
          style: TextStyle(
              color: Color(0xFFCCDDEE),
              fontFamily: 'monospace',
              fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the real height of the room walls.',
              style: TextStyle(
                  color: Color(0xFF556677),
                  fontFamily: 'monospace',
                  fontSize: 11),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style:
                  const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                suffixText: 'm',
                suffixStyle: TextStyle(color: Color(0xFF00AA66)),
                hintText: 'e.g. 2.400',
                hintStyle: TextStyle(color: Color(0xFF445566)),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF334466))),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00AA66))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL',
                style: TextStyle(
                    color: Color(0xFF778899), fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v != null && v > 0.5 && v < 20.0) {
                setState(() => _wallHeightMm = v * 1000);
                widget.onHeightChanged?.call(v * 1000);
                _sendRoomData(); // push updated height to Three.js
              }
              Navigator.pop(ctx);
            },
            child: const Text('APPLY',
                style: TextStyle(
                    color: Color(0xFF00AA66), fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  void _triggerBleMeasurement() {
    if (_selectedWallIndex == null || widget.bleManager == null) return;
    final wallIdx = _selectedWallIndex!;
    setState(() => _waitingForBle = true);

    widget.bleManager!.packetStream
        .where((p) => !p.isCapturing && p.distanceMm > 0)
        .first
        .then((packet) {
      if (!mounted) return;
      final mm = packet.distanceMm;
      setState(() {
        _waitingForBle = false;
        widget.wallRealMm[wallIdx] = mm;
        _selectedWallIndex = null;
      });
      widget.onWallMeasured?.call(wallIdx, mm);
      _webController
          .runJavaScript('window.highlightWall(-1)'); // deselect in Three.js
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Wall ${wallIdx + 1}: ${mm.toStringAsFixed(0)} mm — updated!',
            style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: const Color(0xFF003311),
      ));
    });
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 3D Painter (legacy — kept as fallback / Phase 3D-1 baseline)
// ════════════════════════════════════════════════════════════════════════════
class _Room3DPainter extends CustomPainter {
  final List<Offset> points;
  final List<RoomObject> roomObjects;
  final Map<int, double> wallRealMm;
  final List<FurnitureItem> furnitureItems;
  final double rotX;
  final double rotY;
  final double zoom;
  final Offset panOffset;
  final int? selectedWallIndex;
  final double wallHeightMm;
  final double mmScale;
  final List<List<Offset>> wallPolygons;
  final bool showCeiling;
  final bool showDimensions;

  _Room3DPainter({
    required this.points,
    required this.roomObjects,
    required this.wallRealMm,
    required this.furnitureItems,
    required this.rotX,
    required this.rotY,
    required this.zoom,
    required this.panOffset,
    required this.selectedWallIndex,
    required this.wallHeightMm,
    required this.mmScale,
    required this.wallPolygons,
    required this.showCeiling,
    required this.showDimensions,
  });

  Offset _project(double x, double y, double z, Size size) {
    final cosY = math.cos(rotY), sinY = math.sin(rotY);
    final x1 = x * cosY - z * sinY;
    final z1 = x * sinY + z * cosY;

    final cosX = math.cos(rotX), sinX = math.sin(rotX);
    final y2 = y * cosX - z1 * sinX;
    final z2 = y * sinX + z1 * cosX;

    const fov = 700.0;
    final perspective = fov / (fov + z2 + 500);

    return Offset(
      size.width / 2 + x1 * perspective * zoom + panOffset.dx,
      size.height / 2 + y2 * perspective * zoom + panOffset.dy,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    wallPolygons.clear();
    for (int k = 0; k < points.length; k++) wallPolygons.add([]);

    double cx = 0, cy = 0;
    for (final p in points) {
      cx += p.dx * mmPerUnit;
      cy += p.dy * mmPerUnit;
    }
    cx /= points.length;
    cy /= points.length;

    final int n = points.length;
    final double H = wallHeightMm * mmScale;

    double wx(double worldX) => (worldX * mmPerUnit - cx) * mmScale;
    double wz(double worldZ) => (worldZ * mmPerUnit - cy) * mmScale;

    // ── Floor ─────────────────────────────────────────────────────────────
    final floorPath = Path();
    for (int i = 0; i < n; i++) {
      final s = _project(wx(points[i].dx), 0, wz(points[i].dy), size);
      if (i == 0) floorPath.moveTo(s.dx, s.dy);
      else floorPath.lineTo(s.dx, s.dy);
    }
    floorPath.close();
    canvas.drawPath(floorPath,
        Paint()
          ..color = const Color(0xFFB0B8C0)
          ..style = PaintingStyle.fill);
    canvas.drawPath(floorPath,
        Paint()
          ..color = const Color(0xFF666666)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // ── Draw order: walls + furniture + corner caps, back-to-front ────────
    final drawOrder = <(int, int, double)>[];
    for (int i = 0; i < n; i++) {
      final Offset a = points[i];
      final Offset b = points[(i + 1) % n];
      final double midX = (wx(a.dx) + wx(b.dx)) / 2;
      final double midZ = (wz(a.dy) + wz(b.dy)) / 2;
      drawOrder.add((0, i, midX * math.sin(rotY) + midZ * math.cos(rotY)));
    }
    for (int fi = 0; fi < furnitureItems.length; fi++) {
      final item = furnitureItems[fi];
      drawOrder.add((1, fi,
          wx(item.position.dx) * math.sin(rotY) +
              wz(item.position.dy) * math.cos(rotY)));
    }
    for (int j = 0; j < n; j++) {
      drawOrder.add((2, j,
          wx(points[j].dx) * math.sin(rotY) +
              wz(points[j].dy) * math.cos(rotY)));
    }
    drawOrder.sort((a, b) => b.$3.compareTo(a.$3));

    // ── Pre-compute inward normals ─────────────────────────────────────────
    const double wallThickMm = 200.0;
    final double wallThickW = wallThickMm / mmPerUnit;
    final double cxWorld = cx / mmPerUnit;
    final double cyWorld = cy / mmPerUnit;
    final List<Offset> wallNormals = List.filled(n, Offset.zero);
    for (int k = 0; k < n; k++) {
      final Offset pa = points[k];
      final Offset pb = points[(k + 1) % n];
      final double dxW = pb.dx - pa.dx;
      final double dyW = pb.dy - pa.dy;
      final double len = math.sqrt(dxW * dxW + dyW * dyW);
      if (len < 1e-6) continue;
      double nx = dyW / len;
      double ny = -dxW / len;
      final double mx = (pa.dx + pb.dx) / 2;
      final double my = (pa.dy + pb.dy) / 2;
      if ((cxWorld - mx) * nx + (cyWorld - my) * ny < 0) {
        nx = -nx;
        ny = -ny;
      }
      wallNormals[k] = Offset(nx, ny);
    }

    // ── Pre-compute miter inner corners ───────────────────────────────────
    final List<Offset> innerCorners = List.filled(n, Offset.zero);
    for (int j = 0; j < n; j++) {
      final int prevW = (j - 1 + n) % n;
      final Offset pj = points[j];
      final Offset pprev = points[prevW];
      final Offset pnext = points[(j + 1) % n];
      final Offset nPrev = wallNormals[prevW];
      final Offset nNext = wallNormals[j];

      final double p1x = pj.dx + nPrev.dx * wallThickW;
      final double p1y = pj.dy + nPrev.dy * wallThickW;
      final double p2x = pj.dx + nNext.dx * wallThickW;
      final double p2y = pj.dy + nNext.dy * wallThickW;

      final double d1x = pj.dx - pprev.dx;
      final double d1y = pj.dy - pprev.dy;
      final double d2x = pnext.dx - pj.dx;
      final double d2y = pnext.dy - pj.dy;

      final double cross = d1x * d2y - d1y * d2x;
      if (cross.abs() < 1e-6) {
        innerCorners[j] = Offset(
          pj.dx + (nPrev.dx + nNext.dx) * wallThickW * 0.5,
          pj.dy + (nPrev.dy + nNext.dy) * wallThickW * 0.5,
        );
      } else {
        final double t =
            ((p2x - p1x) * d2y - (p2y - p1y) * d2x) / cross;
        final double maxT = 3.0 *
            wallThickW /
            math.sqrt(d1x * d1x + d1y * d1y).clamp(1e-6, double.infinity);
        final double tc = t.clamp(-maxT, maxT);
        innerCorners[j] = Offset(p1x + tc * d1x, p1y + tc * d1y);
      }
    }

    for (final entry in drawOrder) {
      // ── Corner cap ──────────────────────────────────────────────────────
      if (entry.$1 == 2) {
        final int j = entry.$2;
        final Offset pj = points[j];
        final Offset ic = innerCorners[j];
        final double dxCap = ic.dx - pj.dx;
        final double dyCap = ic.dy - pj.dy;
        double cnx = dyCap, cny = -dxCap;
        if ((pj.dx - cxWorld) * cnx + (pj.dy - cyWorld) * cny < 0) {
          cnx = -cnx;
          cny = -cny;
        }
        final double capVis = cnx * math.sin(rotY) + cny * math.cos(rotY);
        if (capVis <= 0) continue;

        final cfo = _project(wx(pj.dx), 0, wz(pj.dy), size);
        final cfi = _project(wx(ic.dx), 0, wz(ic.dy), size);
        final cti = _project(wx(ic.dx), -H, wz(ic.dy), size);
        final cto = _project(wx(pj.dx), -H, wz(pj.dy), size);

        final double depth = entry.$3;
        final int capL =
            (175 + (depth * 8).clamp(-60.0, 60.0)).toInt().clamp(90, 230);
        canvas.drawPath(
          Path()
            ..moveTo(cfo.dx, cfo.dy)
            ..lineTo(cfi.dx, cfi.dy)
            ..lineTo(cti.dx, cti.dy)
            ..lineTo(cto.dx, cto.dy)
            ..close(),
          Paint()
            ..color = Color.fromARGB(255, capL, capL, capL).withOpacity(0.9)
            ..style = PaintingStyle.fill,
        );
        continue;
      }

      // ── Furniture item ───────────────────────────────────────────────────
      if (entry.$1 == 1) {
        final item = furnitureItems[entry.$2];
        final double frad = item.rotationDeg * math.pi / 180.0;
        final double fcosR = math.cos(frad);
        final double fsinR = math.sin(frad);
        final double fhw = item.widthMm / (2.0 * mmPerUnit);
        final double fhd = item.depthMm / (2.0 * mmPerUnit);
        final double fH2 = item.type.heightMm * mmScale;

        final fWorldPts = [
          const Offset(-1.0, -1.0),
          const Offset(1.0, -1.0),
          const Offset(1.0, 1.0),
          const Offset(-1.0, 1.0),
        ].map((lp) {
          final rx = lp.dx * fhw * fcosR - lp.dy * fhd * fsinR;
          final ry = lp.dx * fhw * fsinR + lp.dy * fhd * fcosR;
          return Offset(item.position.dx + rx, item.position.dy + ry);
        }).toList();

        final fBotPts = fWorldPts
            .map((wp) => _project(wx(wp.dx), 0, wz(wp.dy), size))
            .toList();
        final fTopPts = fWorldPts
            .map((wp) => _project(wx(wp.dx), -fH2, wz(wp.dy), size))
            .toList();

        double fscx = 0, fscy = 0;
        for (final bp in fBotPts) {
          fscx += bp.dx;
          fscy += bp.dy;
        }
        fscx /= 4;
        fscy /= 4;
        final double fsW = (fBotPts[1] - fBotPts[0]).distance +
            (fBotPts[2] - fBotPts[3]).distance;
        final double fsD = (fBotPts[3] - fBotPts[0]).distance +
            (fBotPts[2] - fBotPts[1]).distance;
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(fscx, fscy), width: fsW * 0.65, height: fsD * 0.65),
          Paint()..color = Colors.black.withOpacity(0.22),
        );

        final fBaseColor = item.type.color;
        final double ffcx = item.position.dx;
        final double ffcz = item.position.dy;

        final fFaceDepths = List.generate(4, (f) {
          final j = (f + 1) % 4;
          final mx = (fWorldPts[f].dx + fWorldPts[j].dx) / 2;
          final mz = (fWorldPts[f].dy + fWorldPts[j].dy) / 2;
          return wx(mx) * math.sin(rotY) + wz(mz) * math.cos(rotY);
        });
        final fFaceOrder = [0, 1, 2, 3]
          ..sort((a, b) => fFaceDepths[b].compareTo(fFaceDepths[a]));

        for (final f in fFaceOrder) {
          final int j = (f + 1) % 4;
          final double fdx = fWorldPts[j].dx - fWorldPts[f].dx;
          final double fdz = fWorldPts[j].dy - fWorldPts[f].dy;
          final double flen =
              math.sqrt(fdx * fdx + fdz * fdz).clamp(1e-6, 1e9);
          double fnx = fdz / flen, fnz = -fdx / flen;
          final double fmx = (fWorldPts[f].dx + fWorldPts[j].dx) / 2;
          final double fmz = (fWorldPts[f].dy + fWorldPts[j].dy) / 2;
          if ((fmx - ffcx) * fnx + (fmz - ffcz) * fnz < 0) {
            fnx = -fnx;
            fnz = -fnz;
          }
          final double fvis = fnx * math.sin(rotY) + fnz * math.cos(rotY);
          if (fvis >= 0) continue;
          final double fshade = (-fvis).clamp(0.0, 1.0);
          final fFaceColor =
              Color.lerp(Colors.black, fBaseColor, 0.45 + fshade * 0.55)!;
          final sidePath = Path()
            ..moveTo(fBotPts[f].dx, fBotPts[f].dy)
            ..lineTo(fBotPts[j].dx, fBotPts[j].dy)
            ..lineTo(fTopPts[j].dx, fTopPts[j].dy)
            ..lineTo(fTopPts[f].dx, fTopPts[f].dy)
            ..close();
          canvas.drawPath(
              sidePath, Paint()..color = fFaceColor..style = PaintingStyle.fill);
          canvas.drawPath(
              sidePath,
              Paint()
                ..color = Colors.black.withOpacity(0.25)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.7);
        }

        final fTopColor = Color.lerp(Colors.white, fBaseColor, 0.65)!;
        final fTopPath = Path()
          ..moveTo(fTopPts[0].dx, fTopPts[0].dy)
          ..lineTo(fTopPts[1].dx, fTopPts[1].dy)
          ..lineTo(fTopPts[2].dx, fTopPts[2].dy)
          ..lineTo(fTopPts[3].dx, fTopPts[3].dy)
          ..close();
        canvas.drawPath(
            fTopPath, Paint()..color = fTopColor..style = PaintingStyle.fill);
        canvas.drawPath(
            fTopPath,
            Paint()
              ..color = Colors.black.withOpacity(0.2)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.7);
        for (int k = 0; k < 4; k++) {
          canvas.drawLine(fBotPts[k], fTopPts[k],
              Paint()
                ..color = Colors.black.withOpacity(0.2)
                ..strokeWidth = 0.7);
        }

        final ftp = TextPainter(
          text: TextSpan(
            text: item.type.displayName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontFamily: 'monospace',
                shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        double flx = 0, fly = 0;
        for (final p in fTopPts) {
          flx += p.dx;
          fly += p.dy;
        }
        ftp.paint(
            canvas, Offset(flx / 4 - ftp.width / 2, fly / 4 - ftp.height / 2));
        continue;
      }

      // ── Wall ────────────────────────────────────────────────────────────
      final int i = entry.$2;
      final Offset a = points[i];
      final Offset b = points[(i + 1) % n];
      final bool isSelected = i == selectedWallIndex;
      final Offset norm = wallNormals[i];

      final s0 = _project(wx(a.dx), 0, wz(a.dy), size);
      final s1 = _project(wx(b.dx), 0, wz(b.dy), size);
      final s2 = _project(wx(b.dx), -H, wz(b.dy), size);
      final s3 = _project(wx(a.dx), -H, wz(a.dy), size);

      wallPolygons[i] = [s0, s1, s2, s3];

      final Offset icA = innerCorners[i];
      final Offset icB = innerCorners[(i + 1) % n];
      final si0 = _project(wx(icA.dx), 0, wz(icA.dy), size);
      final si1 = _project(wx(icB.dx), 0, wz(icB.dy), size);
      final si2 = _project(wx(icB.dx), -H, wz(icB.dy), size);
      final si3 = _project(wx(icA.dx), -H, wz(icA.dy), size);

      final double depth = entry.$3;
      final int outerL =
          (180 + (depth * 8).clamp(-60.0, 60.0)).toInt().clamp(100, 240);
      final int topL = (outerL + 35).clamp(100, 255);
      final int innerL = (outerL - 45).clamp(60, 200);
      final outerCol = Color.fromARGB(255, outerL, outerL, outerL);
      final topCol = Color.fromARGB(255, topL, topL, topL);
      final innerCol = Color.fromARGB(255, innerL, innerL, innerL);

      final double innerVis =
          norm.dx * math.sin(rotY) + norm.dy * math.cos(rotY);
      if (innerVis > 0) {
        canvas.drawPath(
          Path()
            ..moveTo(si0.dx, si0.dy)
            ..lineTo(si1.dx, si1.dy)
            ..lineTo(si2.dx, si2.dy)
            ..lineTo(si3.dx, si3.dy)
            ..close(),
          Paint()
            ..color = (isSelected
                    ? const Color(0xFF2A5F8A)
                    : innerCol)
                .withOpacity(0.9)
            ..style = PaintingStyle.fill,
        );
      }

      canvas.drawPath(
        Path()
          ..moveTo(s3.dx, s3.dy)
          ..lineTo(s2.dx, s2.dy)
          ..lineTo(si2.dx, si2.dy)
          ..lineTo(si3.dx, si3.dy)
          ..close(),
        Paint()
          ..color = (isSelected
                  ? const Color(0xFF5AAAE0)
                  : topCol)
              .withOpacity(0.95)
          ..style = PaintingStyle.fill,
      );

      if (innerVis <= 0) {
        final wallPath = Path()
          ..moveTo(s0.dx, s0.dy)
          ..lineTo(s1.dx, s1.dy)
          ..lineTo(s2.dx, s2.dy)
          ..lineTo(s3.dx, s3.dy)
          ..close();
        canvas.drawPath(
            wallPath,
            Paint()
              ..color = (isSelected
                      ? const Color(0xFF4A90D9)
                      : outerCol)
                  .withOpacity(0.85)
              ..style = PaintingStyle.fill);
        if (isSelected) {
          canvas.drawPath(
              wallPath,
              Paint()
                ..color = const Color(0xFF00AAFF)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.5);
        }
      }

      // ── Doors & windows on this wall ──────────────────────────────────
      for (final obj in roomObjects) {
        if (obj.wallIndex != i) continue;

        final double ocx = a.dx + obj.positionAlong * (b.dx - a.dx);
        final double ocy = a.dy + obj.positionAlong * (b.dy - a.dy);

        final double dxW2 = b.dx - a.dx;
        final double dyW2 = b.dy - a.dy;
        final double wallLen = math.sqrt(dxW2 * dxW2 + dyW2 * dyW2);
        if (wallLen < 1) continue;
        final double udx = dxW2 / wallLen;
        final double udy = dyW2 / wallLen;

        final double halfWW = (obj.widthMm / mmPerUnit) / 2;
        final double objH2 = obj.heightMm * mmScale;
        final double elevDraw = obj.elevationMm * mmScale;

        final double lx2 = ocx - udx * halfWW;
        final double ly2 = ocy - udy * halfWW;
        final double rx = ocx + udx * halfWW;
        final double ry = ocy + udy * halfWW;

        final obl = _project(wx(lx2), -elevDraw, wz(ly2), size);
        final obr = _project(wx(rx), -elevDraw, wz(ry), size);
        final otr = _project(wx(rx), -(elevDraw + objH2), wz(ry), size);
        final otl = _project(wx(lx2), -(elevDraw + objH2), wz(ly2), size);

        final ilx = lx2 + norm.dx * wallThickW;
        final ily = ly2 + norm.dy * wallThickW;
        final irx = rx + norm.dx * wallThickW;
        final iry = ry + norm.dy * wallThickW;

        final ibl = _project(wx(ilx), -elevDraw, wz(ily), size);
        final ibr = _project(wx(irx), -elevDraw, wz(iry), size);
        final itr = _project(wx(irx), -(elevDraw + objH2), wz(iry), size);
        final itl = _project(wx(ilx), -(elevDraw + objH2), wz(ily), size);

        if (obj.isDoor) {
          _drawDoor3D(canvas, obl, obr, otr, otl, ibl, ibr, itr, itl);
        } else {
          _drawWindow3D(canvas, obl, obr, otr, otl, ibl, ibr, itr, itl);
        }
      }

      // ── Wall dimension label ──────────────────────────────────────────
      if (showDimensions) {
        final mid = Offset((s0.dx + s1.dx) / 2, (s0.dy + s1.dy) / 2);
        final topMid = Offset((s2.dx + s3.dx) / 2, (s2.dy + s3.dy) / 2);
        final labelPos =
            Offset((mid.dx + topMid.dx) / 2, (mid.dy + topMid.dy) / 2);
        final lenMm = wallRealMm[i] ?? ((b - a).distance * mmPerUnit);
        final label = lenMm >= 1000
            ? '${(lenMm / 1000).toStringAsFixed(2)} m'
            : '${lenMm.toStringAsFixed(0)} mm';

        final tp = TextPainter(
          text: TextSpan(
            text: 'W${i + 1}  $label',
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFF00AAFF)
                  : const Color(0xFF4A5568),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(labelPos.dx - tp.width / 2, labelPos.dy - tp.height / 2));
      }
    }

    // ── Ceiling ──────────────────────────────────────────────────────────────
    if (showCeiling) {
      final ceilPath = Path();
      for (int i = 0; i < n; i++) {
        final s = _project(wx(points[i].dx), -H, wz(points[i].dy), size);
        if (i == 0) ceilPath.moveTo(s.dx, s.dy);
        else ceilPath.lineTo(s.dx, s.dy);
      }
      ceilPath.close();
      canvas.drawPath(
          ceilPath,
          Paint()
            ..color = const Color(0xFF161B22).withOpacity(0.7)
            ..style = PaintingStyle.fill);
      canvas.drawPath(
          ceilPath,
          Paint()
            ..color = const Color(0xFF2D3748)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
    }

    // ── Corner dots ───────────────────────────────────────────────────────────
    for (int i = 0; i < n; i++) {
      final s = _project(wx(points[i].dx), 0, wz(points[i].dy), size);
      canvas.drawCircle(
          s,
          3.5,
          Paint()
            ..color = i == 0
                ? const Color(0xFF48BB78)
                : const Color(0xFF4299E1));
    }
  }

  void _drawReveal(Canvas canvas, Offset a, Offset b, Offset c, Offset d) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
    canvas.drawPath(path,
        Paint()..color = const Color(0xFF0D1117)..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF333333)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
  }

  void _drawDoor3D(Canvas canvas, Offset bl, Offset br, Offset tr, Offset tl,
      Offset ibl, Offset ibr, Offset itr, Offset itl) {
    final outerHole = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(tl.dx, tl.dy)
      ..close();
    canvas.drawPath(outerHole,
        Paint()..color = const Color(0xFF0A0E14)..style = PaintingStyle.fill);

    _drawReveal(canvas, tl, bl, ibl, itl);
    _drawReveal(canvas, br, tr, itr, ibr);
    _drawReveal(canvas, tr, tl, itl, itr);

    canvas.drawPath(
      Path()
        ..moveTo(ibl.dx, ibl.dy)
        ..lineTo(ibr.dx, ibr.dy)
        ..lineTo(itr.dx, itr.dy)
        ..lineTo(itl.dx, itl.dy)
        ..close(),
      Paint()..color = const Color(0xFF0A0E14)..style = PaintingStyle.fill,
    );

    final centre = Offset((bl.dx + br.dx + tr.dx + tl.dx) / 4,
        (bl.dy + br.dy + tr.dy + tl.dy) / 4);
    Offset ins(Offset p) => Offset(
        p.dx + (centre.dx - p.dx) * 0.05, p.dy + (centre.dy - p.dy) * 0.05);

    final doorPath = Path()
      ..moveTo(ins(bl).dx, ins(bl).dy)
      ..lineTo(ins(br).dx, ins(br).dy)
      ..lineTo(ins(tr).dx, ins(tr).dy)
      ..lineTo(ins(tl).dx, ins(tl).dy)
      ..close();
    canvas.drawPath(doorPath,
        Paint()..color = const Color(0xFF8B4513)..style = PaintingStyle.fill);
    canvas.drawPath(
        doorPath,
        Paint()
          ..color = const Color(0xFF5C2E00)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    canvas.drawPath(
        outerHole,
        Paint()
          ..color = const Color(0xFF4A3728)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    final knobPos = Offset(ins(br).dx + (ins(bl).dx - ins(br).dx) * 0.15,
        ins(br).dy + (ins(tl).dy - ins(bl).dy) * 0.45);
    canvas.drawCircle(
        knobPos, 3, Paint()..color = const Color(0xFFFFD700));
  }

  void _drawWindow3D(Canvas canvas, Offset bl, Offset br, Offset tr, Offset tl,
      Offset ibl, Offset ibr, Offset itr, Offset itl) {
    final outerPath = Path()
      ..moveTo(bl.dx, bl.dy)
      ..lineTo(br.dx, br.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(tl.dx, tl.dy)
      ..close();
    canvas.drawPath(outerPath,
        Paint()..color = const Color(0xFF0A0E14)..style = PaintingStyle.fill);
    canvas.drawPath(
        outerPath,
        Paint()
          ..color = const Color(0xFF4FC3F7).withOpacity(0.25)
          ..style = PaintingStyle.fill);

    _drawReveal(canvas, tl, bl, ibl, itl);
    _drawReveal(canvas, br, tr, itr, ibr);
    _drawReveal(canvas, tr, tl, itl, itr);
    _drawReveal(canvas, bl, br, ibr, ibl);

    canvas.drawPath(
      Path()
        ..moveTo(ibl.dx, ibl.dy)
        ..lineTo(ibr.dx, ibr.dy)
        ..lineTo(itr.dx, itr.dy)
        ..lineTo(itl.dx, itl.dy)
        ..close(),
      Paint()
        ..color = const Color(0xFF4FC3F7).withOpacity(0.15)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
        outerPath,
        Paint()
          ..color = const Color(0xFF90A4AE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);

    final midTop = Offset((tl.dx + tr.dx) / 2, (tl.dy + tr.dy) / 2);
    final midBot = Offset((bl.dx + br.dx) / 2, (bl.dy + br.dy) / 2);
    final midLeft = Offset((tl.dx + bl.dx) / 2, (tl.dy + bl.dy) / 2);
    final midRight = Offset((tr.dx + br.dx) / 2, (tr.dy + br.dy) / 2);
    final crossPaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..strokeWidth = 1.5;
    canvas.drawLine(midTop, midBot, crossPaint);
    canvas.drawLine(midLeft, midRight, crossPaint);

    canvas.drawLine(
      Offset(tl.dx + (tr.dx - tl.dx) * 0.1, tl.dy + (tr.dy - tl.dy) * 0.1),
      Offset(bl.dx + (br.dx - bl.dx) * 0.1, bl.dy + (br.dy - bl.dy) * 0.1),
      Paint()..color = Colors.white.withOpacity(0.2)..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_Room3DPainter old) =>
      old.rotX != rotX ||
      old.rotY != rotY ||
      old.zoom != zoom ||
      old.panOffset != panOffset ||
      old.selectedWallIndex != selectedWallIndex ||
      old.wallHeightMm != wallHeightMm ||
      old.showCeiling != showCeiling ||
      old.showDimensions != showDimensions ||
      old.roomObjects.length != roomObjects.length ||
      old.furnitureItems.length != furnitureItems.length;
}
