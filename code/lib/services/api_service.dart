// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl =
      'https://e21-3yp-smart-laser-distance-meter-production.up.railway.app';

  static const _storage = FlutterSecureStorage();

  // ── Token management ─────────────────────────────────────────────────

  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: 'jwt_token');
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  // ── Headers ───────────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Auth ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register(
      String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'error': 'Cannot connect to server. Check your connection.'};
    }
  }

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final data = jsonDecode(response.body);
      // Save token automatically on successful login
      if (data['token'] != null) {
        await saveToken(data['token']);
      }
      return data;
    } catch (e) {
      return {'error': 'Cannot connect to server. Check your connection.'};
    }
  }

  static Future<void> logout() async {
    await deleteToken();
  }

  // ── Sync ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> uploadProject(
      Map<String, dynamic> projectData) async {
    try {
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/sync/upload'),
        headers: headers,
        body: jsonEncode(projectData),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'error': 'Upload failed. Check your connection.'};
    }
  }

  static Future<Map<String, dynamic>?> downloadProject(
      int cloudProjectId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/sync/download/$cloudProjectId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<dynamic>> getCloudProjects() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/projects'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> pollForUpdates(
      int cloudProjectId, String since) async {
    try {
      final headers = await _authHeaders();
      final uri = Uri.parse(
          '$baseUrl/sync/updates/$cloudProjectId?since=${Uri.encodeComponent(since)}');
      final response = await http.get(uri, headers: headers);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['updated'] == false) return null;
      return data;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> joinProject(String inviteCode) async {
    try {
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/projects/join'),
        headers: headers,
        body: jsonEncode({'invite_code': inviteCode}),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'error': 'Cannot connect to server.'};
    }
  }

  static Future<List<dynamic>> getSharedProjects() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/projects/shared'),
        headers: headers,
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<String?> getInviteCode(int cloudProjectId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/projects/$cloudProjectId/invite-code'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return (jsonDecode(response.body))['invite_code'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<List<dynamic>> getCollaborators(int cloudProjectId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/projects/$cloudProjectId/collaborators'),
        headers: headers,
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> leaveProject(int cloudProjectId) async {
    try {
      final headers = await _authHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/projects/$cloudProjectId/leave'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}