import re, json, os, glob
from schema import COLS
import pathlib
ROOT=str(pathlib.Path(__file__).resolve().parents[2]/'lib')
# Which live tables each file's row maps come from (repos/models/screens that read Supabase rows).
FILE_TABLES = {
 'features/projects/models/investor_unit.dart':['investor_units','projects'],
 'features/projects/models/marketplace_project.dart':['projects'],
 'features/projects/models/project_phase.dart':['project_phases'],
 'features/projects/models/project.dart':['projects'],
 'features/projects/models/project_update.dart':['project_updates'],
 'features/financials/models/payout.dart':['payouts','projects'],
 'features/profile/kyc_screen.dart':['investors'],
 'features/profile/bank_details_screen.dart':['investors','bank_change_requests'],
 'features/profile/privacy_screen.dart':['nominees'],
 'features/profile/security_screen.dart':['login_events','user_settings'],
 'features/home/models/portfolio_summary.dart':['rpc:get_portfolio_summary'],
 'features/activity/models/notification.dart':['notifications'],
 'features/documents/models/project_document.dart':['project_documents'],
 'features/documents/models/document.dart':['documents','projects'],
 'features/gallery/models/gallery_photo.dart':['gallery_photos','projects'],
 'features/support/ticket_detail_screen.dart':['support_tickets','ticket_messages'],
 'features/exit/exit_screen.dart':['investor_units','exit_requests'],
 'core/repositories/documents_repository.dart':['documents','project_documents'],
 'core/repositories/gallery_repository.dart':['gallery_photos'],
 'core/repositories/user_settings_repository.dart':['user_settings','consents'],
 'core/repositories/projects_repository.dart':['projects','investor_units','project_phases','project_updates'],
 'core/repositories/financials_repository.dart':['payouts','projects'],
 'features/home/home_provider.dart':['investors'],
}
SKIP_VARS={'json','q','params','query','extra','queryParameters','config','metadata','m2','meta'}
pat=re.compile(r"\b([a-zA-Z_]\w*)\[\s*'([a-z_0-9]+)'\s*\]")
refs=[]
for rel,tables in FILE_TABLES.items():
    p=os.path.join(ROOT,rel)
    lines=open(p).read().split('\n')
    for i,l in enumerate(lines):
        for m in pat.finditer(l):
            var,key=m.group(1),m.group(2)
            if var in SKIP_VARS: continue
            if key in [t for t in COLS] : kind='embed'   # r['projects'] = joined table
            else: kind='col'
            fm=re.search(r"\b(\w+)\s*:\s*[^,]*"+re.escape(m.group(0)), l)
            ctx='\n'.join(lines[max(0,i-2):i+3])
            refs.append(dict(file=rel,line=i+1,var=var,key=key,kind=kind,dart_field=fm.group(1) if fm else None,code=ctx,tables=tables))
# dedupe same file+key+field
seen=set(); out=[]
for r in refs:
    k=(r['file'],r['key'],r['dart_field'])
    if k in seen: continue
    seen.add(k); out.append(r)
for r in out:
    cols={f"{t}.{c}" for t in r['tables'] for c,_,_ in COLS[t]}
    r['exact']=[f"{t}.{r['key']}" for t in r['tables'] if any(c==r['key'] for c,_,_ in COLS[t])]
json.dump(out,open(pathlib.Path(__file__).with_name('refs.json'),'w'),indent=1)
col=[r for r in out if r['kind']=='col']
print(len(out),'refs;',sum(1 for r in col if not r['exact']),'keys with no exact column;',sum(1 for r in col if r['exact'] and r['dart_field']),'exact with a Dart field')
for r in col:
    if not r['exact']: print('  missing:',r['file'].split('/')[-1],r['line'],r['var']+"['"+r['key']+"']")
