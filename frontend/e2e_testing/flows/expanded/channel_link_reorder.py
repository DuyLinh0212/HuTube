"""Verify channel links can be reordered by keyboard and drag, then persist."""
import json
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module


def _settings(value):
    if isinstance(value,dict):return dict(value)
    try:return json.loads(value or '{}')
    except (TypeError,ValueError):return {}


def run(suite,config,actors):
    snapshot_module(suite,__file__);owner=actors['owner'];page=owner['page']

    def run_case(entry):
        channel=suite.api(owner,'get','/channels/me').json();channel_id=channel['channelId'];route='/channel/'+channel['handle']+'/customize'
        detail=suite.api(owner,'get','/channels/'+channel_id).json()
        original_settings=_settings(detail.get('settings'))
        original_links=list(original_settings.get('links') or [])
        original_settings_raw=detail.get('settings') or '{}'
        local_links_key='hutube_channel_links_'+channel_id
        original_local_links=page.evaluate('key=>localStorage.getItem(key)',local_links_key)
        changed_on_server=False

        def load():
            suite.go(owner,route,'app-channel-settings-page');expect(page.locator('.basic-tab-pane')).to_be_visible()

        def current_order():
            return [value.strip() for value in page.locator('.link-row-card input[type=url]').evaluate_all('(nodes)=>nodes.map(node=>node.value)')]

        def save():
            nonlocal changed_on_server
            response=suite.response(owner,'/channels/'+channel_id,lambda:page.locator('.basic-tab-pane .form-actions .btn-primary').click(),method='PATCH')
            changed_on_server=True
            return response

        try:
            load()
            while page.locator('.link-row-card').count()<2:
                page.locator('.btn-add-link').click()
            rows=page.locator('.link-row-card')
            initial_count=rows.count()
            for index in range(len(original_links),initial_count):
                page.locator('#link-platform-'+str(index)).select_option('instagram' if index%2 else 'facebook')
                page.locator('#link-url-'+str(index)).fill('https://example.test/qc-reorder-'+suite.run_id+'-'+str(index))
            if initial_count>len(original_links):
                save()
                server=suite.api(owner,'get','/channels/'+channel_id).json();server_links=_settings(server.get('settings')).get('links',[])
                assert len(server_links)==initial_count, 'Temporary reorder fixtures did not persist before interaction'
                load();rows=page.locator('.link-row-card')

            order_before=current_order();assert len(order_before)>=2 and len(set(order_before))==len(order_before)
            first_handle=rows.nth(0).locator('.link-drag-handle')
            assert first_handle.evaluate('(element)=>element.tagName.toLowerCase()')=='button', 'Reorder handle is not keyboard focusable'
            assert first_handle.get_attribute('aria-label'), 'Reorder handle has no accessible name'
            page.evaluate("""() => {
                window.__qcReorderKeyProbe = [];
                document.addEventListener('keydown', event => {
                    if (event.target instanceof Element && event.target.closest('.link-drag-handle')) {
                        window.__qcReorderKeyProbe.push({key:event.key,altKey:event.altKey,ctrlKey:event.ctrlKey,metaKey:event.metaKey,defaultPrevented:event.defaultPrevented});
                    }
                });
            }""")
            first_handle.focus();first_handle.press('ArrowDown')
            order_after_keyboard=current_order()
            expected_keyboard=order_before.copy();expected_keyboard[0],expected_keyboard[1]=expected_keyboard[1],expected_keyboard[0]
            status_text=page.locator('.channel-links-section [role="status"]').inner_text()
            key_probe=page.evaluate('() => window.__qcReorderKeyProbe')
            assert order_after_keyboard==expected_keyboard, f'ArrowDown did not move the first link down one position: before={order_before}, after={order_after_keyboard}, status={status_text!r}, disabled={first_handle.is_disabled()}, key_probe={key_probe}'
            expect(page.locator('.channel-links-section [role="status"]')).to_contain_text('2')
            save()
            server=suite.api(owner,'get','/channels/'+channel_id).json();saved_keyboard=[link['url'] for link in _settings(server.get('settings')).get('links',[])]
            assert saved_keyboard==expected_keyboard, 'Keyboard reorder was not persisted in the exact link order'
            load();assert current_order()==expected_keyboard, 'Keyboard reorder was lost after route reload'

            rows=page.locator('.link-row-card')
            rows.nth(0).locator('.link-drag-handle').drag_to(rows.nth(1))
            order_after_drag=current_order()
            assert order_after_drag==order_before, 'Dragging the first link to the second row did not restore the expected order'
            save()
            server=suite.api(owner,'get','/channels/'+channel_id).json();saved_drag=[link['url'] for link in _settings(server.get('settings')).get('links',[])]
            assert saved_drag==order_before, 'Dragged order was not persisted in the exact link order'
            load();assert current_order()==order_before, 'Dragged link order was lost after route reload'

            entry['steps']=['Load existing channel links; add temporary links only if needed and save their real records','Move the first link down with the keyboard control and verify exact API order after reload','Drag the first row to the second row and verify exact API order after reload','Restore the original channel settings and confirm its original link order']
            entry['assertions']=['Drag handle is a keyboard-focusable button with an accessible reorder label','ArrowDown moves one link exactly one position and announces the new position','Native drag-and-drop moves the exact row to its drop position','Each saved order matches the real channel API and survives full reload','Original channel settings are restored after the test']
            entry['resource_ids']=[channel_id]
            entry['link_order_before']=order_before
            entry['link_order_keyboard']=expected_keyboard
            entry['link_order_drag']=order_after_drag
            suite.evidence(owner,entry,'reordered-links-persisted')
        finally:
            if changed_on_server:
                suite.api(owner,'patch','/channels/'+channel_id,data={'settings':original_settings_raw})
                if original_local_links is None:page.evaluate('key=>localStorage.removeItem(key)',local_links_key)
                else:page.evaluate('([key,value])=>localStorage.setItem(key,value)',[local_links_key,original_local_links])
                restored=suite.api(owner,'get','/channels/'+channel_id).json()
                restored_links=_settings(restored.get('settings')).get('links',[])
                assert restored_links==original_links, 'Original channel link settings did not restore'
                load();assert current_order()==[link.get('url','') for link in original_links], 'Original channel link UI state did not restore'

    case(suite,owner,'CHANNEL-LINK-REORDER-KEYBOARD-DRAG-PERSIST','U-CHANNEL.02','Channel links reorder by keyboard and drag, then persist',run_case,'channel')
