"""Use real Chromium touch input in explicitly emulated touch contexts."""
from playwright.sync_api import Locator

def install_touch_actions():
    if getattr(Locator,'_qc_touch_installed',False):return
    original_click=Locator.click;original_check=Locator.check;original_uncheck=Locator.uncheck
    def is_touch(locator):return getattr(locator.page.context,'_qc_touch_actions',False)
    def click(locator,*args,**kwargs):
        if not is_touch(locator) or args or any(key in kwargs for key in ('button','click_count','delay')):
            return original_click(locator,*args,**kwargs)
        return locator.tap(**kwargs)
    def checked(locator,wanted,original,*args,**kwargs):
        if not is_touch(locator) or args:return original(locator,*args,**kwargs)
        if locator.is_checked()!=wanted:locator.tap(**kwargs)
        if not kwargs.get('trial'):assert locator.is_checked()==wanted,'Touch input did not update checked state'
    def check(locator,*args,**kwargs):return checked(locator,True,original_check,*args,**kwargs)
    def uncheck(locator,*args,**kwargs):return checked(locator,False,original_uncheck,*args,**kwargs)
    Locator.click=click;Locator.check=check;Locator.uncheck=uncheck;Locator._qc_touch_installed=True
