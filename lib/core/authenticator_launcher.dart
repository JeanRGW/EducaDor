import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthenticatorLauncher {
  Future<bool> open(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'otpauth' ||
        uri.host != 'totp' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.fragment.isNotEmpty ||
        (uri.queryParameters['secret'] ?? '').isEmpty) {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

final authenticatorLauncherProvider = Provider<AuthenticatorLauncher>(
  (_) => AuthenticatorLauncher(),
);
