# apps

jeremyl861225 的 iPhone App 的公開頁面：隱私權政策與支援（App Store Connect 的「隱私權政策網址」「支援網址」指到這裡）。
App 本身的 repo 是私有的；這裡只放公開頁面，網址 <https://jeremyl861225.github.io/apps/>。

- 旅ことば：`tabi-kotoba/privacy.html`、`tabi-kotoba/support.html`
- 여행말：`yeohaengmal/privacy.html`、`yeohaengmal/support.html`
- Street Talk：`street-talk/privacy.html`、`street-talk/support.html`
- Typeday：`typeday/privacy.html`、`typeday/support.html`（英文 `typeday/en/…`）。這兩頁由 Typeday 自己的 `checkly-ios/tools/appstore/build_site.py --apps` 產生（來源 `appstore/privacy.md`、`support.md` 與 `.en.md`），`build.py` 只把它列進首頁
- Radius：`radius/privacy/`、`radius/support/`（資料夾形式，9 種語言在同一頁切換，各語言的錨點 `#zh`、`#en`、`#ja`…）。由 Radius 自己的 `radius/scripts/build_public_pages.py` 產生（來源 `docs/privacy/<語言>.md`、`docs/support/<語言>.md`），`build.py` 只把它列進首頁
  - `radius/source/`：「原始碼與建置說明」（LGPL／MPL 元件的原始碼、修補、建置腳本，檔案在 `radius/source/files/`，單檔 < 50 MB）。由 Radius 的原始碼包流程產生（`make_package.py`、`make_page.py`，版型同上），整個資料夾直接複製過來

內容來源是各 App repo 的 `PRIVACY.md`、`SUPPORT.md`；改了那邊跑 `python3 build.py` 重新產生。聯絡：lins.program@gmail.com，或開 Issue。
