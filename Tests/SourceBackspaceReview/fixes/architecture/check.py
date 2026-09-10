#!/usr/bin/env python3
"""Compare the documented cleanup branches with source text; run no editor."""
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FILES = ['Sources/Browser/AppController.m','Sources/Browser/AppController_Search.m',
         'Sources/Editor/LinkingEditor.h','Sources/Editor/LinkingEditor.m']
def hashes():
    return {name: hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in FILES}
def body(source, signature):
    start = source.index(signature)
    end, depth = source.index('{',start)+1, 1
    while depth:
        depth += (source[end]=='{')-(source[end]=='}')
        end += 1
    return source[start:end]

before = hashes()
editor = (ROOT/FILES[3]).read_text()
controller = (ROOT/FILES[0]).read_text()
doc = (ROOT/'architecture.md').read_text()
cleanup = body(editor,'- (void)removeHighlightedTerms {')
attachment = body(controller,'- (void)_setCurrentNote:(NoteObject *)aNote finishingEditing:(BOOL)finishOldEditing {')
drawing = body(editor,'- (NSDictionary *)layoutManager:(NSLayoutManager *)manager shouldUseTemporaryAttributes:')
cancel = cleanup.index('cancelPreviousPerformRequestsWithTarget:self')
guard = cleanup.index('if ([[self textStorage] editedMask] & NSTextStorageEditedCharacters)')
retry = cleanup.index('afterDelay:0.01')
returned = cleanup.index('return;',retry)
remove = cleanup.index('removeTemporaryAttribute:NSBackgroundColorAttributeName')
checks = {
 'cleanup cancels the old selector before checking character edits': cancel < guard,
 'character-edit branch reschedules and returns before removal': guard < retry < returned < remove,
 'character-edit branch retains immediate display suppression':
     'searchHighlightsInvalidated = YES;' in cleanup[guard:returned]
     and 'searchHighlightsInvalidated && [attributes objectForKey:NSBackgroundColorAttributeName]' in drawing
     and '[display removeObjectForKey:NSBackgroundColorAttributeName]' in drawing,
 'note switch requests cleanup before detaching the layout':
     attachment.index('[textView removeHighlightedTerms]') < attachment.index('removeLayoutManager:layout'),
 'documentation states selector cancellation': 'Explicit cleanup cancels any old scheduled selector.' in doc,
 'documentation states guarded deferral and suppression':
     'If character editing remains open, cleanup defers removal while drawing suppresses stale backgrounds.' in doc,
 'documentation limits immediate removal to the other branch':
     'Otherwise, removal completes before the layout manager changes storage.' in doc,
 'documentation removes the unconditional guarantee':
     'Note switches clear the old backgrounds and cancel cleanup before the layout manager changes storage.' not in doc,
}
after = hashes()
checks['four production files remain unchanged'] = before == after
output = {'scope':'Static source/documentation consistency. No runtime validation.',
          'checks':checks,'passed':sum(checks.values()),'total':len(checks)}
(HERE/'output.json').write_text(json.dumps(output,indent=2)+'\n')
(HERE/'manifest.json').write_text(json.dumps({
 'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
 'production_sha256_before':before,'production_sha256_after':after,
 'architecture_sha256':hashlib.sha256(doc.encode()).hexdigest(),
 'native_execution':False,'limitation':'Textual branch and wording checks do not establish runtime reachability.'
},indent=2)+'\n')
print(f"Static documentation checks: {sum(checks.values())}/{len(checks)} passed. Native executions: 0.")
raise SystemExit(not all(checks.values()))
