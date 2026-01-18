import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/version_service.dart';

class UpdateAvailableDialog extends StatelessWidget {
  final UpdateInfo updateInfo;
  final VoidCallback? onDismiss;

  const UpdateAvailableDialog({
    required this.updateInfo,
    this.onDismiss,
    super.key,
  });

  Future<void> _openPlayStore() async {
    try {
      final url = Uri.parse(updateInfo.updateUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch URL';
      }
    } catch (e) {
      print('Error launching Play Store: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Prevent dismissing if force update
      onWillPop: () async => !updateInfo.isForceUpdate,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFce4323).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update,
                  size: 40,
                  color: Color(0xFFce4323),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                updateInfo.isForceUpdate
                    ? 'Update Required'
                    : 'Update Available',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // Version info
              Text(
                'Version ${updateInfo.latestVersion}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Release notes
              if (updateInfo.releaseNotes.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What\'s New:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        updateInfo.releaseNotes,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              if (updateInfo.releaseNotes.isNotEmpty)
                const SizedBox(height: 16),

              // Message
              Text(
                updateInfo.isForceUpdate
                    ? 'This version is no longer supported. Please update to continue using the app.'
                    : 'A new version is available with improvements and bug fixes.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Update Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _openPlayStore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFce4323),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Update Now',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              // Skip button (only if not force update)
              if (!updateInfo.isForceUpdate) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onDismiss?.call();
                    },
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                      ),
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFce4323),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
