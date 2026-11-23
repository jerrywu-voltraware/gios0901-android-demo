[CmdletBinding()]
param(
    [string]$AndroidSdk = $env:ANDROID_HOME
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
Push-Location $project
try {
    if (-not $AndroidSdk) { $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    $buildTools = Get-ChildItem (Join-Path $AndroidSdk 'build-tools') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $buildTools) { throw 'Android SDK Build Tools missing.' }
    $manifestVersion = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
    if (-not $manifestVersion) { throw 'Expected MAJOR.MINOR.PATCH+BUILD in pubspec.yaml.' }
    $version = $manifestVersion.Matches[0].Groups[1].Value
    $code = $manifestVersion.Matches[0].Groups[2].Value
    flutter test
    if ($LASTEXITCODE) { throw 'Tests failed.' }
    flutter build apk --release
    if ($LASTEXITCODE) { throw 'APK build failed.' }
    $apk = 'build/app/outputs/flutter-apk/app-release.apk'
    $info = & (Join-Path $buildTools.FullName 'aapt.exe') dump badging $apk
    if ($LASTEXITCODE -or $info[0] -notlike "package: name='com.voltraware.gios0901.demo' versionCode='$code' versionName='$version'*") {
        throw 'APK package or version mismatch.'
    }
    $signer = '314038d83636b383d63f3da7044976d9bf8a5dcac51c2f1386d56459b0c2fe4f'
    $signature = & (Join-Path $buildTools.FullName 'apksigner.bat') verify --print-certs $apk
    if ($LASTEXITCODE -or $signature -notcontains "Signer #1 certificate SHA-256 digest: $signer") {
        throw 'The APK cannot update existing installations. Check the signing keystore.'
    }
    $dest = "build/GIOS0901-Demo-$version-$code.apk"
    Copy-Item -LiteralPath $apk -Destination $dest -Force
    Get-FileHash -Algorithm SHA256 -LiteralPath $dest | Format-List
} finally {
    Pop-Location
}
