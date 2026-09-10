#!/usr/bin/env python3
"""Exercise exact controller entrypoints and cleanup methods without a window."""
import hashlib
import json
import pathlib
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FILES = ['Sources/Browser/AppController.m', 'Sources/Browser/AppController_Search.m',
         'Sources/Editor/LinkingEditor.h', 'Sources/Editor/LinkingEditor.m']
def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES}
def method(path, signature):
    source = (ROOT / path).read_text()
    start = source.index(signature)
    brace = source.index('{', start)
    level, end = 1, brace + 1
    while level:
        level += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

before = hashes()
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
editor_signatures = ['- (void)invalidateSearchHighlights {', '- (void)removeHighlightedTerms {',
    '- (void)setSearchHighlightRanges:(NSArray *)ranges {',
    '- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:']
controller_signatures = [('- (void)_setCurrentNote:(NoteObject *)aNote finishingEditing:(BOOL)finishOldEditing {', FILES[0]),
    ('- (void)textDidChange:(NSNotification *)aNotification {', FILES[0]),
    ('- (void)textDidBeginEditing:(NSNotification *)aNotification {', FILES[0]),
    ('- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification {', FILES[1])]
editor = '\n\n'.join(method(FILES[3], s) for s in editor_signatures)
controller = '\n\n'.join(method(path, s) for s, path in controller_signatures)
source = (HERE / 'probe.m.in').read_text().replace('/* PRODUCTION_METHODS */', editor).replace('/* CONTROLLER_METHODS */', controller)
variants = {
    'candidate': source,
    'missing-attachment-clear': source.replace('    [textView removeHighlightedTerms];\n    // replaceTextStorage:', '    // replaceTextStorage:'),
    'missing-new-observer-registration': source.replace('    if (editingSession) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(searchSourceStorageWillProcessEditing:) name:NSTextStorageWillProcessEditingNotification object:storage];', ''),
    'missing-edit-guard': source.replace('if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)', 'if (NO)'),
}
results = {}
with tempfile.TemporaryDirectory(prefix='nv-review-controller-') as folder:
    folder = pathlib.Path(folder)
    for label, variant in variants.items():
        assert label == 'candidate' or variant != source, label
        code, binary = folder / f'{label}.m', folder / label
        code.write_text(variant)
        compiled = subprocess.run(['xcrun','clang','-arch','x86_64','-fno-objc-arc','-Wall','-framework','Cocoa','-o',str(binary),str(code)],text=True,capture_output=True)
        (HERE / f'{label}-compile.txt').write_text(compiled.stdout + compiled.stderr)
        compiled.check_returncode()
        run = subprocess.run([str(binary)],text=True,capture_output=True,timeout=30)
        output = run.stdout + run.stderr
        (HERE / f'{label}-output.txt').write_text(output)
        results[label] = {'exit_code': run.returncode, 'generated_sha256': hashlib.sha256(variant.encode()).hexdigest()}
        print(label, run.returncode, output)
        if label == 'candidate':
            run.check_returncode()
        else:
            assert run.returncode == 1 and 'FAIL ' in output and 'EXCEPTION ' not in output, (label, output)
after = hashes()
manifest = {'tested_head_start':head,'head_end':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
 'production_sha256_before':before,'production_sha256_after':after,'unchanged':before==after,
 'extracted_editor_methods':editor_signatures,'extracted_controller_methods':controller_signatures,
 'platform':subprocess.check_output(['sw_vers'],text=True).strip(),'architecture':'x86_64 via Rosetta','results':results,
 'limits':['No browser, window, application launch, or pixel drawing.',
 'Controller collaborators record callbacks and expose storage; their implementations are not tested.',
 'finishEditing is a counter stub; this probe does not operate an input method.',
 'The user macOS 13.7.8 environment is unavailable.']}
(HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
assert before == after
