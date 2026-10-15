"""從各 App repo 的 PRIVACY.md、SUPPORT.md 產生這裡的公開 HTML（2026-10-10）。
App 的 repo 是私有的，App Store 要的隱私權政策與支援網址指到這裡：https://jeremyl861225.github.io/apps/<repo>/privacy.html
用法：python3 build.py（App repo 要在同一層：../tabi-kotoba、../yeohaengmal、../street-talk）。改完 commit＋push。"""
import html, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
APPS = [('tabi-kotoba', '旅ことば', '日本旅遊日文單字卡'), ('yeohaengmal', '여행말', '韓國旅遊韓文單字卡'), ('street-talk', 'Street Talk', '美國生活英文單字卡'),
        ('typeday', 'Typeday', '打字機風格的待辦月曆'), ('radius', 'Radius', '在 iPhone 上離線轉檔')]
# 頁面由 App 自己產生、直接寫進這裡的子資料夾（這支只列在首頁）：Typeday＝../checkly-ios 的 tools/appstore/build_site.py --apps（中英兩版）；
# Radius＝../radius 的 scripts/build_public_pages.py（9 種語言、一頁切換，網址是資料夾形式 radius/privacy/、radius/support/）
PREBUILT = {'typeday', 'radius'}
# 首頁連結的路徑（沒列的照 <repo>/privacy.html、<repo>/support.html）
LINKS = {'radius': ('radius/privacy/', 'radius/support/')}
STYLE = """:root{--bg:#faf7f9;--ink:#2b1a35;--ink2:#655a6b;--line:#e7dde4;--a:#5b2a6e}
@media (prefers-color-scheme:dark){:root{--bg:#1c1420;--ink:#f3ecf4;--ink2:#c4b6c8;--line:#3c2f41;--a:#d9b8ea}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:17px/1.75 -apple-system,"PingFang TC","Noto Sans TC",sans-serif}
main{max-width:720px;margin:0 auto;padding:28px 18px 56px}h1{font-size:26px;line-height:1.35;margin:8px 0 12px}h2{font-size:20px;margin:30px 0 8px;padding-top:14px;border-top:1px solid var(--line)}
h3{font-size:17px;margin:20px 0 4px}ul{padding-left:1.2em}a{color:var(--a)}nav{font-size:14px;color:var(--ink2)}nav a{color:var(--ink2)}hr{border:0;border-top:1px solid var(--line);margin:24px 0}"""


def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', t)
    t = re.sub(r'&lt;(https?://[^&\s]+)&gt;', r'<a href="\1">\1</a>', t)
    t = re.sub(r'&lt;([\w.+-]+@[\w.-]+)&gt;', r'<a href="mailto:\1">\1</a>', t)
    t = re.sub(r'(?<!">)(?<![\w"/:.])([\w.+-]+@[\w-]+\.[\w.-]+)', r'<a href="mailto:\1">\1</a>', t)
    t = re.sub(r'\[([^\]]+)\]\((https?://[^)]+)\)', r'<a href="\2">\1</a>', t)
    return t


def md2html(md):
    out, inlist = [], False
    for line in md.splitlines():
        if line.startswith('- '):
            if not inlist:
                out.append('<ul>'); inlist = True
            out.append(f'<li>{inline(line[2:])}</li>'); continue
        if inlist:
            out.append('</ul>'); inlist = False
        if not line.strip():
            continue
        m = re.match(r'(#{1,3}) (.*)', line)
        if m:
            out.append(f'<h{len(m.group(1))}>{inline(m.group(2))}</h{len(m.group(1))}>'); continue
        out.append('<hr>' if line.strip() == '---' else f'<p>{inline(line)}</p>')
    if inlist:
        out.append('</ul>')
    return '\n'.join(out)


def page(title, body, back=True):
    nav = '<nav><a href="../">← 所有 App</a></nav>' if back else ''
    return (f'<!doctype html>\n<html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
            f'<title>{html.escape(title)}</title><style>{STYLE}</style></head><body><main>{nav}\n{body}\n</main></body></html>\n')


def main():
    for repo, name, _ in APPS:
        if repo in PREBUILT:
            continue
        os.makedirs(os.path.join(HERE, repo), exist_ok=True)
        for kind, fn, title in (('privacy', 'PRIVACY.md', '隱私權政策'), ('support', 'SUPPORT.md', '使用說明與支援')):
            md = open(os.path.join(BASE, repo, fn), encoding='utf-8').read()
            open(os.path.join(HERE, repo, f'{kind}.html'), 'w', encoding='utf-8').write(page(f'{name} {title}', md2html(md)))
    idx = '<h1>App 隱私權政策與支援</h1>\n<p>jeremyl861225 的 iPhone App。聯絡：<a href="mailto:lins.program@gmail.com">lins.program@gmail.com</a></p>\n' + '\n'.join(
        f'<h2>{name}<span style="font-weight:400;color:var(--ink2);font-size:15px">　{sub}</span></h2>'
        f'<ul><li><a href="{LINKS.get(repo, (f"{repo}/privacy.html",))[0]}">隱私權政策 Privacy Policy</a></li>'
        f'<li><a href="{LINKS.get(repo, (None, f"{repo}/support.html"))[1]}">使用說明與支援 Support</a></li></ul>'
        for repo, name, sub in APPS)
    open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(page('App 隱私權政策與支援', idx, back=False))
    print('ok')


if __name__ == '__main__':
    main()
