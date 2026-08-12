# ZOS – Bug Tracking

## Resolved

- **Pause**: CRT unfocuses and sets the entry non-editable at game speed 0; refocuses on unpause. Device Options / Turn On / Play ignore clicks while paused (handlers only — buttons stay normal white, not the red disabled look). Turn Off still works visually as enabled; clicks are ignored until unpaused.

## Known Limitations

- Terminal has a fixed size (not resizable) in v1.

## Open Issues

- **CRT light + screen glow**: While the PC is on / the CRT is open, add an `IsoLightSource` on the computer square via `getCell():addLamppost` (green CRT tint, small radius); remove it on Turn Off, power loss, walk-away close, and chunk unload. Pair with a glowing monitor overlay (`IsoObject:setOverlaySprite`) — custom per-facing green-screen textures for Desktop Computers. Stay on plain `IsoObject` (no `DeviceData` / `IsoWaveSignal`).
- **Playtest needed**: Device Options opens the device window; floppy icon in Media; drag floppy leaves inventory / right-click eject works unpowered (inv or at feet) and aborts Zork if playing; pickup dumps disk on square; Turn On lights LED only; Play opens CRT and types `a:` then matching zork (greyed without grid power / device off / no disk); Turn Off closes CRT; per-title SAVE/RESTORE.
- **Playtest needed**: confirm the ZOS terminal's `ISTextEntryBox` blocks WASD movement while focused, the same as any other vanilla text-entry dialog. Not verifiable without launching the game.
- **Playtest needed**: confirm the transparent `ISTextEntryBox` (background/border alpha 0) truly reads as "inline" text with no visible seam against the black backdrop, and that its blinking caret is visible against black.
- **Playtest needed**: confirm the scrollback panel auto-scrolls to the newest line as output grows (`ZosTerminal:refreshOutput` sets `YScroll` to `-(scrollHeight - height)` after each append).
- **Playtest needed**: confirm the "Device Options" context menu option appears only for Desktop Computer objects (`CustomName=Computer` + `GroupName=Desktop`). Unpowered PCs still open the device window; Turn On and the floppy slot stay locked.
- Clicking the scrollback after clicking off the CRT should refocus the input (`output.onMouseDown` → `refocus`). Playtest after a full restart.
