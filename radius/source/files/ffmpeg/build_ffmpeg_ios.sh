#!/bin/bash
# 編 iPhone 版的 FFmpeg（LGPL 2.1 以上）與我們自己寫的介接層 FFTools，做成動態的 xcframework 放到 iOS/Vendor/FFmpeg（不進 git）。
#
# 2026-10-15 改寫（上架前改成全部 LGPL 2.1，docs/APP_STORE_IOS.md 第二節第 1 項）：
#   • 原本用 FFmpegKitNext：它的建置寫死 --enable-version3（FFmpeg 變 LGPL 3），包裝層 ffmpegkit 本身也是 LGPL 3。
#     現在 FFmpeg 直接從官方原始碼編，**不加 --enable-version3、--enable-gpl、--enable-nonfree**，configure 印出的授權一定要是
#     「LGPL version 2.1 or later」，不是就停（下面 check_license）。
#   • 包裝層換成自己寫的 FFTools（iOS/FFTools/）：把 FFmpeg 上游的 fftools（ffmpeg、ffprobe）編成可以在 App 行程裡反覆呼叫的
#     動態 framework，照 FFmpeg 的 LGPL 2.1 以上授權。對 fftools 的修改全在 scripts/patches/fftools-n9.0.1-radius.patch，
#     另外有幾個編譯時的改名（-D，見 build_fftools），都寫在 iOS/FFTools/README.md。
#   • 外部函式庫和原本同一組，而且都相容 LGPL 2.1：LAME（LGPL 2 以上）、Opus（BSD 3）、libvpx（BSD 3）、libwebp（BSD 3），
#     加上 iOS 內建的 zlib、bzip2、iconv、VideoToolbox、AudioToolbox。沒有任何需要 version3 的元件
#     （FFmpeg 的 configure 遇到需要 v3 的函式庫會直接拒絕，這裡也沒開）。
#   • 只編 arm64（實機）與 arm64 模擬器（Apple 晶片的 Mac），最低 iOS 18，和 App 一致。全部是動態 framework（LGPL 要能替換）。
#
# 需要（Homebrew）：brew install pkgconf cmake autoconf automake libtool
# 這台 Mac 只有 8 GB 記憶體：一律 nice、make -j3（JOBS 可改），同一時間只跑一個步驟。
# 原始碼與中間檔放在 $WORK（預設 ~/Developer/radius-vendor/ffmpeg-lgpl；FFmpeg 的 configure 遇到路徑有空白會失敗，專案在「Claude code」底下，所以不放 repo 裡）。
#
# 用法：
#   scripts/build_ffmpeg_ios.sh                 全部（下載 → 兩個平台的相依庫、FFmpeg、FFTools → xcframework → 複製到 iOS/Vendor/FFmpeg）
#   scripts/build_ffmpeg_ios.sh fetch           只下載、驗證校驗碼
#   scripts/build_ffmpeg_ios.sh deps device     LAME、Opus、libvpx、libwebp（device｜sim）
#   scripts/build_ffmpeg_ios.sh ffmpeg device   FFmpeg 的函式庫（device｜sim）
#   scripts/build_ffmpeg_ios.sh fftools device  介接層 FFTools（device｜sim）
#   scripts/build_ffmpeg_ios.sh package         兩個平台都編好之後：做成 xcframework、複製到 iOS/Vendor/FFmpeg
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
WORK="${RADIUS_FFMPEG_WORK:-$HOME/Developer/radius-vendor/ffmpeg-lgpl}"
case "$WORK" in *" "*) echo "✘ 建置資料夾的路徑不能有空白：$WORK"; exit 1;; esac
JOBS="${JOBS:-3}"
MIN_IOS=18.0
NICE=(nice -n 10)

