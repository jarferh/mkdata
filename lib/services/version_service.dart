import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'api_service.dart';

class VersionService {
  static const Duration _checkInterval = Duration(hours: 1);
  final ApiService _apiService = ApiService();
  DateTime? _lastCheckTime;

  /// Compare two semantic versions (e.g., "1.0.0").
  /// Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
  int compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = v2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    // Pad with zeros
    while (parts1.length < parts2.length) parts1.add(0);
    while (parts2.length < parts1.length) parts2.add(0);

    for (int i = 0; i < parts1.length; i++) {
      if (parts1[i] < parts2[i]) return -1;
      if (parts1[i] > parts2[i]) return 1;
    }
    return 0;
  }

  /// Fetch latest app version from backend.
  /// Returns a Map with: latest_version, min_version, force_update, update_url, release_notes
  Future<Map<String, dynamic>?> fetchLatestVersion() async {
    try {
      print('[VersionService] Fetching latest version from API...');
      final response = await _apiService.get('app-version');

      print('[VersionService] API Response: $response');

      // Check if response indicates success
      final isSuccess =
          response['status'] == 'success' || response['success'] == true;

      if (isSuccess) {
        // Data might be nested in 'data' field or at top level
        final data = response['data'] ?? response;
        return {
          'latest_version': data['latest_version'] ?? '1.0.0',
          'min_version': data['min_version'] ?? '1.0.0',
          'force_update': data['force_update'] ?? false,
          'update_url': data['update_url'] ?? '',
          'release_notes': data['release_notes'] ?? '',
        };
      }

      print(
        '[VersionService] API returned non-success: ${response['message']}',
      );
      return null;
    } catch (e) {
      print('[VersionService] Error fetching latest version: $e');
      return null;
    }
  }

  /// Get current app version
  Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      print(
        '[VersionService] Current app version: ${packageInfo.version}+${packageInfo.buildNumber}',
      );
      return packageInfo.version;
    } catch (e) {
      print('[VersionService] Error getting package info: $e');
      return '0.0.0';
    }
  }

  /// Check if update is available.
  /// Respects check interval to avoid excessive API calls.
  /// Returns UpdateInfo or null if no update available.
  Future<UpdateInfo?> checkForUpdate({bool forceCheck = false}) async {
    try {
      // Skip if recently checked and not forced
      if (!forceCheck &&
          _lastCheckTime != null &&
          DateTime.now().difference(_lastCheckTime!) < _checkInterval) {
        print('[VersionService] Skipping check (checked recently)');
        return null;
      }

      _lastCheckTime = DateTime.now();

      final currentVersion = await getCurrentVersion();
      final latestInfo = await fetchLatestVersion();

      if (latestInfo == null) {
        print('[VersionService] No version info available from API');
        return null;
      }

      final latestVersion = latestInfo['latest_version'] ?? '1.0.0';
      final minVersion = latestInfo['min_version'] ?? '1.0.0';
      final forceUpdate = latestInfo['force_update'] ?? false;
      final updateUrl = latestInfo['update_url'] ?? '';
      final releaseNotes = latestInfo['release_notes'] ?? '';

      print(
        '[VersionService] Comparing: current=$currentVersion vs latest=$latestVersion',
      );

      // Check if current version is below minimum required
      if (compareVersions(currentVersion, minVersion) < 0) {
        print('[VersionService] Current version is below minimum');
        return UpdateInfo(
          isUpdateAvailable: true,
          isForceUpdate: true,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          updateUrl: updateUrl,
          releaseNotes: releaseNotes,
        );
      }

      // Check if newer version is available
      if (compareVersions(currentVersion, latestVersion) < 0) {
        print('[VersionService] Update available: $latestVersion');
        return UpdateInfo(
          isUpdateAvailable: true,
          isForceUpdate: forceUpdate,
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          updateUrl: updateUrl,
          releaseNotes: releaseNotes,
        );
      }

      print('[VersionService] App is up to date');
      return null;
    } catch (e) {
      print('[VersionService] Error checking for update: $e');
      return null;
    }
  }
}

class UpdateInfo {
  final bool isUpdateAvailable;
  final bool isForceUpdate;
  final String currentVersion;
  final String latestVersion;
  final String updateUrl;
  final String releaseNotes;

  UpdateInfo({
    required this.isUpdateAvailable,
    required this.isForceUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.updateUrl,
    required this.releaseNotes,
  });
}
