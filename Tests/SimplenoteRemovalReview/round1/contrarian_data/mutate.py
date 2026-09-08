#!/usr/bin/env python3
"""Use ordinary plist values to vary only obsolete fields in the old fixture."""
from pathlib import Path
import copy
import plistlib
import struct
import zlib

root = Path(__file__).resolve().parent
original = plistlib.loads((root / 'old-native.notation').read_bytes())


def replace_fields(archive, keys, value):
    count = 0
    objects = archive['$objects']
    for obj in objects[:]:
        if not isinstance(obj, dict):
            continue
        for key in keys:
            if key in obj:
                obj[key] = plistlib.UID(0 if value is None else len(objects))
                if value is not None:
                    objects.append(copy.deepcopy(value))
                count += 1
    return count


for name, value in [('null', None), ('string', 'ordinary obsolete scalar'),
                    ('array', {'$class': None}), ('data', b'ordinary obsolete bytes')]:
    archive = copy.deepcopy(original)
    # An NSArray class entry needs an existing class UID. This fixture has arrays.
    if name == 'array':
        class_index = next(i for i, obj in enumerate(archive['$objects'])
                           if isinstance(obj, dict) and obj.get('$classname') in ('NSArray', 'NSMutableArray'))
        value = {'$class': plistlib.UID(class_index), 'NS.objects': []}
    assert replace_fields(archive, ['syncServiceAccounts', 'deletedNoteSet'], value) == 2
    frozen = next(obj for obj in archive['$objects'] if isinstance(obj, dict) and 'notesData' in obj)
    data_index = frozen['notesData'].data
    packed = archive['$objects'][data_index]['NS.data']
    inner = plistlib.loads(zlib.decompress(packed[:-4]))
    inner_value = value
    if name == 'array':
        class_index = next(i for i, obj in enumerate(inner['$objects'])
                           if isinstance(obj, dict) and obj.get('$classname') in ('NSArray', 'NSMutableArray'))
        inner_value = {'$class': plistlib.UID(class_index), 'NS.objects': []}
    assert replace_fields(inner, ['syncServicesMD'], inner_value) == 3
    payload = plistlib.dumps(inner, fmt=plistlib.FMT_BINARY)
    archive['$objects'][data_index]['NS.data'] = zlib.compress(payload) + struct.pack('>I', len(payload))
    (root / f'obsolete-{name}.notation').write_bytes(plistlib.dumps(archive, fmt=plistlib.FMT_BINARY))
    print(f'{name}: changed exactly 2 outer obsolete keys and 3 note obsolete keys')

# A benign oracle sensitivity check: change one retained local sequence field.
archive = copy.deepcopy(original)
frozen = next(obj for obj in archive['$objects'] if isinstance(obj, dict) and 'notesData' in obj)
data_index = frozen['notesData'].data
inner = plistlib.loads(zlib.decompress(archive['$objects'][data_index]['NS.data'][:-4]))
note = next(obj for obj in inner['$objects'] if isinstance(obj, dict) and 'logSequenceNumber' in obj)
note['logSequenceNumber'] += 1
payload = plistlib.dumps(inner, fmt=plistlib.FMT_BINARY)
archive['$objects'][data_index]['NS.data'] = zlib.compress(payload) + struct.pack('>I', len(payload))
(root / 'negative-local-sequence.notation').write_bytes(plistlib.dumps(archive, fmt=plistlib.FMT_BINARY))
print('negative control: changed one retained local logSequenceNumber by 1')
