// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // When testing on Android phone on same WiFi as your computer
  // replace with your computer's actual IP address
  // example: http://192.168.1.5:3000
  // To find your IP run ipconfig in terminal and look for IPv4 Address
  static const String baseUrl = 'http://192.168.1.102:3000';

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
}