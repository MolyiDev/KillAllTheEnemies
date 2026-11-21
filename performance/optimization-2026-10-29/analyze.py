"""Summarize raw-*.json captures: python analyze.py > summary.md (also writes summary.json)."""
from pathlib import Path
import json, statistics, re

HERE = Path(__file__).resolve().parent
ARMS = ['base', 'A', 'AB', 'ABC', 'ABCD', 'E', 'F', 'all', 'final', 's2base', 's2A', 's2E', 's2F', 's2all', 's2final', 's3f0', 's3f1', 's3f2', 's3f12']
rows = {}
for f in sorted(HERE.glob('raw-*.json')):
    data = json.loads(f.read_text())
    label = data['label']
    m = re.fullmatch(r'(.+)-(\d)', label)
    if not m or m.group(1) not in ARMS:
        continue
    arm, rep = m.group(1), m.group(2)
    for e in data['entries']:
        msg = e.get('message', '')
        if not msg.startswith('[BALLARC_BENCH'):
            continue
        j = json.loads(msg.split('] ', 1)[1])
        if msg.startswith('[BALLARC_BENCH_SERVER]') and j.get('phase') == 'result':
            rows.setdefault((arm, j['name']), {}).setdefault(rep, {})['server'] = j
        elif msg.startswith('[BALLARC_BENCH_SERVER]') and j.get('phase') == 'check':
            rows.setdefault((arm, j['name']), {}).setdefault(rep, {})['check'] = j['result']
        elif msg.startswith('[BALLARC_BENCH_CLIENT]') and re.fullmatch(r'\d+-(ground|mixed|spin|spread|bees|charm)', j.get('phase', '')):
            rows.setdefault((arm, j['phase']), {}).setdefault(rep, {})['client'] = j

def metrics(run):
    s, c = run['server'], run['client']
    sec = s['seconds']
    m = s['metrics']
    rowsSent = m.get('absRows', 0) + m.get('deltaRows', 0)
    return {
        'frameMedianMs': c['medianMs'], 'frameP95Ms': c['p95Ms'], 'frameP99Ms': c['p99Ms'],
        'fps': c['frames'] / sec,
        'clientUpdateMeanMs': c['updateMeanMs'], 'clientUpdateP95Ms': c['updateP95Ms'],
        'resident': c['resident'], 'visible': c['visible'],
        'kBps': m.get('bytes', 0) / sec / 1000, 'packetsPerS': m.get('packets', 0) / sec,
        'bytesPerRow': m.get('bytes', 0) / rowsSent if rowsSent else 0,
        'rowsPerS': rowsSent / sec,
        'serverSendKbps': s['sendKbpsMean'],
        'serverHbMeanMs': s['heartbeatTimeMeanMs'], 'serverHbP95Ms': s['heartbeatTimeP95Ms'],
        'workerMsPerS': m.get('workerMs', 0) / sec, 'commitMsPerS': m.get('commitMs', 0) / sec,
        'packMsPerS': m.get('filterMs', 0) / sec, 'aoiTickMsPerS': m.get('aoiTickMs', 0) / sec,
        'damagedEventsPerS': (m.get('DamagedEvents', 0) + m.get('DamagedMultipleEvents', 0)) / sec,
        'addedPerS': m.get('AddedEvents', 0) / sec, 'removedPerS': m.get('RemovedEvents', 0) / sec,
        'checkBad': run.get('check', {}).get('bad'), 'checked': run.get('check', {}).get('checked'),
        'focusLost': c['focusLost'],
    }

out = {}
COLS = [('fps', '{:.0f}'), ('frameMedianMs', '{:.2f}'), ('frameP95Ms', '{:.2f}'), ('clientUpdateMeanMs', '{:.2f}'),
        ('resident', '{:.0f}'), ('kBps', '{:.1f}'), ('bytesPerRow', '{:.2f}'), ('packetsPerS', '{:.0f}'),
        ('serverHbMeanMs', '{:.2f}'), ('serverHbP95Ms', '{:.2f}'), ('workerMsPerS', '{:.0f}'),
        ('commitMsPerS', '{:.0f}'), ('packMsPerS', '{:.1f}'), ('aoiTickMsPerS', '{:.1f}'), ('damagedEventsPerS', '{:.0f}'), ('addedPerS', '{:.0f}'),
        ('removedPerS', '{:.0f}'), ('checkBad', '{}')]
for scene in ('8000-ground', '8000-mixed', '8000-spin', '8000-spread', '8000-bees', '8000-charm'):
    print(f'\n### {scene}\n')
    print('| arm | runs | ' + ' | '.join(c for c, _ in COLS) + ' |')
    print('|' + '---|' * (len(COLS) + 2))
    for arm in ARMS:
        reps = rows.get((arm, scene), {})
        ms = [metrics(r) for r in reps.values() if 'server' in r and 'client' in r]
        if not ms:
            continue
        agg = {}
        cells = []
        for col, fmt in COLS:
            vals = [x[col] for x in ms if x[col] is not None]
            if col == 'checkBad':
                agg[col] = sum(vals); cells.append(str(sum(vals))); continue
            mean = statistics.mean(vals)
            agg[col] = mean
            cells.append(fmt.format(mean) + ('' if len(vals) < 2 else ' (' + '/'.join(fmt.format(v) for v in vals) + ')'))
        focus = any(x['focusLost'] for x in ms)
        out[f'{arm}/{scene}'] = {'runs': ms, 'mean': agg}
        print(f'| {arm}{" ⚠focus" if focus else ""} | {len(ms)} | ' + ' | '.join(cells) + ' |')
(HERE / 'summary.json').write_text(json.dumps(out, indent=1))
