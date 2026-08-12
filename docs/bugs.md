# ZOS – Bug Tracking

## Resolved

(None yet.)

## Known Limitations

- Terminal has a fixed size (not resizable) in v1.

## Open Issues

- **Playtest needed**: Device Options opens the device window; floppy icon in Media; drag floppy leaves inventory / right-click eject works unpowered (inv or at feet) and aborts Zork if playing; pickup dumps disk on square; Play types `a:` then matching zork on the CRT; Turn On still boots to `C:\>`; Turn Off closes it; per-title SAVE/RESTORE.
- **Playtest needed**: confirm the ZOS terminal's `ISTextEntryBox` blocks WASD movement while focused, the same as any other vanilla text-entry dialog. Not verifiable without launching the game.
- **Playtest needed**: confirm the transparent `ISTextEntryBox` (background/border alpha 0) truly reads as "inline" text with no visible seam against the black backdrop, and that its blinking caret is visible against black.
- **Playtest needed**: confirm the scrollback panel auto-scrolls to the newest line as output grows (`ZosTerminal:refreshOutput` sets `YScroll` to `-(scrollHeight - height)` after each append).
- **Playtest needed**: confirm the "Device Options" context menu option appears only for Desktop Computer objects (`CustomName=Computer` + `GroupName=Desktop`). Unpowered PCs still open the device window; Turn On and the floppy slot stay locked.
- Clicking the scrollback after clicking off the CRT should refocus the input (`output.onMouseDown` → `refocus`). Playtest after a full restart.
