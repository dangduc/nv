# Renderer limit failure fix

The renderer now creates a parser context for each request and captures its structured errors.
It keeps resource failures even if a later HTML diagnostic replaces the parser's last error.
The callback uses the existing libxml APIs available at the macOS 10.13 deployment target.

Memory, text-node, name, and nesting limits return `NVMarkupLimitExceeded` without a render result.
Other fatal parser errors return `NVMarkupInvalidOutput`.
Ordinary recovered HTML and HTML5 elements still render.
The parser keeps its default resource limits. No process-wide error handler is installed.

Validation:

- `python3 Tests/Regression/source-viewers/run.py` passed 113 checks.
- The 9 MiB paragraph retains its start marker, end marker, and following HTML5 section.
- The 11 and 15 MiB paragraphs return an error without partial output.
- A 16 MiB source with separate bounded paragraphs renders both boundary markers.
- One byte above 16 MiB returns a source-limit error.
- A 240-level nested document preserves its inner text. A 300-level document returns a parser-limit error.
- Existing malformed HTML recovery, HTML5, Unicode, helper, cancellation, and concurrent-request checks pass.
- The new tests fail against the pre-fix renderer at the 11 MiB paragraph assertion.

The original boundary probe also passes its 9 MiB control and reports errors for both larger cases:

```text
9437184 input=9437217 output=9438152 start=1 end=1 error=none
11534336 input=11534369 output=0 start=0 end=0 error=The generated HTML exceeds the parser's resource limits.
15728640 input=15728673 output=0 start=0 end=0 error=The generated HTML exceeds the parser's resource limits.
```

These checks compile an Intel binary with a macOS 10.13 minimum target.
They run on the current host; they do not establish runtime validation on macOS 10.13.
