# ZalupaGram: rough check that the fork modules have no dependency cycles
# (reads deps = [...] of BUILD files, no Bazel needed). Run before pushing.
import re, os
root=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
cache={}
def deps(label):
    pkg=label.split(':')[0].lstrip('/')
    if pkg in cache: return cache[pkg]
    path=os.path.join(root,pkg,'BUILD'); out=[]
    if os.path.exists(path):
        s=open(path,encoding='utf-8').read()
        for block in re.findall(r'deps\s*=\s*\[(.*?)\]', s, re.S):
            out+=[m.split(':')[0] for m in re.findall(r'"(//(?:submodules|third-party)/[^"]+)"', block)]
    cache[pkg]=list(dict.fromkeys(out)); return cache[pkg]
for start in ['//submodules/ZalupaGram','//submodules/ZalupaGramCore']:
    seen={start}; stack=[start]
    while stack:
        x=stack.pop()
        for d in deps(x):
            if d not in seen: seen.add(d); stack.append(d)
    users=[]
    for dirpath,_,files in os.walk(os.path.join(root,'submodules')):
        if 'BUILD' in files:
            s=open(os.path.join(dirpath,'BUILD'),encoding='utf-8').read()
            if re.search(r'"'+re.escape(start)+r'(:[A-Za-z]+)?"', s):
                users.append('//'+os.path.relpath(dirpath,root).replace(os.sep,'/'))
    print(start, 'users', users, 'CYCLE' if any(u in seen for u in users) else 'ok')
