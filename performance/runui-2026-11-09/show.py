"""python show.py LABEL...: one line per client arm from raw-LABEL.json."""
import json, sys
for label in sys.argv[1:]:
    for e in json.load(open(f'raw-{label}.json'))['entries']:
        m = e['message']
        if '[BALLARC_BENCH_CLIENT]' not in m or '"phase":"arm"' not in m:
            continue
        d = json.loads(m.split('] ', 1)[1])
        extra = {k: d[k] for k in d if k.startswith('x_')}
        print(f"{label:10} {json.dumps(d['arm']):34} anim {d['animated']:4} vis {d['visible']:4} frame {d['medianMs']:.2f}/{d['meanMs']:.2f} "
              f"animStep {d.get('animStepMeanMs', 0):.3f} med {d.get('animStepMedianMs', 0):.3f} p95 {d.get('animStepP95Ms', 0):.3f} "
              f"rcpu {d.get('renderCpuMedianMs', 0):.2f} {'FOCUSLOST' if d['focusLost'] else ''} {extra if extra else ''}")
