"""Benchmark harness for the 2026-10-29 replication work. Never publish the probes.

python performance/optimization-2026-10-29/harness.py flags A,B,...   set feature flags on disk (Rojo syncs)
python performance/optimization-2026-10-29/harness.py instrument      add tagged timing hooks
python performance/optimization-2026-10-29/harness.py strip           remove every tagged hook
Flags: A send tiers, B client far snap, C deltas, D merged sends, E far half-rate sim, F release offscreen.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
TAG = '-- BALLARC_BENCH'
FLAGS = {
    'A': [('src/Survivors/Shared/Packers/EnemyPacker.luau', 'SEND_TIERS')],
    'B': [('src/Survivors/Client/Controllers/Actor/EnemiesController.luau', 'FAR_SNAP')],
    'C': [('src/Survivors/Shared/Packers/EnemyPacker.luau', 'DELTA_POSITIONS')],
    'D': [('src/Survivors/Server/Services/AOIService.luau', 'MERGE_SENDS')],
    'E': [('src/Survivors/Server/Utils/enemiesUpdateServer.luau', 'FAR_HALF_RATE'),
          ('src/Survivors/Server/Utils/flyingEnemiesUpdateServer.luau', 'FAR_HALF_RATE')],
    'F': [('src/Survivors/Server/Services/AOIService.luau', 'RELEASE_OFFSCREEN')],
}
ACTORS = ['EnemiesActor', 'FlyingEnemiesActor', 'CharmEnemiesActor', 'CharmFlyingEnemiesActor']


VARIANTS = {
    # (file, real line, old line). Whole lines, untagged: the old lines sit inside calls, so
    # `strip` must never touch them; `variant fix1,fix2` is what restores the real code.
    'fix1': [(f'src/Survivors/Server/Utils/{f}.luau',
              '\t\t\tmath.min(SEPARATION_QUERY_RADIUS, radius + maxNeighborHalfExtent),\n',
              '\t\t\tSEPARATION_QUERY_RADIUS,\n')
             for f in ('flyingEnemiesUpdateServer', 'charmFlyingEnemiesUpdateServer')],
    'fix2': [(f'src/Survivors/Server/Actors/{a}/Parallel/init.luau',
              '\t\tEnemiesService.QueueContactDamage(inflictorEntity, targetEnemyEntity, damage)\n',
              '\t\tEnemiesService.Damage(inflictorEntity, targetEnemyEntity, damage)\n')
             for a in ('CharmEnemiesActor', 'CharmFlyingEnemiesActor')],
}


def set_variant(on):
    """Enabled fixes keep the real code; disabled ones swap in the old line."""
    for key, sites in VARIANTS.items():
        for rel, new, old in sites:
            p = ROOT / rel
            s = p.read_text()
            want, other = (new, old) if key in on else (old, new)
            if want in s:
                continue
            assert s.count(other) == 1, (rel, key)
            p.write_text(s.replace(other, want))


def set_flags(on):
    for key, sites in FLAGS.items():
        for rel, name in sites:
            p = ROOT / rel
            s = p.read_text()
            s, n = re.subn(rf'^local {name} = (true|false)$', f'local {name} = {"true" if key in on else "false"}', s, flags=re.M)
            assert n == 1, (rel, name, n)
            p.write_text(s)


def insert_after(s, anchor, text, count=1):
    assert s.count(anchor) == count, (anchor, s.count(anchor))
    return s.replace(anchor, anchor + text)


def insert_before(s, anchor, text, count=1):
    assert s.count(anchor) == count, (anchor, s.count(anchor))
    return s.replace(anchor, text + anchor)


def instrument():
    for actor in ACTORS:
        p = ROOT / f'src/Survivors/Server/Actors/{actor}/Parallel/Work.luau'
        s = p.read_text()
        assert TAG not in s
        s = 'local BENCH = game:GetService("SharedTableRegistry"):GetSharedTable("BallarcBench") ' + TAG + '\n' + s
        s = insert_after(s, 'messageActor, messageTick = caller, tickId\n',
                         '\t\t\tlocal benchStart = os.clock() ' + TAG + '\n')
        s = insert_before(s, '\t\t\tcaller:SendMessage("Receive"',
                          '\t\t\tSharedTable.increment(BENCH, "workerUs", math.floor((os.clock() - benchStart) * 1e6)) ' + TAG + '\n'
                          '\t\t\tSharedTable.increment(BENCH, "workerJobs", 1) ' + TAG + '\n')
        p.write_text(s)
        p = ROOT / f'src/Survivors/Server/Actors/{actor}/Parallel/init.luau'
        s = p.read_text()
        assert TAG not in s
        s = insert_before(s, '\t\tdebug.profilebegin("WorldSet")', '\t\tlocal benchCommit = os.clock() ' + TAG + '\n')
        s = insert_after(s, '\t\tAOIService.SendPositions(instanceIds, positions)\n',
                         '\t\tlocal bench = shared.BallarcBench ' + TAG + '\n'
                         '\t\tif bench then bench.commitMs += (os.clock() - benchCommit) * 1000; bench.commitRows += #instanceIds end ' + TAG + '\n')
        p.write_text(s)
    p = ROOT / 'src/Survivors/Client/Controllers/Actor/EnemiesController.luau'
    s = p.read_text()
    assert TAG not in s
    s = insert_after(s, 'local function Update(dt: number)\n', '\tlocal benchStart = os.clock() ' + TAG + '\n')
    a = s.index('local function Update(dt: number)')
    b = s.index('\nlocal function onPositions', a)
    body = s[a:b].rstrip()
    assert body.endswith('end')
    body = body[:-3] + '\tEnemiesController.BenchUpdateMs = (os.clock() - benchStart) * 1000 ' + TAG + '\nend\n'
    s = s[:a] + body + s[b:]
    s = insert_before(s, 'return Ignis.Register(EnemiesController)',
                      'EnemiesController.BenchPositions = EnemiesPosition ' + TAG + '\n'
                      'EnemiesController.BenchLastUpdate = EnemiesLastUpdate ' + TAG + '\n')
    p.write_text(s)


def strip():
    for p in (ROOT / 'src').rglob('*.luau'):
        s = p.read_text()
        if TAG not in s:
            continue
        p.write_text(''.join(l for l in s.splitlines(keepends=True) if TAG not in l))
        print('stripped', p.relative_to(ROOT))


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'flags':
        set_flags(set(filter(None, (sys.argv[2] if len(sys.argv) > 2 else '').split(','))))
    elif cmd == 'variant':
        set_variant(set(filter(None, (sys.argv[2] if len(sys.argv) > 2 else '').split(','))))
    elif cmd == 'instrument':
        instrument()
    elif cmd == 'strip':
        strip()
