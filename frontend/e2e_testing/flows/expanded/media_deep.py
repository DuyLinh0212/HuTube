from pathlib import Path
from urllib.parse import urlsplit
import json
import re
import shutil
import subprocess
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.live_adapter import FunctionalAdapter
from support.live_suite import PrerequisiteMissing
from flows.user import media
from flows.expanded.channels import png_bytes

def upload_fixture(suite,owner,member,label):
    cid=suite.fixtures['channel']['channelId']
    adapter=FunctionalAdapter(suite,'U-STUDIO.03',cid,prefix='FULL-'+label+'-')
    adapter.state['video_title']='QC '+label+' '+suite.run_id
    if label=='RESUME':adapter.state.update({'fixture_name':'resume-fixture.mp4','fixture_seconds':30})
    media.run(adapter,owner,member)
    if not adapter.state.get('video_id'):raise PrerequisiteMissing('Real upload did not create a fixture video for '+label)
    video=suite.api(owner,'get','/videos/'+adapter.state['video_id']).json()
    suite.fixtures.setdefault('videos',[]).append(video)
    return video

def submit_public(suite,owner,admin,video):
    suite.api(owner,'patch','/videos/'+video['videoId'],data={'visibility':'public'})
    queue=suite.api(admin,'get','/admin/moderation/queue',params={'page':1,'pageSize':100}).json()
    return next(item for item in queue if item['videoId']==video['videoId'])

