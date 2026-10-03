#!/usr/bin/env python3
"""一次性、精確 GitHub run 的本機私有素材閘門。憑證僅送 stdin。"""
import argparse, hashlib, json, os, pathlib, subprocess, time, uuid

REPO = 'leadingtw273/tank-skirmish'
LOCK_PATH = pathlib.Path(__file__).resolve().parents[2] / 'docs/assets/local-ci-assets-lock.json'
ARCHIVE_SHA = json.loads(LOCK_PATH.read_text())['archiveSha256']
WORKFLOW = '.github/workflows/ci.yml'

def command(argv):
    return subprocess.check_output(argv, text=True, stderr=subprocess.PIPE)

def api(path, method='GET'):
    # 不列印 response 中可能含有的 token。
    return json.loads(command(['gh', 'api', '--method', method, f'repos/{REPO}/{path}']))

def trusted_run(run, head, pr):
    if run['head_sha'] != head or run['path'].split('@')[0] != WORKFLOW:
        return False
    if pr is None:
        return run['event'] == 'push' and run['head_branch'] == 'main'
    return (run['event'] == 'pull_request' and
            any(p['number'] == pr for p in run['pull_requests']) and
            run['head_repository']['full_name'] == REPO)

def assignment_matches(job, run_id, runner_id, name):
    return (job['run_id'] == run_id and job['name'] == 'quality' and
            job['status'] == 'in_progress' and job['runner_id'] == runner_id and
            job['runner_name'] == name)

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--head', required=True)
    p.add_argument('--run-id', type=int, required=True)
    p.add_argument('--pr', type=int)
    p.add_argument('--image', required=True, help='Exact local image ID built from scripts/ci/Dockerfile')
    p.add_argument('--archive', type=pathlib.Path, required=True)
    p.add_argument('--output', type=pathlib.Path, required=True)
    a = p.parse_args()
    if len(a.head) != 40 or any(c not in '0123456789abcdef' for c in a.head):
        raise RuntimeError('invalid head')
    if a.pr is not None and a.pr <= 0:
        raise RuntimeError('invalid PR')
    if not a.image.startswith('sha256:') or len(a.image) != 71 or any(c not in '0123456789abcdef' for c in a.image[7:]):
        raise RuntimeError('exact image ID required')
    image = json.loads(command(['docker', 'image', 'inspect', a.image]))[0]
    if image['Id'] != a.image or image['Config']['User'] != 'runner':
        raise RuntimeError('runner image identity or user mismatch')
    archive = a.archive.resolve()
    if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA:
        raise RuntimeError('archive mismatch')
    run = api(f'actions/runs/{a.run_id}')
    if not trusted_run(run, a.head, a.pr) or run['status'] == 'completed':
        raise RuntimeError('run identity invalid')
    attempt = run['run_attempt']
    if a.pr:
        pr = api(f'pulls/{a.pr}')
        if pr['state'] != 'open' or pr['head']['sha'] != a.head or pr['head']['repo']['full_name'] != REPO:
            raise RuntimeError('PR identity invalid')
    else:
        if api('git/ref/heads/main')['object']['sha'] != a.head:
            raise RuntimeError('main identity invalid')
    a.output.mkdir(parents=True, exist_ok=False)
    gate = a.output.resolve() / 'asset-gate'
    gate.mkdir(mode=0o755)
    os.chmod(a.output, 0o755)
    name = 'lea178-quality-' + uuid.uuid4().hex[:12]
    cid = None
    runner_id = None
    process = None
    result = {'head': a.head, 'run_id': a.run_id, 'attempt': attempt,
              'runner_name': name, 'released': False, 'status': 'running',
              'image_id': a.image, 'dockerfile_sha256': hashlib.sha256(
                  pathlib.Path(__file__).with_name('Dockerfile').read_bytes()).hexdigest(),
              'asset_lock_sha256': hashlib.sha256(LOCK_PATH.read_bytes()).hexdigest()}
    log = (a.output / 'runner.log').open('w')
    try:
        # 空目錄是唯一 host mount；沒有 home、Docker socket 或私有檔案。
        shell = ('set -eu; IFS= read -r registration; '
                 './config.sh --url https://github.com/' + REPO +
                 ' --token "$registration" --unattended --ephemeral --disableupdate '
                 '--labels tank-skirmish-private-assets --name ' + name +
                 '; unset registration; exec ./run.sh --once')
        cid = command(['docker', 'create', '--name', name, '--label', 'lea178.owner=' + name,
                       '--init', '--interactive', '--cap-drop', 'ALL',
                       '--security-opt', 'no-new-privileges', '--pids-limit', '512',
                       '--cpus', '4', '--memory', '8g', '--workdir', '/home/runner',
                       '--mount', f'type=bind,source={gate},target=/opt/tank-skirmish-ci-assets,readonly',
                       '--entrypoint', '/bin/bash', a.image, '-c', shell]).strip()
        result['container_id'] = cid
        registration = api('actions/runners/registration-token', 'POST')['token']
        process = subprocess.Popen(['docker', 'start', '--attach', '--interactive', cid],
                                   stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT)
        process.stdin.write((registration + '\n').encode())
        process.stdin.close()
        del registration
        deadline = time.monotonic() + 180
        busy_since = None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('runner exited before assignment')
            live = api(f'actions/runs/{a.run_id}')
            if not trusted_run(live, a.head, a.pr) or live['run_attempt'] != attempt:
                raise RuntimeError('run drift')
            runners = api('actions/runners?per_page=100')['runners']
            own = next((r for r in runners if r['name'] == name), None)
            if own:
                runner_id = own['id']
                result['runner_id'] = runner_id
                jobs = api(f'actions/runs/{a.run_id}/attempts/{attempt}/jobs')['jobs']
                job = next((j for j in jobs if assignment_matches(j, a.run_id, runner_id, name)), None)
                if job:
                    # 同一 API assignment 身分已證實；現在才釋出固定 tar。
                    (a.output / 'verified-assignment.json').write_text(json.dumps({'run': live, 'job': job}, indent=2))
                    temporary = gate / 'quarter.tmp'
                    with archive.open('rb') as source, temporary.open('xb') as target:
                        while chunk := source.read(1024 * 1024):
                            target.write(chunk)
                    if hashlib.sha256(temporary.read_bytes()).hexdigest() != ARCHIVE_SHA:
                        raise RuntimeError('copied archive mismatch')
                    temporary.chmod(0o644)
                    temporary.rename(gate / 'quarter.tar')
                    result['released'] = True
                    result['job_id'] = job['id']
                    print('已核對 GitHub 精確 job／runner 身分，釋出本機素材。', flush=True)
                    break
                if own['busy']:
                    busy_since = busy_since or time.monotonic()
                    if time.monotonic() - busy_since > 20:
                        raise RuntimeError('unexpected runner assignment; assets withheld')
            time.sleep(3)
        else:
            raise RuntimeError('assignment timeout; assets withheld')
        deadline = time.monotonic() + 1900
        while time.monotonic() < deadline:
            live = api(f'actions/runs/{a.run_id}')
            if not trusted_run(live, a.head, a.pr) or live['run_attempt'] != attempt:
                raise RuntimeError('run drift after assignment')
            if live['status'] == 'completed':
                result['status'] = live['conclusion']
                result['final_run'] = live
                break
            time.sleep(5)
        else:
            raise RuntimeError('quality timeout')
    except Exception as e:
        result['status'] = 'error'
        # 不包含 gh stderr／registration response。
        result['error_type'] = type(e).__name__
        if isinstance(e, RuntimeError):
            result['error'] = str(e)
    finally:
        if cid:
            # 全量列容器，再核對固定 ID／owner 才停止並移除本次容器。
            (a.output / 'containers-before-cleanup.txt').write_text(command(['docker', 'ps', '-a', '--no-trunc']))
            inspected = json.loads(command(['docker', 'inspect', cid]))[0]
            if inspected['Id'] != cid or inspected['Config']['Labels'].get('lea178.owner') != name:
                raise RuntimeError('container cleanup identity mismatch')
            if inspected['State']['Running']:
                command(['docker', 'stop', '--time', '15', cid])
            command(['docker', 'rm', cid])
            result['container_removed'] = True
        if process:
            process.wait(timeout=30)
        log.close()
        if runner_id:
            runners = api('actions/runners?per_page=100')['runners']
            own = next((r for r in runners if r['id'] == runner_id), None)
            if own:
                if own['name'] != name:
                    raise RuntimeError('runner cleanup identity mismatch')
                # DELETE 無 JSON body。
                command(['gh', 'api', '--method', 'DELETE', f'repos/{REPO}/actions/runners/{runner_id}'])
            result['runner_removed'] = not any(r['id'] == runner_id for r in api('actions/runners?per_page=100')['runners'])
        # The gate was created by this invocation; list every entry before exact cleanup.
        entries = list(gate.iterdir())
        result['asset_gate_before_cleanup'] = [entry.name for entry in entries]
        if any(entry.name not in ('quarter.tar', 'quarter.tmp') or entry.is_symlink()
               or not entry.is_file() for entry in entries):
            raise RuntimeError('unexpected asset gate content; cleanup withheld')
        for entry in entries:
            entry.unlink()
        gate.rmdir()
        result['asset_gate_removed'] = True
        (a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({k: result.get(k) for k in ('status', 'released', 'runner_removed', 'container_removed', 'error')}, ensure_ascii=False))
    return 0 if result['status'] == 'success' else 1

if __name__ == '__main__':
    raise SystemExit(main())
