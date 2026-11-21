"""python ui.py LABEL: per arm, writes per frame by gui, property and element, then the census."""
import json, sys
label = sys.argv[1]
census = {}
for e in json.load(open(f'raw-{label}.json'))['entries']:
    m = e['message']
    if '[BALLARC_BENCH_CLIENT]' not in m: continue
    d = json.loads(m.split('] ', 1)[1])
    ph = d.get('phase')
    if ph == 'arm':
        print(f"\n=== {d['arm'].get('name')} frames {d['frames']} dirtyRoots/frame {d['dirtyRootsPerFrame']:.2f} layoutWrites/frame {d['layoutWritesPerFrame']:.1f}")
        print('  roots:', d['byRoot']); print('  props:', d['byProp'])
        if 'shownDirtyPerFrame' in d:
            print(f"  visible elements in written roots per frame {d['shownDirtyPerFrame']:.0f} (~{d['shownDirtyPerFrame']*0.7:.0f} us PC at 0.7 us each); by root, per frame:")
            for x in d['shownDirtyTop']: print('     ', x)
        if 'siblingsPerFrame' in d:
            print(f"  siblings re-laid out per frame {d['siblingsPerFrame']:.0f} (~{d['siblingsPerFrame']*0.25:.1f} us PC at 0.25 us each); by parent [children], per frame:")
            for x in d['siblingTop']: print('     ', x)
    elif ph == 'elements':
        for x in d['list']:
            if float(x.split()[0]) >= 0.05: print('   ', x)
    elif ph == 'layout':
        print('  layout us (top-level probe / deepest element / depth / descendants):')
        for k, c in sorted(d['cost'].items(), key=lambda kv: -max(kv[1]['top'], kv[1]['deep'])):
            print(f"     {k:30} {c['top']:8.1f} {c['deep']:8.1f}  d{c['depth']:2} n{c['n']}")
    elif ph == 'census':
        census.update(d['guis'])
print('\ncensus (last arm): gui shown desc auto textScaled layouts strokes canvas')
for k, c in sorted(census.items(), key=lambda kv: -kv[1]['gui']):
    print(f"  {k:45} {'on ' if c['enabled'] else 'OFF'} gui {c['gui']:4} shown {c['shown']:4} auto {c['autoSize']:3} tscaled {c['textScaled']:3} lay {c['layouts']:2} stroke {c['strokes']:3} canvas {c['canvas']}")
