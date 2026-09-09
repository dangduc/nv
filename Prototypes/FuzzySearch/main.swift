// A standalone AppKit experiment. This target does not link or open nvALT.
import AppKit

struct Note: Codable {
    let id: String
    var title: String
    var tags: String
    var body: String
    var candidate: String { title + "\n" + tags + "\n" + body }
    var bodyOffset: Int { (title + "\n" + tags + "\n").utf16.count }
}

final class Cancellation {
    let pointer: OpaquePointer
    init() { pointer = nvfzf_cancel_create()! }
    func cancel() { nvfzf_cancel_set(pointer) }
    var cancelled: Bool { nvfzf_cancel_is_set(pointer) }
    deinit { nvfzf_cancel_free(pointer) }
}

// NSData owns stable byte storage for the duration of every C call.
struct PreparedNote {
    let note: Note
    let bytes: NSData
    init(_ note: Note) {
        self.note = note
        bytes = note.candidate.precomposedStringWithCanonicalMapping.data(using: .utf8)! as NSData
    }
    var input: NVFZFCandidate {
        NVFZFCandidate(bytes: bytes.bytes.assumingMemoryBound(to: CChar.self), length: bytes.length)
    }
}

struct Hit {
    let id: String
    let score: Int
    let rawScore: Int
    let length: Int
}

struct SearchOutput {
    let hits: [Hit]
    let milliseconds: Double
    let preparationMilliseconds: Double
    let error: String?
}

func originalRanges(for scalarPositions: [Int], in text: String, cancel: Cancellation?) -> [NSRange] {
    guard !scalarPositions.isEmpty else { return [] }
    // Normalization can combine codepoints and Cocoa uses UTF-16 offsets.
    // Map only the selected note, not every character of the corpus.
    let wanted = Set(scalarPositions)
    let last = scalarPositions.max()!
    var scalarIndex = 0
    var found: [NSRange] = []
    (text as NSString).enumerateSubstrings(in: NSRange(location: 0, length: text.utf16.count),
                                         options: .byComposedCharacterSequences) { substring, range, _, stop in
        if cancel?.cancelled == true || scalarIndex > last { stop.pointee = true; return }
        let count = (substring ?? "").precomposedStringWithCanonicalMapping.unicodeScalars.count
        if (scalarIndex..<(scalarIndex + count)).contains(where: { wanted.contains($0) }) {
            if let previous = found.last, NSMaxRange(previous) == range.location {
                found[found.count - 1] = NSUnionRange(previous, range)
            } else { found.append(range) }
        }
        scalarIndex += count
    }
    return found
}

final class SearchWorker {
    private let queue = DispatchQueue(label: "nv.prototype.search", qos: .userInitiated)
    private let engine = nvfzf_engine_create()
    private var prepared: [PreparedNote] = [] // Access only on queue.
    private var preparedRevision = -1
    deinit { nvfzf_engine_free(engine) }

    func search(notes: [Note], revision: Int, query: String, mode: NVFZFQueryMode,
                cancel: Cancellation, completion: @escaping (SearchOutput) -> Void) {
        queue.async { [self] in
            autoreleasepool {
                guard !cancel.cancelled else { return }
                let prepareStart = ProcessInfo.processInfo.systemUptime
                if preparedRevision != revision {
                    var next: [PreparedNote] = []
                    next.reserveCapacity(notes.count)
                    for note in notes {
                        if cancel.cancelled { return }
                        next.append(PreparedNote(note))
                    }
                    prepared = next
                    preparedRevision = revision
                }
                let preparation = (ProcessInfo.processInfo.systemUptime - prepareStart) * 1000
                let inputs = prepared.map { $0.input }
                let queryData = query.precomposedStringWithCanonicalMapping.data(using: .utf8)! as NSData
                let started = ProcessInfo.processInfo.systemUptime
                var result = NVFZFSearchResult(matches: nil, count: 0)
                let status = inputs.withUnsafeBufferPointer { buffer in
                    nvfzf_search(engine, buffer.baseAddress, buffer.count,
                                 queryData.bytes.assumingMemoryBound(to: CChar.self), queryData.length,
                                 mode, cancel.pointer, &result)
                }
                defer { nvfzf_search_result_free(&result) }
                guard status != NVFZF_CANCELLED, !cancel.cancelled else { return }
                var hits: [Hit] = []
                if status == NVFZF_OK, let matches = result.matches {
                    hits.reserveCapacity(result.count)
                    for i in 0..<result.count {
                        if i % 256 == 0 && cancel.cancelled { return }
                        let match = matches[i]
                        hits.append(Hit(id: prepared[match.candidate_index].note.id,
                                        score: Int(match.rank_score), rawScore: Int(match.public_score),
                                        length: Int(match.trimmed_length)))
                    }
                }
                let output = SearchOutput(hits: hits,
                    milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000,
                    preparationMilliseconds: preparation,
                    error: status == NVFZF_OK ? nil : String(cString: nvfzf_status_message(status)))
                DispatchQueue.main.async { if !cancel.cancelled { completion(output) } }
            }
        }
    }

