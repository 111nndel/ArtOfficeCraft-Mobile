param([switch]$Release)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(-not (Get-Command cargo -ErrorAction SilentlyContinue)){throw 'Rust cargo not on PATH'}
if(-not (Get-Command python -ErrorAction SilentlyContinue)){throw 'Python 3 not on PATH'}
& python (Join-Path $root 'tools\sync_native_pins.py')
if($LASTEXITCODE -ne 0){throw 'Pinned Rust source invalid or missing'}
$sdk = $env:ANDROID_HOME
if(-not $sdk){$sdk=$env:ANDROID_SDK_ROOT}
if(-not $sdk){throw 'ANDROID_HOME must reference your Android SDK'}
$ndk = $env:ANDROID_NDK_HOME
if(-not $ndk){
  $candidates = Get-ChildItem (Join-Path $sdk 'ndk') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
  if(-not $candidates){throw 'Install Android NDK via Android Studio'}
  $ndk=$candidates[0].FullName
}
$linker = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android24-clang.cmd'
if(-not (Test-Path $linker)){throw "NDK ARM64 linker missing: $linker"}
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$linker
$args = @('build','--locked','--manifest-path',(Join-Path $root 'native\artoffice_core\Cargo.toml'),'--target','aarch64-linux-android')
if($Release){$args+='--release'}
& cargo @args
if($LASTEXITCODE -ne 0){throw 'Rust Android build failed'}
$profile = if($Release){'release'}else{'debug'}
$binary=Join-Path $root ("native\artoffice_core\target\aarch64-linux-android\$profile\libartoffice_core.so")
$folder=Join-Path $root 'android\app\src\main\jniLibs\arm64-v8a'
New-Item $folder -ItemType Directory -Force | Out-Null
Copy-Item $binary (Join-Path $folder 'libartoffice_core.so') -Force
Write-Output 'Native ARM64 library installed into Android project'
