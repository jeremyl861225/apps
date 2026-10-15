#!/bin/bash
# 編 iPhone 版的 LibreOffice（Word／簡報 → PDF、舊版 .doc 轉文字），給 App 靜態連結。第四階段，可行性試驗中。
#
# 為什麼這樣編（2026-10-07 實測）：
#   • 上游的 iOS 文件幾乎是空的（ios/README.md 只有標題），distro-configs/LibreOfficeiOS.conf 只給實機（--host=arm64-apple-ios）。
#   • 模擬器在上游是壞的：iOS 分支直接拒絕 arm64＋--enable-ios-simulator、第三方庫被硬設成 x86_64（Intel Mac 時代的遺留）。
#     patches/libreoffice-ios.patch 讓 Apple 晶片的 arm64 模擬器照實機的方式編，只換成 iPhoneSimulator SDK。
#   • 最低 iOS 要從 14.5 拉到 18.0：iOS 27 SDK 的 libc++ 已不支援 14.5（「The selected platform is no longer supported by libc++」）。
#   • curl：iOS 的 distro 關掉 OpenSSL，上游只給 --with-apple-sectrust（那只是附在 TLS 後端上的憑證驗證，curl 8.15 起拿掉了 Secure Transport），
#     configure 就報「沒選 TLS 後端」。我們只做離線轉檔用不到網路：沒有 OpenSSL 時改給 --without-ssl（同一份 patch）。
#   • expat：新版把亂數來源拆成檔案，上游只讓 macOS／WebAssembly 走 getentropy，iOS 掉到 Linux 的 getrandom 系統呼叫而編不過；
#     iOS SDK 沒有公開的 getentropy（沒有 <sys/random.h>），改走 arc4random_buf（iOS 4.3 起就有）。上游的 iOS 建置顯然沒在測，後面可能還有。
#   • vcl 的 iOS 專用程式落後共用程式的改版（5 處）：getBitmap 多了 bWithoutAlpha、SetSize 多了 bAlphaMaskTransparent、
#     ShowNativeMessageBox 改成 void、salgdi.h 少了 SalVirtualDevice 的前置宣告（macOS 剛好別的標頭先宣告了）。
#   • Skia：上游把 macOS 的 Skia 改成必要（沒有就 static_assert），但 iOS 版不編 Skia；iOS 改用 CoreGraphics 那套
#     （macOS 列印時仍在用的 AquaGraphicsBackend）。desktop/lib/init.cxx 的 iOS 路徑 PaintToDevice 改傳參考。
#   • 一次修一個錯很慢：之後用 `make -k` 一次收集所有編譯錯誤（第一次 -k 全樹只剩 3 個錯）。
#   • 連結（App 那邊）：bin/lo-all-static-libs 產生的靜態庫清單漏了 NSS 新加的 AArch64 AES-GCM 組語（在 freebl 的
#     aarch64-gcm-slothy 子資料夾），同一份 patch 補上；NSS 的憑證資料庫要 sqlite3，App 連結時加 -lsqlite3（iOS 內建）。
#   • 編好的東西不搬進 repo：App 直接用 workdir/CustomTarget/ios 裡的 native-code.h、ios-all-static-libs.list（381 個、約 660 MB）
#     與 resources（約 140 MB，建置時複製到 App bundle 的根目錄），路徑寫在 iOS/project.yml 的 LO_SRC／LO_BUILD。
#   • 很吃 CPU（make -j8 要好幾個小時）：編的時候電腦其他工作會變很慢（2026-10-07 害 Mac 版的文字辨識第一次準備模型拖到 5 分鐘）。
#     用 nice -n 15：照樣用全部核心，但別的程式（含系統服務）要用時會讓出來。
#     不要用 taskpolicy -b：那會被限制在省電核心，實機版編了 9 個小時才過半；改 nice 15 後剩下的四成約 1.5 小時編完。
#   • 中途停掉之後要續編：在建置資料夾直接跑 make（環境變數照下面），不要重跑整支指令稿（會重跑 autogen）。
#   • pkg-config（harfbuzz 要）：configure 只認 Homebrew 標準位置的 /opt/homebrew/bin/pkg-config（其他位置一律判「來路不明」），
#     PATH 不能整個放 /opt/homebrew/bin（會先找到 pkgconf 而被擋），所以用環境變數指定；模擬器端清空搜尋路徑，免得抓到 Homebrew 的函式庫。
#     Mac 端（編建置工具用的那一半）會先 unset PKG_CONFIG 和搜尋路徑，只認 PKG_CONFIG_FOR_BUILD。
#   • 第三方原始碼約 100 個、600 MB，官方站一條連線只有約 90 KB/s：先用 `make -n fetch` 列出網址、8 條並行下載到 --with-external-tar。
#   • 要 GNU make 4.2 以上、gperf 3.1 以上（系統的是 3.81、3.0.3），bison 用 Homebrew 的，ninja（harfbuzz 的 meson 要）。
#   • 路徑不能有空白。
#
# 需要：brew install make gperf bison flex autoconf automake ninja pkgconf
# 原始碼：git clone --depth 1 --branch libreoffice-26.8.1.1 https://github.com/LibreOffice/core.git ~/Developer/radius-vendor/libreoffice-core
#         cd ~/Developer/radius-vendor/libreoffice-core && git apply <repo>/scripts/patches/libreoffice-ios.patch
#
# 用法：scripts/build_libreoffice_ios.sh simulator|device
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${1:?用法：scripts/build_libreoffice_ios.sh simulator|device}"
VENDOR="${VENDOR_DIR:-$HOME/Developer/radius-vendor}"
SRC="$VENDOR/libreoffice-core"
BUILD="$VENDOR/lo-build-$([ "$TARGET" = simulator ] && echo sim || echo device)"
case "$VENDOR" in *" "*) echo "✘ 路徑不能有空白：$VENDOR"; exit 1;; esac
[ -x "$SRC/autogen.sh" ] || { echo "✘ 找不到 $SRC（見檔頭）"; exit 1; }
git -C "$SRC" apply --check "$PWD/scripts/patches/libreoffice-ios.patch" 2>/dev/null && git -C "$SRC" apply "$PWD/scripts/patches/libreoffice-ios.patch" || true

