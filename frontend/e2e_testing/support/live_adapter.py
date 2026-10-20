"""Execute existing mutation assertions afresh with uniquely named live fixtures.

No fixture reuse, role elevation or synthetic Member identity is accepted.
"""
import json
from support.live_suite import PrerequisiteMissing

class FunctionalAdapter:
    def __init__(self,suite,parent,channel_id=None,prefix='LIVE-'):
        self.suite=suite
        self.parent=parent
        self.state={}
        self.run_dir=suite.run_dir
        self.channel_id=channel_id
        self.prefix=prefix
        self.config={'state_dir':str(suite.run_dir),'api_url':suite.actors['owner']['api_url']}

    def api(self,actor,method,path,**kwargs):
        return self.suite.api(actor,method,path,expected=(200,201,204,400,401,403,404,409,422,503),**kwargs)

    def go(self,actor,route,selector):
        if route.startswith('/studio/') and self.channel_id:
            route+='?channelId='+self.channel_id
        return self.suite.go(actor,route,selector)

    def save(self):
        (self.suite.run_dir/('fixture-'+self.parent+'.json')).write_text(json.dumps(self.state),encoding='utf-8')

    def evidence(self,actor,step):
        self.suite.evidence(actor,self.current_case,step)

    def case(self,actor,case_id,name,action,expected='',module=None,**kwargs):
        if case_id=='X-COMMENT-ACCESS-01' and getattr(self.suite,'skip_legacy_comment_denial',False):
            return False  # The explicit public-channel journey records this ID.
        if case_id=='X-COMMENT-ACCESS-01':
            name='Other supplied identity cannot delete the owner comment; channel permission boundary'
        def execute(case):
            self.current_case=case
            if actor.get('identity',{}).get('isAdmin') and case_id!='X-COMMENT-ACCESS-01' and (module=='access' or case_id.startswith('X-') and 'ACCESS' in case_id):
                raise PrerequisiteMissing('Both supplied accounts have admin privileges; a distinct Member was not supplied. This denial branch is not executed.')
            if actor['page'].url=='about:blank':
                route,selector='/account','app-account-page'
                self.suite.go(actor,route,selector,'/account/profile' if actor['application']=='user' else '/auth/sessions')
                case['evidence_context']='API assertion with authenticated '+route+' as viewport context; not a claim about the layout of an Admin-denial page'
            result=action()
            assert result!='reused','Fixture reuse is not live functional coverage'
            case['steps']=[name,'Execute source UI/API assertions afresh','Capture desktop/mobile/tablet']
            case['resource_ids']=[value for key,value in self.state.items() if key.endswith('_id') and isinstance(value,str)]
            case['implementation']={'file':action.__code__.co_filename,'line':action.__code__.co_firstlineno}
            if case_id=='U-WATCH-PLAYBACK-01' and self.state.get('audio_control_branch'):
                case['audio_control_branch']=self.state['audio_control_branch']
        return self.suite.case(actor,self.prefix+case_id,self.parent,name,expected,execute,module=module or self.parent.lower())

    def blocked(self,actor,case_id,name,reason):
        def missing(case):
            raise PrerequisiteMissing(reason)
        return self.suite.case(actor,self.prefix+case_id,self.parent,name,'Prerequisites available',missing)
