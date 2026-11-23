import 'package:flutter_test/flutter_test.dart';
import 'package:gios0901/application/android_release.dart';

void main() {
  const name = 'GIOS0901-Demo-1.0.2-3.apk';
  final asset = {
    'name': name,
    'state': 'uploaded',
    'browser_download_url':
        'https://github.com/$releaseRepo/releases/download/v1.0.2/$name',
  };
  final stable = {
    'tag_name': 'v1.0.2',
    'draft': false,
    'prerelease': false,
    'assets': [asset],
  };
  test('reads the Android build number from the matching stable APK', () {
    final release = AndroidRelease.fromGitHub(stable);
    expect(release.version, '1.0.2');
    expect(release.code, 3);
  });
  test(
    'rejects prereleases, missing APKs and links outside the repository',
    () {
      for (final invalid in [
        {...stable, 'prerelease': true},
        {...stable, 'assets': []},
        {
          ...stable,
          'assets': [
            {...asset, 'browser_download_url': 'https://example.com/$name'},
          ],
        },
      ]) {
        expect(() => AndroidRelease.fromGitHub(invalid), throwsFormatException);
      }
    },
  );
}
