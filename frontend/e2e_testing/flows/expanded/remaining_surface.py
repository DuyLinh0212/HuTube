"""Uncovered checklist clauses, including explicit missing-feature failures."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.actor_readiness import ensure_actor_pages

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    ensure_actor_pages(suite,actors,['owner','member'])
    owner,member=actors['owner'],actors['member'];p=owner['page'];created=[]
    vid=suite.fixtures['video']['videoId']
    # These exact synthetic names were created by an earlier test attempt whose
    # wrong expected status interrupted ID tracking. Never sweep user playlists.
    abandoned={prefix+' '+run for prefix in ['QC delete target','QC retained control']
        for run in ['20261016T050700.992424Z','20261016T050737.075162Z']}
    for item in suite.api(owner,'get','/playlists').json():
        if item['name'] in abandoned:
            suite.api(owner,'delete','/playlists/'+item['playlistId'],expected=204)
            suite.api(owner,'get','/playlists/'+item['playlistId'],expected=404)
            suite.report['cleanup'].append({'resource':'exact synthetic playlist from interrupted fixture preparation','id':item['playlistId'],'status':'deleted through owner API'})
    def disposable(name):
        result=suite.api(owner,'post','/playlists',data={'name':name+' '+suite.run_id,'description':'Owned disposable checklist fixture','visibility':'private'},expected=200).json()
        created.append(result['playlistId']);return result['playlistId']
    try:
        def delete(entry):
            target=disposable('QC delete target');kept=disposable('QC retained control')
            path='/playlists/'+target
            entry['resource_ids']=[target,kept,vid]
            entry['steps']=['Create two disposable private playlists through actual API','Add real source video to target','Open actual edit dialog and cancel deletion','Confirm deletion; reload and verify target gone, other playlist and video retained']
            suite.api(owner,'post',path+'/videos',data={'videoId':vid},expected=(200,201))
            suite.go(owner,path,'app-playlists-page',path)
            p.locator('.title-edit-button').click()
            expect(p.locator('.playlist-modal--edit')).to_be_visible()
            p.once('dialog',lambda dialog:dialog.dismiss())
            p.locator('.text-danger-button').click()
            assert suite.api(owner,'get',path).json()['playlistId']==target
            suite.evidence(owner,entry,'delete-cancel-retains-playlist')
            p.once('dialog',lambda dialog:dialog.accept())
            response=suite.response(owner,path,lambda:p.locator('.text-danger-button').click(),method='DELETE',status=(200,204))
            assert response.status in (200,204)
            expect(p).to_have_url(re.compile(r'/playlists$'))
            suite.api(owner,'get',path,expected=404)
            assert suite.api(owner,'get','/playlists/'+kept).json()['playlistId']==kept
            assert suite.api(owner,'get','/videos/'+vid).json()['videoId']==vid
            p.reload();expect(p.locator('a.playlist-card[href="'+path+'"]')).to_have_count(0)
            expect(p.locator('a.playlist-card[href="/playlists/'+kept+'"]')).to_be_visible()
            entry['resource_ids']=[target,kept,vid]
            entry['steps']=['Create two disposable private playlists through actual API','Add real source video to target','Actual delete confirmation cancelled; target survives API read','Actual confirmation accepted; target 404 after reload','Second playlist and source video remain unchanged']
        case(suite,owner,'PLAYLIST-DELETE-CANCEL-CONFIRM-SOURCE-SAFE','U-PLAYLIST.04','Delete only the confirmed disposable playlist',delete,'playlists')
        if config.get('surface_delete_only'):
            suite.report.setdefault('group_skips',[]).append({'group':'remaining-surface','reason':'Only supported delete flow rerun. Missing playlist/history filter operations remain FAIL in their original UI evidence; no synthetic PASS.'})
            return
        def playlist_filter(entry):
            suite.go(owner,'/playlists','app-playlists-page','/playlists')
            entry['steps']=['Load actual owner playlist collection','Inspect the list area, excluding the create form','Checklist requires filtering the collection; global video search does not filter playlists']
            suite.evidence(owner,entry,'playlist-list-controls')
            controls=p.locator('.library-main input,.library-main select,.library-main [role=searchbox]')
            entry['observed_list_filter_controls']=controls.count()
            assert controls.count()>0,'U-PLAYLIST.04: playlist collection has no filter control; only the separate create form and global video search exist'
        case(suite,owner,'PLAYLIST-LIST-FILTER-CONTRACT','U-PLAYLIST.04','Owner can filter the playlist collection',playlist_filter,'playlists')
        def history_filter(entry):
            suite.go(owner,'/history','app-library-page')
            expect(p.locator('.library-page [aria-busy=true]')).to_have_count(0)
            entry['steps']=['Load actual authenticated watch history','Inspect controls inside history component, excluding global search','Checklist requires history search/sort/filter as well as pagination']
            suite.evidence(owner,entry,'history-controls')
            entry['observed_history_inputs']=p.locator('.library-page input,.library-page select,.library-page button').count()
            assert entry['observed_history_inputs']>0,'U-LIBRARY.01: history has no search, sort or filter controls; grouped infinite scrolling does not execute those required clauses'
        case(suite,owner,'HISTORY-SEARCH-SORT-FILTER-CONTRACT','U-LIBRARY.01','History exposes its required search, sort and filter operations',history_filter,'library')
    finally:
        for pid in created:
            existing=suite.api(owner,'get','/playlists').json()
            if any(item['playlistId']==pid for item in existing):
                suite.api(owner,'delete','/playlists/'+pid,expected=204)
            suite.api(owner,'get','/playlists/'+pid,expected=404)
