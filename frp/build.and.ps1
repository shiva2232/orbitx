# powershell
# Set NDK Path and Toolchain
$NDK = "C:\Users\vsiva\AppData\Local\Android\Sdk\ndk\28.2.13676358"
$TOOLCHAIN = "$NDK\toolchains\llvm\prebuilt\windows-x86_64\bin"
$API = "23"

# 1. Build for arm64-v8a (Most modern phones)
$env:CGO_ENABLED="1"; $env:GOOS="android"; $env:GOARCH="arm64"
$env:CC="$TOOLCHAIN\aarch64-linux-android$API-clang.cmd"
go build -buildmode=c-shared -o ../android/app/src/main/jniLibs/arm64-v8a/libfrpwrapper.so .

# 2. Build for armeabi-v7a (Older phones)
$env:CGO_ENABLED="1"; $env:GOOS="android"; $env:GOARCH="arm"
$env:CC="$TOOLCHAIN\armv7a-linux-androideabi$API-clang.cmd"
go build -buildmode=c-shared -o ../android/app/src/main/jniLibs/armeabi-v7a/libfrpwrapper.so .

# 3. Build for x86_64 (Simulators)
$env:CGO_ENABLED="1"; $env:GOOS="android"; $env:GOARCH="amd64"
$env:CC="$TOOLCHAIN\x86_64-linux-android$API-clang.cmd"
go build -buildmode=c-shared -o ../android/app/src/main/jniLibs/x86_64/libfrpwrapper.so .