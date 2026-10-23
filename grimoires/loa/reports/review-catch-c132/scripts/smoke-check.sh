#!/usr/bin/env bash
# smoke-check.sh — summarise the smoke rows (batches c132-smoke2 and c132-smoke3) per task: a1_full validity fields, costs, and the
# realized cost ratio full/bare beside the registered k (PREREGISTRATION §11: the ratio is recorded and never changes k).
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa
python3 -I - evals/results/ablation-2.0/runs.jsonl <<'PY'
import json, sys, re, os
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
smoke=[r for r in rows if r.get('batch') in ('c132-smoke2','c132-smoke3')]
k={}
for t in sorted(os.listdir('grimoires/loa/evals/ablation-2.0-c132/tasks')):
    y=open(f'grimoires/loa/evals/ablation-2.0-c132/tasks/{t}/task.yaml').read()
    m=re.search(r'bare_sessions_matched: (\d+)', y); k[t]=int(m.group(1)) if m else None
by={}
for r in smoke:
    by.setdefault(r['task_id'],{}).setdefault(r['arm'],[]).append(r)
print('| task | k | a1_full status | recall_pm3 | dissent rev/aud dp | oracle_closed | contaminated | USD full | a0_bare status | recall_pm3 | USD bare | ratio |')
print('|---|---|---|---|---|---|---|---|---|---|---|---|')
def g(r,key,default='—'):
    return r.get(key, default) if r else '—'
for t in sorted(by):
    fulls=by[t].get('a1_full',[]); bares=by[t].get('a0_bare',[])
    f=sorted(fulls, key=lambda r:(r.get('status')!='completed', r.get('started','')))[0] if fulls else None
    b=sorted(bares, key=lambda r:(r.get('status')!='completed', r.get('started','')))[0] if bares else None
    te=(f or {}).get('took_effect') or {}
    dis=(f or {}).get('dissent_absent_reason') or {}
    cont=(f or {}).get('contaminated')
    cont_s='—' if f is None else ('null' if cont is None else f"{cont.get('pattern')}{' (repo)' if cont.get('repo_named') else ''}")
    ratio=(f['cost_usd']/b['cost_usd']) if (f and b and b.get('cost_usd')) else None
    print(f"| {t} | {k.get(t)} | {g(f,'status')} | {g(f,'defect_catch_rate_pm3')} | {dis.get('review','—')}/{dis.get('audit','—')} dp={te.get('dissent_present','—')} | {te.get('oracle_closed','—')} | {cont_s} | {g(f,'cost_usd')} | {g(b,'status')} | {g(b,'defect_catch_rate_pm3')} | {g(b,'cost_usd')} | {('%.1f' % ratio) if ratio else '—'} |")
n_full=sum(1 for r in smoke if r['arm']=='a1_full' and r.get('status')=='completed')
n_bare=sum(1 for r in smoke if r['arm']=='a0_bare' and r.get('status')=='completed')
spend=sum((r.get('all_spend_usd') or r.get('cost_usd') or 0) for r in smoke)
print(f"\nrows: {len(smoke)}; a1_full completed {n_full}, a0_bare completed {n_bare}; smoke spend USD {spend:.2f}")
PY
