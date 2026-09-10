Round 1 review — Linus Torvalds-inspired perspective on native correctness and packaging. This does not represent his views.

**[P1] Bound the complete Org scanner state before serialization**

At `ThirdParty/TreeSitter/org/src/scanner.c:111`, the serializer appends its math flag after loops that can consume the entire buffer. The runtime checks the returned size only after this write. The format also clamps its count independently of the copied payload, narrows stack values, and decodes counts without a complete length check. Before this dependency ships, the scanner needs consistent counts and widths, complete capacity accounting, and validated decoding. Unsupported state must select plain-source fallback rather than partial scanner state. This is a defensive source finding. No crashing input was constructed.

Evidence: `Tests/OrgSourceReview/round1/torvalds/run.py` compiled the production runtime and Org wrappers for Intel and arm64. Thirteen ordinary fixtures passed **2,014 checks per architecture**, including incremental/fresh tree equality and byte-range bounds. Package checks passed for the pinned file hashes, bundled query and notice, document registration, and the Intel application's macOS 10.13 deployment target. Actual macOS 10.13 execution was not checked.

Full report and captured output: `Tests/OrgSourceReview/round1/torvalds/`.
