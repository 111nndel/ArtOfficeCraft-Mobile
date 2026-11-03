param([Parameter(Mandatory=$true)][string]$Device)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
$manifest = Join-Path $root 'android\app\src\debug\AndroidManifest.xml'
$backup = $null
try {
    # A VM-service test APK is private QA output. Always rebuild the offline APK
    # after this script; never distribute its integration-test build.
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) {$sdk = $env:ANDROID_SDK_ROOT}
    if (-not $sdk) {throw 'Set ANDROID_HOME or ANDROID_SDK_ROOT'}
    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    $api = & $adb -s $Device shell getprop ro.build.version.sdk
    if ($LASTEXITCODE -ne 0 -or [int]$api -lt 36) {throw 'Use an Android 16 or newer QA device'}
    New-Item -ItemType Directory -Force 'build' | Out-Null
    $backup = Join-Path $root ('build\manifest-' + [guid]::NewGuid().ToString('N') + '.xml')
    Copy-Item $manifest $backup
    [System.IO.File]::WriteAllText($manifest,
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><uses-permission android:name="android.permission.INTERNET"/></manifest>')
    flutter test integration_test/native_editors_test.dart -d $Device --disable-dds --reporter expanded
    $testExit = $LASTEXITCODE
} finally {
    if ($backup -and (Test-Path $backup)) {
        Copy-Item $backup $manifest -Force
        Remove-Item $backup
    }
    Pop-Location
}
if ($testExit -ne 0) {throw 'Android integration tests failed'}
