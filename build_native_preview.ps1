$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
& (Join-Path $root 'native\build_android_arm64.ps1') -Release
if($LASTEXITCODE -ne 0){throw 'Native build failed'}
Push-Location $root
try{
& flutter pub get
if($LASTEXITCODE -ne 0){throw 'pub get failed'}
& flutter analyze
if($LASTEXITCODE -ne 0){throw 'flutter analyze failed'}
& flutter test
if($LASTEXITCODE -ne 0){throw 'flutter test failed'}
& flutter build apk --debug --target-platform android-arm64
if($LASTEXITCODE -ne 0){throw 'APK build failed'}
Write-Output "Debug APK: $root\build\app\outputs\flutter-apk\app-debug.apk"
} finally {Pop-Location}
