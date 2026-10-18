# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MySelf is a "personal OS" SwiftUI app: dashboard, TODOs, University (classes, syllabus, assignments, exams), Office Tasks, Job Study, Product Dev (Kanban), and Workout. The UI is a native port of a Claude Design HTML/React prototype (`MySelf.zip`; the macOS variant is `MySelf macOS.html` + `native-app.jsx` + `native.css`). When adding or changing screens, treat that prototype as the visual spec.

Current state is a **static design implementation**: all data comes from `SampleData` and lives in memory (`AppStore`). Only settings are persisted (UserDefaults); app data is not, and editor sheets ("Add todo", "Add class", edit/delete pencils on some rows) are placeholders with no action yet.

## Build & run

`xcode-select` points at CommandLineTools on this machine, so prefix `xcodebuild` with `DEVELOPER_DIR`:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Myself.xcodeproj -scheme Myself -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
```

- Multiplatform target (macOS, iOS/iPadOS, visionOS; deployment targets 26.x/27.0). macOS is the primary design target; guard AppKit/UIKit-only code with `#if os(macOS)`.
- No test target or linter exists yet.
- The project uses a file-system-synchronized group: any `.swift` file placed under `Myself/` is compiled automatically. Do not edit `project.pbxproj` to add files.
- App icon is the Icon Composer bundle `Myself/AppIcon.icon` (`icon.json` + SVG layers in `Assets/`), wired via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Default and dark colours are set per layer with `*-specializations`; the system derives Clear and Tinted (which follows the user's theme colour). Preview any variant with `"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" Myself/AppIcon.icon --export-image --output-file out.png --platform macOS --rendition <Default|Dark|ClearLight|ClearDark|TintedLight|TintedDark> --width 512 --height 512 --scale 1`.
- Build settings: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (everything is main-actor by default; mark helpers called from non-main closures `nonisolated`), Swift 5 language mode, approachable concurrency.

## Architecture

- `MyApp.swift` creates the single `AppStore` (`@Observable`), injects it via `.environment(store)`, applies the light/dark override stored in `@AppStorage("appearance")`, and defines the menu commands (Quick Open ⌘K, Go menu with ⌘[ / ⌘] and ⌘1–⌘7).
- `ContentView.swift` is the `NavigationSplitView` shell: sidebar (sections from `Page.groups`, badge counts from `store.count(for:)`), toolbar (back/forward, appearance toggle, search), and a switch from `store.page` to a page view.
- `Models/AppStore.swift` holds the `Page` enum (title, subtitle, SF Symbol, sidebar group), all app data, navigation history (`go`/`back`/`forward`), and all mutations. Views call store methods rather than mutating nested arrays directly.
- `Models/SampleData.swift` is the seed ported from the prototype's `store.js`. Dates are relative to today (`Day.offset(n)`) so the app always looks current.
- `Support/Dates.swift`: `Day` helpers (`fromToday`, `sessions(on:count:)`, which generates class dates from weekdays), `DueMeta` (the "Today / Tomorrow / 2d overdue" badge text and tone), `Weekday`, `ClockTime`.
- `Support/Theme.swift`: `Palette` holds the design tokens from `native.css` as adaptive light/dark colors, built with `Color.dynamic(light:dark:)`. Use `Palette.*` and `Color.accentColor` instead of hard-coded colors. User-chosen colors (labels, classes, projects) are stored as `UInt32` hex in the models.
- `Components/Components.swift` contains the shared design-system pieces: `PageScroll` (page padding/max width; it also publishes `pageWidth` into the environment), `AdaptiveColumns` (two columns when wide, stacked when narrow), `Card`, `StatTile`, `Badge`/`PriorityBadge`/`DueBadge`/`LabelChip`, `CheckCircle`, `ProgressBar`, `Donut`, `ColorTabs`, `RowActions` (hover-revealed edit/delete), `FlowLayout`, `ListRow`.
- `Pages/` has one view per sidebar page, plus `QuickOpenView` (the ⌘K palette) and `SettingsView` (the ⌘, window on macOS, a sheet elsewhere; tabs General / Features / iCloud). Open it from code with `store.openSettings(tab)`.
- `Support/Preferences.swift`: `PrefKey` (all `@AppStorage` keys), `AccentChoice`, `SidebarStyle`, `RowDensity` (read by `ListRow` via `\.rowDensity`), and `appPreferences(...)`, which both scenes apply. The accent needs `.accentColor(_:)` as well as `.tint`, because `Color.accentColor` ignores `.tint`.

## Feature visibility

University, Office Tasks, Job Study, Product Dev and Workout can be turned off in Settings › Features (`store.isEnabled`, `store.setEnabled`, persisted as `disabledFeatures` in UserDefaults). A disabled feature must be hidden everywhere: sidebar (`Page.groups(store.enabledPages)`), Dashboard cards and tiles, Quick Open, and the Go menu. Its data stays in the store. Dashboard and TODOs can't be turned off. When adding UI that surfaces a feature's data outside its own page, guard it with `store.isEnabled(_:)`. iCloud sync is simulated for now: the toggles and the last-synced time are stored locally, and nothing leaves the device.

## Domain rules carried over from the design

- Office tasks and university assignments are always high priority (shown as "High · locked").
- Dashboard "Today's focus" lists todos and office tasks that are due today or overdue, plus assignments due by tomorrow.
- Job Study: ticking a topic adds one revision dated today, and un-ticking it the same day undoes that (`previousRevised` restores the earlier date).
- Workout: a program's completed weeks always form a prefix, and weeks after the current one are locked. Programs without `weeks` show a simple counter out of 8 weeks.
- Product Dev boards always have the columns Backlog / In Progress / Review / Done. The sidebar count and the dashboard both read the "In Progress" column by title.
