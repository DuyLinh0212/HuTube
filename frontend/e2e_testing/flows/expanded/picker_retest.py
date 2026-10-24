from flows.expanded.common import snapshot_module
from support.live_adapter import FunctionalAdapter
from flows.user import playlist_items

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner,member=actors['owner'],actors['member']
    fixture=suite.api(owner,'post','/playlists',data={'name':'QC empty picker fixture '+suite.run_id,'description':'Separate from multi-item autoplay queue','visibility':'private'},expected=(200,201)).json();pid=fixture['playlistId']
    adapter=FunctionalAdapter(suite,'U-PLAYLIST.02',suite.fixtures['channel']['channelId'],prefix='FULL-FOUNDATION-FULL-PICKER-');adapter.state.update({'playlist_id':pid,'video_id':suite.fixtures['video']['videoId']})
    try:
        snapshot_module(suite,playlist_items.__file__);playlist_items.run(adapter,owner,member)
    finally:suite.api(owner,'delete','/playlists/'+pid,expected=(200,204))
