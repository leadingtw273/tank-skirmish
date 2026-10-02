#!/usr/bin/env python3
import contextlib, copy, hashlib, importlib.util, io, json, pathlib, subprocess, sys, tarfile
from unittest import mock

import argparse, tempfile

parser = argparse.ArgumentParser(description="Offline local asset and runner contract tests")
parser.add_argument('--archive', type=pathlib.Path, help='Opt in to checking the real private archive locally')
parser.add_argument('--output', type=pathlib.Path)
args = parser.parse_args()
ROOT = pathlib.Path(__file__).resolve().parents[1]
workspace = tempfile.TemporaryDirectory(prefix='tank-local-ci-tests-') if args.output is None else None
OUT = pathlib.Path(workspace.name) if workspace else args.output.resolve()
OUT.mkdir(parents=True, exist_ok=True)
S = OUT / 'synthetic-runner-input.tar'
S.write_bytes(b'SYNTHETIC LOCAL RUNNER INPUT; NOT PRIVATE ART')
IMAGE = 'sha256:' + 'd' * 64
cases = []
sha = lambda b: hashlib.sha256(b).hexdigest()

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

restore = load('restore_fresh', ROOT / 'scripts/restore-local-ci-assets.py')
runner = load('runner_fresh', ROOT / 'scripts/ci/run-private-quality.py')

def record(name, ok, **detail):
    cases.append({'case': name, 'status': 'PASS' if ok else 'FAIL', **detail})
    print(('PASS ' if ok else 'FAIL ') + name)

def tree(root):
    return {str(p.relative_to(root)): ('link', str(p.readlink())) if p.is_symlink() else ('file', sha(p.read_bytes()))
            for p in root.rglob('*') if '.git' not in p.parts and (p.is_file() or p.is_symlink())}

def restore_case(name, change=None, expect_reject=True, optimized=False):
    root = OUT / 'restore' / (name + ('-optimized' if optimized else ''))
    project = root / 'checkout'
    project.mkdir(parents=True)
    subprocess.run(['git', 'init', '-q', str(project)], check=True)
    payload = [('private/a.bin', b'first'), ('private/b.bin', b'second')]
    lock = {'schemaVersion': 1, 'fileCount': 2, 'files': [
        {'path': n, 'bytes': len(b), 'sha256': sha(b)} for n, b in payload]}
    archive = root / 'assets.tar'
    extra = {}
    if change:
        change(project, payload, lock, extra)
    with tarfile.open(archive, 'w') as tar:
        for n, b in payload:
            member = tarfile.TarInfo(n)
            if extra.get('symlink') == n:
                member.type = tarfile.SYMTYPE
                member.linkname = '../../escape'
                tar.addfile(member)
            else:
                member.size = len(b)
                tar.addfile(member, io.BytesIO(b))
    lock['archiveSha256'] = '0' * 64 if extra.get('bad_archive_hash') else sha(archive.read_bytes())
    lock_file = root / 'lock.json'
    lock_file.write_text(json.dumps(lock))
    before = tree(project)
    stream = io.StringIO()
    rejected = False
    error = None
    try:
        if optimized:
            result = subprocess.run([sys.executable, '-O', str(ROOT / 'scripts/restore-local-ci-assets.py'),
                '--project', str(project), '--lock', str(lock_file), '--archive', str(archive)], capture_output=True, text=True)
            stream.write(result.stdout)
            if result.returncode != 0:
                raise ValueError(result.stderr)
        else:
            with contextlib.redirect_stdout(stream):
                restore.restore(project, lock_file, archive)
    except Exception as e:
        rejected, error = True, str(e)
    after = tree(project)
    if expect_reject:
        ok = rejected and before == after
    else:
        ok = not rejected and all((project / n).read_bytes() == b for n, b in payload)
    (root / 'result.json').write_text(json.dumps({'rejected': rejected, 'error': error, 'unchanged': before == after,
                                                'before': before, 'after': after, 'stdout': stream.getvalue()}, indent=2))
    record('restore-' + name + ('-optimized' if optimized else ''), ok, rejected=rejected, unchanged=before == after, error=error)

def traversal(p,b,l,e):
    b[1] = ('../escape', b[1][1]); l['files'][1]['path'] = '../escape'
def absolute(p,b,l,e):
    b[1] = ('/absolute', b[1][1]); l['files'][1]['path'] = '/absolute'
def tracked(p,b,l,e):
    q = p / b[1][0]; q.parent.mkdir(); q.write_bytes(b'original')
    subprocess.run(['git', '-C', str(p), 'add', b[1][0]], check=True)
def target_link(p,b,l,e):
    (p/'private').mkdir(); (p/'existing').write_bytes(b'original'); (p/b[1][0]).symlink_to(p/'existing')
def escaping_parent(p,b,l,e):
    q = p.parent/'outside'; q.mkdir(); (p/'private').symlink_to(q, target_is_directory=True)


