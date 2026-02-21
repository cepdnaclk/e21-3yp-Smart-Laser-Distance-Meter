import 'package:flutter/material.dart';
import '../core/constants.dart';
import 'sketch_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SketchScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}