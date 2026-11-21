"""Parse raw MCP captures; report per-run summaries, never pool their quantiles."""
from pathlib import Path
import json
import statistics
import sys

here=Path(__file__).resolve().parent
parsed=[]
for file in sorted(here.glob('*.json')):
    if file.name in ('parsed-results.json','source-hashes.json','summary.json'):
        continue
    data=json.loads(file.read_text())
    for block in data.get('content',[]):
        if block.get('type')!='text':
            continue
        try:
            entries=json.loads(block['text']).get('entries',[])
        except (ValueError,AttributeError):
            continue
        for entry in entries:
            message=entry['message']
            if not message.startswith('[BALLARC_') or '] ' not in message:
                continue
            try:
                row=json.loads(message.split('] ',1)[1])
            except ValueError:
                continue
            row.update(capture=file.name,peer=entry['peer'],marker=message.split(']')[0]+']')
            parsed.append(row)
(here/'parsed-results.json').write_text(json.dumps(parsed,indent=2)+'\n')

final_labels=sys.argv[1:] or ['after-final-native']
summary={'final_labels':final_labels,'scenes':{}}
for phase in ('1500-ground','3000-ground','1500-mixed','3000-mixed'):
    before=[x for x in parsed if x.get('phase')==phase and x['peer']=='client'
            and x.get('label') in ('before-1','before-2') and not x['focusLost']]
    after=[x for x in parsed if x.get('phase')==phase and x['peer']=='client'
           and x.get('label') in final_labels and not x['focusLost']]
    if not before or not after:
        continue
    fields={}
    for field in ('medianMs','p95Ms','updateMedianMs'):
        a=statistics.mean(x[field] for x in before)
        b=statistics.mean(x[field] for x in after)
        fields[field]={'before_mean_of_run_summaries':a,'after_mean_of_run_summaries':b,'reduction_percent':(1-b/a)*100}
    def estimated_fps(client):
        server=next(x for x in parsed if x.get('label')==client['label']
                    and x.get('name')==phase and x['peer']=='server' and 'seconds' in x)
        return client['frames']/server['seconds']
    a=statistics.mean(estimated_fps(x) for x in before)
    b=statistics.mean(estimated_fps(x) for x in after)
    fields['approximateCapturedFps']={'before':a,'after':b,'increase_percent':(b/a-1)*100,
                                   'method':'client frame count divided by server capture duration; replication timing adds uncertainty'}
    summary['scenes'][phase]={'before_runs':len(before),'after_runs':len(after),'fields':fields}
    print(phase, json.dumps(fields))
(here/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('Parsed',len(parsed),'records. Frame comparisons exclude before-1 focus-lost sample and all after-1 background-throttled samples.')