# ── 版本與校驗碼（換版本時一起改；SHA-256 是 2026-10-15 從官方網址下載後算的）──────────────────────────────
FFMPEG_VERSION=9.0.1
FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz
FFMPEG_SHA256=cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635
LAME_URL=https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
LAME_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
OPUS_URL=https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz
OPUS_SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
VPX_URL=https://github.com/webmproject/libvpx/archive/refs/tags/v1.16.0.tar.gz
VPX_FILE=libvpx-1.16.0.tar.gz
VPX_SHA256=7a479a3c66b9f5d5542a4c6a1b7d3768a983b1e5c14c60a9396edc9b649e015c
WEBP_URL=https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz
WEBP_SHA256=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564

DL="$WORK/downloads"
LOGS="$WORK/logs"
FFTOOLS_PATCH="$REPO/scripts/patches/fftools-n$FFMPEG_VERSION-radius.patch"
FFTOOLS_SRC="$REPO/iOS/FFTools"
DEST="$REPO/iOS/Vendor/FFmpeg"
LIBS=(libavutil libswresample libswscale libavcodec libavformat libavfilter libavdevice)
mkdir -p "$DL" "$LOGS"

say() { printf '\n▶ %s\n' "$*"; }
die() { echo "✘ $*" >&2; exit 1; }

fetch_one() {   # 網址 檔名 SHA-256
    local file="$DL/$2"
    [ -f "$file" ] || { say "下載 $2"; curl -sSfL -o "$file.part" "$1" && mv "$file.part" "$file"; }
    echo "$3  $file" | shasum -a 256 -c --status || die "$2 的校驗碼不對（刪掉 $file 重新下載，或確認上游換了檔案）"
}

fetch() {
    fetch_one "$FFMPEG_URL" "ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
    fetch_one "$LAME_URL" lame-3.100.tar.gz "$LAME_SHA256"
    fetch_one "$OPUS_URL" opus-1.5.2.tar.gz "$OPUS_SHA256"
    fetch_one "$VPX_URL" "$VPX_FILE" "$VPX_SHA256"
    fetch_one "$WEBP_URL" libwebp-1.6.0.tar.gz "$WEBP_SHA256"
    echo "✔ 原始碼都在 $DL，校驗碼相符"
}

# 平台：device＝iPhone 實機、sim＝Apple 晶片 Mac 上的模擬器。設好 SDK、編譯目標、資料夾，並產生 clang 的包裝。
platform() {
    PLAT="$1"
    case "$PLAT" in
        device) SDK=iphoneos;        TARGET="arm64-apple-ios$MIN_IOS";           FW_PLATFORM=iPhoneOS ;;
        sim)    SDK=iphonesimulator; TARGET="arm64-apple-ios$MIN_IOS-simulator"; FW_PLATFORM=iPhoneSimulator ;;
        *) die "平台只能是 device 或 sim：$PLAT" ;;
    esac
    SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
    B="$WORK/build/$PLAT"
    PREFIX="$B/prefix"
    TC="$B/toolchain"
    mkdir -p "$B/src" "$PREFIX" "$TC"
    # 各套件的建置系統會自己加 -isysroot、-miphoneos-version-min（libvpx 的 iOS 目標寫死 7.0、模擬器根本沒有 arm64 目標）。
    # 包裝把那些拿掉，一律換成這個平台的 -target 與 SDK，四個相依庫與 FFmpeg 就都用同一組參數編。
    local clang; clang="$(xcrun -f clang)"
    for tool in cc:"$clang" cxx:"$(xcrun -f clang++)"; do
        cat > "$TC/${tool%%:*}" <<EOF
#!/bin/bash
args=(); skip=0
for a in "\$@"; do
  if [ \$skip = 1 ]; then skip=0; continue; fi
  case "\$a" in
    -isysroot) skip=1 ;;
    -isysroot*|-miphoneos-version-min=*|-mios-version-min=*|-mmacosx-version-min=*|-mios-simulator-version-min=*) ;;
    *) args+=("\$a") ;;
  esac
done
exec "${tool#*:}" -target $TARGET -isysroot $SYSROOT "\${args[@]}"
EOF
        chmod +x "$TC/${tool%%:*}"
    done
    export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" PKG_CONFIG_PATH=""
}

