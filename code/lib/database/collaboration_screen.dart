// lib/database/collaboration_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../database/database_helper.dart';
import '../sketch/sketch_screen.dart';
import '../sketch/sketch_model.dart';
import '../sketch/room_object.dart';

class CollaborationScreen extends StatefulWidget {
  const CollaborationScreen({super.key});

  @override
  State<CollaborationScreen> createState() => _CollaborationScreenState();
}

class _CollaborationScreenState extends State<CollaborationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _ownedProjects = [];
  List<dynamic> _sharedProjects = [];
  bool _loadingOwned = true;
  bool _loadingShared = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOwned();
    _loadShared();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOwned() async {
    final projects = await ApiService.getCloudProjects();
    if (mounted) {
      setState(() {
        _ownedProjects = projects;
        _loadingOwned = false;
      });
    }
  }

  Future<void> _loadShared() async {
    final projects = await ApiService.getSharedProjects();
    if (mounted) {
      setState(() {
        _sharedProjects = projects;
        _loadingShared = false;
      });
    }
  }

  // ── Restore project to local SQLite ──────────────────────────────────────

  Future<void> _restoreProject(int cloudProjectId, String name) async {
    setState(() => _working = true);
    final data = await ApiService.downloadProject(cloudProjectId);
    if (data == null) {
      setState(() => _working = false);
      _snack('Restore failed. Try again.', error: true);
      return;
    }
    final (shapes, roomObjects, wallAngles, wallLengths) =
        _parseProjectData(data);
    await DatabaseHelper.instance.saveProject(
      name: name,
      shapes: shapes,
      roomObjects: roomObjects,
      wallAngles: wallAngles,
      wallDrawnLengths: wallLengths,
    );
    setState(() => _working = false);
    _snack('Project restored to device');
    if (mounted) Navigator.pop(context);
  }

  // ── Open shared project with live polling ────────────────────────────────

  Future<void> _openLive(int cloudProjectId, String name) async {
    setState(() => _working = true);
    final data = await ApiService.downloadProject(cloudProjectId);
    if (data == null) {
      setState(() => _working = false);
      _snack('Could not load project.', error: true);
      return;
    }
    final (shapes, roomObjects, wallAngles, wallLengths) =
        _parseProjectData(data);
    final lastUpdatedAt =
        data['project']['updated_at'] as String? ?? '';
    setState(() => _working = false);
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LiveCollabWrapper(
          cloudProjectId: cloudProjectId,
          projectName: name,
          initialShapes: shapes,
          initialWallAngles: wallAngles,
          initialWallLengths: wallLengths,
          lastKnownUpdatedAt: lastUpdatedAt,
        ),
      ),
    );
  }

  // ── Join project by invite code ───────────────────────────────────────────

  Future<void> _showJoinDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2A3A),
        title: const Text('Join Project',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the 8-character invite code\nshared by the project owner.',
              style: TextStyle(color: Color(0xFF778899), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                letterSpacing: 4,
                fontSize: 20,
              ),
              maxLength: 8,
              decoration: const InputDecoration(
                hintText: 'ABCD1234',
                hintStyle: TextStyle(color: Color(0xFF556677)),
                counterStyle: TextStyle(color: Color(0xFF556677)),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF334466)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF00AAFF)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF556677))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Join',
                style: TextStyle(color: Color(0xFF00AAFF))),
          ),
        ],
      ),
    );

    if (code == null || code.length != 8) return;
    setState(() => _working = true);
    final result = await ApiService.joinProject(code);
    setState(() => _working = false);

    if (result['error'] != null) {
      _snack(result['error'], error: true);
    } else {
      _snack('Joined "${result['project']['name']}" successfully!');
      _loadShared();
      _tabController.animateTo(1);
    }
  }

  // ── Show invite code dialog ───────────────────────────────────────────────

  Future<void> _showInviteCode(int cloudProjectId, String name) async {
    final code = await ApiService.getInviteCode(cloudProjectId);
    if (!mounted) return;
    if (code == null) {
      _snack('Could not fetch invite code.', error: true);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2A3A),
        title: Text('Invite Code — $name',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share this with your collaborators.\nThey tap "Join Project" and enter it.',
              style: TextStyle(color: Color(0xFF778899), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1A27),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334466)),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  color: Color(0xFF00AAFF),
                  fontFamily: 'monospace',
                  fontSize: 28,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.copy,
                  size: 16, color: Color(0xFF00AAFF)),
              label: const Text('Copy code',
                  style: TextStyle(color: Color(0xFF00AAFF))),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(ctx);
                _snack('Invite code copied!');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF556677))),
          ),
        ],
      ),
    );
  }

  // ── Show collaborators list ───────────────────────────────────────────────

  Future<void> _showCollaborators(
      int cloudProjectId, String name) async {
    final list = await ApiService.getCollaborators(cloudProjectId);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2A3A),
        title: Text('Collaborators — $name',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: list.isEmpty
            ? const Text('No one has joined yet.',
                style: TextStyle(color: Color(0xFF778899)))
            : SizedBox(
                width: 280,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Color(0xFF334466), height: 1),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline,
                          color: Color(0xFF00AAFF), size: 18),
                      title: Text(c['email'] as String,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                      subtitle: Text(
                        '${c['role']} · joined ${_shortDate(c['joined_at'])}',
                        style: const TextStyle(
                            color: Color(0xFF556677), fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(color: Color(0xFF556677))),
          ),
        ],
      ),
    );
  }

  // ── Leave shared project ──────────────────────────────────────────────────

  Future<void> _leaveProject(int cloudProjectId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2A3A),
        title: Text('Leave "$name"?',
            style: const TextStyle(color: Colors.white)),
        content: const Text('You will lose access to this shared project.',
            style: TextStyle(color: Color(0xFF778899))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF556677))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: Color(0xFFFF4444))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ApiService.leaveProject(cloudProjectId);
    if (ok) {
      _snack('Left project');
      _loadShared();
    } else {
      _snack('Failed', error: true);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  (List<SketchShape>, List<RoomObject>, List<double>, List<double>)
      _parseProjectData(Map<String, dynamic> data) {
    final shapesData = data['shapes'] as List<dynamic>;
    final objectsData = data['roomObjects'] as List<dynamic>;

    final shapes = shapesData.map<SketchShape>((s) {
      final shape = SketchShape.empty();
      shape.isClosed = s['is_closed'] as bool;
      shape.points = (s['points'] as List<dynamic>)
          .map((r) => Offset(
                (r['x'] as num).toDouble(),
                (r['y'] as num).toDouble(),
              ))
          .toList();
      for (final r in s['wall_real_mm'] as List<dynamic>) {
        shape.wallRealMm[r['wall_index'] as int] =
            (r['real_mm'] as num).toDouble();
      }
      return shape;
    }).toList();

    final wallAngles = shapesData.isEmpty
        ? <double>[]
        : (shapesData.first['wall_angles'] as List<dynamic>)
            .map((r) => (r['angle'] as num).toDouble())
            .toList();

    final wallLengths = shapesData.isEmpty
        ? <double>[]
        : (shapesData.first['wall_lengths'] as List<dynamic>)
            .map((r) => (r['length'] as num).toDouble())
            .toList();

    final roomObjects = objectsData.map<RoomObject>((r) {
      return RoomObject(
        id: r['object_id'] as String,
        type: r['type'] == 'door'
            ? RoomObjectType.door
            : RoomObjectType.window,
        wallIndex: r['wall_index'] as int,
        positionAlong: (r['position_along'] as num).toDouble(),
        widthMm: (r['width_mm'] as num).toDouble(),
        heightMm: (r['height_mm'] as num).toDouble(),
        elevationMm: (r['elevation_mm'] as num).toDouble(),
      );
    }).toList();

    return (shapes, roomObjects, wallAngles, wallLengths);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red : const Color(0xFF00AA44),
    ));
  }

  String _shortDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw as String).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A27),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A27),
        foregroundColor: Colors.white,
        title: const Text('Collaboration'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00AAFF),
          labelColor: const Color(0xFF00AAFF),
          unselectedLabelColor: const Color(0xFF556677),
          tabs: const [
            Tab(text: 'My Projects'),
            Tab(text: 'Shared With Me'),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.group_add,
                color: Color(0xFF00AAFF), size: 18),
            label: const Text('Join',
                style: TextStyle(color: Color(0xFF00AAFF))),
            onPressed: _showJoinDialog,
          ),
        ],
      ),
      body: _working
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00AAFF)),
                  SizedBox(height: 16),
                  Text('Working...',
                      style: TextStyle(color: Colors.white)),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOwnedTab(),
                _buildSharedTab(),
              ],
            ),
    );
  }

  Widget _buildOwnedTab() {
    if (_loadingOwned) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00AAFF)));
    }
    if (_ownedProjects.isEmpty) {
      return const Center(
        child: Text(
          'No cloud projects yet.\nBackup a project from the sketch screen.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF556677)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadOwned,
      child: ListView.builder(
        itemCount: _ownedProjects.length,
        itemBuilder: (ctx, i) {
          final p = _ownedProjects[i];
          final id = p['id'] as int;
          final name = p['name'] as String;
          return Card(
            color: const Color(0xFF1A2A3A),
            margin: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.cloud,
                  color: Color(0xFF8844FF)),
              title: Text(name,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                _shortDate(p['updated_at']),
                style: const TextStyle(
                    color: Color(0xFF556677), fontSize: 11),
              ),
              trailing: PopupMenuButton<String>(
                color: const Color(0xFF1A2A3A),
                icon: const Icon(Icons.more_vert,
                    color: Color(0xFF778899)),
                onSelected: (action) {
                  switch (action) {
                    case 'restore':
                      _restoreProject(id, name);
                    case 'invite':
                      _showInviteCode(id, name);
                    case 'collaborators':
                      _showCollaborators(id, name);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'restore',
                    child: Row(children: [
                      Icon(Icons.download,
                          color: Color(0xFF00AAFF), size: 16),
                      SizedBox(width: 8),
                      Text('Restore to device',
                          style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'invite',
                    child: Row(children: [
                      Icon(Icons.share,
                          color: Color(0xFF00AA44), size: 16),
                      SizedBox(width: 8),
                      Text('Share invite code',
                          style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'collaborators',
                    child: Row(children: [
                      Icon(Icons.people_outline,
                          color: Color(0xFF00AAFF), size: 16),
                      SizedBox(width: 8),
                      Text('View collaborators',
                          style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSharedTab() {
    if (_loadingShared) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00AAFF)));
    }
    if (_sharedProjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'No shared projects yet.',
              style: TextStyle(color: Color(0xFF556677)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.group_add),
              label: const Text('Join a project'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00AAFF),
                foregroundColor: Colors.white,
              ),
              onPressed: _showJoinDialog,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadShared,
      child: ListView.builder(
        itemCount: _sharedProjects.length,
        itemBuilder: (ctx, i) {
          final p = _sharedProjects[i];
          final id = p['id'] as int;
          final name = p['name'] as String;
          final owner = p['owner_email'] as String? ?? 'unknown';
          return Card(
            color: const Color(0xFF1A2A3A),
            margin: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.people,
                  color: Color(0xFF00AAFF)),
              title: Text(name,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                'Owner: $owner · ${_shortDate(p['updated_at'])}',
                style: const TextStyle(
                    color: Color(0xFF556677), fontSize: 11),
              ),
              trailing: PopupMenuButton<String>(
                color: const Color(0xFF1A2A3A),
                icon: const Icon(Icons.more_vert,
                    color: Color(0xFF778899)),
                onSelected: (action) {
                  switch (action) {
                    case 'open_live':
                      _openLive(id, name);
                    case 'restore':
                      _restoreProject(id, name);
                    case 'leave':
                      _leaveProject(id, name);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'open_live',
                    child: Row(children: [
                      Icon(Icons.sync,
                          color: Color(0xFF00FF99), size: 16),
                      SizedBox(width: 8),
                      Text('Open live (auto-sync)',
                          style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'restore',
                    child: Row(children: [
                      Icon(Icons.download,
                          color: Color(0xFF00AAFF), size: 16),
                      SizedBox(width: 8),
                      Text('Restore to device',
                          style: TextStyle(color: Colors.white)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'leave',
                    child: Row(children: [
                      Icon(Icons.exit_to_app,
                          color: Color(0xFFFF4444), size: 16),
                      SizedBox(width: 8),
                      Text('Leave project',
                          style: TextStyle(
                              color: Color(0xFFFF4444))),
                    ]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live collaboration wrapper — polls every 10 seconds for updates
// ─────────────────────────────────────────────────────────────────────────────

class _LiveCollabWrapper extends StatefulWidget {
  final int cloudProjectId;
  final String projectName;
  final List<SketchShape> initialShapes;
  final List<double> initialWallAngles;
  final List<double> initialWallLengths;
  final String lastKnownUpdatedAt;

  const _LiveCollabWrapper({
    required this.cloudProjectId,
    required this.projectName,
    required this.initialShapes,
    required this.initialWallAngles,
    required this.initialWallLengths,
    required this.lastKnownUpdatedAt,
  });

  @override
  State<_LiveCollabWrapper> createState() => _LiveCollabWrapperState();
}

class _LiveCollabWrapperState extends State<_LiveCollabWrapper> {
  Timer? _pollTimer;
  String _lastUpdatedAt = '';
  bool _syncing = false;
  DateTime? _lastSyncTime;
  Key _sketchKey = UniqueKey();
  late List<SketchShape> _shapes;
  late List<double> _wallAngles;
  late List<double> _wallLengths;

  @override
  void initState() {
    super.initState();
    _lastUpdatedAt = widget.lastKnownUpdatedAt;
    _shapes = widget.initialShapes;
    _wallAngles = widget.initialWallAngles;
    _wallLengths = widget.initialWallLengths;
    _pollTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_syncing) return;
    _syncing = true;

    final data = await ApiService.pollForUpdates(
        widget.cloudProjectId, _lastUpdatedAt);

    if (!mounted) {
      _syncing = false;
      return;
    }

    if (data != null) {
      _lastUpdatedAt =
          data['project']['updated_at'] as String? ?? _lastUpdatedAt;

      final newShapes =
          (data['shapes'] as List<dynamic>).map<SketchShape>((s) {
        final shape = SketchShape.empty();
        shape.isClosed = s['is_closed'] as bool;
        shape.points = (s['points'] as List<dynamic>)
            .map((r) => Offset(
                  (r['x'] as num).toDouble(),
                  (r['y'] as num).toDouble(),
                ))
            .toList();
        for (final r in s['wall_real_mm'] as List<dynamic>) {
          shape.wallRealMm[r['wall_index'] as int] =
              (r['real_mm'] as num).toDouble();
        }
        return shape;
      }).toList();

      setState(() {
        _shapes = newShapes;
        _lastSyncTime = DateTime.now();
        _sketchKey = UniqueKey();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Project updated by owner'),
          backgroundColor: Color(0xFF004488),
          duration: Duration(seconds: 2),
        ));
      }
    }
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SketchScreen(
          key: _sketchKey,
          bleManager: null,
        ),
        Positioned(
          top: 56,
          right: 8,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF004422),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00AA44)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync,
                    color: Color(0xFF00AA44), size: 12),
                const SizedBox(width: 4),
                Text(
                  _lastSyncTime == null
                      ? 'Live sync active'
                      : 'Synced ${_timeAgo(_lastSyncTime!)}',
                  style: const TextStyle(
                    color: Color(0xFF00AA44),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}