for optimized in (False, True):
    restore_case('valid', expect_reject=False, optimized=optimized)
    restore_case('archive-sha', lambda p,b,l,e: e.update(bad_archive_hash=True), optimized=optimized)
    restore_case('payload-sha-late-member', lambda p,b,l,e: l['files'][1].update(sha256='0' * 64), optimized=optimized)
    restore_case('payload-size', lambda p,b,l,e: l['files'][1].update(bytes=999), optimized=optimized)
    restore_case('missing-member', lambda p,b,l,e: b.pop(), optimized=optimized)
    restore_case('unexpected-member', lambda p,b,l,e: b.append(('private/c.bin', b'extra')), optimized=optimized)
    restore_case('duplicate-member', lambda p,b,l,e: b.append(b[0]), optimized=optimized)
    restore_case('tar-symlink', lambda p,b,l,e: e.update(symlink=b[1][0]), optimized=optimized)
    restore_case('traversal', traversal, optimized=optimized)
    restore_case('absolute-path', absolute, optimized=optimized)
    restore_case('tracked-overwrite', tracked, optimized=optimized)
    restore_case('target-symlink', target_link, optimized=optimized)
    restore_case('escaping-parent-symlink', escaping_parent, optimized=optimized)

# Real private input is checked only after explicit local --archive opt-in.
lock = json.loads((ROOT / 'docs/assets/local-ci-assets-lock.json').read_text())
if args.archive is not None:
    with tarfile.open(args.archive) as tar:
        members = tar.getmembers(); by = {m.name:m for m in members}
        exact = len(members) == len(by) == lock['fileCount'] == 586 and set(by) == {r['path'] for r in lock['files']}
        exact = exact and sha(args.archive.read_bytes()) == lock['archiveSha256'] == runner.ARCHIVE_SHA
        exact = exact and all(by[r['path']].isfile() and by[r['path']].size == r['bytes'] and
                             sha(tar.extractfile(by[r['path']]).read()) == r['sha256'] for r in lock['files'])
    record('known-586-lock-exact', exact)

HEAD, RUN, RID, PR = 'a'*40, 12345, 678, 124
class Clock:
    def __init__(self): self.now = 0
    def monotonic(self): self.now += 2; return self.now
    def sleep(self, delay): self.now += delay

class Pipe:
    def __init__(self): self.data = b''
    def write(self, data): self.data += data
    def close(self): pass
class Proc:
    def __init__(self, argv, **kwargs): self.argv = argv; self.stdin = Pipe()
    def poll(self): return None
    def wait(self, timeout): return 0