fresh_src() {   # 壓縮檔 → 解到 $B/src/<資料夾>（每次重解，不沿用上次編過的）
    local archive="$DL/$1" dir="$B/src/$2"
    rm -rf "${dir:?}"
    tar xf "$archive" -C "$B/src"
    [ -d "$dir" ] || die "解開 $1 之後找不到 $dir"
    echo "$dir"
}

autotools_env() { export CC="$TC/cc" CXX="$TC/cxx" AR="$(xcrun -f ar)" RANLIB="$(xcrun -f ranlib)" CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC"; }

build_lame() {
    say "LAME 3.100（$PLAT）"
    local s; s="$(fresh_src lame-3.100.tar.gz lame-3.100)"
    ( cd "$s" && autotools_env &&
      # lame 只當 FFmpeg 的 MP3 編碼器：不要命令列程式、不要解碼器（FFmpeg 自己會解 MP3）。
      ./configure --host=aarch64-apple-darwin --prefix="$PREFIX" --disable-shared --enable-static \
          --disable-frontend --disable-decoder --disable-gtktest &&
      "${NICE[@]}" make -j"$JOBS" && make install )
}

build_opus() {
    say "Opus 1.5.2（$PLAT）"
    local s; s="$(fresh_src opus-1.5.2.tar.gz opus-1.5.2)"
    ( cd "$s" && autotools_env &&
      ./configure --host=aarch64-apple-darwin --prefix="$PREFIX" --disable-shared --enable-static --with-pic \
          --disable-doc --disable-extra-programs &&
      "${NICE[@]}" make -j"$JOBS" && make install )
}

build_vpx() {
    say "libvpx 1.16.0（$PLAT）"
    local s; s="$(fresh_src "$VPX_FILE" libvpx-1.16.0)"
    # libvpx 的 iOS 目標（arm64-darwin-gcc）用 xcrun 找 iphoneos 的 clang；編譯時把 CC 換成包裝，模擬器也能用同一個目標。
    # arm64 只用 NEON 內建函式（沒有組合語言檔），執行時偵測 dotprod／i8mm。
    ( cd "$s" && "./configure" --target=arm64-darwin-gcc --prefix="$PREFIX" --enable-static --disable-shared --enable-pic \
          --disable-examples --disable-tools --disable-docs --disable-unit-tests --enable-vp8 --enable-vp9 &&
      "${NICE[@]}" make -j"$JOBS" CC="$TC/cc" CXX="$TC/cxx" LD="$TC/cxx" AR="$(xcrun -f ar)" &&
      make install CC="$TC/cc" CXX="$TC/cxx" LD="$TC/cxx" AR="$(xcrun -f ar)" )
}

build_webp() {
    say "libwebp 1.6.0（$PLAT）"
    local s; s="$(fresh_src libwebp-1.6.0.tar.gz libwebp-1.6.0)"
    # 只要函式庫（libwebp、libwebpmux、libsharpyuv），不要 cwebp 等工具：工具才需要 libpng、libjpeg、giflib、libtiff。
    ( mkdir -p "$s/radius-build" && cd "$s/radius-build" &&
      cmake .. -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$SYSROOT" -DCMAKE_OSX_ARCHITECTURES=arm64 \
          -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" -DCMAKE_C_COMPILER="$TC/cc" -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
          -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF \
          -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
          -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_LIBWEBPMUX=ON -DWEBP_USE_THREAD=ON &&
      "${NICE[@]}" cmake --build . -j "$JOBS" && cmake --install . )
}

deps() {
    platform "$1"
    build_lame > "$LOGS/lame-$PLAT.log" 2>&1 || die "LAME 失敗（$LOGS/lame-$PLAT.log）"
    build_opus > "$LOGS/opus-$PLAT.log" 2>&1 || die "Opus 失敗（$LOGS/opus-$PLAT.log）"
    build_vpx > "$LOGS/libvpx-$PLAT.log" 2>&1 || die "libvpx 失敗（$LOGS/libvpx-$PLAT.log）"
    build_webp > "$LOGS/libwebp-$PLAT.log" 2>&1 || die "libwebp 失敗（$LOGS/libwebp-$PLAT.log）"
    for lib in libmp3lame.a libopus.a libvpx.a libwebp.a libwebpmux.a libsharpyuv.a; do
        [ -f "$PREFIX/lib/$lib" ] || die "沒有 $PREFIX/lib/$lib"
        lipo -info "$PREFIX/lib/$lib" | grep -q arm64 || die "$lib 不是 arm64"
    done
    echo "✔ 相依庫（$PLAT）：$(ls "$PREFIX"/lib/*.a | xargs -n1 basename | tr '\n' ' ')"
}

# configure 的「License:」那一行必須是 LGPL 2.1 以上。是 3（或 GPL、nonfree）就停：這份不能上架。
check_license() {
    local log="$1" config_h="$2"
    local line; line="$(grep -E '^License: ' "$log" || true)"
    echo "$line"
    [ "$line" = "License: LGPL version 2.1 or later" ] || die "授權不是 LGPL 2.1 以上：「$line」（$log）"
    grep -q '#define FFMPEG_LICENSE "LGPL version 2.1 or later"' "$config_h" || die "config.h 的 FFMPEG_LICENSE 不是 LGPL 2.1 以上"
    grep -Eq '^#define CONFIG_(GPL|VERSION3|NONFREE) 1' "$config_h" && die "config.h 開了 GPL／version3／nonfree" || true
}

build_ffmpeg() {
    platform "$1"
    local src="$B/src/ffmpeg-$FFMPEG_VERSION" bld="$B/ffmpeg-build"
    rm -rf "${src:?}" "${bld:?}"
    tar xf "$DL/ffmpeg-$FFMPEG_VERSION.tar.xz" -C "$B/src"
    mkdir -p "$bld"
    say "FFmpeg $FFMPEG_VERSION configure（$PLAT）"
    # 授權：只有 LGPL 2.1（明寫 --disable-version3 等三項）。其餘照原本 FFmpegKitNext 那份的功能：只開明列的外部函式庫
    # （--disable-autodetect）、--enable-small、不要程式（fftools 由 build_fftools 另外編成 FFTools.framework）。
    # -liconv：iOS 的 iconv 不在 libSystem 裡；9.0.1 的 configure 在 --disable-autodetect 時只試 libc 的 iconv、試不到也不會改加 -liconv，
    # 結果 libavcodec 連結時找不到 _iconv（字幕轉碼用）。系統的 libiconv 是 iOS 內建的系統函式庫。
    # -headerpad_max_install_names：做成 framework 時要把 install name 改長（@rpath/libavdevice.framework/libavdevice），
    # 沒有預留空間 install_name_tool 會失敗（模擬器版的 libavdevice 就踩到）。
    ( cd "$bld" && "$src/configure" \
        --prefix="$PREFIX" --enable-cross-compile --target-os=darwin --arch=aarch64 \
        --cc="$TC/cc" --cxx="$TC/cxx" --ar="$(xcrun -f ar)" --ranlib="$(xcrun -f ranlib)" --nm="$(xcrun -f nm)" --strip="$(xcrun -f strip)" \
        --pkg-config="$(command -v pkg-config)" --pkg-config-flags=--static \
        --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib -Wl,-headerpad_max_install_names" --extra-libs=-liconv \
        --disable-gpl --disable-version3 --disable-nonfree \
        --enable-shared --disable-static --enable-pic --install-name-dir=@rpath \
        --disable-autodetect --disable-programs --disable-doc --disable-debug --enable-small --enable-pthreads \
        --disable-xmm-clobber-test --disable-neon-clobber-test \
        --enable-libmp3lame --enable-libopus --enable-libvpx --enable-libwebp \
        --enable-zlib --enable-bzlib --enable-iconv --enable-videotoolbox --enable-audiotoolbox \
        --disable-outdev=audiotoolbox --disable-filter=scale_vt --disable-avfoundation --disable-coreimage --disable-appkit \
        --disable-securetransport ) > "$LOGS/ffmpeg-configure-$PLAT.log" 2>&1 || die "configure 失敗（$LOGS/ffmpeg-configure-$PLAT.log，細節在 $bld/ffbuild/config.log）"
    check_license "$LOGS/ffmpeg-configure-$PLAT.log" "$bld/config.h"
    say "FFmpeg $FFMPEG_VERSION make（$PLAT，-j$JOBS）"
    ( cd "$bld" && "${NICE[@]}" make -j"$JOBS" && make install ) > "$LOGS/ffmpeg-make-$PLAT.log" 2>&1 || die "make 失敗（$LOGS/ffmpeg-make-$PLAT.log）"
    for lib in "${LIBS[@]}"; do ls "$PREFIX/lib/$lib".*.dylib >/dev/null 2>&1 || die "沒有 $lib 的 dylib"; done
    echo "✔ FFmpeg（$PLAT）：$(ls "$PREFIX"/lib/lib{av,sw}*.[0-9]*.dylib | xargs -n1 basename | tr '\n' ' ')"
}

# 介接層：上游 fftools（ffmpeg、ffprobe 與共用的 cmdutils、opt_common、textformat…）套上我們的修補，
# 加上 iOS/FFTools 的 fft_bridge.c，連成 FFTools.framework（動態，依賴上面的 FFmpeg 函式庫）。
build_fftools() {
    platform "$1"
    local src="$B/src/ffmpeg-$FFMPEG_VERSION" bld="$B/ffmpeg-build" obj="$B/fftools-obj" fsrc="$B/fftools-src"
    [ -f "$bld/config.h" ] || die "先編 FFmpeg：$0 ffmpeg $PLAT"
    rm -rf "${obj:?}" "${fsrc:?}"
    mkdir -p "$obj" "$fsrc"
    # 上游 fftools 的副本＋我們的修補（修補只動 fftools，FFmpeg 的函式庫一行都沒改）。
    cp -R "$src/fftools" "$fsrc/"
    ( cd "$fsrc" && patch -p1 --no-backup-if-mismatch < "$FFTOOLS_PATCH" ) > "$LOGS/fftools-patch-$PLAT.log" 2>&1 || die "修補套不上（$LOGS/fftools-patch-$PLAT.log）"
    # 編譯參數照 FFmpeg 自己編 fftools 的那一套（make -n 印出來的），只換來源檔與輸出位置。
    local cmd; cmd="$(cd "$bld" && make -n -B fftools/cmdutils.o 2>/dev/null | grep -E -- '-c -o fftools/cmdutils.o' | tail -1)"
    [ -n "$cmd" ] || die "拿不到 fftools 的編譯參數（make -n fftools/cmdutils.o）"
    cmd="${cmd#*; }"   # 前面是 Makefile 印「CC 檔名」的 printf
    local flags; flags="$(printf '%s' "$cmd" | sed -E 's/ +-MMD -MF [^ ]+ -MT [^ ]+//; s/ +-c -o fftools\/cmdutils\.o .*$//')"
    case "$flags" in "$TC/cc "*) ;; *) die "fftools 的編譯參數看起來不對：$flags";; esac
    echo "$flags" > "$LOGS/fftools-cflags-$PLAT.txt"
    # graph／resources（-print_graphs 的 HTML 樣板）由 FFmpeg 的 Makefile 產生（bin2c），直接拿它編好的。
    ( cd "$bld" && mkdir -p fftools/resources && "${NICE[@]}" make fftools/resources/graph.html.o fftools/resources/graph.css.o ) \
        > "$LOGS/fftools-resources-$PLAT.log" 2>&1 || die "resources 失敗（$LOGS/fftools-resources-$PLAT.log）"
    cp "$bld/fftools/resources/graph.html.o" "$bld/fftools/resources/graph.css.o" "$obj/"
    say "FFTools 編譯（$PLAT）"
    local sources=(cmdutils opt_common ffmpeg ffmpeg_dec ffmpeg_demux ffmpeg_enc ffmpeg_filter ffmpeg_hw ffmpeg_mux ffmpeg_mux_init
                   ffmpeg_opt ffmpeg_sched sync_queue thread_queue ffprobe graph/graphprint resources/resman
                   textformat/avtextformat textformat/tf_compact textformat/tf_default textformat/tf_flat textformat/tf_ini
                   textformat/tf_json textformat/tf_mermaid textformat/tf_xml textformat/tw_avio textformat/tw_buffer textformat/tw_stdout)
    local f extra
    for f in "${sources[@]}"; do
        # ffmpeg 與 ffprobe 原本是兩支程式，各有 main、program_name 等同名符號：編進同一個 framework 要改名（只改名，行為不變）。
        case "$f" in
            ffmpeg) extra="-Dmain=fft_ffmpeg_main" ;;
            ffprobe) extra="-Dmain=fft_ffprobe_main -Dprogram_name=fft_ffprobe_program_name -Dprogram_birth_year=fft_ffprobe_program_birth_year -Dshow_help_default=fft_ffprobe_show_help_default" ;;
            *) extra="" ;;
        esac
        # fft_compat.h：把 fftools 的標準輸出、標準錯誤與寫到 pipe:1 的輸出接到這一次執行（每個檔案最先引入，見該檔說明）。
        # shellcheck disable=SC2086
        ( cd "$bld" && "${NICE[@]}" $flags -I"$fsrc" -I"$FFTOOLS_SRC" -include "$FFTOOLS_SRC/fft_compat.h" $extra \
              -c -o "$obj/$(echo "$f" | tr / _).o" "$fsrc/fftools/$f.c" ) >> "$LOGS/fftools-cc-$PLAT.log" 2>&1 \
            || die "編 $f.c 失敗（$LOGS/fftools-cc-$PLAT.log）"
    done
    # shellcheck disable=SC2086
    ( cd "$bld" && $flags -I"$FFTOOLS_SRC" -c -o "$obj/fft_bridge.o" "$FFTOOLS_SRC/fft_bridge.c" ) >> "$LOGS/fftools-cc-$PLAT.log" 2>&1 \
        || die "編 fft_bridge.c 失敗（$LOGS/fftools-cc-$PLAT.log）"
    say "FFTools 連結（$PLAT）"
    mkdir -p "$B/fftools-dylib"
    # 只匯出 FFTools.h 的介面：fftools 的 main、options 等全域符號不外露（和 App 裡的符號不會撞名）。
    printf '_%s\n' fft_start fft_cancel fft_run fft_list_codecs fft_get_stats > "$B/fftools-exports.txt"
    "$TC/cc" -dynamiclib -o "$B/fftools-dylib/FFTools" "$obj"/*.o \
        -install_name @rpath/FFTools.framework/FFTools -compatibility_version 1.0 -current_version 1.0 -Wl,-headerpad_max_install_names \
        -exported_symbols_list "$B/fftools-exports.txt" -dead_strip \
        -L"$PREFIX/lib" -lavdevice -lavfilter -lavformat -lavcodec -lswresample -lswscale -lavutil -lz \
        > "$LOGS/fftools-link-$PLAT.log" 2>&1 || die "連結失敗（$LOGS/fftools-link-$PLAT.log）"
    echo "✔ FFTools（$PLAT）：$(du -h "$B/fftools-dylib/FFTools" | cut -f1)"
}

# 一個 dylib → framework：改 install name、把對其他 FFmpeg 函式庫的依賴改指到 framework、附 Info.plist 與授權檔。
make_framework() {   # 名稱 來源dylib 版本 輸出資料夾
    local name="$1" dylib="$2" version="$3" out="$4/$1.framework"
    rm -rf "${out:?}"; mkdir -p "$out"
    cp "$dylib" "$out/$name"
    install_name_tool -id "@rpath/$name.framework/$name" "$out/$name"
    local dep
    for dep in $(otool -L "$out/$name" | awk 'NR>1 {print $1}' | grep '^@rpath/lib.*\.dylib$' || true); do
        local base; base="$(basename "$dep")"; base="${base%%.*}"
        install_name_tool -change "$dep" "@rpath/$base.framework/$base" "$out/$name"
    done
    /usr/libexec/PlistBuddy -c "Clear dict" "$out/Info.plist" >/dev/null 2>&1 || true
    plutil -create xml1 "$out/Info.plist"
    local key value
    while IFS='=' read -r key value; do
        plutil -insert "$key" -string "$value" "$out/Info.plist"
    done <<EOF
CFBundleDevelopmentRegion=en
CFBundleExecutable=$name
CFBundleIdentifier=com.jeremyl861225.radius.ffmpeg.$(echo "$name" | tr -cd 'A-Za-z0-9')
CFBundleInfoDictionaryVersion=6.0
CFBundleName=$name
CFBundlePackageType=FMWK
CFBundleShortVersionString=$version
CFBundleVersion=$version
MinimumOSVersion=$MIN_IOS
EOF
    plutil -insert CFBundleSupportedPlatforms -array "$out/Info.plist"
    plutil -insert CFBundleSupportedPlatforms -string "$FW_PLATFORM" -append "$out/Info.plist"
    # 修改過 install name 的簽章失效：重新做臨時簽章（Xcode 嵌進 App 時會用開發者的憑證重簽）。
    codesign --force --sign - "$out/$name" >/dev/null 2>&1
}

frameworks() {
    platform "$1"
    local out="$B/frameworks" src="$B/src/ffmpeg-$FFMPEG_VERSION"
    rm -rf "${out:?}"; mkdir -p "$out"
    local lib dylib version
    for lib in "${LIBS[@]}"; do
        dylib="$(ls "$PREFIX/lib/$lib".*.*.*.dylib | head -1)"
        version="$(basename "$dylib" .dylib)"; version="${version#"$lib".}"
        make_framework "$lib" "$dylib" "$version" "$out"
        # FFmpeg 本身：LGPL 2.1 全文（configure 確認過授權是 LGPL 2.1 以上）。
        cp "$src/COPYING.LGPLv2.1" "$out/$lib.framework/LICENSE"
    done
    # 靜態連進 libavcodec 的編碼器：各自的授權全文（「關於」頁讀 Frameworks/libavcodec.framework/LICENSE.*）。
    cp "$B/src/lame-3.100/COPYING" "$out/libavcodec.framework/LICENSE.LAME"
    cp "$B/src/opus-1.5.2/COPYING" "$out/libavcodec.framework/LICENSE.OPUS"
    { cat "$B/src/libvpx-1.16.0/LICENSE"; printf '\n\n'; cat "$B/src/libvpx-1.16.0/PATENTS"; } > "$out/libavcodec.framework/LICENSE.LIBVPX"
    { cat "$B/src/libwebp-1.6.0/COPYING"; printf '\n\n'; cat "$B/src/libwebp-1.6.0/PATENTS"; } > "$out/libavcodec.framework/LICENSE.LIBWEBP"
    make_framework FFTools "$B/fftools-dylib/FFTools" 1.0 "$out"
    cp "$src/COPYING.LGPLv2.1" "$out/FFTools.framework/LICENSE"
    mkdir -p "$out/FFTools.framework/Headers" "$out/FFTools.framework/Modules"
    cp "$FFTOOLS_SRC/FFTools.h" "$out/FFTools.framework/Headers/"
    cp "$FFTOOLS_SRC/module.modulemap" "$out/FFTools.framework/Modules/"
    codesign --force --sign - "$out/FFTools.framework/FFTools" >/dev/null 2>&1
    # 依賴檢查：只能連到系統的東西或彼此（@rpath/*.framework），不能有建置資料夾的路徑。
    local fw
    for fw in "$out"/*.framework; do
        local bin; bin="$fw/$(basename "$fw" .framework)"
        if otool -L "$bin" | awk 'NR>1 {print $1}' | grep -Ev '^(/usr/lib/|/System/Library/|@rpath/[A-Za-z]+\.framework/)'; then
            die "$bin 有不該有的依賴（見上）"
        fi
    done
    echo "✔ framework（$PLAT）：$(ls "$out" | tr '\n' ' ')"
}

package() {
    local out="$WORK/out"
    rm -rf "${out:?}"; mkdir -p "$out"
    local name
    for name in "${LIBS[@]}" FFTools; do
        xcodebuild -create-xcframework \
            -framework "$WORK/build/device/frameworks/$name.framework" \
            -framework "$WORK/build/sim/frameworks/$name.framework" \
            -output "$out/$name.xcframework" > "$LOGS/xcframework-$name.log" 2>&1 || die "$name.xcframework 失敗（$LOGS/xcframework-$name.log）"
    done
    cat > "$out/Package.swift" <<'EOF'
// swift-tools-version:5.7
// 由 scripts/build_ffmpeg_ios.sh 產生（不進 git）：FFmpeg（LGPL 2.1 以上）的函式庫與介接層 FFTools，全部是動態 framework。
import PackageDescription

let package = Package(
    name: "FFmpeg",
    platforms: [.iOS("18.0")],
    products: [
        .library(name: "FFmpeg", targets: ["FFTools", "libavcodec", "libavdevice", "libavfilter", "libavformat", "libavutil", "libswresample", "libswscale"]),
    ],
    targets: [
        .binaryTarget(name: "FFTools", path: "FFTools.xcframework"),
        .binaryTarget(name: "libavcodec", path: "libavcodec.xcframework"),
        .binaryTarget(name: "libavdevice", path: "libavdevice.xcframework"),
        .binaryTarget(name: "libavfilter", path: "libavfilter.xcframework"),
        .binaryTarget(name: "libavformat", path: "libavformat.xcframework"),
        .binaryTarget(name: "libavutil", path: "libavutil.xcframework"),
        .binaryTarget(name: "libswresample", path: "libswresample.xcframework"),
        .binaryTarget(name: "libswscale", path: "libswscale.xcframework"),
    ]
)
EOF
    # 建置資訊（給原始碼頁與日後查證）：授權行、完整 configure 參數、各元件版本與校驗碼。
    {
        echo "FFmpeg $FFMPEG_VERSION（$FFMPEG_URL，SHA-256 $FFMPEG_SHA256）"
        grep -E '^License: ' "$LOGS/ffmpeg-configure-device.log"
        echo "configure（實機）：$(grep -E '^#define FFMPEG_CONFIGURATION' "$WORK/build/device/ffmpeg-build/config.h" | sed -E 's/^#define FFMPEG_CONFIGURATION "(.*)"$/\1/' | sed "s#$WORK#\$WORK#g")"
        echo "LAME 3.100（$LAME_URL，$LAME_SHA256）"
        echo "Opus 1.5.2（$OPUS_URL，$OPUS_SHA256）"
        echo "libvpx 1.16.0（$VPX_URL，$VPX_SHA256）"
        echo "libwebp 1.6.0（$WEBP_URL，$WEBP_SHA256）"
        echo "fftools 修補：scripts/patches/$(basename "$FFTOOLS_PATCH")（SHA-256 $(shasum -a 256 "$FFTOOLS_PATCH" | cut -d' ' -f1)）"
        echo "介接層：iOS/FFTools（$(cd "$FFTOOLS_SRC" && ls | tr '\n' ' ')）"
    } > "$out/BUILD-INFO.txt"
    rm -rf "${DEST:?}"; mkdir -p "$DEST"
    cp -R "$out"/. "$DEST"/
    echo "✔ 已複製到 $DEST"
    ls "$DEST"
}

step="${1:-all}"
case "$step" in
    fetch) fetch ;;
    deps) fetch; deps "${2:?device 或 sim}" ;;
    ffmpeg) fetch; build_ffmpeg "${2:?device 或 sim}" ;;
    fftools) build_fftools "${2:?device 或 sim}"; frameworks "$2" ;;
    package) package ;;
    all)
        fetch
        for p in device sim; do deps "$p"; build_ffmpeg "$p"; build_fftools "$p"; frameworks "$p"; done
        package ;;
    *) die "不認得的步驟：$step（all｜fetch｜deps｜ffmpeg｜fftools｜package）" ;;
esac
