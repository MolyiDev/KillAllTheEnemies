import json, re, sys, collections

d = json.load(open(sys.argv[1]))
sg = d['StarterGui']

# Values shared by every instance of a class; stated once in the legend instead of per node.
GLOBAL_OMIT = {
    'AutomaticSize': 'None', 'BorderMode': 'Outline', 'SizeConstraint': 'RelativeXY',
    'SelectionBehaviorDown': 'Escape', 'SelectionBehaviorLeft': 'Escape', 'SelectionBehaviorRight': 'Escape',
    'SelectionBehaviorUp': 'Escape', 'BorderSizePixel': 0, 'Interactable': False, 'AutoButtonColor': False,
    'TextScaled': True, 'TextWrapped': True, 'TextYAlignment': 'Top', 'TextXAlignment': 'Left',
    'DominantAxis': 'Height',
}
VARY = {'Position', 'Size', 'ZIndex', 'Text', 'ImageContent', 'TextColor3', 'LayoutOrder', 'Visible', 'Rotation', 'TextTransparency'}


def num(x):
    if isinstance(x, float):
        s = ('%.4f' % x).rstrip('0').rstrip('.')
        return s if s not in ('-0', '') else '0'
    return str(x)


def udim2(v):
    sx, ox, sy, oy = v
    if ox == 0 and oy == 0:
        return '(%s, %s)' % (num(sx), num(sy))
    return '{%s,%s},{%s,%s}' % (num(sx), num(ox), num(sy), num(oy))


def props_of(n):
    p = dict(n['props'])
    for k, v in GLOBAL_OMIT.items():
        if p.get(k) == v:
            del p[k]
    if n['class'] in ('Frame', 'ImageLabel', 'ImageButton', 'TextLabel') and p.get('BackgroundTransparency') == 1:
        del p['BackgroundTransparency']
    if n['class'] == 'TextLabel' and 'TextXAlignment' not in n['props']:
        p['TextXAlignment'] = 'Center'
    return p


def fmt_props(n, p):
    out = []
    p = dict(p)
    if 'Position' in p: out.append('P' + udim2(p.pop('Position')))
    if 'Size' in p: out.append('S' + udim2(p.pop('Size')))
    if 'AnchorPoint' in p: out.append('A(%s, %s)' % tuple(num(x) for x in p.pop('AnchorPoint')))
    if 'ZIndex' in p: out.append('z%s' % p.pop('ZIndex'))
    if 'Text' in p:
        out.append(json.dumps(p.pop('Text'), ensure_ascii=False))
    if 'FontFace' in p:
        f = p.pop('FontFace')
        fam = f['family'].split('/')[-1].replace('.json', '')
        s = f['weight'] if fam == 'Montserrat' else '%s %s' % (fam, f['weight'])
        if f['style'] != 'Normal': s += ' ' + f['style']
        out.append(s)
    if 'TextColor3' in p: out.append(p.pop('TextColor3'))
    if 'TextXAlignment' in p: out.append('align=' + p.pop('TextXAlignment'))
    if 'ImageContent' in p:
        out.append('img:' + p.pop('ImageContent').replace('rbxassetid://', ''))
    if 'BackgroundColor3' in p: out.append('bg=' + p.pop('BackgroundColor3'))
    if 'BackgroundTransparency' in p: out.append('bgT=' + num(p.pop('BackgroundTransparency')))
    # inline constraint children
    for c in n['children']:
        if c['class'] == 'UITextSizeConstraint':
            cp = props_of(c)
            out.append('max=%s' % cp.get('MaxTextSize', 100) + ('' if 'MinTextSize' not in cp else ' min=%s' % cp['MinTextSize']))
        elif c['class'] == 'UIAspectRatioConstraint':
            cp = props_of(c)
            s = 'AR=%s' % num(cp.pop('AspectRatio', 1.0))
            for k, v in cp.items(): s += ' %s=%s' % (k, v)
            out.append(s)
    for k, v in sorted(p.items()):
        out.append('%s=%s' % (k, v if not isinstance(v, (list, dict)) else json.dumps(v)))
    return ' '.join(out)


def is_inline(c):
    return c['class'] in ('UITextSizeConstraint', 'UIAspectRatioConstraint') and c['name'] in ('UITextSizeConstraint', 'UIAspectRatioConstraint')


def sig(n, full=False):
    p = props_of(n)
    keep = {k: v for k, v in p.items() if full or k not in VARY}
    name = n['name'] if full else re.sub(r'\d+', '#', n['name'])
    return json.dumps([n['class'], name, keep, [sig(c, full) for c in n['children']]], sort_keys=True)


def flat_vary(n, path=''):
    out = {}
    p = props_of(n)
    for k in VARY:
        if k in p: out[(path, k)] = p[k]
    seen = collections.Counter()
    for c in n['children']:
        seen[c['name']] += 1
        cp = c['name'] if seen[c['name']] == 1 else '%s#%d' % (c['name'], seen[c['name']])
        out.update(flat_vary(c, (path + '.' if path else '') + cp))
    return out


