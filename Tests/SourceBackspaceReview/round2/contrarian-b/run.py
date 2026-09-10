#!/usr/bin/env python3
"""Check appearance ownership in native windowless NSTextViews."""
import hashlib
import json
import pathlib
import subprocess
import tempfile
HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[3]
FILES=['Sources/Browser/AppController.m','Sources/Browser/AppController_Search.m','Sources/Editor/LinkingEditor.h','Sources/Editor/LinkingEditor.m']
def hashes(): return {p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in FILES}
def extract(path,signature):
    source=(ROOT/path).read_text(); start=source.index(signature); end=source.index('{',start)+1; level=1
    while level:
        level+=(source[end]=='{')-(source[end]=='}'); end+=1
    return source[start:end]
def head(): return subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
before=hashes(); start=head()
signatures=['- (void)invalidateSearchHighlights {','- (void)removeHighlightedTerms {','- (void)setSearchHighlightRanges:(NSArray *)ranges {','- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:']
observer='- (void)searchSourceStorageWillProcessEditing:(NSNotification *)notification {'
source=(HERE/'probe.m.in').read_text().replace('/* PRODUCTION_EDITOR_METHODS */','\n\n'.join(extract(FILES[3],s) for s in signatures)).replace('/* PRODUCTION_OBSERVER */',extract(FILES[1],observer))
variants={'candidate':source,
 'source-background-removal':source.replace('    searchHighlightsInvalidated = NO;\n    [[self layoutManager] removeTemporaryAttribute:', '    searchHighlightsInvalidated = NO;\n    [[self textStorage] removeAttribute:NSBackgroundColorAttributeName range:NSMakeRange(0, [[self string] length])];\n    [[self layoutManager] removeTemporaryAttribute:'),
 'cross-layout-cleanup':source.replace('    [[self layoutManager] removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0, [[self string] length])];','    for (NSLayoutManager *peer in [[self textStorage] layoutManagers]) [peer removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:NSMakeRange(0, [[self string] length])];'),
 'missing-display-suppression':source.replace('if (searchHighlightsInvalidated && [attributes objectForKey:NSBackgroundColorAttributeName])','if (NO)'),
 'premature-no-color-return':source.replace('- (void)setSearchHighlightRanges:(NSArray *)ranges {\n    [self removeHighlightedTerms];','- (void)setSearchHighlightRanges:(NSArray *)ranges {\n    if (![[self currentSearchHighlightAttributes] objectForKey:NSBackgroundColorAttributeName]) return;\n    [self removeHighlightedTerms];')}
results={}
with tempfile.TemporaryDirectory(prefix='nv-review-native-appearance-') as folder:
    folder=pathlib.Path(folder)
    for label,code in variants.items():
        assert label=='candidate' or code!=source
        objective_c,binary=folder/f'{label}.m',folder/label
        objective_c.write_text(code)
        compiled=subprocess.run(['xcrun','clang','-arch','x86_64','-fno-objc-arc','-Wall','-framework','Cocoa','-o',str(binary),str(objective_c)],text=True,capture_output=True)
        (HERE/f'{label}-compile.txt').write_text(compiled.stdout+compiled.stderr); compiled.check_returncode()
        run=subprocess.run([str(binary)],text=True,capture_output=True,timeout=30)
        output=run.stdout+run.stderr; (HERE/f'{label}-output.txt').write_text(output)
        results[label]={'exit_code':run.returncode,'generated_sha256':hashlib.sha256(code.encode()).hexdigest()}
        print(label,run.returncode,output)
        if label=='candidate': run.check_returncode()
        else: assert run.returncode==1 and 'FAIL ' in output and 'EXCEPTION ' not in output, (label,output)
after=hashes()
(HERE/'manifest.json').write_text(json.dumps({'tested_head_start':start,'head_end':head(),'production_sha256_before':before,'production_sha256_after':after,'unchanged':before==after,'extracted_editor_methods':signatures,'extracted_observer':observer,'results':results,'platform':subprocess.check_output(['sw_vers'],text=True).strip(),'architecture':'Intel through Rosetta','limits':['Four real NSTextViews are windowless; there are no drawn pixels or UI activation.','Composition uses NSTextView setMarkedText directly; no input method or candidate window runs.','Adapter supplies capture validity, preferred colors, and source colors.','macOS 13.7.8 is unavailable.']},indent=2)+'\n')
assert before==after
