import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/provider_profile.dart';

class ProviderProfileService {
  static const String _profilesKey = 'provider_profiles_v1';
  static const String _activeProfileKey = 'active_provider_profile_id';
  static const String _secretPrefix = 'provider_profile_api_key_';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  Future<List<ProviderProfile>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => ProviderProfile.fromJson(item as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      return [];
    }
  }

  Future<void> save(ProviderProfile profile, String apiKey) async {
    final profiles = await list();
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
    await _secureStorage.write(
      key: '$_secretPrefix${profile.id}',
      value: apiKey,
    );
    await prefs.setString(_activeProfileKey, profile.id);
  }

  Future<String> readApiKey(String profileId) async =>
      await _secureStorage.read(key: '$_secretPrefix$profileId') ?? '';

  Future<String?> activeProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeProfileKey);
  }

  Future<void> setActive(String? profileId) async {
    final prefs = await SharedPreferences.getInstance();
    if (profileId == null) {
      await prefs.remove(_activeProfileKey);
    } else {
      await prefs.setString(_activeProfileKey, profileId);
    }
  }

  Future<void> delete(String profileId) async {
    final profiles = await list();
    profiles.removeWhere((item) => item.id == profileId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
    if (prefs.getString(_activeProfileKey) == profileId) {
      await prefs.remove(_activeProfileKey);
    }
    await _secureStorage.delete(key: '$_secretPrefix$profileId');
  }
}
