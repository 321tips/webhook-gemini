from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1440, "height": 900})
    page.goto("http://127.0.0.1:8080/index.html", wait_until="networkidle")
    page.wait_for_timeout(500)
    page.screenshot(path="tests/screenshots/index_desktop.png", full_page=True)
    browser.close()
print("Saved to: tests/screenshots/index_desktop.png")