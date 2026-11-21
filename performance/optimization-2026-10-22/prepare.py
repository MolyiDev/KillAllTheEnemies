"""Prepare private source chunks for Tripwire A/B (never publish the probes).

python performance/optimization-2026-10-22/prepare.py before|after|clean LABEL
Concatenate chunks for each path in numeric order, then update_script_source.
The before variant uses HEAD movement/client modules, with the current shared
hash correctness and startup fixes common to both arms. Disk src stays final.
"""
from pathlib import Path
import subprocess
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
mode, label = sys.argv[1:3]
assert mode in ("before", "after", "clean")
OUT = Path('/tmp/ballarc-final-bench')
OUT.mkdir(exist_ok=True)

def studio_path(f):
    for prefix, target in (
        ('Global/Shared', 'game.ReplicatedStorage.GlobalShared'),
        ('Global/Server', 'game.ServerScriptService.GlobalServer'),
        ('Global/Client', 'game.StarterPlayer.StarterPlayerScripts.GlobalClient'),
        ('Survivors/Shared', 'game.ReplicatedStorage.Shared'),
        ('Survivors/Server', 'game.ServerScriptService.Server'),
        ('Survivors/Client', 'game.StarterPlayer.StarterPlayerScripts.Client'),
    ):
        stem = 'src/' + prefix + '/'
        if not f.startswith(stem):
            continue
        tail = f[len(stem):]
        for ext in ('.server.luau', '.client.luau', '.luau'):
            tail = tail.removesuffix(ext)
        parts = tail.split('/')
        if parts[-1] == 'init':
            parts.pop()
        return '.'.join([target] + parts)

changed = subprocess.check_output(['git','diff','--name-only'],cwd=ROOT,text=True).splitlines()
changed += subprocess.check_output(['git','ls-files','--others','--exclude-standard','src'],cwd=ROOT,text=True).splitlines()
changed += [str(f.relative_to(ROOT)) for f in (ROOT/'src/Survivors/Server/Actors').glob('*/EnemiesUpdater.luau')]
mapping = {}
for f in dict.fromkeys(changed):
    path = studio_path(f)
    if not path or not (ROOT/f).is_file() or f == "src/Global/Server/Network.luau":
        continue
    src = (ROOT/f).read_text()
    if mode == 'after' and label.startswith('detach') and f.endswith('Controllers/Actor/EnemiesController.luau'):
        src = (HERE/'held/EnemiesControllerDetachedPools.luau').read_text()
    if mode == 'before' and (f.startswith('src/Survivors/Server/Actors/') or
       f.startswith('src/Survivors/Server/Utils/') and Path(f).name in (
       'enemiesUpdateServer.luau','flyingEnemiesUpdateServer.luau',
       'charmEnemiesUpdateServer.luau','charmFlyingEnemiesUpdateServer.luau','nearestEnemy.luau') or
       f.endswith('Server/Services/EnemyHashPackerService.luau') or
       f.endswith('Controllers/Actor/EnemiesController.luau') or
       f.endswith('Controllers/CameraController.luau')):
        src = subprocess.check_output(['git','show','HEAD:'+f],cwd=ROOT,text=True)
    if mode == 'before' and f.endswith(('Packers/EntityPacker.luau','Packers/EnemyPacker.luau')):
        src=src.removeprefix('--!native\n').removeprefix('--!optimize 2\n')
    if 'native' in label and f.endswith(('Packers/EntityPacker.luau','Packers/EnemyPacker.luau')) and not src.startswith('--!native'):
        src='--!native\n--!optimize 2\n'+src
    if 'actor-native' in label and '/Actors/' in f and '/Parallel/' in f:
        src='--!native\n--!optimize 2\n'+src
    if mode != 'clean' and f.endswith('Controllers/Actor/EnemiesController.luau'):
        if 'ownership' in label:
            src=src.replace('ServerNetworkEnemies.Added.On(AddEnemy)', '''EnemiesController.AuditOwnership={adds=0,removes=0,addMs=0,removeMs=0,firstAdd=0,readySeconds=0}
local auditOwnership=EnemiesController.AuditOwnership
local originalAuditAdd=AddEnemy
AddEnemy=function(...)
 local t=os.clock()
 if auditOwnership.adds==0 then auditOwnership.firstAdd=t end
 originalAuditAdd(...)
 auditOwnership.adds+=1
 auditOwnership.addMs+=(os.clock()-t)*1000
end
local originalAuditRemove=removeEntityInternal
removeEntityInternal=function(...)
 local t=os.clock()
 originalAuditRemove(...)
 auditOwnership.removes+=1
 auditOwnership.removeMs+=(os.clock()-t)*1000
end
ServerNetworkEnemies.Added.On(AddEnemy)''')
        # Snapshot ownership counts only when a sample ends, outside timed Update.
        src = src.replace('return Ignis.Register(EnemiesController)', '''function EnemiesController.AuditPools()
 local entries,unique,duplicates,tracks=0,{},0,0
 for _,pools in {EnemyPools,EliteEnemyPools,EnemyDeathPools} do
  for _,pool in pools do
   for _,object in pool.Pool do
    entries+=1
    if unique[object] then duplicates+=1 else unique[object]=true end
   end
  end
 end
 for _ in ModelToWalkTrack do tracks+=1 end
 return {entries=entries,duplicates=duplicates,cachedTracks=tracks}
end
return Ignis.Register(EnemiesController)''')
        a = src.index('local function Update(dt: number)')
        b = src.index('\nUpdateEnemiesEvent.OnClientEvent', a)
        body = src[a:b]
        assert body.rstrip().endswith('end')
        body = body.replace('local function Update(dt: number)',
             'local function Update(dt: number)\nlocal auditStarted=os.clock()',1)
        body = body.rstrip()[:-3] + 'EnemiesController.AuditUpdate.lastMs=(os.clock()-auditStarted)*1000\nend\n'
        src = src[:a] + 'EnemiesController.AuditUpdate={lastMs=0}\n' + body + src[b:]
    mapping[path] = src
if mode != 'clean':
    server = 'ownership-benchmark.server.luau' if 'ownership' in label else 'pool-benchmark.server.luau' if label.startswith('pool') else 'benchmark.server.luau'
    mapping['game.ServerScriptService.BallarcFinalBench'] = (HERE/server).read_text().replace('__LABEL__',label)
    mapping['game.StarterPlayer.StarterPlayerScripts.BallarcFinalBench'] = (HERE/'benchmark.client.luau').read_text().replace('__LABEL__',label)

chunks = []
for path, src in mapping.items():
    for offset in range(0,len(src),12000):
        chunks.append({'path':path,'source':src[offset:offset+12000]})
for i, c in enumerate(chunks):
    (OUT/f'chunk-{i}.json').write_text(json.dumps(c))
(OUT/'manifest.json').write_text(json.dumps({'mode':mode,'label':label,'chunks':len(chunks),'scripts':len(mapping)}))
print(json.dumps({'mode':mode,'label':label,'chunks':len(chunks),'scripts':len(mapping)}))
