# Library switching

Changing the notes folder replaces the library under every open browser window. During that
replacement the table is given a fresh data source while its own row count still describes the
previous library, and `-[NotesTableView viewingLocation]` used to index the data source's backing
array using that cached count:

```objc
if (pivotRow < nRows) {                                  // nRows = [self numberOfRows]
    ... [(FastListDataSource*)[self dataSource] immutableObjects][pivotRow]
```

`-[FastListDataSource fillArrayFromArray:]` only allocates its backing array when the new count
exceeds the old one, so a data source that has never held a row returns NULL from
`-immutableObjects`. Indexing it crashed with `EXC_BAD_ACCESS` at address 0x0. Measured at the
crash: `immutableObjects` NULL, `[self numberOfRows]` 1, `[[self dataSource] count]` 0.

The crash needs a library with rows on the way back, so switching to an empty folder and then
returning to the original one is the reproduction.

These checks cover:

- a data source that has never held a row reports zero rows and a NULL backing array
- changing the notes folder installs a different library and opens an empty folder as empty
- switching back to the original folder restores its notes without crashing

The stale-count window cannot be staged directly, because `-setDataSource:` invalidates the
table's cached row count. It opens only during a real library switch, so these checks drive the
switch end to end through the `setAliasDataForDefaultDirectory:sender:` default that the
Preferences "Other..." item writes.

Run after a Development build, from an active desktop session:

```sh
python3 Tests/Regression/library-switch/run.py
```

Reverting the guard in `-[NotesTableView viewingLocation]` must crash these checks.
