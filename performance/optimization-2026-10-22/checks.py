"""Run actual pure Luau algorithms in Lune with only require paths adapted."""
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[2]
here=Path(__file__).resolve().parent
modules={
 'SpatialHash':'src/Global/Shared/Utils/SpatialHash.luau',
 'SpatialHashDecoder':'src/Global/Shared/Utils/SpatialHashDecoder.luau',
 'MovementPartitions':'src/Survivors/Server/Utils/MovementPartitions.luau',
 'nearestEnemy':'src/Survivors/Server/Utils/nearestEnemy.luau',
 'Jecs':'Packages/_Index/ukendio_jecs@0.11.0/jecs/src/jecs.luau',
}
with tempfile.TemporaryDirectory(prefix='ballarc-checks-') as temp:
 p=Path(temp)
 for name,f in modules.items():
  s=(root/f).read_text().replace('local ReplicatedStorage = game:GetService("ReplicatedStorage")','')
  s=s.replace('local jecs = require(ReplicatedStorage.Packages.jecs)','')
  s=s.replace('require(ReplicatedStorage.GlobalShared.Utils.SpatialHash)','require("./SpatialHash")')
  (p/(name+'.luau')).write_text(s)
 for family in ('EnemiesActor','FlyingEnemiesActor','CharmEnemiesActor','CharmFlyingEnemiesActor'):
  s=(root/'src/Survivors/Server/Actors'/family/'Parallel/init.luau').read_text()
  start=s.index('\n\t\t\t-- jecs.record validates')
  end=s.index('\n\t\t\tlocal entityInfo = receivedEntitiesInfo[entity]',start)
  kernel=s[start:end]
  (p/(family+'.luau')).write_text('return function(EnemyWorld, entity, dispatchedRevisions, Components, Tags, jecs)\nfor _=1,1 do\n'+kernel+'\nreturn id,currentPos\nend\nreturn nil\nend')
 (p/'checks.luau').write_text((here/'checks.luau').read_text())
 subprocess.run(['lune','run',str(p/'checks.luau')],check=True,cwd=root)