    func positions(note: Note, query: String, mode: NVFZFQueryMode, cancel: Cancellation,
                   completion: @escaping ([NSRange]) -> Void) {
        queue.async { [self] in
            autoreleasepool {
                guard !cancel.cancelled else { return }
                let candidate = PreparedNote(note)
                let queryData = query.precomposedStringWithCanonicalMapping.data(using: .utf8)! as NSData
                var output = NVFZFPositions(offsets: nil, count: 0, matched: false)
                let status = nvfzf_positions(engine, candidate.input,
                    queryData.bytes.assumingMemoryBound(to: CChar.self), queryData.length, mode,
                    cancel.pointer, &output)
                defer { nvfzf_positions_free(&output) }
                guard status == NVFZF_OK, !cancel.cancelled else { return }
                let scalars = output.offsets.map { Array(UnsafeBufferPointer(start: $0, count: output.count)).map(Int.init) } ?? []
                let ranges = originalRanges(for: scalars, in: note.candidate, cancel: cancel)
                DispatchQueue.main.async { if !cancel.cancelled { completion(ranges) } }
            }
        }
    }
}

final class NoteCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let excerpt = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        excerpt.font = .systemFont(ofSize: 12)
        excerpt.textColor = .secondaryLabelColor
        for label in [title, excerpt] {
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            excerpt.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            excerpt.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            excerpt.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

final class Prototype: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate,
                       NSSearchFieldDelegate, NSTextViewDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let search = NSSearchField()
    private let modeControl = NSSegmentedControl(labels: ["Fuzzy", "Exact terms"], trackingMode: .selectOne, target: nil, action: nil)
    private let corpusControl = NSPopUpButton()
    private let status = NSTextField(labelWithString: "Loading sample notes…")
    private let title = NSTextField(labelWithString: "Select a note")
    private let tags = NSTextField(labelWithString: "")
    private let details = NSTextField(labelWithString: "")
    private let source = NSTextView()
    private let table = NSTableView()
    private let worker = SearchWorker()
    private var notes: [Note] = []
    private var noteIndexes: [String: Int] = [:]
    private var hits: [Hit] = []
    private var corpusRevision = 0
    private var request = 0
    private var selectionEpoch = 0
    private var appliedRequest = 0
    private var token: Cancellation?
    private var highlightToken: Cancellation?
    private var selectedID: String?
    private var updatingEditor = false
    private var pending = false
    private var deferredReturn: Int?
    private var submittedQuery: String?
    private var submittedRevision = -1
    private var submittedMode: NVFZFQueryMode?
    private var importGeneration = 0
    private var origin = "40 sample notes"
    private var sampleNotes: [Note] = []
    private var suppressedSelection = false
    private let smoke = CommandLine.arguments.contains("--ui-smoke")
    private var smokePhase = 0

    var mode: NVFZFQueryMode { modeControl.selectedSegment == 1 ? NVFZF_NATIVE_EXACT : NVFZF_NATIVE_FUZZY }
    private var queryHasMarkedText: Bool { (search.currentEditor() as? NSTextView)?.hasMarkedText() == true }
    private var resultsAreCurrent: Bool { !pending && appliedRequest == request && !queryHasMarkedText }

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenu()
        makeWindow()
        do {
            let path = Bundle.main.url(forResource: "sample-notes", withExtension: "json")!
            sampleNotes = try JSONDecoder().decode([Note].self, from: Data(contentsOf: path))
            replaceCorpus(sampleNotes, origin: "40 sample notes")
        } catch { status.stringValue = "Could not load sample notes: \(error.localizedDescription)" }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(search)
        if smoke {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                fputs("FAIL: UI smoke timed out\n", stderr); exit(1)
            }
        }
    }

    private func makeMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit NV Search Prototype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let load = fileMenu.addItem(withTitle: "Load Notes Folder…", action: #selector(loadFolder), keyEquivalent: "o")
        load.target = self
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu; menu.addItem(fileItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let find = editMenu.addItem(withTitle: "Search Notes", action: #selector(focusSearch), keyEquivalent: "f")
        find.target = self
        editItem.submenu = editMenu; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func label(_ string: String, size: CGFloat, color: NSColor = .labelColor) -> NSTextField {
        let view = NSTextField(labelWithString: string)
        view.font = .systemFont(ofSize: size); view.textColor = color
        view.lineBreakMode = .byTruncatingTail
        return view
    }

    private func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 850),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "NV Search Prototype"
        window.minSize = NSSize(width: 760, height: 620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let root = NSView(frame: window.contentView!.bounds)
        let rootController = NSViewController()
        rootController.view = root
        window.contentViewController = rootController
        let heading = label("Note Search", size: 23)
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = label("Explore fzf-native matching and ordering", size: 12, color: .secondaryLabelColor)
        let load = NSButton(title: "Load Notes Folder…", target: self, action: #selector(loadFolder))
        load.bezelStyle = .rounded
        corpusControl.addItems(withTitles: ["40 sample notes", "1,000 generated notes", "10,000 generated notes"])
        corpusControl.target = self; corpusControl.action = #selector(changeCorpus)
        let reset = NSButton(title: "Reset Samples", target: self, action: #selector(resetSamples))
        reset.bezelStyle = .rounded
        let headingStack = NSStackView(views: [heading, subtitle])
        headingStack.orientation = .vertical; headingStack.alignment = .leading; headingStack.spacing = 3
        let spacer = NSView()
        let header = NSStackView(views: [headingStack, spacer, corpusControl, reset, load])
        header.orientation = .horizontal; header.spacing = 10
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        search.placeholderString = "Search titles, tags, and complete source text"
        search.font = .systemFont(ofSize: 16)
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = false
        search.setAccessibilityIdentifier("corpus-search")
        modeControl.selectedSegment = 0; modeControl.target = self; modeControl.action = #selector(changeMode)
        let searchRow = NSStackView(views: [search, modeControl])
        searchRow.orientation = .horizontal; searchRow.spacing = 12
        searchRow.setHuggingPriority(.required, for: .vertical)
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)
        search.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let hint = label("fzf syntax: words = AND    'word = exact    !word = exclude    ^word = prefix    | = OR", size: 11, color: .secondaryLabelColor)
        let examples = NSStackView()
        examples.orientation = .horizontal; examples.spacing = 7
        examples.addArrangedSubview(label("Try:", size: 11, color: .secondaryLabelColor))
        for query in ["nebula42", "qzr", "copper lantern", "'cafe", "鴨川", "cobaltquartz"] {
            let button = NSButton(title: query, target: self, action: #selector(example(_:)))
            button.bezelStyle = .roundRect; button.controlSize = .small; button.font = .systemFont(ofSize: 11)
            examples.addArrangedSubview(button)
        }
        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.setAccessibilityIdentifier("search-status")

        let splitController = NSSplitViewController()
        rootController.addChild(splitController)
        // Loading the controller installs its managed split view.
        _ = splitController.view
        let split = splitController.splitView
        split.isVertical = false; split.dividerStyle = .thin
        let listScroll = NSScrollView()
        listScroll.hasVerticalScroller = true; listScroll.autohidesScrollers = true
        table.frame = NSRect(x: 0, y: 0, width: 1000, height: 260)
        table.autoresizingMask = [.width]
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note")))
        let scoreColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("score"))
        scoreColumn.title = "fzf score"; scoreColumn.width = 84; scoreColumn.minWidth = 84; scoreColumn.maxWidth = 84
        table.addTableColumn(scoreColumn)
        table.tableColumns[0].title = "Matching notes · native order"
        table.tableColumns[0].width = 800
        table.rowHeight = 57; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.dataSource = self; table.delegate = self
        table.setAccessibilityIdentifier("search-results")
        listScroll.documentView = table

        let editorPanel = NSView()
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        tags.font = .systemFont(ofSize: 11); tags.textColor = .secondaryLabelColor
        details.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); details.textColor = .secondaryLabelColor
        let sourceScroll = NSScrollView()
        sourceScroll.hasVerticalScroller = true; sourceScroll.autohidesScrollers = true
        source.frame = NSRect(x: 0, y: 0, width: 1000, height: 300)
        source.minSize = NSSize(width: 0, height: 0)
        source.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        source.isVerticallyResizable = true; source.isHorizontallyResizable = false
        source.autoresizingMask = [.width]
        source.textContainer?.containerSize = NSSize(width: 900, height: CGFloat.greatestFiniteMagnitude)
        source.textContainer?.widthTracksTextView = true
        source.isRichText = false; source.isAutomaticQuoteSubstitutionEnabled = false
        source.isAutomaticDashSubstitutionEnabled = false; source.isAutomaticSpellingCorrectionEnabled = false
        source.isAutomaticTextReplacementEnabled = false
        source.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        source.textColor = .textColor; source.backgroundColor = .textBackgroundColor
        source.insertionPointColor = .textColor
        source.textContainerInset = NSSize(width: 12, height: 12)
        source.allowsUndo = true; source.delegate = self; source.isEditable = false
        source.setAccessibilityIdentifier("note-source")
        sourceScroll.documentView = source
        let temporary = label("Source · edits stay in this prototype session. Imported files are never written.", size: 11, color: .secondaryLabelColor)
        for view in [title, tags, details, temporary, sourceScroll] {
            view.translatesAutoresizingMaskIntoConstraints = false; editorPanel.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: editorPanel.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: editorPanel.leadingAnchor, constant: 4),
            title.trailingAnchor.constraint(equalTo: editorPanel.trailingAnchor, constant: -4),
            tags.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            tags.leadingAnchor.constraint(equalTo: title.leadingAnchor), tags.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            details.topAnchor.constraint(equalTo: tags.bottomAnchor, constant: 5),
            details.leadingAnchor.constraint(equalTo: title.leadingAnchor), details.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            sourceScroll.topAnchor.constraint(equalTo: details.bottomAnchor, constant: 10),
            sourceScroll.leadingAnchor.constraint(equalTo: editorPanel.leadingAnchor),
            sourceScroll.trailingAnchor.constraint(equalTo: editorPanel.trailingAnchor),
            sourceScroll.bottomAnchor.constraint(equalTo: temporary.topAnchor, constant: -8),
            temporary.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            temporary.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            temporary.bottomAnchor.constraint(equalTo: editorPanel.bottomAnchor, constant: -2)
        ])
        let listController = NSViewController(); listController.view = listScroll
        let listItem = NSSplitViewItem(viewController: listController)
        listItem.minimumThickness = 120
        let editorController = NSViewController(); editorController.view = editorPanel
        let editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = 230
        splitController.addSplitViewItem(listItem); splitController.addSplitViewItem(editorItem)
        let top = NSStackView(views: [header, searchRow, hint, examples, status])
        top.orientation = .vertical; top.alignment = .leading; top.spacing = 10
        top.setHuggingPriority(.required, for: .vertical)
        // Reserve the controls' fitting height so extra space belongs to the split.
        let headerHeight = top.fittingSize.height
        for view in [top, split] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            top.heightAnchor.constraint(equalToConstant: headerHeight),
            header.widthAnchor.constraint(equalTo: top.widthAnchor), searchRow.widthAnchor.constraint(equalTo: top.widthAnchor),
            status.widthAnchor.constraint(equalTo: top.widthAnchor),
            split.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            split.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        ])
        root.layoutSubtreeIfNeeded()
        split.setPosition(260, ofDividerAt: 0)
        DispatchQueue.main.async { split.setPosition(260, ofDividerAt: 0) }
    }

    @objc private func focusSearch() { window.makeFirstResponder(search); search.selectText(nil) }
    @objc private func changeMode() { deferredReturn = nil; submit() }
    @objc private func example(_ sender: NSButton) {
        search.stringValue = sender.title; window.makeFirstResponder(search); submit()
    }
    @objc private func resetSamples() { corpusControl.selectItem(at: 0); changeCorpus() }
    @objc private func changeCorpus() {
        importGeneration += 1
        let count = [40, 1000, 10000][corpusControl.indexOfSelectedItem]
        if count == 40 { replaceCorpus(sampleNotes, origin: "40 sample notes"); return }
        let generated = (0..<count).map { i -> Note in
            var note = sampleNotes[i % sampleNotes.count]
            note = Note(id: String(format: "generated-%06d", i), title: "\(note.title) · \(i + 1)",
                        tags: note.tags, body: note.body + "\n\nRecord \(i + 1). Batch \(i / 100).")
            return note
        }
        replaceCorpus(generated, origin: "\(count.formatted()) generated notes")
    }
    private func replaceCorpus(_ values: [Note], origin: String) {
        token?.cancel(); highlightToken?.cancel(); deferredReturn = nil
        let wasEditingSource = window.firstResponder === source
        notes = values.sorted { $0.id < $1.id }
        noteIndexes = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($0.element.id, $0.offset) })
        corpusRevision += 1; self.origin = origin
        selectedID = nil; hits = []; table.reloadData()
        updatingEditor = true; source.isEditable = false; source.string = ""
        source.undoManager?.removeAllActions(); updatingEditor = false
        title.stringValue = "Select a note"; tags.stringValue = ""; details.stringValue = ""
        if wasEditingSource { window.makeFirstResponder(search) }
        submit()
    }

    @objc private func loadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Load UTF-8 text notes into this temporary prototype. Files stay unchanged."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let folder = panel.url else { return }
            self.importGeneration += 1
            let generation = self.importGeneration
            self.status.stringValue = "Reading text files…"
            DispatchQueue.global(qos: .userInitiated).async {
                let supported: Set<String> = ["txt", "md", "markdown", "textile", "html", "htm", "json", "yaml", "yml", "toml", "xml", "csv", "log"]
                var imported: [Note] = [], skipped = 0, totalBytes = 0
                let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                if let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let url as URL in enumerator {
                        guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                        guard values.isSymbolicLink != true, supported.contains(url.pathExtension.lowercased()),
                              (values.fileSize ?? Int.max) <= 16 * 1024 * 1024, imported.count < 20000,
                              totalBytes + (values.fileSize ?? 0) <= 128 * 1024 * 1024,
                              let data = try? Data(contentsOf: url),
                              let text = String(data: data, encoding: .utf8) else { skipped += 1; continue }
                        let relative = String(url.path.dropFirst(folder.path.count + 1))
                        imported.append(Note(id: relative, title: url.deletingPathExtension().lastPathComponent,
                                             tags: url.pathExtension, body: text))
                        totalBytes += data.count
                    }
                }
                DispatchQueue.main.async {
                    guard self.importGeneration == generation else { return }
                    if imported.isEmpty {
                        self.status.stringValue = "No supported UTF-8 notes found. \(skipped) files skipped."
                    } else {
                        self.replaceCorpus(imported, origin: "\(folder.lastPathComponent) · \(skipped) files skipped")
                    }
                }
            }
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === search else { return }
        deferredReturn = nil
        submitCommittedQueryIfNeeded()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if textView.hasMarkedText() { deferredReturn = nil; return false }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if pending { deferredReturn = request } else { activateResult() }
            return true
        }
        if selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.moveUp(_:)) {
            guard resultsAreCurrent, !hits.isEmpty else { return true }
            let delta = selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let next = min(hits.count - 1, max(0, table.selectedRow + delta))
            table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            table.scrollRowToVisible(next)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            deferredReturn = nil
            if !search.stringValue.isEmpty { search.stringValue = ""; submit() }
            return true
        }
        return false
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSSearchField === search else { return }
        deferredReturn = nil
        submitCommittedQueryIfNeeded()
    }

    private func suspendForQueryComposition() {
        deferredReturn = nil
        token?.cancel(); highlightToken?.cancel(); clearHighlights()
        request += 1; submittedQuery = nil; pending = true
        status.stringValue = "Finish composing to search…"
    }

    private func submitCommittedQueryIfNeeded() {
        guard !queryHasMarkedText else { suspendForQueryComposition(); return }
        if submittedQuery != search.stringValue || submittedRevision != corpusRevision ||
           submittedMode != mode || token?.cancelled != false {
            submit()
        }
    }

    private func submit() {
        guard !queryHasMarkedText else { suspendForQueryComposition(); return }
        token?.cancel(); highlightToken?.cancel()
        clearHighlights()
        let cancellation = Cancellation(); token = cancellation
        request += 1
        let expectedRequest = request, expectedRevision = corpusRevision, intent = selectionEpoch
        let query = search.stringValue
        submittedQuery = query; submittedRevision = expectedRevision; submittedMode = mode
        let started = ProcessInfo.processInfo.systemUptime
        pending = true
        status.stringValue = "Searching \(notes.count.formatted()) notes…"
        worker.search(notes: notes, revision: expectedRevision, query: query, mode: mode, cancel: cancellation) { [weak self] output in
            guard let self, self.request == expectedRequest, self.corpusRevision == expectedRevision else { return }
            guard !self.queryHasMarkedText else { self.suspendForQueryComposition(); return }
            guard self.search.stringValue == query else { return }
            self.pending = false
            if let error = output.error {
                self.status.stringValue = "Search failed: \(error)"; self.deferredReturn = nil
                if self.smoke { self.advanceSmoke() }
                return
            }
            self.hits = output.hits; self.appliedRequest = expectedRequest
            self.suppressedSelection = true
            self.table.reloadData()
            let editing = self.window.firstResponder === self.source &&
                self.selectedID.flatMap { self.noteIndexes[$0] } != nil
            var row: Int?
            if editing || self.selectionEpoch != intent {
                row = self.hits.firstIndex { $0.id == self.selectedID }
            } else { row = self.hits.isEmpty ? nil : 0 }
            if let row { self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            else { self.table.deselectAll(nil) }
            self.suppressedSelection = false
            if let row { self.showNote(self.hits[row].id, preserveEditor: editing) }
            else if !editing { self.showNote(nil) }
            let wall = (ProcessInfo.processInfo.systemUptime - started) * 1000
            self.status.stringValue = String(format: "%@ of %@ notes · search %.1f ms · prepare %.1f ms · response %.1f ms · %@",
                self.hits.count.formatted(), self.notes.count.formatted(), output.milliseconds,
                output.preparationMilliseconds, wall, self.origin)
            if self.deferredReturn == expectedRequest {
                self.deferredReturn = nil
                if !self.queryHasMarkedText && self.window.firstResponder === self.search.currentEditor() { self.activateResult() }
            }
            if self.smoke { self.advanceSmoke() }
        }
    }

    private func activateResult() {
        guard resultsAreCurrent, !hits.isEmpty else { return }
        let row = max(0, table.selectedRow)
        showNote(hits[row].id)
        window.makeFirstResponder(source)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { hits.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { resultsAreCurrent }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < hits.count, let index = noteIndexes[hits[row].id] else { return nil }
        let hit = hits[row], note = notes[index]
        if tableColumn?.identifier.rawValue == "score" {
            let key = NSUserInterfaceItemIdentifier("scoreCell")
            let field = (tableView.makeView(withIdentifier: key, owner: nil) as? NSTextField) ?? label("", size: 12)
            field.identifier = key; field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.stringValue = String(hit.score)
            field.toolTip = "Native rank score: \(hit.score)\nPublic score: \(hit.rawScore)\nTrimmed candidate length key: \(hit.length)"
            return field
        }
        let key = NSUserInterfaceItemIdentifier("noteCell")
        let cell = (tableView.makeView(withIdentifier: key, owner: nil) as? NoteCell) ?? NoteCell(frame: .zero)
        cell.identifier = key; cell.title.stringValue = note.title
        let prefix = note.body.prefix(180).replacingOccurrences(of: "\n", with: " ")
        cell.excerpt.stringValue = note.tags.isEmpty ? prefix : "\(note.tags)  ·  \(prefix)"
        cell.toolTip = note.title
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressedSelection, resultsAreCurrent, table.selectedRow >= 0, table.selectedRow < hits.count else { return }
        selectionEpoch += 1; deferredReturn = nil
        showNote(hits[table.selectedRow].id)
    }

    private func showNote(_ id: String?, preserveEditor: Bool = false) {
        highlightToken?.cancel(); clearHighlights()
        guard let id, let index = noteIndexes[id] else {
            selectedID = nil; title.stringValue = hits.isEmpty ? "No matching notes" : "Select a note"
            tags.stringValue = ""; details.stringValue = ""
            updatingEditor = true; source.string = ""; source.undoManager?.removeAllActions(); updatingEditor = false
            source.isEditable = false
            return
        }
        let note = notes[index], changed = selectedID != id
        selectedID = id; title.stringValue = note.title; tags.stringValue = note.tags
        source.isEditable = true
        if changed || (!preserveEditor && source.string != note.body) {
            updatingEditor = true; source.string = note.body; source.undoManager?.removeAllActions(); updatingEditor = false
            source.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
        let hit = hits.first { $0.id == id }
        details.stringValue = hit.map { "Native score \($0.score) · length key \($0.length) · \(note.body.utf8.count.formatted()) source bytes" }
            ?? "The current note no longer matches this query."
        guard !search.stringValue.isEmpty, !source.hasMarkedText() else { return }
        let cancel = Cancellation(); highlightToken = cancel
        let expectedRequest = request, expectedRevision = corpusRevision
        worker.positions(note: note, query: search.stringValue, mode: mode, cancel: cancel) { [weak self] ranges in
            guard let self, self.request == expectedRequest, self.corpusRevision == expectedRevision,
                  self.selectedID == id, self.source.string == note.body, !self.source.hasMarkedText() else { return }
            self.clearHighlights()
            let bodyRange = NSRange(location: note.bodyOffset, length: note.body.utf16.count)
            let bodyHits = ranges.compactMap { range -> NSRange? in
                let overlap = NSIntersectionRange(range, bodyRange)
                return overlap.length > 0 ? NSRange(location: overlap.location - note.bodyOffset, length: overlap.length) : nil
            }
            for range in bodyHits {
                self.source.layoutManager?.addTemporaryAttribute(.backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.33), forCharacterRange: range)
            }
            if let first = bodyHits.first, !preserveEditor { self.source.scrollRangeToVisible(first) }
            if !ranges.isEmpty {
                self.details.stringValue += " · \(bodyHits.count) source highlight runs"
            }
        }
    }
    private func clearHighlights() {
        source.layoutManager?.removeTemporaryAttribute(.backgroundColor,
            forCharacterRange: NSRange(location: 0, length: source.string.utf16.count))
    }
    func textDidChange(_ notification: Notification) {
        guard !updatingEditor, notification.object as? NSTextView === source else { return }
        highlightToken?.cancel(); clearHighlights(); deferredReturn = nil
        guard !source.hasMarkedText(), let id = selectedID, let index = noteIndexes[id] else { return }
        notes[index].body = source.string; corpusRevision += 1
        submit()
    }
    func windowWillClose(_ notification: Notification) {
        request += 1; importGeneration += 1; token?.cancel(); highlightToken?.cancel()
        NSApp.terminate(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func advanceSmoke() {
        func require(_ value: Bool, _ message: String) {
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        switch smokePhase {
        case 0:
            require(hits.count == 40, "initial sample count")
            let listScroll = table.enclosingScrollView!
            let listFrame = listScroll.convert(listScroll.bounds, to: window.contentView)
            let statusFrame = status.convert(status.bounds, to: window.contentView)
            let headerGap = statusFrame.minY - listFrame.maxY
            let sourceViewport = source.enclosingScrollView!.contentView.visibleRect
            print(String(format: "UI GEOMETRY: header gap %.1f pt, notes pane %.1f pt, visible table %.1f × %.1f pt, source viewport %.1f × %.1f pt",
                         headerGap, listFrame.height, table.visibleRect.width, table.visibleRect.height,
                         sourceViewport.width, sourceViewport.height))
            require(headerGap >= 0 && headerGap < 30, "notes list starts directly below header content")
            require(table.visibleRect.width > 400 && table.visibleRect.height > 200, "notes list has visible geometry")
            require(sourceViewport.width > 400 && sourceViewport.height > 80, "source editor has visible geometry")
            smokePhase = 1
            search.stringValue = "never-match-000-invalid"; submit()
            search.stringValue = "'nebula42"; submit()
        case 1:
            require(search.stringValue == "'nebula42" && !hits.isEmpty, "latest request wins")
            require(hits.allSatisfy { notes[noteIndexes[$0.id]!].candidate.lowercased().contains("nebula42") }, "body-only hit identity")
            require(selectedID != nil && !source.string.isEmpty, "selection displays source")
            smokePhase = 2; search.stringValue = ""; submit()
        case 2:
            require(hits.count == 40, "clear returns complete corpus")
            let saved = notes[noteIndexes[selectedID!]!]
            window.makeFirstResponder(source)
            source.setSelectedRange(NSRange(location: source.string.utf16.count, length: 0))
            source.insertText("\nprototypeeditfixturexyz", replacementRange: source.selectedRange())
            require(notes[noteIndexes[saved.id]!].body.contains("prototypeeditfixturexyz"), "temporary source edit commits")
            smokePhase = 3; window.makeFirstResponder(search)
            search.stringValue = "prototypeeditfixturexyz"; submit()
        case 3:
            require(hits.count == 1 && source.string.contains("prototypeeditfixturexyz"), "source edit searchable")
            smokePhase = 4; search.stringValue = ""; submit()
        case 4:
            require(hits.count == 40, "complete corpus before failure")
            smokePhase = 5; search.stringValue = "invalid\u{0}query"; submit()
        case 5:
            require(status.stringValue.hasPrefix("Search failed:") && !pending, "terminal query failure")
            require(hits.count == 40 && appliedRequest != request, "failed query retains obsolete rows")
            let previousID = selectedID, previousIntent = selectionEpoch
            require(!tableView(table, shouldSelectRow: 1), "failed query rejects mouse selection")
            table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: table))
            activateResult()
            require(selectedID == previousID && selectionEpoch == previousIntent, "stale row cannot activate a note")
            window.makeFirstResponder(source)
            search.stringValue = ""; smokePhase = 6
            replaceCorpus(sampleNotes, origin: "40 sample notes")
            require(selectedID == nil && !source.isEditable && source.string.isEmpty, "corpus replacement disables orphan editor")
        case 6:
            require(selectedID != nil && source.isEditable && hits.count == 40, "replacement corpus selects an editable note")
            smokePhase = 7; search.stringValue = "'nevermatchzzzzzzzzzzzzzzzzzzzzzzzz"; submit()
        case 7:
            require(hits.isEmpty && selectedID == nil, "final zero results")
            print("UI SMOKE PASSED: initial corpus, supersession, body search, selection, clear, temporary edit, failure selection, corpus replacement, zero results")
            NSApp.terminate(nil)
        default: break
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    func check(_ value: Bool, _ message: String) {
        if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    let text = "😀 cafe\u{301} 鴨川 🧑🏽‍💻"
    let positions = [0, 5, 7, 10]
    let ranges = originalRanges(for: positions, in: text, cancel: nil)
    check(ranges.allSatisfy { NSMaxRange($0) <= text.utf16.count }, "mapped bounds")
    let pieces = ranges.map { (text as NSString).substring(with: $0) }
    check(pieces.contains("😀") && pieces.contains("e\u{301}") && pieces.contains("鴨") && pieces.contains("🧑🏽‍💻"), "NFC scalar to original grapheme mapping")
    let note = Note(id: "test", title: "Title", tags: "tag", body: "Body")
    check(note.bodyOffset == 10 && note.candidate == "Title\ntag\nBody", "candidate/source offsets")
    let token = Cancellation(); check(!token.cancelled, "initial token")
    token.cancel(); check(token.cancelled, "cancel token")
    print("SWIFT CHECKS PASSED: original Unicode ranges, field offsets, cancellation")
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let prototype = Prototype()
application.delegate = prototype
application.run()
