// lib/database/cloud_projects_screen.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../database/database_helper.dart';
import '../sketch/room_object.dart';
import '../sketch/sketch_model.dart';

class CloudProjectsScreen extends StatefulWidget {
  const CloudProjectsScreen({super.key});

  @override
  State<CloudProjectsScreen> createState() => _CloudProjectsScreenState();
}

class _CloudProjectsScreenState extends State<CloudProjectsScreen> {
  List<dynamic> _projects = [];
  bool _loading = true;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _loadCloudProjects();
  }

  Future<void> _loadCloudProjects() async {
    final projects = await ApiService.getCloudProjects();
    setState(() {
      _projects = projects;
      _loading = false;
    });
  }

  Future<void> _restoreProject(int cloudProjectId, String name) async {
    setState(() => _restoring = true);

    final data = await ApiService.downloadProject(cloudProjectId);

    if (data == null) {
      setState(() => _restoring = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restore failed. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Save downloaded data to local SQLite
    final shapesData = data['shapes'] as List<dynamic>;
    final objectsData = data['roomObjects'] as List<dynamic>;

    // Rebuild shapes
    final List<dynamic> shapes = shapesData.map((s) {
      final shape = SketchShape.empty();
      shape.isClosed = s['is_closed'] as bool;
      final pointRows = s['points'] as List<dynamic>;
      shape.points = pointRows
          .map((r) => Offset(
                (r['x'] as num).toDouble(),
                (r['y'] as num).toDouble(),
              ))
          .toList();
      final mmRows = s['wall_real_mm'] as List<dynamic>;
      for (final r in mmRows) {
        shape.wallRealMm[r['wall_index'] as int] =
            (r['real_mm'] as num).toDouble();
      }
      return shape;
    }).toList();

    // Rebuild wall angles
    final List<double> wallAngles = [];
    final List<double> wallLengths = [];
    if (shapesData.isNotEmpty) {
      final angleRows = shapesData.first['wall_angles'] as List<dynamic>;
      wallAngles.addAll(
          angleRows.map((r) => (r['angle'] as num).toDouble()));
      final lengthRows = shapesData.first['wall_lengths'] as List<dynamic>;
      wallLengths.addAll(
          lengthRows.map((r) => (r['length'] as num).toDouble()));
    }

    // Rebuild room objects
    final List<RoomObject> roomObjects = objectsData.map((r) {
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

    // Save to local SQLite
    await DatabaseHelper.instance.saveProject(
      name: name,
      shapes: shapes,
      roomObjects: roomObjects,
      wallAngles: wallAngles,
      wallDrawnLengths: wallLengths,
    );

    setState(() => _restoring = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project restored to local storage'),
          backgroundColor: Color(0xFF00AA44),
        ),
      );
      // Go back after restore
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A27),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A27),
        title: const Text('Cloud Projects',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _restoring
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Restoring project...',
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                )
              : _projects.isEmpty
                  ? const Center(
                      child: Text('No cloud projects found',
                          style: TextStyle(color: Color(0xFF556677))),
                    )
                  : ListView.builder(
                      itemCount: _projects.length,
                      itemBuilder: (ctx, i) {
                        final p = _projects[i];
                        return ListTile(
                          title: Text(
                            p['name'],
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            p['updated_at'] ?? '',
                            style: const TextStyle(
                                color: Color(0xFF556677), fontSize: 11),
                          ),
                          leading: const Icon(Icons.cloud,
                              color: Color(0xFF8844FF)),
                          trailing: IconButton(
                            icon: const Icon(Icons.download,
                                color: Color(0xFF00AAFF)),
                            tooltip: 'Restore to device',
                            onPressed: () => _restoreProject(
                              p['id'] as int,
                              p['name'] as String,
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}