def short(k, v):
    path, prop = k
    if prop == 'Position': s = 'P' + udim2(v)
    elif prop == 'Text': s = json.dumps(v, ensure_ascii=False)
    elif prop == 'ImageContent': s = 'img:' + v.replace('rbxassetid://', '')
    elif prop == 'Size': s = 'S' + udim2(v)
    elif prop == 'ZIndex': s = 'z%s' % v
    elif prop == 'TextColor3': s = v
    else: s = '%s=%s' % (prop, v)
    return (path + ' ' if path else '') + s


def close(a, b):
    if isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        return all(abs(x - y) <= 0.0015 for x, y in zip(a, b))
    return a == b


def diff(a, b):
    fa, fb = flat_vary(a), flat_vary(b)
    parts = []
    for k in fb:
        if not close(fa.get(k), fb[k]): parts.append(short(k, fb[k]))
    for k in fa:
        if k not in fb: parts.append(('%s ' % k[0] if k[0] else '') + '%s=<default>' % k[1])
    return '; '.join(parts) if parts else 'identical'


def count(n):
    return 1 + sum(count(c) for c in n['children'])


lines = []


def pxs(n):
    r = n.get('_px')
    return '  px[%d,%d %dx%d]' % tuple(round(x) for x in r) if r else ''


def emit(n, depth):
    ind = '  ' * depth
    lines.append('%s%s [%s] %s%s' % (ind, n['name'], n['class'], fmt_props(n, props_of(n)), pxs(n)))
    emit_children(n['children'], depth + 1)


def emit_children(children, depth):
    kids = [c for c in children if not is_inline(c)]
    groups = collections.OrderedDict()
    for c in kids:
        groups.setdefault(sig(c), []).append(c)
    done = set()
    ind = '  ' * depth
    for c in kids:
        s = sig(c)
        if s in done: continue
        done.add(s)
        g = groups[s]
        emit(g[0], depth)
        if len(g) > 1:
            lines.append('%s  ⤷ ×%d siblings like "%s" (same tree); per-copy differences:' % (ind, len(g), g[0]['name']))
            for o in g[1:]:
                lines.append('%s    · %s: %s' % (ind, o['name'], diff(g[0], o)))


printed_full = {}
printed_struct = {}
screens_md = []
import glob, os
for si, screen in enumerate(sg['children']):
    lines = []
    scene = json.load(open(glob.glob(os.path.join(sys.argv[3], '%02d_*' % (si + 1), 'scene.json'))[0]))
    root_id = next(x['id'] for x in scene['nodes'] if x.get('name') == 'Root')
    top = [x for x in scene['nodes'] if x.get('parent') == root_id]
    real = [c for c in screen['children']]
    for c, x in zip(real, top):
        assert c['name'] == x['name'], (c['name'], x['name'])
        c['_px'] = x['rect']
    sp = props_of(screen)
    lines.append('%s [ScreenGui] %s' % (screen['name'], ' '.join('%s=%s' % kv for kv in sorted(sp.items()))))
    kids = [c for c in screen['children'] if not is_inline(c)]
    groups = collections.OrderedDict()
    for c in kids: groups.setdefault(sig(c), []).append(c)
    done = set()
    for c in kids:
        s = sig(c)
        if s in done: continue
        fs = sig(c, True)
        if fs in printed_full:
            lines.append('  %s [%s] = identical to %s (%d instances)%s' % (c['name'], c['class'], printed_full[fs], count(c), pxs(c)))
            continue
        if s in printed_struct and len(groups[s]) == 1:
            ref, refnode = printed_struct[s]
            lines.append('  %s [%s] ≈ %s%s, differs: %s' % (c['name'], c['class'], ref, pxs(c), diff(refnode, c)))
            done.add(s)
            continue
        done.add(s)
        g = groups[s]
        emit(g[0], 1)
        printed_full.setdefault(fs, '%s › %s' % (screen['name'], c['name']))
        printed_struct.setdefault(s, ('%s › %s' % (screen['name'], c['name']), c))
        if len(g) > 1:
            lines.append('    ⤷ ×%d siblings like "%s" (same tree); per-copy differences:' % (len(g), g[0]['name']))
            for o in g[1:]:
                lines.append('      · %s: %s' % (o['name'], diff(g[0], o)))
    screens_md.append((screen['name'], count(screen), '\n'.join(lines)))

with open(sys.argv[2], 'w') as f:
    for name, cnt, body in screens_md:
        f.write('### %s (%d instances)\n\n```\n%s\n```\n\n' % (name, cnt, body))
print(sum(len(b.splitlines()) for _, _, b in screens_md), 'lines')
