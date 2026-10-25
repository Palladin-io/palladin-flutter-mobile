"""Value-free mobile release identity and artifact validation."""
import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ENVIRONMENTS = {'prod': ('production', 'io.palladin.mobile'),
                'stg': ('staging', 'io.palladin.mobile.staging')}
PLATFORMS = {'android', 'ios', 'both'}
VERSION = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)')


def version_tuple(value):
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        raise ValueError('Version must be canonical X.Y.Z')
    parts = tuple(map(int, value.split('.')))
    if any(p > 9999 for p in parts):
        raise ValueError('Marketing version component exceeds 9999')
    return parts


def resolve_version(base, mode, manual):
    parts = list(version_tuple(base))
    if mode == 'manual':
        if version_tuple(manual) < tuple(parts):
            raise ValueError('Version cannot decrease')
        return manual
    if manual or mode not in {'keep', 'patch', 'minor', 'major'}:
        raise ValueError('Invalid version mode or unexpected manual version')
    if mode != 'keep':
        index = {'major': 0, 'minor': 1, 'patch': 2}[mode]
        parts[index] += 1
        parts[index+1:] = [0] * (2-index)
    result = '.'.join(map(str, parts))
    version_tuple(result)
    return result


def ios_build(sequence):
    if type(sequence) is not int or not 1 <= sequence <= 99989999:
        raise ValueError('Build sequence out of range')
    return f'{sequence // 10000 + 1}.{sequence // 100 % 100}.{sequence % 100}'


def reserve_record(inputs, records, floor, bootstrap):
    if inputs['environment'] not in ENVIRONMENTS or inputs['platform'] not in PLATFORMS:
        raise ValueError('Invalid environment or platform')
    if type(floor) is not int or floor < 0:
        raise ValueError('Invalid migration floor')
    if not re.fullmatch('[0-9a-f]{40}', inputs['source_sha']):
        raise ValueError('Invalid source SHA')
    if type(inputs['run_id']) is not int or inputs['run_id'] <= 0:
        raise ValueError('Invalid run ID')
    for record in records:
        if record['run_id'] == inputs['run_id']:
            if record['inputs'] != inputs:
                raise ValueError('Existing reservation has different inputs')
            return record
    sequence = max([floor] + [r['sequence'] for r in records]) + 1
    prior = sorted((r for r in records if r['environment'] == inputs['environment']),
                   key=lambda r: r['sequence'])
    base = prior[-1]['marketing_version'] if prior else bootstrap
    flavor, bundle_id = ENVIRONMENTS[inputs['environment']]
    return dict(schema=1, inputs=inputs, sequence=sequence,
                marketing_version=resolve_version(base, inputs['version_mode'], inputs['version']),
                android_build=sequence, ios_build=ios_build(sequence), flavor=flavor,
                bundle_id=bundle_id, environment=inputs['environment'], platform=inputs['platform'],
                source_sha=inputs['source_sha'], run_id=inputs['run_id'], repository=inputs['repository'])


def create_manifest(record, artifact, platform):
    if platform not in {'android', 'ios'} or record['platform'] not in {platform, 'both'}:
        raise ValueError('Platform outside reservation')
    if artifact.is_symlink() or not artifact.is_file():
        raise ValueError('Artifact must be a regular file')
    with artifact.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return dict(record, artifact={'name': artifact.name, 'sha256': digest},
                artifact_platform=platform)


def verify_manifest(record, manifest, directory, platform):
    if any(manifest.get(k) != v for k, v in record.items()):
        raise ValueError('Artifact identity differs from reservation')
    if manifest.get('artifact_platform') != platform or record['platform'] not in {platform, 'both'}:
        raise ValueError('Artifact platform mismatch')
    item = manifest.get('artifact', {})
    name = item.get('name', '')
    suffix = '.aab' if platform == 'android' else '.ipa'
    if not name or Path(name).name != name or not name.endswith(suffix):
        raise ValueError('Unsafe artifact filename')
    artifact = directory / name
    if artifact.is_symlink() or not artifact.is_file():
        raise ValueError('Missing or unsafe artifact')
    with artifact.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != item.get('sha256'):
            raise ValueError('Artifact checksum mismatch')
    return artifact


def validate_run(run, record, workflow_id, environment, platform):
    if (run['id'] != record['run_id'] or run['head_sha'] != record['source_sha'] or
        run['head_branch'] != 'main' or run['event'] != 'workflow_dispatch' or
        run['workflow_id'] != workflow_id or run['repository']['full_name'] != record['repository']):
        raise ValueError('Untrusted source run')
    if environment != record['environment'] or platform not in PLATFORMS:
        raise ValueError('Resume environment/platform mismatch')
    if record['platform'] != 'both' and platform != record['platform']:
        raise ValueError('Cannot resume a platform absent from the original release')


def gh_api(path, payload=None):
    args = ['gh', 'api', path]
    if payload is not None:
        args += ['--method', 'POST', '--input', '-']
    result = subprocess.run(args, input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True)
    if result.returncode:
        raise ValueError('GitHub API operation failed; check repository permissions and resource availability')
    return json.loads(result.stdout)


