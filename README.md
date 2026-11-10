# Platinum Explorer Icon

<p align="center"><img src="explorer-icon.svg" width="160" alt="Platinum File Explorer icon"></p>

Replaces the yellow/blue File Explorer icon on the taskbar and Start Menu with a premium platinum/silver version.

## Usage

- Run `Apply.cmd` as admin (it asks for elevation on its own). Keep `explorer-icon.ico` in the same folder.
- Run `Revert.cmd` to undo.

## Notes

- Windows 11 only.
- File Explorer shortcuts are found by target, so localized or renamed shortcuts work too. Originals are backed up to `%LOCALAPPDATA%\PlatinumExplorer` and restored by `Revert.cmd`.
- Both scripts clear the icon cache and restart Explorer.
- Only the shortcuts change; `explorer.exe` itself is not modified.
