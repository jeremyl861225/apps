# Radius 1.0 for iPhone: source code for its LGPL and MPL components

This directory belongs to **Radius 1.0 for iPhone** (bundle ID `com.jeremyl861225.radius`, version 1.0, build 1),
made by an individual developer. Radius itself is not open-source software; the licenses below apply only to the
components listed here. The same information, in nine languages, is on
https://jeremyl861225.github.io/apps/radius/source/ (繁體中文: `README.zh-Hant.md`).

Contact: lins.program@gmail.com

## Files

| Path | What it is | License |
|---|---|---|
| `ffmpeg/ffmpeg-9.0.1.tar.xz` (+ `.asc`) | FFmpeg 9.0.1, official release tarball and its signature from ffmpeg.org, unmodified | LGPL 2.1 or later |
| `ffmpeg/radius-fftools-1.0.tar.xz` | Our FFTools interface layer, our patch to FFmpeg's `fftools/`, the build script and build information (see its `README.md`) | LGPL 2.1 or later |
| `ffmpeg/fftools-n9.0.1-radius.patch`, `build_ffmpeg_ios.sh`, `BUILD-INFO.txt` | The same patch, script and build information as plain files, for reading online | LGPL 2.1 or later |
| `ffmpeg/lame-3.100.tar.gz` | LAME 3.100, official release tarball, unmodified (encoder only, linked into libavcodec) | LGPL 2.0 or later |
| `ffmpeg/opus-1.5.2.tar.gz`, `libvpx-1.16.0.tar.gz`, `libwebp-1.6.0.tar.gz` | Official release tarballs, unmodified (linked into libavcodec) | BSD 3-Clause |
| `libreoffice/libreoffice-26.8.1.1-radius-ios.patch` | Our changes to LibreOffice 26.8.1.1 (13 files) | MPL 2.0 |
| `libreoffice/build_libreoffice_ios.sh` | How we build LibreOffice for iOS | MPL 2.0 |
| `libreoffice/libreoffice-external-tarballs.tsv` | The third-party source tarballs LibreOffice's build downloaded (file name, size, SHA-256, URL), unmodified | (various) |
| `libreoffice/libreoffice-externals-unpacked-ios-device.txt` | Which of them the device build actually unpacked | |
| `other/` | Build scripts for libarchive/liblzma and for the CJK fonts used by the Office engine | (BSD-style; for reference) |
| `licenses/` | Full license texts of every third-party component in the app (the same files as in the app) | |
| `SHA256SUMS` | SHA-256 of every file here (`shasum -a 256 -c SHA256SUMS`) | |

## FFmpeg (LGPL 2.1 or later)

- **FFmpeg 9.0.1**, built from the official tarball with `--disable-gpl --disable-version3 --disable-nonfree`; `configure` reports
  “LGPL version 2.1 or later”. The FFmpeg libraries are **not modified**. They ship as seven dynamic frameworks in the app
  (libavcodec, libavdevice, libavfilter, libavformat, libavutil, libswresample, libswscale). The full `configure` command line is in `BUILD-INFO.txt`.
- **FFTools 1.0** (our code, LGPL 2.1 or later): FFmpeg's own `fftools` (`ffmpeg`, `ffprobe`) built as a dynamic framework that the app
  calls in-process, with changes to three files (`fftools-n9.0.1-radius.patch`). It replaced FFmpegKit before Radius 1.0 was released;
  no FFmpegKit code is in the app.
- **Statically linked into libavcodec**, all unmodified: LAME 3.100 (LGPL 2.0 or later), Opus 1.5.2, libvpx 1.16.0, libwebp 1.6.0 (BSD 3-Clause).
  From iOS: zlib, bzip2, iconv, VideoToolbox, AudioToolbox.

**Rebuilding, and replacing the frameworks in the app**: see `README.md` inside `ffmpeg/radius-fftools-1.0.tar.xz`
(the same text is on the web page). In short: `scripts/build_ffmpeg_ios.sh` builds all eight frameworks; in the app bundle they are
`RadiusPhone.app/Frameworks/<name>.framework/<name>`, loaded through `@rpath`; replace them and re-sign the app with your own identity.

## Office engine based on LibreOffice (MPL 2.0)

- **LibreOffice 26.8.1.1**: tag `libreoffice-26.8.1.1`, commit `bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1`
  (https://git.libreoffice.org/core, mirrored at https://github.com/LibreOffice/core). It is statically linked into the app and is used
  only to convert Word, Excel and presentation files to PDF.
- **Our changes** (`libreoffice-26.8.1.1-radius-ios.patch`, 13 files): build for the arm64 simulator on Apple silicon, minimum iOS 18,
  curl without TLS, expat's random source on iOS, iOS-specific fixes in vcl, and the static library list.
- Third-party components that are statically linked and offer a choice of licenses (for example librevenge, libwpd, libwps, libmwaw,
  libodfgen, liblangtag, Hunspell, Hyphen, Graphite, Redland) are used under their MPL or Apache 2.0 option.
- To rebuild: `brew install make gperf bison flex autoconf automake ninja pkgconf`, then

```sh
git clone --depth 1 --branch libreoffice-26.8.1.1 https://github.com/LibreOffice/core.git ~/Developer/radius-vendor/libreoffice-core
mkdir -p work/scripts/patches
cp build_libreoffice_ios.sh work/scripts/
cp libreoffice-26.8.1.1-radius-ios.patch work/scripts/patches/libreoffice-ios.patch
cd work && scripts/build_libreoffice_ios.sh device      # or: simulator; takes several hours
```

  The script applies the patch, configures with `--with-distro=LibreOfficeiOS` and builds in `~/Developer/radius-vendor/lo-build-device`
  (set `VENDOR_DIR` to use another folder without spaces). The app links the static libraries listed in
  `workdir/CustomTarget/ios/ios-all-static-libs.list` and copies `workdir/CustomTarget/ios/resources` into the app bundle.
- LibreOffice is a trademark of The Document Foundation. Radius is not affiliated with or endorsed by The Document Foundation.

## Other components (permissive licenses)

libarchive 3.8.9 (BSD 2-Clause), XZ Utils / liblzma 5.8.4 (0BSD), SwiftDraw 0.29.0 (zlib),
Noto Sans CJK and Noto Serif CJK (SIL OFL 1.1), and subsets of Instrument Serif, Instrument Sans, 清松手寫體 1 (JasonHandwriting1),
Klee One, Nanum Pen Script and Caveat, renamed as required by the SIL OFL 1.1. Their license texts are in `licenses/`.

## Written offer

For at least three years after the last distribution of Radius 1.0, anyone who received it can ask for the source code on this page
by email at lins.program@gmail.com; we charge no more than the cost of providing it.
