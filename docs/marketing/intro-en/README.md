# English introduction images

The six README images use real English UI captures from the current Debug app.
Each image is an independent 2880 x 1800 composition, with the headline and
subtitle editable in the app-store-screenshots editor. The fourth image uses a
dark presentation area for contrast. The images remain independent so each
README table cell makes sense on its own.

## Source files

- `project.json`: editable English copy, element positions, typography, and deck
  settings. This is the canonical editor project.
- `compose.py`: vector compositions, screenshot crop rectangles, and export
  import. It uses only the Python standard library.
- `captures/`: seven original English JPEG captures made with disposable demo
  repositories. They include a selection view and its confirmation sheet.
- `../../images/intro-en/`: the six PNGs used by the repository README.

Generated SVG compositions and the editor's dependencies stay in a disposable
editor directory. These documentation assets are outside the app target.

## Capture fresh UI

From the repository root, run each scenario with an English Debug build:

```sh
WORKTREE_DEMO_LANGUAGE=en WORKTREE_DEMO_SCENARIO=cleanup \
  WORKTREE_DEMO_ROOT=/tmp/wtc-en-repositories ./scripts/run-demo.sh

WORKTREE_DEMO_LANGUAGE=en WORKTREE_DEMO_SCENARIO=locations \
  WORKTREE_DEMO_ROOT=/tmp/wtc-en-locations ./scripts/run-demo.sh

WORKTREE_DEMO_LANGUAGE=en WORKTREE_DEMO_SCENARIO=disk-usage \
  WORKTREE_DEMO_ROOT=/tmp/wtc-en-disk ./scripts/run-demo.sh

WORKTREE_DEMO_LANGUAGE=en WORKTREE_DEMO_SCENARIO=decision \
  WORKTREE_DEMO_ROOT=/tmp/wtc-en-decision ./scripts/run-demo.sh
```

Close the previous demo instance before launching the next scenario. Capture
only the generated repositories, keeping personal workspace data out of images.

1. For `01-repositories.jpg`, show the sidebar with `aurora-editor` selected.
2. For `02-locations.jpg`, hide the sidebar, clear the selection, and scroll the
   table horizontally to its right edge so full paths are visible.
3. For `03-disk-usage.jpg`, keep the sidebar hidden, clear the selection, and
   leave the horizontal scroll position at the left edge.
4. For `04-cleanup-decision.jpg`, sort **Branch** in ascending order and clear
   the selection. The linked rows should be completed, experiment, and in-progress.
5. For `05-batch-selected.jpg`, select the two clean linked worktrees. The main
   worktree and uncommitted work remain unselected.
6. Open the batch cleanup confirmation and save the sheet as
   `06-batch-confirmation.jpg`. Cancel after capturing it.
7. For `07-sort-select.jpg`, use a disposable repository with six merged linked
   worktrees: `agent/docs`, `agent/layout`, `agent/preview`, `agent/release`,
   `agent/search`, and `agent/theme`. Leave an uncommitted edit in `agent/layout`
   and lock `agent/release`. Hide the sidebar, sort **Branch** in ascending order,
   and clear the selection. Click the `agent/docs` checkbox, then Shift-click
   `agent/theme`. Capture the resulting four selected worktrees; the dirty and
   locked rows remain unselected. This screenshot illustrates range selection
   alongside the four supported sort columns.

Save the JPEGs under `captures/`. The first five window captures use approximately
2912 x 1898 pixels, the confirmation sheet uses 1080 x 694 pixels, and the
sort-and-select capture uses 2200 x 1440 pixels. When window
geometry or table columns change, update the crop rectangles in `compose.py`.
Update displayed example measurements if the fresh app reports different values.

## Edit and export

Install the app-store-screenshots skill and copy its prebuilt editor template to
a disposable directory. Set `SCREENSHOT_SKILL_DIR` to that skill's installed
directory; the source files do not depend on a particular user's installation.

```sh
SCREENSHOT_SKILL_DIR=/path/to/app-store-screenshots
editor_dir="$(mktemp -d "${TMPDIR:-/tmp}/wtc-intro-editor.XXXXXX")"
cp -R "$SCREENSHOT_SKILL_DIR/template/." "$editor_dir/"
python3 docs/marketing/intro-en/compose.py --editor "$editor_dir"
cd "$editor_dir"
bun install
bun dev
```

Open the URL printed by the editor. Edit the English deck, inspect each image at
full size and as a small thumbnail, then click **Export bundle**. The editor
exports all four Mac sizes with an opaque RGB background. Keep the 2880 x 1800
files for the README.

From the repository root, save any editor changes and import the exported ZIP:

```sh
cp "$editor_dir/app-store-screenshots.json" docs/marketing/intro-en/project.json
python3 docs/marketing/intro-en/compose.py --import-export /path/to/editor-export.zip
```

The importer validates all six full-size English PNGs before replacing README
assets. Commit the project, composition script, captures, and updated PNGs together.
The prebuilt editor and its dependencies do not belong in this repository.
