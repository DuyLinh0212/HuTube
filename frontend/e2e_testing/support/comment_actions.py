"""Open the author-only menu before using comment actions."""


def comment_menu(row):
    return row.locator(':scope > .comment-body > .comment-author > .comment-menu')


def click_comment_delete(row):
    menu = comment_menu(row)
    menu.locator('summary').click()
    menu.locator('button.is-danger').click()


def click_comment_edit(row):
    menu = comment_menu(row)
    menu.locator('summary').click()
    menu.locator('button').first.click()
