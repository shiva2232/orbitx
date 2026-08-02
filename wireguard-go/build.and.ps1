# ===== CONFIG =====
$ErrorActionPreference = "Stop"

$NDK = "C:\Users\vsiva\AppData\Local\Android\Sdk\ndk\28.2.13676358"
$API = "23"
$BASE_TOOLCHAIN = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin"

function Build-Arch($goarch, $target, $folder) {
    Write-Host "`n--- Building for $folder ---"

    $env:GOOS = "android"
    $env:GOARCH = $goarch
    $env:CGO_ENABLED = "1"
    $env:GO111MODULE = "on"
    $env:CC = "$BASE_TOOLCHAIN\$target$API-clang.cmd"

    go build -v -buildmode=c-shared -o libvpnengine.so .

    $dest = "../android/app/src/main/jniLibs/$folder"

    if (!(Test-Path $dest)) {
        New-Item -ItemType Directory -Force $dest | Out-Null
    }

    Copy-Item libvpnengine.so "$dest/libvpnengine.so" -Force

    if (Test-Path libvpnengine.h) {
        Remove-Item libvpnengine.h
    }

    Remove-Item libvpnengine.so -Force
}

# ===== Build Targets =====

# ARM 32-bit (armeabi-v7a)
Build-Arch "arm" "armv7a-linux-androideabi" "armeabi-v7a"

# ARM 64-bit (arm64-v8a)
Build-Arch "arm64" "aarch64-linux-android" "arm64-v8a"

# x86_64 Emulator
Build-Arch "amd64" "x86_64-linux-android" "x86_64"

Write-Host ""
Write-Host "======================================="
Write-Host " Build completed successfully!"
Write-Host "======================================="