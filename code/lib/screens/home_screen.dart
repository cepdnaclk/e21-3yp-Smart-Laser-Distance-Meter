import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_providers.dart';
import '../core/constants.dart';
import '../ble/ble_manager.dart';
import '../ble/ble_connection_screen.dart';
import '../sketch/sketch_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () => ref.read(authServiceProvider).signOut(),
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
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Precision hardware. Smart sketching.',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Start Room Sketch'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: () {
                // Create a single BleManager for this session
                final bleManager = BleManager();

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BleConnectionScreen(
                      bleManager: bleManager,
                      onConnected: () {
                        // Replace connection screen with sketch screen
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SketchScreen(bleManager: bleManager),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}