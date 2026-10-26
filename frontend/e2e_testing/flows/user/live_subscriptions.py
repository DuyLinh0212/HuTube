"""Public channel data, guest CTA and subscription mutations with restoration."""
from support.subscription_confirmation import toggle_channel_subscription
from urllib.parse import parse_qs,urlsplit
from playwright.sync_api import expect

def run(suite,owner,other):
    channel=suite.api(owner,'get','/channels/me').json()
    channel_id=channel['channelId']; handle=channel['handle']
    route='/channel/'+handle
    guest=suite.actor('public-channel-guest','user','guest')
    guest['api_url']=owner['api_url']
    def public(case):
        page=guest['page']
        data=suite.go(guest,route,'app-channel-page','/videos/search')
        assert all(video['channelId']==channel_id and video['visibility']=='public' for video in data['items'])
        for index in [0,1]:
            page.locator('.channel-tabs-bar button').nth(index).click()
            expect(page.locator('.channel-tabs-bar button').nth(index)).to_have_class(__import__('re').compile('active'))
            expect(page.locator('.channel-video-card')).to_have_count(len(data['items']))
            for video in data['items']:
                expect(page.locator('.channel-video-card[href="/watch/'+video['videoId']+'"]')).to_contain_text(video['title'])
            suite.evidence(guest,case,'channel-tab-'+str(index))
        lists=suite.api(guest,'get','/playlists/channel/'+channel_id).json()
        page.locator('.channel-tabs-bar button').nth(2).click()
        expect(page.locator('.channel-playlist-card')).to_have_count(len(lists))
        for item in lists:
            expect(page.locator('.channel-playlist-card[href="/channel/'+handle+'/playlists/'+item['playlistId']+'"]')).to_contain_text(item['name'])
        case['resource_ids']=[channel_id]
        case['steps']=['Open owner channel as guest','Home and Videos tabs → compare every real API ID/title/visibility','Playlists tab → compare public playlist IDs and count']
    suite.case(guest,'LIVE-CHANNEL-PUBLIC-TABS','U-CHANNEL.03','Public channel tabs and data','Every public card matches the real public catalogue; private videos stay absent',public,module='channel')
    def guest_cta(case):
        page=guest['page']
        suite.go(guest,'/subscriptions','app-subscriptions-page')
        expect(page.locator('.guest-prompt')).to_be_visible()
        page.locator('.btn-signin').click()
        expect(page.locator('#email')).to_be_visible()
        assert parse_qs(urlsplit(page.url).query)['returnUrl']==['/subscriptions']
        case['steps']=['Guest subscriptions → explicit login CTA','Click CTA → login retains exact subscriptions return URL']
    suite.case(guest,'LIVE-SUBSCRIPTIONS-GUEST-CTA','U-SUBSCRIPTION.01','Guest subscriptions CTA','Guest sees no private feed and login keeps the intended subscriptions route',guest_cta,module='subscriptions')
    original=suite.api(other,'get','/channels/'+channel_id+'/subscribe-status').json()
    (suite.run_dir/'subscription-restore.json').write_text(__import__('json').dumps({'channel_id':channel_id,'actor_user_id':other['identity']['userId'],'original':original}),encoding='utf-8')
    def navigate():
        suite.go(other,route,'app-channel-page')
        expect(other['page'].locator('.btn-subscribe')).to_be_enabled()
    def status(): return suite.api(other,'get','/channels/'+channel_id+'/subscribe-status').json()
    try:
        def subscribe(case):
            page=other['page']; navigate()
            if status()['status']=='active':
                suite.response(other,'/channels/'+channel_id+'/subscribe',lambda:toggle_channel_subscription(page, '.btn-subscribe'),method='DELETE',status=(200,204))
            before=suite.api(other,'get','/channels/handle/'+handle).json()['subscriberCount']
            suite.response(other,'/channels/'+channel_id+'/subscribe',lambda:toggle_channel_subscription(page, '.btn-subscribe'),method='POST',status=(200,201))
            expect(page.locator('.btn-subscribe')).to_have_class(__import__('re').compile('is-subscribed'))
            assert status()['status']=='active'
            assert suite.api(other,'get','/channels/handle/'+handle).json()['subscriberCount']==before+1
            duplicate=suite.api(other,'post','/channels/'+channel_id+'/subscribe',data={},expected=(200,201,409))
            assert suite.api(other,'get','/channels/handle/'+handle).json()['subscriberCount']==before+1
            navigate()
            expect(page.locator('.btn-subscribe')).to_have_class(__import__('re').compile('is-subscribed'))
            case['resource_ids']=[channel_id]
            case['steps']=['Other supplied identity opens owner channel','Subscribe through UI → count increases once','Repeat subscribe API → no duplicate count','Reload → subscription remains active']
        suite.case(other,'LIVE-SUBSCRIPTION-PERSIST-IDEMPOTENT','U-SUBSCRIPTION.01','Subscribe, duplicate and reload','Exactly one subscription belongs to the second supplied identity',subscribe,module='subscriptions')
        for enabled in [False,True]:
            def notifications(case,enabled=enabled):
                page=other['page']; navigate()
                if status()['status']!='active':
                    suite.api(other,'post','/channels/'+channel_id+'/subscribe',data={},expected=(200,201))
                    navigate()
                bell=page.locator('.btn-bell-notice')
                if (bell.get_attribute('aria-pressed')=='true')==enabled:
                    suite.response(other,'/channels/'+channel_id+'/subscribe-notifications',bell.click,method='PATCH')
                suite.response(other,'/channels/'+channel_id+'/subscribe-notifications',bell.click,method='PATCH')
                assert status()['notificationsEnabled']==enabled
                navigate()
                expect(bell).to_have_attribute('aria-pressed',str(enabled).lower())
                case['resource_ids']=[channel_id]
                case['steps']=['Toggle channel notification bell to '+str(enabled),'Read back exact subscription','Reload → aria-pressed agrees with persisted API state']
            suite.case(other,'LIVE-SUBSCRIPTION-NOTIFICATIONS-'+str(enabled).upper(),'U-CHANNEL.05','Subscription notifications '+str(enabled),'Notification flag persists for the exact channel and actor',notifications,module='subscriptions')
        def feed(case):
            page=other['page']
            channels=suite.api(other,'get','/subscriptions').json()
            data=suite.go(other,'/subscriptions','app-subscriptions-page','/feed/subscriptions')
            expect(page.locator('.channel-chip')).to_have_count(len(channels))
            expect(page.locator('.videos-section .card')).to_have_count(len(data['items']))
            ids={item['channelId'] for item in channels}
            assert channel_id in ids
            assert all(video['channelId'] in ids for video in data['items'])
            for video in data['items']:
                expect(page.locator('.videos-section .card[href="/watch/'+video['videoId']+'"]')).to_contain_text(video['title'])
            case['steps']=['Read this actor subscriptions','Open subscriptions feed','Compare every channel chip, feed ID/title and source channel membership']
        suite.case(other,'LIVE-SUBSCRIPTIONS-FEED-ISOLATION','U-SUBSCRIPTION.01','Subscriptions feed payload and identity','Feed contains exactly real items from this identity subscribed channels',feed,module='subscriptions')
        def unsubscribe(case):
            page=other['page']; navigate()
            before=suite.api(other,'get','/channels/handle/'+handle).json()['subscriberCount']
            suite.response(other,'/channels/'+channel_id+'/subscribe',lambda:toggle_channel_subscription(page, '.btn-subscribe'),method='DELETE',status=(200,204))
            assert status()['status']!='active'
            assert suite.api(other,'get','/channels/handle/'+handle).json()['subscriberCount']==max(0,before-1)
            navigate()
            expect(page.locator('.btn-bell-notice')).to_have_count(0)
            assert channel_id not in {item['channelId'] for item in suite.api(other,'get','/subscriptions').json()}
            case['steps']=['Unsubscribe through UI','Read-back count decreases once and status inactive','Reload → bell absent','This actor subscribed channel list no longer includes target']
        suite.case(other,'LIVE-SUBSCRIPTION-UNSUBSCRIBE','U-SUBSCRIPTION.01','Unsubscribe persistence','Only target subscription is removed and count remains consistent',unsubscribe,module='subscriptions')
    finally:
        current=status()
        if original['status']=='active':
            if current['status']!='active': suite.api(other,'post','/channels/'+channel_id+'/subscribe',data={},expected=(200,201))
            suite.api(other,'patch','/channels/'+channel_id+'/subscribe-notifications',data={'enabled':original['notificationsEnabled']})
        elif current['status']=='active':
            suite.api(other,'delete','/channels/'+channel_id+'/subscribe',expected=(200,204))
        restored=status()
        assert (restored['status']=='active')==(original['status']=='active')
        if original['status']=='active': assert restored['notificationsEnabled']==original['notificationsEnabled']
        suite.report['cleanup'].append({'resource':'subscription','channel_id':channel_id,'actor':other['name'],'status':'restored'})
