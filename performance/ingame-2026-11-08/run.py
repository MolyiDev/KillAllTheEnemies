"""Run one bench through Tripwire: python run.py LABEL 'ARMS_JSON' [COUNT]. Writes raw-LABEL.json."""
from pathlib import Path
import json, sys, time
sys.path.insert(0, str(Path(__file__).resolve().parent))
import tw

HERE = Path(__file__).resolve().parent
label, arms = sys.argv[1], sys.argv[2]
count = sys.argv[3] if len(sys.argv) > 3 else '1200'
sid = tw.session()

def call(name, args=None):
    r, _ = tw.post({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": name, "arguments": args or {}}}, sid)
    if r is None or 'error' in r:
        raise RuntimeError(f'{name}: {r}')
    text = ''.join(c.get('text', '') for c in r['result'].get('content', []))
    if r['result'].get('isError'):
        raise RuntimeError(f'{name}: {text}')
    return text

def sub(src):
    return src.replace('__LABEL__', label).replace('__ARMS__', arms).replace('__COUNT__', count)

for path in ('game.ServerScriptService.BallarcBench', 'game.StarterPlayer.StarterPlayerScripts.BallarcBench'):
    try:
        call('delete_instance', {'path': path})
    except Exception:
        pass
call('create_instance', {'className': 'Script', 'name': 'BallarcBench', 'parentPath': 'game.ServerScriptService'})
call('create_instance', {'className': 'LocalScript', 'name': 'BallarcBench', 'parentPath': 'game.StarterPlayer.StarterPlayerScripts'})
call('update_script_source', {'path': 'game.ServerScriptService.BallarcBench', 'source': sub((HERE / 'bench.server.luau').read_text())})
call('update_script_source', {'path': 'game.StarterPlayer.StarterPlayerScripts.BallarcBench', 'source': sub((HERE / 'bench.client.luau').read_text())})
call('start_playtest')
lines, cursor, started, done = [], None, time.time(), False
while time.time() - started < 900:
    time.sleep(3)
    try:
        out = json.loads(call('get_playtest_output', {'since': cursor} if cursor else {}))
    except Exception as exc:
        print('poll error', str(exc)[:200])
        continue
    cursor = out.get('cursor', cursor)
    for e in out.get('entries', out.get('lines', [])):
        msg = e.get('message', '')
        lines.append(e)
        if '[BALLARC_BENCH' in msg:
            print(msg[:400], flush=True)
        if '"phase":"done"' in msg or '"phase":"abort"' in msg:
            done = True
    if done:
        break
time.sleep(1)
(HERE / f'raw-{label}.json').write_text(json.dumps({'label': label, 'arms': arms, 'count': count, 'entries': lines}, indent=1))
try:
    call('stop_playtest')
except Exception as exc:
    print('stop error', exc)
for _ in range(40):
    time.sleep(2)
    st = json.loads(call('list_studios'))
    if not any(s.get('playtestActive') for s in st if s.get('connected')):
        break
# Remove the probes from the edit DataModel so nothing is left behind.
for path in ('game.ServerScriptService.BallarcBench', 'game.StarterPlayer.StarterPlayerScripts.BallarcBench'):
    try:
        call('delete_instance', {'path': path})
    except Exception as exc:
        print('delete error', path, exc)
errs = [e for e in lines if e.get('messageType', e.get('type', '')) in ('MessageError', 'Error', 'error')]
print(f'{label}: {len(lines)} lines, {len(errs)} errors, done={done}')
for e in errs[:15]:
    print('  ERR', e.get('peer'), e.get('message', '')[:250])
