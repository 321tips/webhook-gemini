from pathlib import Path
from playwright.sync_api import sync_playwright

out_dir = Path("tests/screenshots")
out_dir.mkdir(parents=True, exist_ok=True)

init_img = out_dir / "index_desktop.png"
refresh_img = out_dir / "点刷新按钮后图片.png"
move_img = out_dir / "点移动按钮后图片.png"

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 1440, "height": 900})
    page.goto("http://127.0.0.1:9000/hooks/index", wait_until="networkidle")
    page.wait_for_timeout(500)
    page.screenshot(path=str(init_img), full_page=True)

    with page.expect_response(lambda r: "/hooks/api/Downloads/" in r.url and r.request.method == "GET"):
        page.locator("#refresh").click()
    page.wait_for_timeout(500)
    page.screenshot(path=str(refresh_img), full_page=True)

    first_move_btn = page.locator("#list .item button.move").first
    if first_move_btn.count() > 0:
        first_move_btn.click()
        page.locator("#modal").wait_for(state="visible")
        page.wait_for_timeout(300)
    page.screenshot(path=str(move_img), full_page=True)

    browser.close()

print("Saved to:", init_img)
print("Saved to:", refresh_img)
print("Saved to:", move_img)