# Smart Collections (KOReader plugin)

Smart Collections adds AO3-style, metadata‑driven filtering and auto‑updating “smart shelves” to KOReader’s file browser.

It reuses the metadata KOReader already knows about (especially from Calibre) and lets you:

- Filter your library by tags, authors, series, collections, reading status, and custom Calibre columns.
- Create “smart collections” (saved searches) that automatically stay up to date as your library changes.
- Browse results in a normal book list, with full metadata and summary.
- Optionally bind Smart Collections to gestures/hotkeys or custom toolbar buttons via Dispatcher actions.

This plugin is self‑contained and does not modify KOReader’s core files.

## Installation

1. Download or clone this plugin so that you have a folder named:

   - `smartcollections.koplugin/`

2. Copy that folder into KOReader’s user plugin directory on your device:

   - If you run KOReader from a folder:
     - Put it in `koreader/plugins/`
   - If you use `KO_HOME` (e.g. on desktop builds):
     - Put it in `$KO_HOME/plugins/`

3. Restart KOReader.

4. In KOReader, go to:

   - `Tools → Plugin management` and ensure **Smart Collections** is enabled if needed.

## Where to find it in KOReader

Once enabled, Smart Collections integrates in three places:

- **Search menu (File browser)**  
  - Open the top toolbar → **Search** tab → **Smart Collections**  
  - This opens the main filter dialog.

- **Tools → Smart Collections submenu**
  - `Tools → Smart Collections ▸`
    - `Smart Collections` — opens the filter dialog (same as above).
    - `Smart Collections: settings` — choose which custom columns are filterable.
    - `Smart Collections: show custom columns` — debug view of detected Calibre custom columns.

- **Dispatcher actions (for gestures/hotkeys/toolbar patches)**
  - `smartcollections_filter` → opens the filter dialog.
  - `smartcollections_settings` → opens the Smart Collections settings screen.

## Metadata sources and requirements

Smart Collections prefers Calibre metadata when available, but it is designed to degrade gracefully.

It will read metadata from, in order of preference:

1. **Calibre Companion / Calibre search cache** (if present in KOReader’s data directory).
2. **Calibre’s `.metadata.calibre` JSON file** for enabled libraries (via KOReader’s Calibre integration).
3. **KOReader’s Read History** as a last resort (so you can still filter recent books by status/collections even without Calibre).

For full functionality (especially custom columns), using KOReader with a Calibre library is strongly recommended.

## Quick start: basic filter

1. In the file browser, open the search menu and choose **Smart Collections**.
2. In the main dialog:
   - `Tags to include` — e.g. `fluff, hurt/comfort`
   - `Tags to exclude` — e.g. `angst, incomplete`
3. Tap **Search**.

You’ll see a results screen with:

- A list of matching books (title + authors).
- Long‑press on a book to see full details (series, tags, summary/comments).
- A `+` button in the title bar to save results as a collection or smart collection.

## Filtering options

The filter dialog has two levels: quick tag filters and a “More filters…” screen.

### Tag filters (main dialog)

Fields:

- **Tags to include**
- **Tags to exclude**

Hints:

- Tags are comma‑separated (`fluff, romance, space opera`).
- The dialog shows a “Top tags: …” line above the include field:
  - On the first search: based on the whole library.
  - When refining a search: based only on the current result set.

Hierarchical tags (e.g. `5 - Movies and TV Shows.3 - (G - I).Harry Potter`) are split, and **searching by the last component** (`harry potter`) will match them.

### More filters…

Tap **More filters…** in the main dialog to open an additional menu with:

- **Authors…**
- **Series…**
- **Status…** (`new`, `reading`, `finished`, `abandoned`, etc.)
- **Collections…** (include / exclude KOReader collections)
- **Custom columns…**

Each submenu provides:

- “include” and/or “exclude” fields (comma‑separated, case‑insensitive).
- A compact summary so you can see what’s configured at a glance.

### Custom Calibre columns

Smart Collections detects Calibre custom columns and classifies them as:

- **Hierarchical** — values containing dots (`.`), e.g. nested categories.
- **Numeric** — Calibre datatypes like `int`, `float`, `rating`, or strings that look numeric.

You can pick which columns are filterable under:

- `Tools → Smart Collections ▸ Smart Collections: settings`

Then, in **More filters → Custom columns…**, you can define per‑column rules.

For each enabled column:

- Non‑numeric columns:
  - “Values to include” and “Values to exclude” (comma‑separated).
  - Matching is case‑insensitive substring.
  - Hierarchical columns are matched only against the **last part** of the value.
  - The dialog shows **Top values: …** based on either the whole library or the current result set (when refining).

- Numeric columns:
  - You can use expressions like:
    - `>= 10000`
    - `> 50000`
    - `<= 200000`
    - `= 75000` or simply `75000`
  - Commas and spaces in numbers are ignored (`10,000` is fine).
  - These are interpreted as numeric comparisons on the column value.
  - If parsing fails, the value is treated as a simple include string.

Example:

- `#words` (numeric) with filter `>= 10000` matches books with at least 10,000 words.
- `#fandoms` (hierarchical) with include `Harry Potter` matches values like  
  `5 - Movies and TV Shows.3 - (G - I).Harry Potter`.

## Saving and using Smart Collections

From the results screen:

1. Tap the `+` icon in the title bar.
2. In **Save results as collection**:
   - Enter a collection name.
   - Choose:
     - **Save static** — one‑time snapshot collection.
     - **Save smart** — a “smart collection” backed by the current filters.

Behavior:

- Static collections behave like any other KOReader collection.
- Smart collections:
  - Store both the filter definition and the last generated path list.
  - Are automatically rebuilt on KOReader startup and whenever Smart Collections runs its rebuild hook.
  - Are written into KOReader’s regular collections so they look like normal shelves.

Deleting a smart collection from KOReader’s standard collections menu also removes its saved filter, so it will not be recreated.

## Refining a search

When viewing results:

- Tap the `+` button and choose **Refine search**:
  - The filter dialog opens with your previous filters pre‑filled.
  - “Top tags” and “Top values” hints are computed from **the current result set**, not the full library.
  - After you adjust the filters and press **Search**, the new result list is a **subset** of the previous one (not a full restart).

## Dispatcher integration (gestures, hotkeys, custom buttons)

Smart Collections exposes two Dispatcher actions you can bind via:

- `Tools → Taps and gestures → Gesture manager`
- Hotkey plugins
- User patches (e.g. toolbar button replacements)

Actions:

- `smartcollections_filter`
  - Category: `general=true`, `filemanager=true`.
  - Opens the Smart Collections filter dialog in the file browser.

- `smartcollections_settings`
  - Category: `general=true`, `filemanager=true`.
  - Opens the Smart Collections settings menu (custom columns configuration).

Example (gesture):

1. Enable gestures in settings.
2. Assign a gesture (e.g. “lower corner tap”) to:
   - General → **Smart Collections filter**.

Example (toolbar button via user patch):

- A patch can call:

  ```lua
  Dispatcher:execute({ "smartcollections_filter" })

The user interface may be a bit cluncky for the moment, I have some ideas for better design but am not sure which direction to go to. If anyone has suggestions it would be appreciated. 

I have never done something like this before so a lot of this was pieced together from other plugins and patches and chat-gpt. I made this mostly for myself because I desperatly needed something that let me perform more complex metadata searches then what I was seeing shipped with KOReader. 

So far I have only tested it on the linux emulator and on my boox (android) reader, so if you test somewhere else and find a problem, please let me know. It was also only tested in the 2025.10 release of KOReader (https://github.com/koreader/koreader/releases/tag/v2025.10).
