#!/bin/bash
# 編 iPhone 版的 libarchive（壓縮與解壓縮：ZIP、7z、tar.gz、RAR…），放到 iOS/Vendor/LibArchive（不進 git）。
#
# 為什麼這樣編：
#   • Mac 版叫系統的 bsdtar；iPhone 不准執行別的程式，系統也不公開 libarchive，所以自己編、靜態連進 App（BSD 授權，靜態連結沒問題）。
#   • 7z 要用 LZMA 壓縮必須連 liblzma（xz），否則會默默退成 bzip2。zlib、bzip2、iconv、CommonCrypto（ZIP 的 AES）用 iPhone SDK 內建的。
#   • 只編 arm64（實機）與 arm64-simulator；最低 iOS 18。
#   • 路徑不能有空白（CMake／configure 的老問題），原始碼放在 ~/Developer/radius-vendor。
#
# 原始碼：
#   git clone --depth 1 --branch v3.8.9 https://github.com/libarchive/libarchive.git ~/Developer/radius-vendor/libarchive
#   git clone --depth 1 --branch v5.8.4 https://github.com/tukaani-project/xz.git      ~/Developer/radius-vendor/xz
# 需要：cmake、ninja（brew install cmake ninja）
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
VENDOR="${VENDOR_DIR:-$HOME/Developer/radius-vendor}"
case "$VENDOR" in *" "*) echo "✘ 原始碼路徑不能有空白：$VENDOR"; exit 1;; esac
for d in libarchive xz; do [ -f "$VENDOR/$d/CMakeLists.txt" ] || { echo "✘ 找不到 $VENDOR/$d（見檔頭）"; exit 1; }; done
WORK="$VENDOR/build-ios"
rm -rf "$WORK"
mkdir -p "$WORK"

build() {   # $1 = iphoneos | iphonesimulator
    local sdk=$1 out="$WORK/$1"
    local common=(-G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64
                  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
                  -DCMAKE_INSTALL_PREFIX="$out/prefix" -DCMAKE_POSITION_INDEPENDENT_CODE=ON)
    cmake -S "$VENDOR/xz" -B "$out/xz" "${common[@]}" -DXZ_NLS=OFF -DXZ_TOOL_XZ=OFF -DXZ_TOOL_XZDEC=OFF \
          -DXZ_TOOL_LZMADEC=OFF -DXZ_TOOL_LZMAINFO=OFF -DXZ_TOOL_SCRIPTS=OFF -DXZ_DOC=OFF -DBUILD_TESTING=OFF > "$out.xz.log"
    cmake --build "$out/xz" --target install >> "$out.xz.log"
    cmake -S "$VENDOR/libarchive" -B "$out/libarchive" "${common[@]}" \
          -DENABLE_TAR=OFF -DENABLE_CPIO=OFF -DENABLE_CAT=OFF -DENABLE_UNZIP=OFF -DENABLE_TEST=OFF -DENABLE_INSTALL=ON \
          -DENABLE_OPENSSL=OFF -DENABLE_MBEDTLS=OFF -DENABLE_NETTLE=OFF -DENABLE_LIBXML2=OFF -DENABLE_EXPAT=OFF -DENABLE_PCREPOSIX=OFF \
          -DENABLE_PCRE2POSIX=OFF -DENABLE_LZ4=OFF -DENABLE_ZSTD=OFF -DENABLE_LIBB2=OFF -DENABLE_CNG=OFF -DENABLE_ACL=OFF -DENABLE_XATTR=OFF \
          -DENABLE_LZMA=ON -DLIBLZMA_INCLUDE_DIR="$out/prefix/include" -DLIBLZMA_LIBRARY="$out/prefix/lib/liblzma.a" \
          -DENABLE_ZLIB=ON -DENABLE_BZip2=ON -DENABLE_ICONV=ON > "$out.libarchive.log"
    cmake --build "$out/libarchive" --target install >> "$out.libarchive.log"
    # 合成一個靜態庫（libarchive＋liblzma），App 只要連一個。
    libtool -static -o "$out/libarchive-all.a" "$out/prefix/lib/libarchive.a" "$out/prefix/lib/liblzma.a"
    grep -q "HAVE_LZMA_H 1\|HAVE_LIBLZMA 1" "$out/libarchive/build/cmake/config.h" 2>/dev/null \
        || grep -q "HAVE_LZMA" "$out/libarchive/config.h" || echo "⚠ $sdk：沒偵測到 liblzma，7z 會退成 bzip2"
}

build iphoneos
build iphonesimulator

HEADERS="$WORK/headers"
mkdir -p "$HEADERS"
cp "$WORK/iphoneos/prefix/include/archive.h" "$WORK/iphoneos/prefix/include/archive_entry.h" "$HEADERS/"
cat > "$HEADERS/module.modulemap" <<'EOF'
module CArchive {
    header "archive.h"
    header "archive_entry.h"
    link "z"
    link "bz2"
    link "iconv"
    export *
}
EOF

DEST="$REPO/iOS/Vendor/LibArchive"
rm -rf "$DEST"
mkdir -p "$DEST"
xcodebuild -create-xcframework \
    -library "$WORK/iphoneos/libarchive-all.a" -headers "$HEADERS" \
    -library "$WORK/iphonesimulator/libarchive-all.a" -headers "$HEADERS" \
    -output "$DEST/CArchive.xcframework" > /dev/null
mkdir -p "$DEST/LICENSES"
cp "$VENDOR/libarchive/COPYING" "$DEST/LICENSES/libarchive-COPYING"
cp "$VENDOR/xz/COPYING" "$DEST/LICENSES/xz-COPYING"
echo "✔ $DEST/CArchive.xcframework"
