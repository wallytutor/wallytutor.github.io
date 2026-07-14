# -*- coding: utf-8 -*-
import sys
from playwright.sync_api import sync_playwright
from bs4 import BeautifulSoup

SELECTOR_BANNER   = 'div[class^="index-row_indexRow__"]'
SELECTOR_CATEGORY = 'div[class^="index-row_index__"]'
SELECTOR_SPAN     = 'div[class^="index-card_value"]'

AGENT = (
    "--user-agent="
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/127.0.0.0 Safari/537.36"
)

def get_index(soup):
    """ Get the index from the span element of a category. """
    if (value_span := soup.select_one(SELECTOR_SPAN)):
        return value_span.get_text(strip=True)

    # .index-card_noIndex__
    return None


def get_utmb_index(runner_id):
    """ Get UTMB index for all categories for a runner. """
    with sync_playwright() as p:
        # add a User-Agent string to your Playwright browser launch
        # to make the script look more like a legitimate browser
        browser = p.chromium.launch(headless=True, args=[AGENT])

        page = browser.new_page()

        # Wait until network activity finishes
        page.goto(f"https://utmb.world/runner/{runner_id}")
        page.wait_for_load_state("networkidle")

        # Ensure the main container is loaded:
        page.wait_for_selector(SELECTOR_BANNER)

        # Parse content and close browser:
        soup = BeautifulSoup(page.content(), "html.parser")
        browser.close()

        # Find all category containers:
        categories = soup.select(SELECTOR_CATEGORY)

        return [get_index(cat) for cat in categories]


if __name__ == "__main__":
    try:
        runner_name = sys.argv[1]
        print(get_utmb_index(runner_name))
    except:
        pass

    exit(0)