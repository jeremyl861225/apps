#!/bin/bash
# 下載 iPhone 版 Office 引擎用的中文字型（Noto Sans 繁中／簡中，SIL OFL 1.1）到 iOS/Vendor/Fonts（不進 git）。
#
# 為什麼要自己帶字型（2026-10-07 實測）：iPhone 的中文字型 PingFang 放在 FontServices 的 CorePrivate/PingFangUI.ttc，
# 用的是新的 'hvgl' 字形表、沒有 'glyf'，LibreOffice 刻意不收（tdf#163000：匯出 PDF 會壞），系統也不把它列進可用字型；
# 結果 Word／簡報轉 PDF 的中文只剩文字層、畫面上一片空白。iPhone 上其他不是 hvgl 的中文字型一個都沒有（日文 Hiragino、
# 韓文 Apple SD Gothic Neo 有）。所以內附 Noto 的地區子集 OTF：繁中黑體 Regular＋Bold、簡中黑體 Regular、繁中明體 Regular
# （約 28 MB；其餘粗體由 LibreOffice 自己加粗），iOS/Office/OfficeBridge.swift 的對應表把文件指定的中文字型換成它們，
# patches/libreoffice-ios.patch 再把 CoreText 建議的缺字備援 PingFang 換成它們。
set -euo pipefail
cd "$(dirname "$0")/.."
DEST=iOS/Vendor/Fonts
mkdir -p "$DEST"
BASE=https://github.com/notofonts/noto-cjk/raw/main
for f in Sans/SubsetOTF/TC/NotoSansTC-Regular.otf Sans/SubsetOTF/TC/NotoSansTC-Bold.otf Sans/SubsetOTF/SC/NotoSansSC-Regular.otf \
         Serif/SubsetOTF/TC/NotoSerifTC-Regular.otf Sans/LICENSE Serif/LICENSE; do
    out="$DEST/$(basename "$f")"
    [ "$f" = Sans/LICENSE ] && out="$DEST/NotoSansCJK-LICENSE.txt"
    [ "$f" = Serif/LICENSE ] && out="$DEST/NotoSerifCJK-LICENSE.txt"
    [ -s "$out" ] && continue
    curl -f -L -sS --retry 3 -o "$out.part" "$BASE/$f" && mv "$out.part" "$out"
done
ls -la "$DEST"
