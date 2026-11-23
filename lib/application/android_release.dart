import 'dart:convert';
import 'dart:io';

const releaseRepo = 'jerrywu-voltraware/gios0901-android-demo';

class AndroidRelease {
  const AndroidRelease(this.version, this.code);
  final String version;
  final int code;

  static AndroidRelease fromGitHub(Map<String, dynamic> release) {
    final tag = release['tag_name'];
    if (release['draft'] != false ||
        release['prerelease'] != false ||
        tag is! String ||
        !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(tag)) {
      throw const FormatException('Invalid stable release');
    }
    final version = tag.substring(1);
    final pattern = RegExp(
      '^GIOS0901-Demo-${RegExp.escape(version)}-([1-9][0-9]*)\\.apk\$',
    );
    for (final asset in (release['assets'] as List).whereType<Map>()) {
      final name = asset['name'];
      if (name is! String || asset['state'] != 'uploaded') continue;
      final match = pattern.firstMatch(name);
      if (match != null &&
          asset['browser_download_url'] ==
              'https://github.com/$releaseRepo/releases/download/$tag/$name') {
        return AndroidRelease(version, int.parse(match.group(1)!));
      }
    }
    throw const FormatException('Missing release APK');
  }
}

Future<AndroidRelease> latestRelease() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  Future<AndroidRelease> fetch() async {
    final request = await client.getUrl(
      Uri.https('api.github.com', '/repos/$releaseRepo/releases/latest'),
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'GIOS0901-Android-Demo');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok)
      throw HttpException('GitHub HTTP ${response.statusCode}');
    return AndroidRelease.fromGitHub(
      jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>,
    );
  }

  try {
    return await fetch().timeout(const Duration(seconds: 15));
  } finally {
    client.close(force: true);
  }
}