def review_row(suite,reviewer,video,index):
    suite.go(reviewer,'/moderation/videos','app-admin-moderation-page','/admin/moderation/queue')
    reviewer['page'].locator('input[type=search]').fill(video['title'])
    reviewer['page'].locator('.status-tabs [role=tab]').nth(index).click()
    row=reviewer['page'].locator('.queue-table tbody tr').filter(has_text=video['videoId'][:8]);expect(row).to_have_count(1)
    return row

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    owner,member,admin=actors['owner'],actors['member'],actors['admin'];page=owner['page'];cid=suite.fixtures['channel']['channelId']
    for name,mime,data in [('empty.mp4','video/mp4',b''),('wrong.txt','text/plain',b'QC not video')]:
        def invalid(entry,name=name,mime=mime,data=data):
            suite.go(owner,'/studio/upload?channelId='+cid,'app-video-upload-wizard')
            before=sum(e['method']=='POST' and e['path']=='/api/v1/videos' for e in suite.report['http_statuses'])
            page.locator('#videoFile').set_input_files({'name':name,'mimeType':mime,'buffer':data})
            expect(page.locator('[role=alert]')).to_be_visible(timeout=45000)
            assert before==sum(e['method']=='POST' and e['path']=='/api/v1/videos' for e in suite.report['http_statuses'])
            entry['steps']=['Real browser file input '+name,'Visible file/preparation error','No upload POST or successful video checkpoint']
        case(suite,owner,'UPLOAD-INVALID-'+name.split('.')[0].upper(),'U-STUDIO.04','Invalid file cannot create video: '+name,invalid,'studio')
    def draft(entry):
        file=suite.run_dir/'draft-fixture.mp4'
        if not file.exists():
            subprocess.run([shutil.which('ffmpeg'),'-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','10','-c:v','libx264','-pix_fmt','yuv420p',str(file)],check=True,timeout=60)
        suite.go(owner,'/studio/upload?channelId='+cid,'app-video-upload-wizard');page.locator('#videoFile').set_input_files(str(file))
        expect(page.locator('.btn-wizard-next')).to_be_enabled(timeout=45000);page.locator('.btn-wizard-next').click();expect(page.locator('#videoTitle')).to_be_visible()
        title='QC draft metadata '+suite.run_id;page.locator('#videoTitle').fill(title);page.locator('#videoDesc').fill('Draft Unicode không upload lại file.')
        page.locator('#newTag').fill('qcdraft');page.locator('#newTag').press('Enter')
        page.locator('.btn-wizard-draft').click()
        stored=page.evaluate('()=>Object.entries(localStorage).filter(([k])=>k.startsWith("hutube.upload.draft.")).map(([k,v])=>JSON.parse(v))')
        assert any(d['videoTitle']==title for d in stored)
        def feedback(child):
            expect(page.locator('app-video-upload-wizard [role=alert],app-video-upload-wizard [role=status]').first).to_be_visible()
            child['steps']=['Save draft at details step','Visible confirmation at the current wizard step']
        case(suite,owner,'UPLOAD-DRAFT-SAVE-FEEDBACK','U-STUDIO.03','Draft save provides visible confirmation',feedback,'studio')
        page.reload();expect(page.locator('.file-name')).to_have_count(0)
        page.locator('#videoFile').set_input_files(str(file));expect(page.locator('.btn-wizard-next')).to_be_enabled(timeout=45000);page.locator('.btn-wizard-next').click()
        expect(page.locator('#videoTitle')).to_have_value(title);expect(page.locator('#videoDesc')).to_have_value('Draft Unicode không upload lại file.')
        page.locator('#thumbnailFile').set_input_files({'name':'qc-thumbnail.png','mimeType':'image/png','buffer':png_bytes()})
        page.locator('.btn-wizard-next').click()
        page.locator('.add-chapter-row input').nth(0).fill('Outside video');page.locator('.add-chapter-row .time-input').fill('99:00');page.locator('.btn-add-ch').first.click()
        expect(page.locator('.chapters-table')).not_to_contain_text('Outside video')
        def chapter_feedback(child):
            expect(page.locator('app-video-upload-wizard [role=alert]')).to_be_visible()
            child['steps']=['Attempt out-of-duration chapter','Error feedback visible next to current step/field']
        case(suite,owner,'UPLOAD-CHAPTER-ERROR-FEEDBACK','U-STUDIO.02','Invalid chapter has visible field error',chapter_feedback,'studio')
        entry['steps']=['Actual file metadata/quota preflight → details','Save title/description/tag draft','Reload clears browser file but restores metadata after reselect','Actual PNG thumbnail input','Out-of-duration chapter rejected']
    case(suite,owner,'UPLOAD-DRAFT-THUMBNAIL-CHAPTER','U-STUDIO.02','Draft persistence, file reselect and chapter boundary',draft,'studio')
    if config.get('fix17_draft_only'):return
    video=upload_fixture(suite,owner,member,'MEDIA');suite.fixtures['video']=video
    reviewer=actors['reviewer1'];pending=submit_public(suite,owner,admin,video);suite.fixtures['video_case']=pending
    def approve(entry):
        row=review_row(suite,reviewer,video,0);mid=pending['moderationCaseId']
        suite.response(reviewer,'/admin/moderation/'+mid+'/claim',lambda:row.locator('.table-action.primary').click(),method='POST')
        conflict=suite.api(actors['reviewer2'],'post','/admin/moderation/'+mid+'/claim',data={},expected=409);assert conflict.json()['code']=='CASE_ALREADY_CLAIMED'
        row=review_row(suite,reviewer,video,1);row.locator('.table-action:not(.subtle)').first.click()
        reviewer['page'].locator('.decision-column input[type=text]').fill('QC primary fixture approval')
        suite.response(reviewer,'/admin/moderation/'+mid+'/resolve',lambda:reviewer['page'].locator('.decision-button.approve').click(),method='POST')
        assert suite.api(owner,'get','/videos/'+video['videoId']).json()['moderationStatus']=='approved'
        suite.api(member,'get','/videos/'+video['videoId']+'/playback')
        entry['resource_ids']=[video['videoId'],mid];entry['steps']=['Reviewer1 UI claims exact pending fixture','Separate Reviewer2 claim conflicts with 409','Reviewer1 UI approves with reason','Owner approved; ordinary Member gets actual playback']
    case(suite,reviewer,'REVIEWER-CLAIM-CONFLICT-APPROVE','A-MODERATION.01','Independent reviewers cannot overwrite claim',approve,'moderation')
    def qualities_fullscreen(entry):
        suite.go(member,'/watch/'+video['videoId'],'app-watch-page');p=member['page'];player=p.locator('video').first
        p.wait_for_function('()=>document.querySelector("video")?.readyState>=1')
        renditions=suite.api(member,'get','/videos/'+video['videoId']+'/playback').json()['renditions']
        select=p.locator('.player-quality-option select')
        for rendition in renditions:
            select.select_option(rendition['quality']);p.wait_for_function('()=>document.querySelector("video")?.readyState>=1');expect(select).to_have_value(rendition['quality'])
            assert player.evaluate('(v)=>v.videoWidth>0')
        player.hover();p.locator('.player-fullscreen-button').click();p.wait_for_function('()=>!!document.fullscreenElement')
        player.hover();p.locator('.player-fullscreen-button').click();p.wait_for_function('()=>!document.fullscreenElement')
        entry['steps']=['Select every actual rendition through UI','Browser decodes each selected stream','UI fullscreen sets actual fullscreenElement','Actual fullscreen button exits; native Windows Escape is certified separately in native_escape, not by DOM keyboard dispatch']
    case(suite,member,'WATCH-QUALITIES-FULLSCREEN','U-WATCH.01','Actual renditions and fullscreen state',qualities_fullscreen,'watch')
    resume_video=upload_fixture(suite,owner,member,'RESUME')
    resume_case=submit_public(suite,owner,admin,resume_video)
    suite.api(reviewer,'post','/admin/moderation/'+resume_case['moderationCaseId']+'/claim',data={})
    suite.api(reviewer,'post','/admin/moderation/'+resume_case['moderationCaseId']+'/resolve',data={'decision':'approve','reason':'Owned thirty-second resume fixture preparation'})
    def resume(entry):
        suite.go(member,'/watch/'+resume_video['videoId'],'app-watch-page');p=member['page'];v=p.locator('video').first
        p.wait_for_function('()=>document.querySelector("video")?.readyState>=2')
        if v.evaluate('(v)=>v.paused'):p.locator('.player-big-play').click()
        p.wait_for_function('()=>!document.querySelector("video").paused')
        v.hover();p.locator('.player-control-group').first.locator('button').first.click()
        p.wait_for_function('()=>document.querySelector("video").paused')
        p.locator('.player-progress').fill('0');p.wait_for_timeout(250)
        suite.response(member,'/videos/'+resume_video['videoId']+'/watch-progress',lambda:p.locator('.player-progress').fill('11'),method='PUT')
        p.wait_for_function('()=>Math.abs(document.querySelector("video").currentTime-11)<0.5')
        if v.evaluate('(v)=>v.paused'):p.locator('.player-big-play').click()
        p.wait_for_function('()=>document.querySelector("video").currentTime>12',timeout=15000)
        v.hover();p.locator('.player-control-group').first.locator('button').first.click();assert v.evaluate('(v)=>v.paused')
        p.wait_for_timeout(1500)
        history=suite.api(member,'get','/library/history',params={'page':1,'pageSize':50}).json()
        item=next(v for v in history['items'] if v['videoId']==resume_video['videoId'])
        assert 10<=item['watchedSeconds']<27,'Resume checkpoint must exceed ten-second save interval and remain unfinished'
        suite.go(member,'/history','app-library-page')
        expect(p.locator('a[href="/watch/'+resume_video['videoId']+'"]').first).to_be_visible()
        suite.go(member,'/watch/'+resume_video['videoId'],'app-watch-page')
        p.wait_for_function('()=>document.querySelector("video")?.readyState>=1')
        p.wait_for_function('()=>document.querySelector("video").currentTime>0',timeout=10000)
        assert p.locator('video').first.evaluate('(v)=>v.currentTime')>=item['watchedSeconds']-1,'Returning to video did not resume saved progress'
        entry['resource_ids']=[resume_video['videoId']];entry['steps']=['Actual thirty-second Member playback','Seek beyond ten-second save interval → real progress POST','History UI contains exact ID and unfinished checkpoint','Reopen watch → currentTime resumes from saved progress']
    case(suite,member,'WATCH-HISTORY-RESUME','U-WATCH.02','Playback checkpoint and resume',resume,'watch')
    def discovery(entry):
        guest=suite.actor('home-guest','user','guest');guest['api_url']=config['api_url']
        result=suite.go(guest,'/home','app-home-page','/feed/home')
        ids=[item['videoId'] for item in result['items']];assert video['videoId'] in ids
        assert all(v.get('visibility','public')=='public' for v in result['items'])
        link=guest['page'].locator('a[href="/watch/'+video['videoId']+'"]').first;expect(link).to_be_visible();link.click();expect(guest['page'].locator('app-watch-page')).to_be_visible();guest['page'].go_back();expect(guest['page'].locator('app-home-page')).to_be_visible()
        suite.evidence(guest,entry,'home-fallback')
        entry['resource_ids']=[video['videoId']];entry['steps']=['Real recommendation-disabled fallback contains actual eligible public video','Guest UI opens same watch ID','Back restores Home; no private source leaks']
    case(suite,member,'HOME-FALLBACK-ELIGIBLE','U-DISCOVERY.01','Anonymous fallback uses actual eligible data',discovery,'discovery')
    from flows.user.live_comment_ownership import run as comments
    comments(suite,owner,member)
