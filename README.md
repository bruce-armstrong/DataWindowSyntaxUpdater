# DataWindow Syntax Updater

A DataWindow's source (`.srd`) keeps the `release n;` line and syntax format of the PowerBuilder version that last saved it in the DataWindow painter. Migrating to a newer version, a full build, PBAutoBuild, PBC and ORCA all compile that source without rewriting it, so old DataWindows stay at release 5, 6, 12.5 and so on until someone opens and saves each one in the painter.

This utility does the painter's part for a whole folder at once. For each `.srd` file it:

1. Loads the source into the DataWindow engine (`DataStore.Create`).
2. Asks the engine for the syntax back (`Describe("DataWindow.Syntax")`). The engine always writes the current release, with every property written out, so nothing depends on the old release's defaults.
3. Puts the initial data back in (`Describe("DataWindow.Syntax.Data")`), since `DataWindow.Syntax` leaves it out.
4. Checks the result: it must load, describe the same objects and hold the same number of initial rows as the original. If it doesn't, the file is left alone and logged as failed.
5. Writes the file back with the same encoding, line endings and any lines that came before `release` (`//objectcomments`, `$PBExportHeader$`).

Files that are already at the current release aren't touched.

## Requirements

- PowerBuilder 2025 R2 (runtime 25.1.0.6430) to build, and that runtime to run. The release it writes is the one for the runtime it runs under, so build it with the PowerBuilder version you're moving to.
- DataWindow source as files on disk: a PowerBuilder solution (`.pbl` folders), or `.srd` files exported from a workspace. PBL files from a workspace aren't read directly; export, convert, and import them, or move to the solution format first.

## Building

Open `DWSyntaxUpdater.pbsln` in the IDE and deploy `p_dwsyntaxupdater_exe`, or from the command line:

```
pbautobuild250.exe /pbc /d DWSyntaxUpdater.pbproj /o dwsyntaxupdater.exe /f /x 64
```

## Usage

```
dwsyntaxupdater [folder] [/out=folder] [/log=file] [/dryrun] [/force] [/quiet]
```

| Option | Meaning |
|---|---|
| `folder` | The folder to scan, with its subfolders. Folders whose names start with `.` (`.git`, `.pb`) are skipped. When left out, you're asked for one. |
| `/out=folder` | Write converted files here, keeping their relative paths, instead of replacing them. It can't be inside the source folder. Only converted files are written. |
| `/log=file` | The log file. Defaults to `dwsyntaxupdater.log` in the current folder. |
| `/dryrun` | Report what would be converted without writing any files. |
| `/force` | Rewrite files that are already at the current release. |
| `/quiet` | Show no messages, for use in scripts; results go to the log only. |

Each file gets one log line: `CONVERTED` (with the old and new release), `CURRENT` or `FAILED` (with the reason). A `WARNING` line follows files that need a second look. A summary ends the log.

## Samples

`samples` holds 15 unconverted DataWindows from PFC 2025: releases 5 to 22, including some with initial data, nested reports and drop-down DataWindows. To see what a conversion does, run the utility on them and look at the diff:

```
dwsyntaxupdater.exe samples
git diff samples
git checkout -- samples
```

The last command puts the samples back the way they were.

## Before converting a code base

- Run it on a branch, or on a clean working copy, so you can review the diff and revert.
- Expect a large diff. The engine writes every property out and orders them its own way, so even an unchanged DataWindow gains many lines.
- The output is the engine's syntax, which the painter writes in its own order and line wrapping. They describe the same DataWindow, but the text won't match a painter save byte for byte. Saving a file in the painter afterwards will reorder it again.
- DataWindows with nested reports get a warning. Their `dataobject` references and arguments are kept, but open one or two in the painter to confirm.
- Build and run the application after converting.

## Tested on

PFC 2025's 164 DataWindows (releases 5 to 22, eight of them with initial data, three with nested reports): all converted to release 25, a second run found them all current, and a project built from the converted DataWindows compiled cleanly.
