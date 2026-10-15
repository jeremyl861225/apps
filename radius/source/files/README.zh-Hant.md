# Radius 1.0（iPhone）：LGPL 與 MPL 元件的原始碼

這個資料夾屬於 **Radius 1.0（iPhone）**（套件識別碼 `com.jeremyl861225.radius`，版本 1.0，建置號 1），由個人開發者製作。
Radius 本身不是開放原始碼軟體；下面的授權只適用於這裡列出的元件。同樣的說明（9 種語言）在
https://jeremyl861225.github.io/apps/radius/source/ （English: `README.md`）。

聯絡：lins.program@gmail.com

## 檔案

| 路徑 | 是什麼 | 授權 |
|---|---|---|
| `ffmpeg/ffmpeg-9.0.1.tar.xz`（＋`.asc`） | FFmpeg 9.0.1：ffmpeg.org 的官方壓縮檔與簽章，未修改 | LGPL 2.1 以上 |
| `ffmpeg/radius-fftools-1.0.tar.xz` | 我們的介接層 FFTools、對 FFmpeg `fftools/` 的修補、建置腳本與建置資訊（說明見裡面的 `README.md`） | LGPL 2.1 以上 |
| `ffmpeg/fftools-n9.0.1-radius.patch`、`build_ffmpeg_ios.sh`、`BUILD-INFO.txt` | 同上的修補、腳本與建置資訊，單獨放一份方便直接看 | LGPL 2.1 以上 |
| `ffmpeg/lame-3.100.tar.gz` | LAME 3.100 官方壓縮檔，未修改（只編編碼器，連進 libavcodec） | LGPL 2.0 以上 |
| `ffmpeg/opus-1.5.2.tar.gz`、`libvpx-1.16.0.tar.gz`、`libwebp-1.6.0.tar.gz` | 官方壓縮檔，未修改（連進 libavcodec） | BSD 3-Clause |
| `libreoffice/libreoffice-26.8.1.1-radius-ios.patch` | 我們對 LibreOffice 26.8.1.1 的修改（13 個檔） | MPL 2.0 |
| `libreoffice/build_libreoffice_ios.sh` | 我們怎麼編 iOS 版的 LibreOffice | MPL 2.0 |
| `libreoffice/libreoffice-external-tarballs.tsv` | LibreOffice 建置時下載的第三方原始碼壓縮檔（檔名、大小、SHA-256、網址），未修改 | （各自的授權） |
| `libreoffice/libreoffice-externals-unpacked-ios-device.txt` | 實機版實際解開用到的是哪幾個 | |
| `other/` | libarchive／liblzma 與 Office 引擎中日韓字型的建置腳本 | （BSD 類；備查） |
| `licenses/` | App 裡每個第三方元件的授權全文（和 App 附的檔案相同） | |
| `SHA256SUMS` | 這裡每個檔案的 SHA-256（`shasum -a 256 -c SHA256SUMS`） | |

## FFmpeg（LGPL 2.1 以上）

- **FFmpeg 9.0.1**：官方壓縮檔，以 `--disable-gpl --disable-version3 --disable-nonfree` 編譯，`configure` 顯示「LGPL version 2.1 or later」。
  FFmpeg 的函式庫**沒有修改**，以 7 個動態 framework 附在 App 裡（libavcodec、libavdevice、libavfilter、libavformat、libavutil、libswresample、libswscale）。
  完整的 `configure` 參數在 `BUILD-INFO.txt`。
- **FFTools 1.0**（我們的程式，LGPL 2.1 以上）：把 FFmpeg 自己的 `fftools`（`ffmpeg`、`ffprobe`）編成 App 在自己的行程裡呼叫的動態 framework，
  修改了 3 個檔（`fftools-n9.0.1-radius.patch`）。Radius 1.0 發行前就以它取代了 FFmpegKit，App 裡沒有 FFmpegKit 的程式碼。
- **靜態連進 libavcodec**（都未修改）：LAME 3.100（LGPL 2.0 以上）、Opus 1.5.2、libvpx 1.16.0、libwebp 1.6.0（BSD 3-Clause）。
  iOS 內建：zlib、bzip2、iconv、VideoToolbox、AudioToolbox。

**怎麼重編、怎麼換掉 App 裡的 framework**：見 `ffmpeg/radius-fftools-1.0.tar.xz` 裡的 `README.md`（網頁上也有同樣的說明）。
簡單說：`scripts/build_ffmpeg_ios.sh` 編出全部 8 個 framework；App 裡它們是 `RadiusPhone.app/Frameworks/<名稱>.framework/<名稱>`，
透過 `@rpath` 載入；換掉之後用你自己的憑證重新簽 App。

## 以 LibreOffice 為基礎的 Office 引擎（MPL 2.0）

- **LibreOffice 26.8.1.1**：標籤 `libreoffice-26.8.1.1`，commit `bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1`
  （https://git.libreoffice.org/core ，GitHub 鏡像 https://github.com/LibreOffice/core ）。靜態連結進 App，只用來把 Word、Excel、簡報檔轉成 PDF。
- **我們的修改**（`libreoffice-26.8.1.1-radius-ios.patch`，13 個檔）：Apple 晶片的 arm64 模擬器、最低 iOS 18、curl 不帶 TLS、
  expat 在 iOS 的亂數來源、vcl 的 iOS 專用修正、靜態庫清單。
- 靜態連結、可以選授權的第三方元件（例如 librevenge、libwpd、libwps、libmwaw、libodfgen、liblangtag、Hunspell、Hyphen、Graphite、Redland），
  一律選用 MPL 或 Apache 2.0。
- 重編：`brew install make gperf bison flex autoconf automake ninja pkgconf`，然後

```sh
git clone --depth 1 --branch libreoffice-26.8.1.1 https://github.com/LibreOffice/core.git ~/Developer/radius-vendor/libreoffice-core
mkdir -p work/scripts/patches
cp build_libreoffice_ios.sh work/scripts/
cp libreoffice-26.8.1.1-radius-ios.patch work/scripts/patches/libreoffice-ios.patch
cd work && scripts/build_libreoffice_ios.sh device      # 或 simulator；要好幾個小時
```

  腳本會套用修補、以 `--with-distro=LibreOfficeiOS` 設定，在 `~/Developer/radius-vendor/lo-build-device` 編譯
  （`VENDOR_DIR` 可以換成別的資料夾，路徑不能有空白）。App 連結 `workdir/CustomTarget/ios/ios-all-static-libs.list` 列的靜態庫，
  並把 `workdir/CustomTarget/ios/resources` 複製進 App。
- LibreOffice 是 The Document Foundation 的商標；Radius 與 The Document Foundation 沒有隸屬關係，也沒有得到其背書。

## 其他元件（寬鬆授權）

libarchive 3.8.9（BSD 2-Clause）、XZ Utils／liblzma 5.8.4（0BSD）、SwiftDraw 0.29.0（zlib）、
Noto Sans CJK 與 Noto Serif CJK（SIL OFL 1.1），以及依 SIL OFL 1.1 改名的子集字型：Instrument Serif、Instrument Sans、清松手寫體 1、
Klee One、Nanum Pen Script、Caveat。授權全文在 `licenses/`。

## 書面提供

Radius 1.0 最後一次散布之後至少三年內，收到這個版本的人都可以來信 lins.program@gmail.com 索取這裡的原始碼，費用不超過提供的成本。