def runner_case(case):
    directory = OUT/'runner'/case
    clock, calls, procs = Clock(), [], []
    state = {'name': None, 'deleted': False, 'run_reads': 0, 'released': False}
    cid = 'c'*64
    secret = 'FAKE_STDIN_ONLY_TOKEN'
    base_run = {'id':RUN,'head_sha':HEAD,'path':runner.WORKFLOW,'event':'pull_request','pull_requests':[{'number':PR}],
                'head_repository':{'full_name':runner.REPO},'head_branch':'approved', 'status':'in_progress','run_attempt':1}
    if case.startswith('main-'):
        base_run.update(event='push', head_branch='main', pull_requests=[])
    def api(path, method='GET'):
        calls.append(['api',path,method])
        if path == f'actions/runs/{RUN}':
            live = copy.deepcopy(base_run); state['run_reads'] += 1
            if case == 'wrong-head-initial' or (case == 'wrong-head-drift' and state['run_reads'] > 1): live['head_sha'] = 'b'*40
            if case == 'wrong-attempt' and state['run_reads'] > 1: live['run_attempt'] = 2
            if case == 'fork-run': live['head_repository']['full_name'] = 'untrusted/fork'
            if case == 'wrong-pr': live['pull_requests'] = [{'number':PR+1}]
            if case == 'main-wrong-branch': live['head_branch'] = 'feature'
            if (directory/'asset-gate/quarter.tar').exists():
                state['released'] = True
                live.update(status='completed', conclusion='success')
            return live
        if path == f'pulls/{PR}':
            return {'state':'closed' if case == 'closed-pr' else 'open','head':{
                'sha':'b'*40 if case == 'pr-head-drift' else HEAD,'repo':{'full_name':runner.REPO}}}
        if path == 'git/ref/heads/main':
            return {'object':{'sha':'b'*40 if case == 'main-wrong-head' else HEAD}}
        if path == 'actions/runners/registration-token': return {'token':secret}
        if path == 'actions/runners?per_page=100':
            return {'runners':[] if state['deleted'] else [{'name':state['name'],'id':RID,'busy':True}]}
        if path == f'actions/runs/{RUN}/attempts/1/jobs':
            job = {'id':11,'run_id':RUN,'name':'quality','status':'in_progress','runner_id':RID,'runner_name':state['name']}
            if case == 'wrong-run': job['run_id'] = RUN+1
            if case == 'wrong-runner-id': job['runner_id'] = RID+1
            if case == 'wrong-runner-name': job['runner_name'] = 'foreign'
            if case == 'wrong-quality-job': job['name'] = 'foreign'
            return {'jobs':[job]}
        raise AssertionError('unexpected mocked API path '+path)
    def command(argv):
        calls.append(argv)
        if argv[:3] == ['docker', 'image', 'inspect']:
            return json.dumps([{'Id': IMAGE, 'Config':{'User':'root' if case == 'root-image' else 'runner'}}])
        if argv[:2] == ['docker','create']:
            state['name'] = argv[argv.index('--name')+1]
            assert len([x for x in argv if x == '--mount']) == 1
            mount = argv[argv.index('--mount')+1]
            assert mount == f'type=bind,source={directory.resolve()}/asset-gate,target=/opt/tank-skirmish-ci-assets,readonly'
            assert list((directory/'asset-gate').iterdir()) == []
            assert '--privileged' not in argv and '--network' not in argv and 'docker.sock' not in str(argv)
            assert '--ephemeral' in argv[-1] and '--once' in argv[-1]
            return cid+'\n'
        if argv[:2] == ['docker','ps']: return cid+' '+state['name']
        if argv[:2] == ['docker','inspect']:
            return json.dumps([{'Id':cid,'Config':{'Labels':{'lea178.owner':state['name']}},'State':{'Running':True}}])
        if argv[:2] in (['docker','stop'], ['docker','rm']): assert argv[-1] == cid; return ''
        if argv[:4] == ['gh','api','--method','DELETE']:
            assert argv[-1].endswith('/'+str(RID)); state['deleted'] = True; return ''
        raise AssertionError('unexpected mocked command '+str(argv))
    def popen(argv, **kw):
        process=Proc(argv, **kw); procs.append(process); return process
    stream, error, exit_code = io.StringIO(), None, None
    argv = ['mock-runner','--head',HEAD,'--run-id',str(RUN),'--image',IMAGE,
            '--archive',str(S),'--output',str(directory)]
    if not case.startswith('main-'):
        argv += ['--pr',str(PR)]
    with mock.patch.object(runner,'ARCHIVE_SHA',sha(S.read_bytes())), mock.patch.object(runner,'api',api), mock.patch.object(runner,'command',command), \
         mock.patch.object(runner,'time',clock), mock.patch.object(runner.subprocess,'Popen',popen), \
         mock.patch.object(sys,'argv',argv):
        try:
            with contextlib.redirect_stdout(stream): exit_code=runner.main()
        except Exception as e: error = str(e)
    released=state['released']
    result=json.loads((directory/'result.json').read_text()) if (directory/'result.json').exists() else {}
    ok = (released and exit_code == 0 and result.get('runner_removed') and result.get('container_removed') and result.get('asset_gate_removed') and not (directory/'asset-gate').exists()) if case in ('valid', 'main-valid') else not released and (exit_code == 1 or error)
    ok = ok and not (directory/'asset-gate').exists()
    token_safe = secret not in str(calls) and secret not in stream.getvalue() and all(p.stdin.data == (secret+'\n').encode() for p in procs)
    token_safe = token_safe and all(secret.encode() not in p.read_bytes() for p in directory.rglob('*') if p.is_file() and p.name != 'quarter.tar')
    record('runner-'+case, bool(ok and token_safe), released=released, exit_code=exit_code, error=error, token_stdin_only=token_safe)
    directory.mkdir(parents=True, exist_ok=True)
    (directory/'mock-evidence.json').write_text(json.dumps({'calls':calls,'result':result,'error':error,'stdout':stream.getvalue()}, indent=2))

for case in ['valid','wrong-head-initial','wrong-head-drift','wrong-attempt','wrong-run','wrong-runner-id','wrong-runner-name','wrong-quality-job','fork-run','wrong-pr','closed-pr','pr-head-drift','root-image',
             'main-valid','main-wrong-head','main-wrong-branch']:
    runner_case(case)

hashes={r['sha256'] for r in lock['files']}
artifact_files=[]
for root in [ROOT/'artifacts']:
    if root.exists(): artifact_files.extend(p for p in root.rglob('*') if p.is_file())
private_artifacts=[str(p) for p in artifact_files if p.is_symlink() or sha(p.read_bytes()) in hashes or p.suffix in ['.png','.glb','.fbx','.tar']]
record('artifacts-no-private-payload', not private_artifacts, files_inspected=len(artifact_files), private_artifacts=private_artifacts)
result={'status':'PASS' if all(c['status']=='PASS' for c in cases) else 'FAIL','count':len(cases),'cases':cases}
(OUT/'independent-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(result['status']+' '+str(len(cases))+' contract cases')
if workspace:
    workspace.cleanup()
sys.exit(0 if result['status']=='PASS' else 1)
