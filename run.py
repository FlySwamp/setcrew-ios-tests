"""Open SetCrew in iOS Simulator Safari on one device; save video, screenshots and frame timings to out/.

Usage: python3 run.py "iPhone 15 Pro" https://opengym.runs-on.dev
"""
import json, os, signal, subprocess, sys, time

DEVICE, URL = sys.argv[1], sys.argv[2]
OUT = "out"
TABS = ["Train", "Feed", "Progress", "Home"]
os.makedirs(OUT, exist_ok=True)
report = {"device": DEVICE, "url": URL, "steps": []}


def simctl(*a, check=True):
    return subprocess.run(["xcrun", "simctl", *a], check=check, capture_output=True, text=True).stdout


# Newest iOS runtime + the requested iPhone model.
data = json.loads(simctl("list", "-j"))
runtimes = [r for r in data["runtimes"] if r["name"].startswith("iOS") and r["isAvailable"]]
runtime = max(runtimes, key=lambda r: [int(x) for x in r["version"].split(".")])
dtype = next((d for d in data["devicetypes"] if d["name"] == DEVICE), None)
if not dtype:
    sys.exit(f"unknown model {DEVICE!r}; available: {[d['name'] for d in data['devicetypes'] if 'iPhone' in d['name']]}")
udid = simctl("create", "test", dtype["identifier"], runtime["identifier"]).strip()
simctl("bootstatus", udid, "-b")
report["ios"] = runtime["version"]

# ponytail: guessed prefs for Safari's "Remote Automation" switch; first CI run tells if WebDriver needs them.
for domain in ("com.apple.mobilesafari", "com.apple.WebInspector"):
    simctl("spawn", udid, "defaults", "write", domain, "RemoteAutomationEnabled", "-bool", "YES", check=False)
subprocess.run(["sudo", "safaridriver", "--enable"], check=False)


def shot(name):
    simctl("io", udid, "screenshot", f"{OUT}/{len(report['steps']):02d}-{name}.png", check=False)


# Records every frame the page paints; slow ones (> 34 ms = at least 2 dropped frames at 60 Hz) are jank.
FRAMES_JS = "window.__f=[];let p=performance.now();(function t(n){window.__f.push(n-p);p=n;requestAnimationFrame(t)})(p)"


def step(driver, name, wait=2.5):
    time.sleep(wait)
    f = driver.execute_script("const f=window.__f||[];window.__f=[];return f") or []
    report["steps"].append({"step": name, "frames": len(f), "slow": sum(x > 34 for x in f), "worst_ms": round(max(f, default=0))})
    shot(name)


rec = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", f"{OUT}/video.mp4"])
time.sleep(2)
try:
    from selenium import webdriver
    from selenium.webdriver.common.by import By
    from selenium.webdriver.safari.options import Options

    opts = Options()
    opts.set_capability("platformName", "iOS")
    opts.set_capability("safari:useSimulator", True)
    opts.set_capability("safari:deviceUDID", udid)
    driver = webdriver.Safari(options=opts)
    driver.get(URL)
    driver.execute_script(FRAMES_JS)
    step(driver, "login", 5)
    # Production build has no guest button; the app reads this flag (store/useStore.js isGuest).
    driver.execute_script("localStorage.setItem('gym_guest','1')")
    driver.refresh()
    time.sleep(3)
    driver.execute_script(FRAMES_JS)
    step(driver, "home", 3)
    for tab in TABS:
        driver.find_element(By.XPATH, f"//button[span[normalize-space()='{tab}']]").click()
        step(driver, tab.lower())
    driver.quit()
except Exception as e:
    # WebDriver unavailable: still get a video of the page loading.
    report["driver_error"] = repr(e)
    simctl("openurl", udid, URL, check=False)
    time.sleep(10)
    shot("fallback")
finally:
    rec.send_signal(signal.SIGINT)
    rec.wait(60)
    json.dump(report, open(f"{OUT}/report.json", "w"), indent=2)
    print(json.dumps(report, indent=2))
