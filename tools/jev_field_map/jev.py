import json, os, sys, time, urllib.request, concurrent.futures as cf
from schema import COLS
KEY=os.environ['TYPESAFE_API_KEY']
def call(state, questions):
    body=json.dumps({"model":"jev-latest","state":state,"questions":questions}).encode()
    for attempt in range(5):
        req=urllib.request.Request("https://api.typesafe.ai/v1/systemone",data=body,headers={"Authorization":"Bearer "+KEY,"Content-Type":"application/json"})
        try:
            with urllib.request.urlopen(req,timeout=120) as r: return json.load(r)
        except urllib.error.HTTPError as e:
            msg=e.read().decode()[:600]
            if e.code in (429,529): time.sleep(2**attempt); continue
            raise RuntimeError(f"{e.code} {msg}")
    raise RuntimeError("retries exhausted")

def build(file, refs):
    tables=sorted({t for r in refs for t in r['tables']})
    state={"app":"Growize investor app (Flutter) reading rows returned by Supabase/PostgREST",
           "file":file,
           "live_tables":{t:[f"{c} ({ty}{', not null' if nn else ''})" for c,ty,nn in COLS[t]] for t in tables},
           "refs":[{"key_read":r['key'],"dart_field":r['dart_field'],"code":r['code']} for r in refs]}
    qs={}
    for i,r in enumerate(refs):
        if r['exact']:
            col=r['exact'][0]
            qs[f"fit{i}"]={"type":"noul",
              "instructions":f"In `refs[{i}]`, the app reads live column `{col}` and uses it as `refs[{i}].dart_field` (or as shown in `refs[{i}].code`). Judge whether the column's meaning matches how the app uses it — e.g. a column named `tier` feeding a field called `cropType` is a mismatch, while `payout_date` feeding `date` is a match.",
              "criteria":{"true":"The column holds the kind of value the app treats it as.","false":"The column holds a different kind of value than the app treats it as, so the screen would show the wrong thing."}}
        else:
            opts={f"{t}.{c}":f"{ty}" for t in r['tables'] for c,ty,_ in COLS[t]}
            opts["derived_or_nested"]="The key is not a table column: it is a nested JSON sub-field, an app-computed/synthetic key, or a field of a joined object."
            opts["none"]="It is meant to be a real column of these tables, but no live column carries this value (the column is missing)."
            qs[f"map{i}"]={"type":"choice",
              "instructions":f"In `refs[{i}]` the app reads key `refs[{i}].key_read`, which does NOT exist as a column in `live_tables`. Which live column does the code actually intend to read?",
              "criteria":opts}
    return state,qs

refs=json.load(open('refs.json'))
refs=[r for r in refs if r['kind']=='col']
byfile={}
for r in refs: byfile.setdefault(r['file'],[]).append(r)
only=sys.argv[1] if len(sys.argv)>1 else None
jobs=[]
for f,rs in byfile.items():
    if only and only not in f: continue
    for k in range(0,len(rs),12): jobs.append((f,rs[k:k+12]))
results=[]; usage=[0,0]
def run(job):
    f,rs=job; st,qs=build(f,rs); res=call(st,qs); return f,rs,res
with cf.ThreadPoolExecutor(4) as ex:
    for f,rs,res in ex.map(run,jobs):
        usage[0]+=res['usage']['input_tokens']; usage[1]+=res['usage']['output_tokens']
        for i,r in enumerate(rs):
            a=res['answers'].get(f"fit{i}") or res['answers'].get(f"map{i}")
            results.append({**{k:r[k] for k in ('file','line','key','dart_field','exact')},"answer":a})
json.dump(results,open('results.json' if not only else 'results_test.json','w'),indent=1)
print(len(results),'answers; model',res.get('model'),'usage',usage)
