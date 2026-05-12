import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import 'api_service.dart';

enum SyncStatus { idle, syncing, offline, conflict }

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  // Notify listeners (sketch screen listens to this)
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  // Emits {local_project_id, cloud_project_id, updated_at} on each successful upload
  final _uploadSuccessController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get uploadSuccessStream =>
      _uploadSuccessController.stream;

  StreamSubscription? _connectivitySub;
  Timer? _retryTimer;
  bool _isProcessing = false;

  // Call this once from main.dart or home_screen initState
  void init() {
    // Listen for connectivity changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      if (connected) {
        processQueue(); // internet came back — try the queue
      } else {
        _setStatus(SyncStatus.offline);
      }
    });

    // Also retry every 60 seconds as fallback
    _retryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      processQueue();
    });
  }

  void dispose() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    _statusController.close();
    _uploadSuccessController.close();
  }

  // Add to queue — call this instead of uploadProject() directly
  Future<void> queueUpload({
    required int projectId,
    required Map<String, dynamic> projectData,
    String? lastModifiedAt,
  }) async {
    final payload = jsonEncode({
      ...projectData,
      if (lastModifiedAt != null) 'last_modified_at': lastModifiedAt,
    });
    await DatabaseHelper.instance.queueUpload(
      projectId: projectId,
      payloadJson: payload,
    );
    _setStatus(SyncStatus.idle);
    processQueue(); // try immediately
  }

  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final item = await DatabaseHelper.instance.getNextPendingUpload();
        if (item == null) break; // queue empty

        _setStatus(SyncStatus.syncing);

        final id = item['id'] as int;
        final payload = jsonDecode(item['payload'] as String)
            as Map<String, dynamic>;

        try {
          final result = await ApiService.uploadProject(payload);

          if (result['conflict'] == true) {
            await DatabaseHelper.instance.markUploadConflict(id);
            _setStatus(SyncStatus.conflict);
            break; // stop processing — user must resolve conflict
          } else if (result['error'] != null) {
            await DatabaseHelper.instance.markUploadAttempted(id);
            _setStatus(SyncStatus.offline);
            break; // network error — stop, retry later
          } else {
            // Success — notify listeners so sketch screen can track cloud ID
            await DatabaseHelper.instance.deletePendingUpload(id);
            _uploadSuccessController.add({
              'local_project_id': item['project_id'],
              'cloud_project_id': result['cloud_project_id'],
              'updated_at': result['updated_at'],
            });
            _setStatus(SyncStatus.idle);
          }
        } catch (e) {
          await DatabaseHelper.instance.markUploadAttempted(id);
          _setStatus(SyncStatus.offline);
          break;
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    _statusController.add(s);
  }
}
