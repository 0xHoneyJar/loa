#!/usr/bin/env python3
"""dispute-dump.py <fixture>: the A<->B group correspondence from agreed items, the disputes that need a
judgment (verdict / class / severity / category / a group the map does not explain) with both records,
and the AUTO list (anchors-only or namespace-only group disputes)."""
import json, collections, re, sys
fx=sys.argv[1]; O=f'grimoires/loa/a2a/sprint-269/annotation/{fx}'
A=json.load(open(O+'/A/labels.json')); B=json.load(open(O+'/B/labels.json')); K=json.load(open(O+'/merge/kappa.json'))
def rec(S,i): return (S['hunks'] if i.startswith('H') else S['incidents'])[i]
ids=list(A['hunks'])+list(A['incidents'])
pairs=collections.Counter()
for i in ids:
    a,b=rec(A,i),rec(B,i)
    if a.get('group') and b.get('group'): pairs[(a['group'],b['group'])]+=1
byB=collections.defaultdict(list)
for (ga,gb),n in pairs.items(): byB[gb].append((n,ga))
mapB={gb:sorted(l,reverse=True)[0][1] for gb,l in byB.items()}
print(f'##### {fx}: B->A map:', dict(sorted(mapB.items(), key=lambda x:int(x[0][1:]))))
print('A groups:', ' '.join(sorted({rec(A,i).get('group') for i in ids if rec(A,i).get('group')}, key=lambda g:int(g[1:]))))
kinds={}
for line in open(O+'/merge/adjudication.md'):
    m=re.match(r'^### (\w+): (.*)$', line.strip())
    if m: kinds[m.group(1)]=m.group(2)
auto=[]
for i in sorted(K['disagreement_ids'], key=lambda x:(x[0],int(x[1:]))):
    a,b=rec(A,i),rec(B,i); k=kinds[i]
    gm=(mapB.get(b.get('group'))==a.get('group')) if (a.get('group') and b.get('group')) else False
    if set(k.split(', '))<={'anchors','group'} and a['verdict']==b['verdict'] and a.get('not_defect_class')==b.get('not_defect_class') and gm:
        auto.append(i); continue
    print(f"\n== {i} [{k}] map(B {b.get('group')})->{mapB.get(b.get('group'))} vs A {a.get('group')}")
    for n,r in (('A',a),('B',b)):
        print(f"  {n}: {r['verdict']}/{r.get('not_defect_class') or '-'}/{r.get('group') or '-'}/{r.get('severity') or '-'}/{r.get('category') or '-'} :: {r.get('description','')[:160]}")
print('\nAUTO:', ' '.join(auto))
