// lib/database/project_list_screen.dart

import 'package:flutter/material.dart';
import 'database_helper.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final projects = await DatabaseHelper.instance.getAllProjects();
    setState(() {
      _projects = projects;
      _loading = false;
    });
  }

  Future<void> _deleteProject(int id) async {
    await DatabaseHelper.instance.deleteProject(id);
    _loadProjects(); // refresh the list
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1A27),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1A27),
        title: const Text('Saved Projects',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? const Center(
                  child: Text('No saved projects yet',
                      style: TextStyle(color: Color(0xFF556677))))
              : ListView.builder(
                  itemCount: _projects.length,
                  itemBuilder: (ctx, i) {
                    final p = _projects[i];
                    return ListTile(
                      title: Text(p['name'],
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(p['updated_at'],
                          style: const TextStyle(
                              color: Color(0xFF556677), fontSize: 11)),
                      leading: const Icon(Icons.folder_outlined,
                          color: Color(0xFF00AAFF)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Color(0xFFFF4444)),
                        onPressed: () => _deleteProject(p['id']),
                      ),
                      // Returns the project id back to whoever opened this screen
                      onTap: () => Navigator.pop(context, p['id']),
                    );
                  },
                ),
    );
  }
}