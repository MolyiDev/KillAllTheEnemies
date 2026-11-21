"""Run one benchmark arm through Tripwire: python run.py LABEL FLAGS [COUNT]
Writes raw-LABEL.json (all playtest output lines with BALLARC markers + errors/warnings)."""
from pathlib import Path
import json, subprocess, sys, time
sys.path.insert(0, str(Path(__file__).resolve().parent))
import tw

HERE = Path(__file__).resolve().parent
label, flags = sys.argv[1], sys.argv[2]
count = sys.argv[3] if len(sys.argv) > 3 else '8000'
if flags != 'final':
    subprocess.check_call([sys.executable, str(HERE / 'harness.py'), 'flags', flags])
sid = tw.session()

def call(name, args=None, timeout_ok=False):
    r, _ = tw.post({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": name, "arguments": args or {}}}, sid)
    if r is None or 'error' in r:
        raise RuntimeError(f'{name}: {r}')
    text = ''.join(c.get('text', '') for c in r['result'].get('content', []))
    if r['result'].get('isError'):
        raise RuntimeError(f'{name}: {text}')
    return text

def sub(src):
    return src.replace('__LABEL__', label).replace('__FLAGS__', flags).replace('__COUNT__', count)

time.sleep(2)  # let Rojo push the flag change
call('update_script_source', {'path': 'game.ServerScriptService.BallarcBench', 'source': sub((HERE / 'bench.server.luau').read_text())})
call('update_script_source', {'path': 'game.StarterPlayer.StarterPlayerScripts.BallarcBench', 'source': sub((HERE / 'bench.client.luau').read_text())})
call('start_playtest')
lines, cursor, started = [], None, time.time()
done = False
while time.time() - started < 600:
    time.sleep(3)
    out = json.loads(call('get_playtest_output', {'since': cursor} if cursor else {}))
    cursor = out.get('cursor', cursor)
    for e in out.get('entries', out.get('lines', [])):
        msg = e.get('message', '')
        lines.append(e)
        if '[BALLARC_BENCH' in msg:
            print(msg[:300], flush=True)
        if '"phase":"abort"' in msg:
            done = True
        if ('smoke' in label and '"phase":"smoke-done"' in msg) or ('smoke' not in label and '"phase":"done"' in msg):
            done = True
    if done:
        break
time.sleep(1)
(HERE / f'raw-{label}.json').write_text(json.dumps({'label': label, 'flags': flags, 'count': count, 'entries': lines}, indent=1))
try:
    call('stop_playtest')
except Exception as exc:
    print('stop error', exc)
for _ in range(40):
    time.sleep(2)
    st = json.loads(call('list_studios'))
    if not any(s.get('playtestActive') for s in st if s.get('connected')):
        break
errs = [e for e in lines if e.get('messageType', e.get('type', '')) in ('MessageError', 'Error', 'error')]
print(f'{label}: {len(lines)} lines, {len(errs)} errors, done={done}')
for e in errs[:15]:
    print('  ERR', e.get('peer'), e.get('message', '')[:250])
