$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
& (Join-Path $root 'native\build_android_arm64.ps1') -Release
if($LASTEXITCODE -ne 0){throw 'Native build failed'}
Push-Location $root
try{
& python tools/collect_rust_licenses.py
if($LASTEXITCODE -ne 0){throw 'Rust license collection failed'}
& python tools/stage_pdf_ocr.py
if($LASTEXITCODE -ne 0){throw 'OCR staging failed'}
& flutter pub get
if($LASTEXITCODE -ne 0){throw 'pub get failed'}
& flutter analyze
if($LASTEXITCODE -ne 0){throw 'flutter analyze failed'}
& flutter test
if($LASTEXITCODE -ne 0){throw 'flutter test failed'}
& flutter build apk --debug --target-platform android-arm64
if($LASTEXITCODE -ne 0){throw 'APK build failed'}
& python tools/verify_android_apk.py build/app/outputs/flutter-apk/app-debug.apk
if($LASTEXITCODE -ne 0){throw 'APK verification failed'}
Write-Output "Debug APK: $root\build\app\outputs\flutter-apk\app-debug.apk"
} finally {Pop-Location}
