"""Drive subscription buttons, including the unsubscribe confirmation."""
from support.ui_confirmation import app_confirm
from playwright.sync_api import expect


def toggle_channel_subscription(page, selector):
    button = page.locator(selector)
    expect(button).to_be_enabled()
    if 'is-subscribed' in (button.get_attribute('class') or '').split():
        app_confirm(page, button.click)
    else:
        button.click()
