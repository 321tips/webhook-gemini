from pathlib import Path
from playwright.sync_api import sync_playwright

out_dir = Path("tests/screenshots")
out_dir.mkdir(parents=True, exist_ok=True)

init_img = out_dir / "index_desktop.png"
refresh_img = out_dir / "点刷新按钮后图片.png"
move_img = out_dir / "点移动按钮后图片.png"
confirm_img = out_dir / "确认移动后图片.png"
after_refresh_img = out_dir / "再次刷新后图片.png"

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

    first_item = page.locator("#list .item").first
    moved_filename = ""
    if first_item.count() > 0:
        moved_filename = first_item.locator(".name").inner_text().strip()
        first_item.locator("button.move").click()
        page.locator("#modal").wait_for(state="visible")
        page.wait_for_timeout(300)
        page.screenshot(path=str(move_img), full_page=True)

        with page.expect_response(lambda r: "/hooks/api/move" in r.url and r.request.method == "POST"):
            page.locator("#confirm").click()
        page.wait_for_timeout(500)
        page.screenshot(path=str(confirm_img), full_page=True)

        with page.expect_response(lambda r: "/hooks/api/Downloads/" in r.url and r.request.method == "GET"):
            page.locator("#refresh").click()
        page.wait_for_timeout(500)
        page.screenshot(path=str(after_refresh_img), full_page=True)

        if moved_filename:
            remaining_names = [n.strip() for n in page.locator("#list .item .name").all_inner_texts()]
            assert moved_filename not in remaining_names, f"文件仍在列表中: {moved_filename}"
    else:
        page.screenshot(path=str(move_img), full_page=True)
        page.screenshot(path=str(confirm_img), full_page=True)
        page.screenshot(path=str(after_refresh_img), full_page=True)

    browser.close()

print("Saved to:", init_img)
print("Saved to:", refresh_img)
print("Saved to:", move_img)
print("Saved to:", confirm_img)
print("Saved to:", after_refresh_img)