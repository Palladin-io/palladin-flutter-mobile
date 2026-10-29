"""API 35 framework evidence for a null response that omits an unavailable callback."""
import re


def password_null_response(dump, *, api, started_ms, form, provider):
    if api != 35 or not isinstance(started_ms, int) or started_ms < 0 or len(dump) > 262144:
        return False
    starts = list(re.finditer(r'^([ ]+)id: [0-9]+$', dump, re.M))
    sessions = []
    for index, start in enumerate(starts):
        block = dump[start.start():starts[index + 1].start() if index + 1 < len(starts) else len(dump)]
        component = re.findall(r'^\s*mComponentName: ComponentInfo\{([^/{}]+)/[^{}]+\}$', block, re.M)
        if component == [form]:
            sessions.append(block)
    if len(sessions) != 1:
        return False
    block = sessions[0]

    def scalar(name):
        values = re.findall(r'^\s*' + re.escape(name) + r': ([^\n]+)$', block, re.M)
        return values[0] if len(values) == 1 else None

    created = scalar('mStartTime')
    if not created or not created.isdigit() or int(created) <= started_ms:
        return False
    if (scalar('state') != 'STATE_ACTIVE' or scalar('mDestroyed') != 'false' or
            scalar('mResponses') != 'null'):
        return False
    logs = re.search(r'^\s*mSessionLogs: ([0-9]+)\n(.*?)^\s*mResponses:', block, re.M | re.S)
    if not logs:
        return False
    requests = []
    for line in logs[2].splitlines():
        match = re.fullmatch(r'\s*#[0-9]+: req=[0-9]+, log=(.*)', line)
        if not match:
            return False
        pairs = [part.split('=', 1) for part in match[1].split(', ')]
        if any(len(pair) != 2 for pair in pairs) or len({pair[0] for pair in pairs}) != len(pairs):
            return False
        request = dict(pairs)
        if (request.get('PKG') != form or request.get('SERVICE') != provider or
                not request.get('ORDINAL', '').isdigit()):
            return False
        requests.append(request)
    if not requests or len(requests) != int(logs[1]):
        return False
    ordinals = [int(request['ORDINAL']) for request in requests]
    if len(set(ordinals)) != len(ordinals):
        return False
    latest = requests[ordinals.index(max(ordinals))]
    flags = latest.get('FLAGS', '')
    # Session.onFillRequestSuccess records -1 only for a successful null response.
    # processNullResponseLocked retains password sessions without notifying unavailable.
    return (latest.get('TYPE') == 'SUCCESS(10)' and latest.get('NUM_DATASETS') == '-1' and
            flags.isdigit() and int(flags) & 0x5 == 0x5 and 'AUTH_STATUS' not in latest)
