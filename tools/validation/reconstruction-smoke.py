"""Exercise real Docker reconstruction engines with our procedural photographs.

This is a pipeline smoke check, not a camera, quality or accuracy benchmark.
"""
import argparse, hashlib, json, os, re, time, urllib.error, urllib.request
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--origin', default='http://127.0.0.1:4180')
parser.add_argument('--archive', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--timeout', type=int, default=1200)
args = parser.parse_args()
token = os.environ['RECONSTRUCTION_TOKEN']
assert len(token) >= 32
args.output.mkdir(parents=True, exist_ok=True)

def request(path, data=None):
    headers = {'Authorization':'Bearer '+token, 'Accept':'application/json'}
    if data is not None: headers['Content-Type'] = 'application/zip'
    call = urllib.request.Request(args.origin+path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(call, timeout=60) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'{path}: HTTP {error.code}: {error.read(1024).decode("utf8", "replace")}') from None

capabilities = json.loads(request('/api/reconstruction/capabilities'))
available = {mode['id']:mode['available'] for mode in capabilities['modes']}
assert available.get('mesh') and available.get('splat'), capabilities
payload = args.archive.read_bytes()
def run_mode(mode):
    job = json.loads(request('/api/reconstruction/jobs?mode='+mode+'&name=Synthetic-cube-'+mode,payload))['job']
    identifier = job['id']; assert re.fullmatch(r'[0-9a-f-]{36}',identifier)
    deadline = time.monotonic()+args.timeout
    last = None
    while True:
        job = json.loads(request('/api/reconstruction/jobs/'+identifier))['job']
        state = (job['status'],job['stage'])
        if state != last: print(mode+': '+' / '.join(state),flush=True); last = state
        if job['status'] in {'complete','failed','cancelled'}: break
        if time.monotonic() > deadline:
            request('/api/reconstruction/jobs/'+identifier+'/cancel',b'')
            raise TimeoutError(mode+' real pipeline timed out; cancellation requested')
        time.sleep(5)
    (args.output / (mode+'-job.json')).write_text(json.dumps(job,indent=2),'utf8')
    assert job['status'] == 'complete', job
    assert job['scaleStatus'] == 'unverified', job
    expected = {'mesh.zip','model.ply','reconstruction.json'} if mode=='mesh' else {'splat.ply','cameras.json','reconstruction.json'}
    artifacts = {item['name']:item for item in job['artifacts']}
    assert expected.issubset(artifacts), job
    folder = args.output/mode; folder.mkdir(exist_ok=True)
    for name in expected:
        assert re.fullmatch(r'[a-z.]+',name)
        content = request('/api/reconstruction/jobs/'+identifier+'/artifacts/'+name)
        item = artifacts[name]
        assert len(content) == item['bytes'] and hashlib.sha256(content).hexdigest() == item['sha256']
        (folder/name).write_bytes(content)
    return {'mode':mode,'job':job}

records = []
failures = []
for mode in ['mesh','splat']:
    try:
        records.append(run_mode(mode))
    except Exception as error:
        # A mesh failure must not hide whether the independent Splat route works.
        # This remains a failed CI run even if the other route succeeds.
        failures.append({'mode':mode,'error':str(error)})
        print(mode+': validation failed: '+str(error),flush=True)
(args.output/'pipeline-results.json').write_text(json.dumps({'synthetic':True,'fieldAccuracyValidated':False,'allModesComplete':not failures,'runs':records,'failures':failures},indent=2),'utf8')
if failures:
    raise SystemExit('Actual reconstruction validation failed for: '+', '.join(item['mode'] for item in failures))
print('Actual mesh and splat pipelines completed; artifact bytes and checksums matched.',flush=True)
