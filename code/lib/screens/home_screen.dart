import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../ble/ble_manager.dart';
import '../ble/ble_connection_screen.dart';
import '../sketch/sketch_screen.dart';
import '../services/api_service.dart';
import '../screens/login_screen.dart';
import '../database/project_list_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadUserEmail();
  }

  Future<void> _loadUserEmail() async {
    final token = await ApiService.getToken();
    if (token != null) {
      // Decode email from token
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
        );
        setState(() => _userEmail = payload['email']);
      }
    }
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_userEmail != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(_userEmail!,
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.straighten, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text('SmartMeasure Pro',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Precision hardware. Smart sketching.',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 40),

            // Start sketch button
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Start Room Sketch'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: () {
                final bleManager = BleManager();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BleConnectionScreen(
                      bleManager: bleManager,
                      onConnected: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SketchScreen(bleManager: bleManager),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // My projects button
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('My Projects'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
                backgroundColor: const Color(0xFF1A2A3A),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ProjectListScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}