B=/opt/homebrew/opt
export PATH="$B/make/libexec/gnubin:$B/bison/bin:$B/gperf/bin:$B/autoconf/bin:$B/automake/bin:$B/flex/bin:$B/ninja/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG=/opt/homebrew/bin/pkg-config PKG_CONFIG_FOR_BUILD=/opt/homebrew/bin/pkg-config PKG_CONFIG_LIBDIR=/var/empty PKG_CONFIG_PATH=
mkdir -p "$BUILD" "$VENDOR/lo-tarballs"
cd "$BUILD"
"$SRC/autogen.sh" --with-distro=LibreOfficeiOS $([ "$TARGET" = simulator ] && echo --enable-ios-simulator) \
    --with-external-tar="$VENDOR/lo-tarballs"
# 並行先把第三方原始碼抓好（make 自己是一個一個抓，很慢）。
# 全都下載過時 grep 找不到網址會回傳 1，pipefail 會讓整支指令稿停在這裡：吞掉。
make -n fetch 2>/dev/null | { grep -o "https://dev-www.libreoffice.org/src/[^ '\"]*" || true; } | sort -u | while read -r url; do
    [ -s "$VENDOR/lo-tarballs/$(basename "$url")" ] || echo "$url"
done | (cd "$VENDOR/lo-tarballs" && xargs -P 8 -n 1 sh -c 'f=$(basename "$0"); curl -f -L -sS --retry 3 -o "$f.part" "$0" && mv "$f.part" "$f"')
nice -n 15 make
