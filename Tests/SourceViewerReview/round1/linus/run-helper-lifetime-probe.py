#!/usr/bin/env python3
from pathlib import Path
import os
import plistlib
import subprocess
import tempfile
root = Path(__file__).resolve().parents[4]
sdk = Path(subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip())
with tempfile.TemporaryDirectory(prefix='nvalt-linus-helper-review-') as temp:
    temp = Path(temp)
    bundle = temp/'Converters.bundle'
    resources = bundle/'Contents/Resources'
    resources.mkdir(parents=True)
    (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.nvalt.review.helper','CFBundlePackageType':'BNDL'}))
    helper = resources/'multimarkdown'
    helper.write_text('#!/usr/bin/perl\n$SIG{TERM}=sub{}; open(my $fh, ">", $ENV{NV_REVIEW_PID}) or die $!; print $fh $$; close($fh); while (1) { select(undef,undef,undef,.02); }\n')
    helper.chmod(0o755)
    binary = temp/'helper-lifetime-probe'
    subprocess.run(['xcrun','clang','-arch','x86_64','-mmacosx-version-min=10.13','-fno-objc-arc','-fblocks','-lxml2','-I',str(sdk/'usr/include/libxml2'),'-framework','Foundation','-I',str(root/'Sources/Preview'),str(root/'Sources/Preview/NVNoteContentSnapshot.m'),str(root/'Sources/Preview/NVMarkupRenderer.m'),str(Path(__file__).with_name('helper-lifetime-probe.m')),'-o',str(binary)],check=True)
    pidfile = temp/'helper.pid'
    try:
        subprocess.run([str(binary),str(bundle),str(pidfile)],env={**os.environ,'NV_REVIEW_PID':str(pidfile)},check=True,timeout=12)
    finally:
        if pidfile.exists():
            try:
                os.kill(int(pidfile.read_text()),9)
            except ProcessLookupError:
                pass
