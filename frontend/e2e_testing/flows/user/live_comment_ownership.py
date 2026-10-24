"""Two supplied identities, channel permission denial and real threaded replies."""
import json
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite,owner,other):
    channel=suite.api(owner,'get','/channels/me').json()
    dataset=suite.api(owner,'get','/videos/manage',params={'channelId':channel['channelId'],'page':1,'pageSize':50}).json()['items']
    videos=[v for v in dataset if v['visibility']=='public' and v['status']=='published' and v['moderationStatus']=='approved']
    if not videos:
        def missing(case):raise PrerequisiteMissing('No existing approved public video on the supplied owner channel; no real video is modified')
        suite.case(owner,'LIVE-COMMENT-THREAD-FIXTURE','U-WATCH.04','Comment thread fixture','Owned public video required',missing,module='watch')
        return
    video_id=videos[0]['videoId']; base='/videos/'+video_id
    text='QC comment ownership '+suite.run_id+' — Unicode <script>text</script>'
    reply_text='QC threaded reply '+suite.run_id+' — trả lời'
    parent={}; reply={}
    def persist_checkpoint():
        (suite.run_dir/'comment-thread-fixture.json').write_text(json.dumps({'video_id':video_id,'parent_id':parent.get('commentId'),'reply_id':reply.get('commentId'),'owner_user_id':owner['identity']['userId'],'reply_user_id':other['identity']['userId']}),encoding='utf-8')
    try:
        def create(case):
            suite.go(owner,'/watch/'+video_id,'app-watch-page')
            expect(owner['page'].locator('.comment-composer button[type=submit]')).to_be_disabled()
            owner['page'].locator('textarea[name=comment]').fill(text)
            response=suite.response(owner,base+'/comments',lambda:owner['page'].locator('.comment-composer button[type=submit]').click(),method='POST',status=201)
            parent.update(response.json()); persist_checkpoint()
            assert parent['userId']==owner['identity']['userId'] and parent['content']==text
            owner['page'].reload()
            expect(owner['page'].locator('.comment-list > .comment-row').filter(has_text=text)).to_have_count(1)
            assert owner['page'].locator('.comment-list script').count()==0
            case['resource_ids']=[video_id,parent['commentId']]
            case['steps']=['Existing approved owned video; blank composer cannot submit','Create unique text through UI → actual comment ID and author','Reload → one comment with literal XSS text, no script element']
        suite.case(owner,'LIVE-COMMENT-THREAD-FIXTURE','U-WATCH.04','Fresh public comment fixture','Create one unique comment on the owned public video and retain the source video',create,module='watch')
        def denied(case):
            if not parent:raise PrerequisiteMissing('Comment fixture was not created')
            info=suite.api(other,'get','/channels/handle/'+channel['handle']).json()
            assert not info['isOwner'] and 'comment.manage' not in info['permissions']
            suite.go(other,'/watch/'+video_id,'app-watch-page')
            row=other['page'].locator('.comment-list > .comment-row').filter(has_text=text)
            expect(row).to_have_count(1)
            expect(row.locator('.is-danger')).to_have_count(0)
            suite.api(other,'delete','/comments/'+parent['commentId'],expected=403)
            suite.api(other,'patch','/comments/'+parent['commentId'],data={'content':'Forbidden edit '+suite.run_id},expected=403)
            items=suite.api(owner,'get',base+'/comments').json()['items']
            assert next(c for c in items if c['commentId']==parent['commentId'])['content']==text
            other['page'].reload(); expect(other['page'].locator('.comment-list > .comment-row').filter(has_text=text)).to_have_count(1)
            case['resource_ids']=[video_id,parent['commentId']]
            case['precondition']='Two different supplied user IDs; other identity is not channel owner and lacks channel comment.manage. Global Admin status is not used to assert ordinary Member RBAC.'
            case['steps']=['Read other actor channel permissions','Other identity can view public comment but has no delete control','Actual DELETE and PATCH on foreign comment → 403','Owner API and other reload → original text still exists']
        suite.case(other,'LIVE-X-COMMENT-ACCESS-01','U-WATCH.04','Other identity cannot delete/edit owner comment','Channel permission boundary is enforced for both UI and API using the two supplied identities',denied,module='watch')
        def threaded(case):
            if not parent:raise PrerequisiteMissing('Comment fixture was not created')
            suite.go(other,'/watch/'+video_id,'app-watch-page')
            page=other['page']; row=page.locator('.comment-list > .comment-row').filter(has_text=text)
            row.locator('.comment-actions > button').nth(2).click()
            row.locator('input[name=reply]').fill(reply_text)
            response=suite.response(other,base+'/comments',lambda:row.locator('.reply-composer button[type=submit]').click(),method='POST',status=201)
            reply.update(response.json()); persist_checkpoint()
            assert reply['parentCommentId']==parent['commentId'] and reply['userId']==other['identity']['userId']
            expect(row.locator('.comment-row--reply')).to_contain_text(reply_text)
            suite.evidence(other,case,'reply-created')
            page.reload(); row=page.locator('.comment-list > .comment-row').filter(has_text=text)
            # Watch loads and expands existing replies automatically. A blind
            # click here closes the thread and can match its in-flight eager GET.
            expect(row.locator('.comment-row--reply')).to_contain_text(reply_text)
            toggle=row.locator('.reply-toggle')
            expect(toggle).to_have_attribute('aria-expanded','true')
            toggle.click(); expect(toggle).to_have_attribute('aria-expanded','false')
            expect(row.locator('.comment-row--reply')).to_have_count(0)
            suite.evidence(other,case,'thread-collapsed')
            toggle.click(); expect(toggle).to_have_attribute('aria-expanded','true')
            expect(row.locator('.comment-row--reply')).to_contain_text(reply_text)
            replies=suite.api(other,'get','/comments/'+parent['commentId']+'/replies').json()['items']
            assert sum(c['commentId']==reply['commentId'] for c in replies)==1
            own_reply=row.locator('.comment-row--reply').filter(has_text=reply_text)
            page.once('dialog',lambda d:d.dismiss()); own_reply.locator('.is-danger').click()
            assert any(c['commentId']==reply['commentId'] for c in suite.api(other,'get','/comments/'+parent['commentId']+'/replies').json()['items'])
            page.once('dialog',lambda d:d.accept())
            suite.response(other,'/comments/'+reply['commentId'],lambda:own_reply.locator('.is-danger').click(),method='DELETE',status=204)
            assert not any(c['commentId']==reply['commentId'] for c in suite.api(other,'get','/comments/'+parent['commentId']+'/replies').json()['items'])
            assert any(c['commentId']==parent['commentId'] for c in suite.api(owner,'get',base+'/comments').json()['items'])
            case['resource_ids']=[video_id,parent['commentId'],reply['commentId']]
            case['steps']=['Other identity replies to owner comment through actual UI','Assert parent/author IDs and visible threaded text','Reload → expand replies → one persisted reply ID','Cancel delete leaves reply; confirm deletes only reply','Parent comment/source video remain']
        suite.case(other,'LIVE-COMMENT-REPLY-PERSIST-DELETE','U-WATCH.04','Threaded reply reload and cancel/confirm delete','Reply belongs to correct parent/author, persists, and deletion preserves the parent video/comment',threaded,module='watch')
    finally:
        for item,actor in [(reply,other),(parent,owner)]:
            if item:
                suite.api(actor,'delete','/comments/'+item['commentId'],expected=(204,404))
                suite.report['cleanup'].append({'resource':'new QC comment','id':item['commentId'],'status':'deleted-test-fixture'})
