# ZOS – Bug Tracking

## Resolved

- **Pause**: CRT unfocuses and sets the entry non-editable at game speed 0; refocuses on unpause. Device Options / Turn On / Play ignore clicks while paused (handlers only — buttons stay normal white, not the red disabled look). Turn Off still works visually as enabled; clicks are ignored until unpaused.
- **CRT light**: Soft green `IsoLightSource` on the PC square while `zosOn` and grid/generator power; removed on Turn Off, power loss, pickup/dismantle; restored via `LoadGridsquare` / tick sync.
- **CRT screen**: While on + powered, swap Desktop Computer sprite to vanilla lit frames `76`–`79` (S/E/N/W); restore `72`–`75` when off.

## Known Limitations

- Terminal has a fixed size (not resizable) in v1.

## Open Issues

- **Playtest needed**: Device Options opens the device window; floppy icon in Media; drag floppy leaves inventory / right-click eject works unpowered (inv or at feet) and aborts Zork if playing; pickup dumps disk on square; Turn On lights LED only; Play opens CRT and types `a:` then matching zork (greyed without grid power / device off / no disk); Turn Off closes CRT; per-title SAVE/RESTORE; Zork commands reduce boredom/unhappiness with a per-minute cap (shell commands do not); moment XP grants once per beat and does not re-fire after RESTART.
- **Playtest needed**: confirm moment detectors (room / score / output phrases) fire on the intended beats for Zork I r119 and Zork II completion.
- **Playtest needed**: confirm the ZOS terminal's `ISTextEntryBox` blocks WASD movement while focused, the same as any other vanilla text-entry dialog. Not verifiable without launching the game.
- **Playtest needed**: confirm the transparent `ISTextEntryBox` (background/border alpha 0) truly reads as "inline" text with no visible seam against the black backdrop, and that its blinking caret is visible against black.
- **Playtest needed**: confirm the scrollback panel auto-scrolls to the newest line as output grows (`ZosTerminal:refreshOutput` sets `YScroll` to `-(scrollHeight - height)` after each append).
- **Playtest needed**: confirm the "Device Options" context menu option appears only for Desktop Computer objects (`CustomName=Computer` + `GroupName=Desktop`). Unpowered PCs still open the device window; Turn On and the floppy slot stay locked.
- Clicking the scrollback after clicking off the CRT should refocus the input (`output.onMouseDown` → `refocus`). Playtest after a full restart.
