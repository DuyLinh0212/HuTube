from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    from support.actor_cleanup import close_finished_auth_tabs
    close_finished_auth_tabs(suite)
    from flows.expanded.branding_boundaries import run as branding_boundaries
    branding_boundaries(suite,config,actors)
    snapshot_module(suite,__file__)
    owner,member=actors['owner'],actors['member'];cid=suite.fixtures['channel']['channelId'];video=suite.fixtures['video'];vid=video['videoId'];base='/videos/'+vid+'/comments'
    fixtures=[];text='QC Studio comments '+suite.run_id
    def create(entry):
        suite.go(member,'/watch/'+vid,'app-watch-page');p=member['page']
        p.locator('textarea[name=comment]').fill(text)
        result=suite.response(member,base,lambda:p.locator('.comment-composer button[type=submit]').click(),method='POST',status=201).json();fixtures.append(result)
        assert result['userId']==member['identity']['userId']
        suite.go(owner,'/studio/comments?channelId='+cid,'app-studio-comments-page','/channels/'+cid+'/comments/manage')
        expect(owner['page'].locator('.comment-card').filter(has_text=text)).to_have_count(1)
        entry['steps']=['Independent Member creates comment through Watch UI','Owner Studio inventory contains exact text and API ID']
    case(suite,member,'STUDIO-COMMENT-INVENTORY','U-STUDIO.08','Watch comment appears in owner Studio',create,'comments')
    if not fixtures:raise PrerequisiteMissing('Studio comment fixture missing')
    comment=fixtures[0];path='/comments/'+comment['commentId'];p=owner['page']
    def studio():
        suite.go(owner,'/studio/comments?channelId='+cid,'app-studio-comments-page','/channels/'+cid+'/comments/manage')
        return p.locator('.comment-card').filter(has_text=text)
    try:
        for sort in ['newest','oldest','mostLiked']:
            def sorting(entry,sort=sort):
                studio()
                control=p.locator('.sort-control select')
                if control.input_value()==sort:
                    suite.response(owner,'/channels/'+cid+'/comments/manage',lambda:control.select_option('oldest' if sort=='newest' else 'newest'))
                data=suite.response(owner,'/channels/'+cid+'/comments/manage',lambda:p.locator('.sort-control select').select_option(sort)).json()
                expect(p.locator('.sort-control select')).to_have_value(sort)
                for item in data['items']:
                    expect(p.locator('.comment-text').filter(has_text=__import__('re').compile('^'+__import__('re').escape(item['content'])+'$'))).to_have_count(1)
                entry['steps']=['Select '+sort+' through actual UI','Compare every rendered comment against real sorted response']
            case(suite,owner,'STUDIO-COMMENTS-SORT-'+sort.upper(),'U-STUDIO.08','Studio comment sort '+sort,sorting,'comments')
        def reply(entry):
            row=studio();row.locator('.action-reply').click();expect(row.locator('.send-reply')).to_be_disabled();row.locator('textarea[name=reply]').fill('Cancel this reply');row.locator('.action-reply').click();expect(row.locator('.reply-form')).to_have_count(0)
            row.locator('.action-reply').click();expect(row.locator('textarea')).to_have_value('');row.locator('textarea').fill('Owner Studio reply '+suite.run_id)
            result=suite.response(owner,base,lambda:row.locator('.send-reply').click(),method='POST',status=201).json();fixtures.append(result)
            assert result['parentCommentId']==comment['commentId']
            assert any(r['commentId']==result['commentId'] for r in suite.api(member,'get',path+'/replies').json()['items'])
            entry['steps']=['Empty reply disabled','Cancel clears unsent draft','Actual Studio reply persists with original parent ID']
        case(suite,owner,'STUDIO-COMMENTS-REPLY-CANCEL','U-STUDIO.08','Studio reply, cancel and persistence',reply,'comments')
        def visibility(entry):
            row=studio();suite.response(owner,path+'/visibility',lambda:row.locator('.action-visibility').click(),method='PATCH')
            assert not any(c['commentId']==comment['commentId'] for c in suite.api(member,'get',base).json()['items'])
            suite.response(owner,'/channels/'+cid+'/comments/manage',lambda:p.locator('.status-tabs button').nth(1).click())
            row=p.locator('.comment-card').filter(has_text=text);expect(row).to_have_count(1)
            suite.api(member,'patch',path+'/visibility',data={'hidden':False},expected=403)
            suite.response(owner,path+'/visibility',lambda:row.locator('.action-visibility').click(),method='PATCH')
            assert any(c['commentId']==comment['commentId'] for c in suite.api(member,'get',base).json()['items']),'Studio deleted the comment immediately; no confirmation/cancel step was offered'
            entry['steps']=['Owner hides actual Member comment through Studio','Public comment API excludes hidden ID','Hidden tab retains record','Member cannot unhide; Owner UI restores visibility']
        case(suite,owner,'STUDIO-COMMENTS-HIDE-RESTORE','U-STUDIO.08','Hidden comment enforcement across actors',visibility,'comments')
        def edit_ui(entry):
            suite.go(member,'/watch/'+vid,'app-watch-page');row=member['page'].locator('.comment-list > .comment-row').filter(has_text=text)
            expect(row.get_by_role('button',name=__import__('re').compile('Edit|Chỉnh sửa|Sửa',__import__('re').I))).to_be_visible()
            q=member['page'];button=row.get_by_role('button',name=__import__('re').compile('Edit|Chỉnh sửa|Sửa',__import__('re').I))
            button.click();form=q.locator('.comment-edit-form');form.locator('textarea').fill('Cancelled edit')
            form.get_by_role('button',name=__import__('re').compile('Cancel|Hủy')).click()
            assert next(c for c in suite.api(member,'get',base).json()['items'] if c['commentId']==comment['commentId'])['content']==text
            button.click();form.locator('textarea').fill('');expect(form.locator('button[type=submit]')).to_be_disabled()
            changed=text+' — edited';form.locator('textarea').fill(changed)
            suite.response(member,path,lambda:form.locator('button[type=submit]').click(),method='PATCH')
            q.reload();expect(q.locator('.comment-list > .comment-row').filter(has_text=changed)).to_have_count(1)
            assert next(c for c in suite.api(member,'get',base).json()['items'] if c['commentId']==comment['commentId'])['content']==changed
            suite.api(actors['target'],'patch',path,data={'content':'Foreign overwrite'},expected=(403,404))
            # Restore via author UI so later moderation cases retain their exact fixture text.
            row=q.locator('.comment-list > .comment-row').filter(has_text=changed);row.get_by_role('button',name=__import__('re').compile('Edit|Chỉnh sửa|Sửa',__import__('re').I)).click()
            q.locator('.comment-edit-form textarea[name=commentEdit]').fill(text);suite.response(member,path,lambda:q.locator('.comment-edit-form button[type=submit]').click(),method='PATCH')
            entry['resource_ids']=[comment['commentId']]
            entry['steps']=['Author opens actual edit UI','Cancel leaves persisted content unchanged','Empty edit cannot save','Save PATCH persists; reload shows edited content','Other Member cannot overwrite author comment','Restore original text through author UI']
        case(suite,member,'WATCH-COMMENT-AUTHOR-EDIT-UI','U-WATCH.04','Author can open comment edit UI',edit_ui,'comments')
        def delete(entry):
            row=studio();p.once('dialog',lambda d:d.dismiss());row.locator('.action-delete').click()
            assert any(c['commentId']==comment['commentId'] for c in suite.api(member,'get',base).json()['items'])
            p.once('dialog',lambda d:d.accept());suite.response(owner,path,lambda:row.locator('.action-delete').click(),method='DELETE',status=204)
            assert not any(c['commentId']==comment['commentId'] for c in suite.api(member,'get',base).json()['items'])
            p.reload();expect(p.locator('.comment-card').filter(has_text=text)).to_have_count(0)
            entry['steps']=['Cancel owner moderation delete leaves comment','Confirm deletes actual comment','Public API and Studio reload exclude deleted ID']
        case(suite,owner,'STUDIO-COMMENTS-DELETE-CANCEL-CONFIRM','U-STUDIO.08','Owner delete cancellation and persistence',delete,'comments')
    finally:
        for item in reversed(fixtures):
            suite.api(owner,'delete','/comments/'+item['commentId'],expected=(204,404))
