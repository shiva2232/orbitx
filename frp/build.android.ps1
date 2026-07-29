# Build script for Android .so libraries
$NDK_PATH = "$env:ANDROID_NDK_HOME"
if (-not $NDK_PATH) {
    $NDK_PATH = "$env:LOCALAPPDATA/Android/Sdk/ndk/25.2.9519653" # Example path, adjust to your NDK version
}

$API = 21
$TOOLCHAIN = "$NDK_PATH/toolchains/llvm/prebuilt/windows-x86_64/bin"

function Build-So {
    param($Arch, $GoArch, $Target, $JniDir)
    Write-Host "Building for $Arch..."
    $env:GOOS = "android"
    $env:GOARCH = $GoArch
    $env:CGO_ENABLED = 1
    $env:CC = "$TOOLCHAIN/$Target$API-clang.cmd"
    
    go build -buildmode=c-shared -o "../android/app/src/main/jniLibs/$JniDir/libfrpwrapper.so" .
}

# Ensure directories exist
New-Item -ItemType Directory -Force "../android/app/src/main/jniLibs/arm64-v8a"
New-Item -ItemType Directory -Force "../android/app/src/main/jniLibs/armeabi-v7a"
New-Item -ItemType Directory -Force "../android/app/src/main/jniLibs/x86_64"

# Build for major architectures
Build-So "arm64" "arm64" "aarch64-linux-android" "arm64-v8a"
Build-So "arm" "arm" "armv7a-linux-androideabi" "armeabi-v7a"
Build-So "x86_64" "amd64" "x86_64-linux-android" "x86_64"

Write-Host "Build complete. .so files placed in android/app/src/main/jniLibs"
