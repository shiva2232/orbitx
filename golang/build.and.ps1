# ===== CONFIG =====
$NDK = "C:\Users\vsiva\AppData\Local\Android\Sdk\ndk\28.2.13676358"
$API = "23"
$BASE_TOOLCHAIN = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin"

function Build-Arch($arch, $target, $folder) {
    Write-Host "`n--- Building for $arch ($folder) ---"
    $env:GOOS = "android"
    $env:GOARCH = $arch
    $env:CGO_ENABLED = "1"
    # Force module mode to use the local go.mod
    $env:GO111MODULE = "on"
    $env:CC = "$BASE_TOOLCHAIN\$target$API-clang.cmd"

    # Build only the JNI-enabled vpnengine source (vpnengine.go contains the cgo preamble)
    # Use verbose output to help diagnose cross-compile issues.
    go build -v -buildmode=c-shared -o libvpnengine.so vpnengine.go
    
    $dest = "../android/app/src/main/jniLibs/$folder"
    if (!(Test-Path $dest)) { New-Item -ItemType Directory -Force $dest }
    Move-Item libvpnengine.so "$dest/libvpnengine.so" -Force
    # Clean up the generated header
    if (Test-Path libvpnengine.h) { Remove-Item libvpnengine.h }
}

# 1. Build for ARM64 (Physical Devices)
Build-Arch "arm64" "aarch64-linux-android" "arm64-v8a"

# 2. Build for x86_64 (Standard Windows Emulators)
Build-Arch "amd64" "x86_64-linux-android" "x86_64"

Write-Host "`nBuild Finished! All architectures deployed to jniLibs."