def records_from_github(repo):
    refs = gh_api(f'repos/{repo}/git/matching-refs/tags/mobile-build/')
    records = []
    for ref in refs:
        if ref['object']['type'] != 'tag':
            raise ValueError('Release ledger contains a non-annotated tag')
        tag = gh_api(f'repos/{repo}/git/tags/{ref["object"]["sha"]}')
        record = json.loads(tag['message'])
        if (tag['object']['type'] != 'commit' or tag['object']['sha'] != record['source_sha'] or
            ref['ref'] != f'refs/tags/mobile-build/{record["run_id"]}' or record['repository'] != repo):
            raise ValueError('Release ledger tag binding mismatch')
        records.append(record)
    return records


def write_outputs(record):
    Path('release-record.json').write_text(json.dumps(record, indent=2) + '\n')
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a') as stream:
            for key in ('run_id','source_sha','flavor','bundle_id','marketing_version','android_build','ios_build','environment','platform'):
                stream.write(f'{key}={record[key]}\n')
            stream.write('record=' + json.dumps(record, separators=(',', ':')) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['reserve','resume','manifest','verify'])
    parser.add_argument('--platform', choices=['android','ios'])
    parser.add_argument('--directory', type=Path)
    args = parser.parse_args()
    if args.operation in {'manifest','verify'}:
        record = json.loads(os.environ['RELEASE_RECORD'])
        manifest_path = args.directory / 'release-manifest.json'
        if args.operation == 'manifest':
            paths = list(args.directory.glob('*.aab' if args.platform == 'android' else '*.ipa'))
            if len(paths) != 1: raise ValueError('Expected exactly one signed artifact')
            manifest_path.write_text(json.dumps(create_manifest(record,paths[0],args.platform),indent=2)+'\n')
        else:
            artifact = verify_manifest(record,json.loads(manifest_path.read_text()),args.directory,args.platform)
            # Manifest itself must be provenance-verified by the caller before this local check.
            if os.environ.get('GITHUB_OUTPUT'):
                with open(os.environ['GITHUB_OUTPUT'],'a') as stream:
                    stream.write(f'artifact={artifact}\n')
        return
    if os.environ['GITHUB_REF'] != 'refs/heads/main':
        raise ValueError('Mobile releases require main')
    environment = os.environ['RELEASE_ENVIRONMENT']
    if environment not in ENVIRONMENTS: raise ValueError('Unknown environment')
    if environment == 'stg' and os.environ.get('STAGING_ENABLED') != 'true':
        raise ValueError('stg releases are disabled')
    repo = os.environ['GITHUB_REPOSITORY']
    records = records_from_github(repo)
    if args.operation == 'reserve':
        if os.environ.get('SOURCE_RUN_ID'): raise ValueError('Unexpected source run')
        inputs = dict(environment=environment,platform=os.environ['RELEASE_PLATFORM'],
                      version_mode=os.environ['VERSION_MODE'],version=os.environ.get('MANUAL_VERSION',''),
                      source_sha=os.environ['GITHUB_SHA'],run_id=int(os.environ['GITHUB_RUN_ID']),repository=repo)
        line = next(x for x in Path('pubspec.yaml').read_text().splitlines() if x.startswith('version:'))
        bootstrap = line.split(':',1)[1].strip().split('+')[0]
        floor = int(os.environ['BUILD_SEQUENCE_FLOOR'])
        record = reserve_record(inputs, records, floor, bootstrap)
        if not any(r['run_id'] == record['run_id'] for r in records):
            tag = gh_api(f'repos/{repo}/git/tags',dict(tag=f'mobile-build/{record["run_id"]}',
                         message=json.dumps(record,sort_keys=True),object=record['source_sha'],type='commit'))
            gh_api(f'repos/{repo}/git/refs',dict(ref=f'refs/tags/mobile-build/{record["run_id"]}',sha=tag['sha']))
    else:
        if os.environ['VERSION_MODE'] != 'keep' or os.environ.get('MANUAL_VERSION'):
            raise ValueError('Resume cannot change version')
        source_run_id = int(os.environ['SOURCE_RUN_ID'])
        record = next((r for r in records if r['run_id'] == source_run_id),None)
        if record is None: raise ValueError('Original release reservation not found')
        run = gh_api(f'repos/{repo}/actions/runs/{source_run_id}')
        workflow = gh_api(f'repos/{repo}/actions/workflows/mobile-store-builds.yml')
        validate_run(run,record,workflow['id'],environment,os.environ['RELEASE_PLATFORM'])
        comparison = gh_api(f'repos/{repo}/compare/{record["source_sha"]}...main')
        if comparison['status'] not in {'ahead','identical'}:
            raise ValueError('Original release source is no longer reachable from main')
    write_outputs(record)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, StopIteration) as error:
        # Do not surface arbitrary remote responses or environment contents.
        raise SystemExit(f'Release validation failed ({type(error).__name__}); check inputs and provisioning') from None
