"""Drive the shared application confirmation after the action that opens it."""
from playwright.sync_api import expect


def app_confirm(page, action, accept=True):
    action()
    dialog = page.locator('app-confirm-dialog dialog:modal').last
    expect(dialog).to_be_visible()
    dialog.locator('.confirm-submit' if accept else '.confirm-cancel').click()
