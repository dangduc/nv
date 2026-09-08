#!/usr/bin/env python3
"""Challenge the corrected fixed fixture without invoking old sync code."""
import copy
import hashlib
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import zlib

here = Path(__file__).resolve().parent
repo = here.parents[3]
output = repo / 'build/SimplenoteRemovalReview/round3-contrarian-data'
output.mkdir(parents=True, exist_ok=True)
fixture = repo / 'Tests/Regression/source-storage/fixtures/legacy-simplenote.notation'
data = fixture.read_bytes()
assert hashlib.sha256(data).hexdigest() == '07bc028440a8dfba96f53023f3035141a94c5b1ecd8b6cd23d99eaeb9bf52f4d'
original = plistlib.loads(data)


def object_at(archive, value):
    return archive['$objects'][value.data] if isinstance(value, plistlib.UID) else value


def field(archive, obj, key):
    return object_at(archive, obj[key])


def dict_item(archive, obj, key):
    keys = [object_at(archive, item) for item in obj['NS.keys']]
    return object_at(archive, obj['NS.objects'][keys.index(key)])


def change_item(archive, obj, key, value, rename=False):
    keys = [object_at(archive, item) for item in obj['NS.keys']]
    index = keys.index(key)
    uid = plistlib.UID(len(archive['$objects']))
    archive['$objects'].append(value)
    obj['NS.keys' if rename else 'NS.objects'][index] = uid


def records(archive):
    root = field(archive, archive['$top'], 'root')
    prefs = field(archive, root, 'prefs')
    tombstone = object_at(archive, field(archive, root, 'deletedNoteSet')['NS.objects'][0])
    packed = field(archive, root, 'notesData')['NS.data']
    payload = zlib.decompress(packed[:-4])
    assert len(payload) == struct.unpack('>I', packed[-4:])[0]
    inner = plistlib.loads(payload)
    notes = field(inner, inner['$top'], 'notes')
    assert len(notes['NS.objects']) == 1
    note = object_at(inner, notes['NS.objects'][0])
    return root, prefs, tombstone, inner, note


def dictionary(archive, obj):
    return {object_at(archive, key): object_at(archive, value)
            for key, value in zip(obj['NS.keys'], obj['NS.objects'])}


root, prefs, tombstone, inner, note = records(original)
accounts = field(original, prefs, 'syncServiceAccounts')
assert dictionary(original, dict_item(original, accounts, 'SN')) == {
    'enabled': True, 'username': 'fixture@example.invalid', 'frequency': 1}
assert dictionary(inner, dict_item(inner, field(inner, note, 'syncServicesMD'), 'SN')) == {
    'key': 'legacy-remote-note', 'version': 7, 'dirty': True,
    'modify': 700000123.5, 'SepStr': 'e\n\n#'}
assert dictionary(original, dict_item(original, field(original, tombstone, 'syncServicesMD'), 'SN')) == {
    'key': 'legacy-remote-deletion', 'version': 11, 'dirty': True, 'modify': 700000124.5}
assert prefs['doesEncryption'] is False and prefs['storesPasswordInKeychain'] is False
assert object_at(original, prefs['keychainDatabaseIdentifier']) == '$null'
assert note['uniqueNoteIDBytes'] == bytes.fromhex('1032547698badcfe0123456789abcdef')
assert (note['createdDate'], note['modifiedDate'], note['logSequenceNumber']) == (700000000.25, 700000123.5, 1)
assert field(inner, note, 'titleString') == 'Local synced title'
assert field(inner, note, 'labelString') == 'keep, 日本語'
body = field(inner, field(inner, note, 'contentString'), 'NSString')['NS.string']
assert body == '# Local café 😀\r\n\tunsent changes\n'
assert dictionary(original, dict_item(original, field(original, prefs, 'sourceMetadataByNoteUUID'),
                                    '10325476-98BA-DCFE-0123-456789ABCDEF')) == {'syntax': 'markdown'}
print('INDEPENDENT PLIST ORACLE: account, live upload, tombstone deletion, local identity/content/syntax, and no encryption/keychain verified', flush=True)

variants = [
    ('correct', [True, True, True], True),
    ('wrong-account-service', [False, True, True], True),
    ('disabled-account', [False, True, True], True),
    ('missing-live-metadata', [True, False, True], True),
    ('clean-live-metadata', [True, False, True], True),
    ('missing-deletion-metadata', [True, True, False], True),
    ('wrong-deletion-key', [True, True, False], True),
    ('changed-local-sequence', [True, True, True], False),
]
manifest = []
for name, guards, local in variants:
    archive = copy.deepcopy(original)
    root, prefs, tombstone, inner, note = records(archive)
    accounts = field(archive, prefs, 'syncServiceAccounts')
    if name == 'wrong-account-service':
        change_item(archive, accounts, 'SN', 'Simplenote', rename=True)
    elif name == 'disabled-account':
        change_item(archive, dict_item(archive, accounts, 'SN'), 'enabled', False)
    elif name == 'missing-live-metadata':
        del note['syncServicesMD']
    elif name == 'clean-live-metadata':
        change_item(inner, dict_item(inner, field(inner, note, 'syncServicesMD'), 'SN'), 'dirty', False)
    elif name == 'missing-deletion-metadata':
        del tombstone['syncServicesMD']
    elif name == 'wrong-deletion-key':
        change_item(archive, dict_item(archive, field(archive, tombstone, 'syncServicesMD'), 'SN'),
                    'key', 'different-remote-deletion')
    elif name == 'changed-local-sequence':
        note['logSequenceNumber'] += 1
    payload = plistlib.dumps(inner, fmt=plistlib.FMT_BINARY)
    field(archive, root, 'notesData')['NS.data'] = zlib.compress(payload) + struct.pack('>I', len(payload))
    encoded = data if name == 'correct' else plistlib.dumps(archive, fmt=plistlib.FMT_BINARY)
    (output / (name + '.notation')).write_bytes(encoded)
    row = dict(name=name, guards=guards, local=local, sha256=hashlib.sha256(encoded).hexdigest())
    manifest.append(row)
    print(json.dumps(row, sort_keys=True), flush=True)
(output / 'manifest.plist').write_bytes(plistlib.dumps(manifest))
(here / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

# Use the exact guard under review, changing only its assertion reporter. That
# records all three outcomes in one process instead of exiting at first failure.
support = (repo / 'Tests/Regression/source-storage/support.h').read_text()
start = support.index('// Decode only the obsolete fixture fields')
end = support.index('// Sequential archives require consuming', start)
guard = support[start:end]
(here / 'fixture_guard.h').write_text('// Extracted verbatim by run.py; assertion reporter is rebound by prefix.h.\n' + guard)
print('GUARD SOURCE SHA256: ' + hashlib.sha256(guard.encode()).hexdigest(), flush=True)
environment = dict(os.environ, NV_FIXTURE_REVIEW_DIR=str(output))
subprocess.run(['python3', str(repo / 'Tests/ViewControlsReview/run-probe.py'),
                '--app', str(repo / 'build/SimplenoteRemovalReview/round1.app'),
                '--prefix', str(here / 'prefix.h'), '--probe', str(here / 'checks.inc')],
               cwd=repo, env=environment, check=True)
