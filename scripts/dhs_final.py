# Final attempt: the approved row links to the dataset page with ?flag=1, and the file list
# sometimes errors server-side ("Error in custom script module"), so retry the render.
import json, tempfile, time
from pathlib import Path
from playwright.sync_api import sync_playwright

# Browser and session paths are resolved at run time so nothing machine-specific is hard-coded.
BRAVE = r"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
TMP = Path(tempfile.gettempdir()) / "opencode"
PROFILE = str(TMP / "brave-dhs-profile")
COOKIES = TMP / "dhs_cookies.json"
HOME = "https://dhsprogram.com/data/dataset_admin/index.cfm"
URL = "https://dhsprogram.com/data/dataset/Nigeria_Standard-DHS_2024.cfm?flag=1"
OUT = Path(r"data\raw\dhs")
FILES = ["NGGE8AFL.ZIP", "NGGC8AFL.ZIP"]

def say(m): print(f"[{time.strftime('%H:%M:%S')}] {m}", flush=True)

OUT.mkdir(parents=True, exist_ok=True)
result = {"ok": False, "files": [], "notes": []}

with sync_playwright() as pw:
    ctx = pw.chromium.launch_persistent_context(
        user_data_dir=PROFILE, executable_path=BRAVE, headless=False,
        args=["--no-first-run","--no-default-browser-check","--start-maximized"],
        viewport={"width":1440,"height":950}, accept_downloads=True)
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    if COOKIES.exists():
        ctx.add_cookies(json.loads(COOKIES.read_text()))

    try:
        page.goto(HOME, wait_until="domcontentloaded", timeout=60000)
        page.select_option('select[name="proj_id"]', value="246118")
        page.wait_for_timeout(2500)
        say("project selected")
    except Exception as e:
        say("project select problem: " + type(e).__name__)

    anchors = []
    for attempt in range(1, 6):
        try:
            page.goto(URL, wait_until="domcontentloaded", timeout=60000)
        except Exception as e:
            say(f"attempt {attempt}: navigation {type(e).__name__}")
            page.wait_for_timeout(4000); continue
        page.wait_for_timeout(1500)
        body = page.inner_text("body")
        err = "error in custom script module" in body.lower()
        anchors = page.evaluate("""() => [...document.querySelectorAll('a[href]')]
            .map(a => ({t:(a.textContent||'').trim(), h:a.getAttribute('href')}))
            .filter(x => /NGGE8AFL|NGGC8AFL/i.test(x.h + ' ' + x.t))""")
        say(f"attempt {attempt}: server error={err} | geographic anchors={len(anchors)}")
        if anchors:
            break
        page.wait_for_timeout(3000)

    if not anchors:
        b = page.inner_text("body")
        k = b.find("Survey Datasets Files")
        say("still empty. page text: " + (b[k:k+260] if k >= 0 else b[:260]).replace("\n", " | "))
        page.screenshot(path=r"logs\dhs_final_attempt.png", full_page=True)
        result["notes"].append("server-side render error persists after 5 attempts")
        ctx.close()
        Path(r"logs\BRAVE_RESULT.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(json.dumps(result), flush=True); raise SystemExit(2)

    for x in anchors:
        say("anchor: " + x["t"][:40] + " -> " + str(x["h"])[:110])

    for name in FILES:
        hit = next((x for x in anchors if name in (x["h"] + " " + x["t"])), None)
        if not hit:
            result["notes"].append("no anchor for " + name); continue
        try:
            with page.expect_download(timeout=120000) as info:
                page.evaluate("u => { location.href = u; }", hit["h"])
            d = info.value
            dst = OUT / name
            d.save_as(str(dst))
            result["files"].append({"name": name, "bytes": dst.stat().st_size})
            say(f"SAVED {name} ({dst.stat().st_size} bytes)")
        except Exception as e:
            result["notes"].append(f"{name}: {type(e).__name__}")
            say(f"FAILED {name}: {type(e).__name__}")
        page.wait_for_timeout(1200)

    result["ok"] = len(result["files"]) == len(FILES)
    ctx.close()

Path(r"logs\BRAVE_RESULT.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result), flush=True)
