param(
    [Parameter(Mandatory=$true)][string]$ApkPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [Parameter(Mandatory=$true)][ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$')][string]$Tag,
    [Parameter(Mandatory=$true)][string]$Notes,
    [string]$Gh = 'gh'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo = '111nndel/ArtOfficeCraft-Mobile'
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$notesFile = (Resolve-Path -LiteralPath $Notes).Path
Push-Location $root
try {
    $resolved = & $Gh api "repos/$repo/commits/$Commit" --jq .sha
    if ($LASTEXITCODE -ne 0 -or $resolved -ne $Commit) {throw 'Source commit unavailable on GitHub'}
    python tools/verify_android_apk.py $apk
    if ($LASTEXITCODE -ne 0) {throw 'APK verification failed'}
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) {$sdk = $env:ANDROID_SDK_ROOT}
    if (-not $sdk) {throw 'Set ANDROID_HOME or ANDROID_SDK_ROOT'}
    $buildTools = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    $permissions = & (Join-Path $buildTools 'aapt.exe') dump permissions $apk
    if ($LASTEXITCODE -ne 0) {throw 'Could not inspect Android permissions'}
    if (($permissions -join "`n") -match 'android.permission.(INTERNET|ACCESS_WIFI_STATE|CHANGE_WIFI_STATE)') {
        throw 'Offline policy violated: network permission in final APK'
    }
    # Java warnings are stderr diagnostics, not signature failure. Windows
    # PowerShell can turn redirected native stderr into a terminating error.
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & (Join-Path $buildTools 'apksigner.bat') verify $apk
        $signatureExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($signatureExit -ne 0) {throw 'APK signature verification failed'}
    & (Join-Path $buildTools 'zipalign.exe') -c -P 16 4 $apk
    if ($LASTEXITCODE -ne 0) {throw 'APK ZIP alignment failed'}
    $folder = Join-Path $root "build\publish-$Tag"
    New-Item -ItemType Directory -Force $folder | Out-Null
    $hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    $shaFile = Join-Path $folder 'SHA256SUMS.txt'
    "$hash  $(Split-Path $apk -Leaf)" | Set-Content $shaFile -Encoding Ascii
    $manifest = Join-Path $folder 'build-info.json'
    @{
        sourceCommit=$Commit; tag=$Tag; apk=(Split-Path $apk -Leaf); sha256=$hash;
        signing='development debug certificate'; offlinePermissionsVerified=$true;
        engines=(Get-Content upstream/engines.lock.json -Raw | ConvertFrom-Json).engines
    } | ConvertTo-Json -Depth 8 | Set-Content $manifest -Encoding UTF8
    & $Gh release create $Tag --repo $repo --target $Commit --draft --prerelease `
        --title "ArtOfficeCraft Mobile $Tag (Android development preview)" --notes-file $notesFile
    if ($LASTEXITCODE -ne 0) {throw 'Could not create draft release'}
    & $Gh release upload $Tag $apk $shaFile $manifest assets/legal/rust-licenses.json --repo $repo
    if ($LASTEXITCODE -ne 0) {throw 'Upload failed; release remains a draft'}
    & $Gh release edit $Tag --repo $repo --draft=false
    if ($LASTEXITCODE -ne 0) {throw 'Could not publish the prepared prerelease'}
    & $Gh release view $Tag --repo $repo --json url,assets
} finally {
    Pop-Location
}
