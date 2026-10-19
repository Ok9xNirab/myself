# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MySelf is a "personal OS" SwiftUI app: dashboard, TODOs, University (classes, syllabus, assignments, exams), Office Tasks, Job Study, Product Dev (Kanban), Workout, and Notes. The UI is a native port of a Claude Design HTML/React prototype (`MySelf.zip`; the macOS variant is `MySelf macOS.html` + `native-app.jsx` + `native.css`; Notes is `notes.jsx` + `notes-editor.jsx` + `notes.css`). When adding or changing screens, treat that prototype as the visual spec.

Current state: **TODOs, labels, office tasks, notes, University and Job Study are persisted and synced** (see "Sync" below). Every other feature still comes from `SampleData` and lives in memory (`AppStore`). Settings are in UserDefaults. Editor sheets outside TODOs, Office Tasks, University and Job Study (edit/delete pencils on some rows) are placeholders with no action yet.

## Build & run

`xcode-select` points at CommandLineTools on this machine, so prefix `xcodebuild` with `DEVELOPER_DIR`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Myself.xcodeproj -scheme Myself -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

- Multiplatform target (macOS, iOS/iPadOS, visionOS; deployment targets 26.x/27.0). macOS is the primary design target; guard AppKit/UIKit-only code with `#if os(macOS)`.
- No test target or linter exists yet.
- One Swift package: **SwiftMath** (LaTeX rendering for Notes), declared in `project.pbxproj`. Resolve with `xcodebuild -resolvePackageDependencies` if a build can't find it.
- `Myself/Fonts/` bundles four OFL Bengali fonts (Noto Sans/Serif Bengali, Hind Siliguri, Tiro Bangla) with their licences. `NoteTypeface` registers them for the process on first use; there's no `Info.plist` font key.
- The project uses a file-system-synchronized group: any `.swift` file placed under `Myself/` is compiled automatically. Do not edit `project.pbxproj` to add files.
- App icon is the Icon Composer bundle `Myself/AppIcon.icon` (`icon.json` + SVG layers in `Assets/`), wired via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Default and dark colours are set per layer with `*-specializations`; the system derives Clear and Tinted (which follows the user's theme colour). Preview any variant with `"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" Myself/AppIcon.icon --export-image --output-file out.png --platform macOS --rendition <Default|Dark|ClearLight|ClearDark|TintedLight|TintedDark> --width 512 --height 512 --scale 1`.
- Build settings: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (everything is main-actor by default; mark helpers called from non-main closures `nonisolated`), Swift 5 language mode, approachable concurrency.

## Architecture

- `MyApp.swift` creates the single `AppStore` (`@Observable`), injects it via `.environment(store)`, applies the light/dark override stored in `@AppStorage("appearance")`, and defines the menu commands (Quick Open ⌘K, Go menu with ⌘[ / ⌘] and ⌘1–⌘8).
- `ContentView.swift` is the `NavigationSplitView` shell: sidebar (sections from `Page.groups`, badge counts from `store.count(for:)`), toolbar (back/forward, search), and a switch from `store.page` to a page view.
- `Models/AppStore.swift` holds the `Page` enum (title, subtitle, SF Symbol, sidebar group), all app data, navigation history (`go`/`back`/`forward`), and all mutations. Views call store methods rather than mutating nested arrays directly.
- `Models/SampleData.swift` is the seed ported from the prototype's `store.js`. Dates are relative to today (`Day.offset(n)`) so the app always looks current.
- `Models/SyncEngine.swift`: file-based persistence and sync (see "Sync").
- `Models/Notes.swift`: `NoteCategory`, `Note` (a title plus `[NoteBlock]`), `NoteBlock.Kind` (p, h1–h3, bullet, num, todo, quote, code, math, hr), `CodeLanguage`, `NoteFont` (per-page Latin design, Bengali typeface, size).
- Notes UI: `Pages/NotesView.swift` (category panel, note list, search, sort, multi-select, drag to a category; fills the detail column instead of using `PageScroll`) and `Pages/NoteEditor.swift` (the block editor). A block shows rendered markdown until clicked, then swaps to `Components/NoteTextView.swift`, an `NSTextView` wrapper that reports Return, Backspace, arrows and Escape to the editor and handles ⌘B/I/E/K and ⇧⌘X/M/H. On iOS it falls back to a plain `TextField`. Rendering helpers: `Support/NoteMarkdown.swift` (inline markdown parser, `MathRenderer` using SwiftMath, which lacks `\operatorname` so it's rewritten to `\mathrm`), `Support/CodeHighlighter.swift` (regex tokenizer and colours), `Support/NoteTypography.swift` (system font with the Bengali face in its cascade list).
- Open the Notes page on a note with `store.openNote(id)`, or create one with `store.newNote()` (⌥⌘N).
- On macOS, double-clicking a note in the list (or Open in New Window in its context menu) opens `Pages/NoteWindow.swift`, a `WindowGroup(id: NoteWindow.id, for: ID.self)` scene; opening the same note again brings its existing window forward. Its "Show in Notes" button brings the main window (`WindowGroup(id: "main")`) forward on that note.
- `Pages/TodoEditorSheet.swift`: the add/edit sheet, opened by setting `store.editingTodo` (`store.newTodo()` for a new one; ⌘N).
- `Pages/OfficeEditorSheet.swift`: the add/edit sheet for an office task (title, notes, reference link, due date; priority is locked to high), opened by setting `store.editingOffice` (`store.newOfficeTask()`; ⇧⌘N). Change tasks with `saveOfficeTask`, `toggleOffice`, `deleteOfficeTask`.
- `Pages/UniversityEditorSheet.swift`: add/edit sheets for classes, assignments, exams and syllabus subjects, opened by setting `store.editingUniversity` (`store.newClass()`, `newAssignment()`, `newExam()`, `newSyllabusSubject()`). Assignments and exams refer to a subject by name; renaming a class renames it on them and on the syllabus. Read the data through `store.university` (`private(set)`) and change it with the store's `save…`/`delete…` methods.
- `Pages/JobStudyView.swift`: subjects panel plus a revision checklist for the selected subject (All / Due / Revised today filters; a topic is due when it wasn't revised in the last `StudyTopic.dueDays` = 7 days). Topics link notes (`noteIDs`) through a search popover; a linked note opens in its own `NoteWindow`, and "New note" creates it in a "Job Study" note category (`store.addTopicNote`). The subject sheet (name, colour) reuses `EditorForm`/`SwatchPicker` from `UniversityEditorSheet.swift`. Change data with `saveStudySubject`, `deleteStudySubject`, `reviseTopic`, `adjustRevisions`, `addStudyTopic`, `renameStudyTopic`, `deleteStudyTopic`, `toggleTopicNote`.
- `Support/Dates.swift`: `Day` helpers (`fromToday`, `sessions(on:count:)`, which generates class dates from weekdays), `DueMeta` (the "Today / Tomorrow / 2d overdue" badge text and tone), `Weekday`, `ClockTime`.
- `Support/Theme.swift`: `Palette` holds the design tokens from `native.css` as adaptive light/dark colors, built with `Color.dynamic(light:dark:)`. Use `Palette.*` and `Color.accentColor` instead of hard-coded colors. User-chosen colors (labels, classes, projects) are stored as `UInt32` hex in the models.
- `Components/Components.swift` contains the shared design-system pieces: `PageScroll` (page padding/max width; it also publishes `pageWidth` into the environment), `AdaptiveColumns` (two columns when wide, stacked when narrow), `Card`, `StatTile`, `Badge`/`PriorityBadge`/`DueBadge`/`LabelChip`, `CheckCircle`, `ProgressBar`, `Donut`, `ColorTabs`, `RowActions` (hover-revealed edit/delete), `FlowLayout`, `ListRow`.
- `Pages/` has one view per sidebar page, plus `QuickOpenView` (the ⌘K palette) and `SettingsView` (the ⌘, window on macOS, a sheet elsewhere; tabs General / Features / iCloud). Open it from code with `store.openSettings(tab)`.
- `Support/Preferences.swift`: `PrefKey` (all `@AppStorage` keys), `AccentChoice`, `SidebarStyle`, `RowDensity` (read by `ListRow` via `\.rowDensity`), and `appPreferences(...)`, which both scenes apply. The accent needs `.accentColor(_:)` as well as `.tint`, because `Color.accentColor` ignores `.tint`.

## Feature visibility

University, Office Tasks, Job Study, Product Dev, Workout and Notes can be turned off in Settings › Features (`store.isEnabled`, `store.setEnabled`, persisted as `disabledFeatures` in UserDefaults). A disabled feature must be hidden everywhere: sidebar (`Page.groups(store.enabledPages)`), Dashboard cards and tiles, Quick Open, and the Go menu. Its data stays in the store. Dashboard and TODOs can't be turned off. When adding UI that surfaces a feature's data outside its own page, guard it with `store.isEnabled(_:)`. Feature visibility and appearance can also sync (see below).

## Sync

There's no paid developer account, so there's no CloudKit or iCloud entitlement. Sync goes through **a folder the user picks in iCloud Drive** (Settings › iCloud). The app reaches it with a security-scoped bookmark, which is why `ENABLE_USER_SELECTED_FILES = readwrite`. It is Mac-to-Mac only.

- Each record is its own JSON file: `todos/<id>.json`, `labels/<id>.json`, `office/<id>.json`, `notecats/<id>.json`, `notes/<id>.json`, `classes/`, `syllabus/` (topics inside the subject file), `jobstudy/` (topics inside the subject file), `assignments/`, `exams/`, `university/notes.json` (the page's notes, saved ~1 s after typing stops like notes), plus `settings.json` for appearance and feature visibility. A type opts in by conforming to `SyncRecord` (`static folder`, `updatedAt`). With sync off, or before a folder is chosen, the same layout lives in `Application Support/<bundle id>/`.
- The folder is the source of truth. Store mutations (`saveTodo`, `toggleTodo`, `deleteTodo`, `addLabel`, `deleteLabel`, `saveOfficeTask`, …) update memory and write the file straight away. `reloadSynced()` re-reads the folder when a file presenter reports a change, when the app becomes active, and on a 30 s poll (5 s while iCloud is still transferring). Never assign `store.todos`/`labels`/`office`/`notes`/`noteCategories`/`university`/`jobStudy` directly; they're `private(set)`.
- Note typing goes through `store.editNote`, which updates memory at once and writes the file about 1 s after typing stops (`saveUnsavedNotes`). Every reload writes pending edits first, so a reload can't bring back older text. Pin and move bump `updatedAt` (sync) but not `editedAt` ("Date edited").
- When two copies of a record conflict, the newer `updatedAt` wins: duplicate files like `<id> 2.json` are merged and leftover `NSFileVersion` conflicts are dropped. Files iCloud hasn't downloaded are skipped, and the in-memory copy is kept until they arrive.
- New installs start with no todos, office tasks, notes, University or Job Study data. The default labels and note categories use fixed IDs (`l1`…`l6`, `nc1`…`nc4`) with `updatedAt = .distantPast`, so two Macs seeding them can't create duplicates or overwrite renames. Settings › Reset loads the sample todos, office tasks, notes, University and Job Study data into the folder.
- Changing the folder or turning sync on/off copies the in-memory records across (`carryData`), never overwriting a newer file.

## Domain rules carried over from the design

- Office tasks and university assignments are always high priority (shown as "High · locked").
- Dashboard "Today's focus" lists todos and office tasks that are due today or overdue, plus assignments due by tomorrow.
- Job Study: ticking a topic adds one revision dated today, and un-ticking it the same day undoes that (`previousRevised` restores the earlier date). The ± stepper corrects the count; + dates it today, and taking it to 0 clears the date. The sidebar badge counts due topics.
- Workout: a program's completed weeks always form a prefix, and weeks after the current one are locked. Programs without `weeks` show a simple counter out of 8 weeks.
- Product Dev boards always have the columns Backlog / In Progress / Review / Done. The sidebar count and the dashboard both read the "In Progress" column by title.
