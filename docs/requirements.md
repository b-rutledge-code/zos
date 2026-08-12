# ZOS – Requirements

## Goal

Bring the Zork trilogy into Project Zomboid's 1993 setting: a period-appropriate
ZOS 6.2 boot sequence on desktop computers as flavor, with Zork I/II/III
floppies found in the world and one disk in A: at a time.

## Functional

1. **Device Options** – Right-clicking a Desktop Computer (`CustomName=Computer`, `GroupName=Desktop`) and walking adjacent opens a ValuTech-style device window (General / Power / Media), same label as TV/radio (`IGUI_DeviceOptions`). Power is LED + vanilla **Turn On** / **Turn Off** + "Has power." / "No power." Turn On switches the PC on (`ModData.zosOn`, LED) without opening the CRT. Turn Off switches it off and closes the CRT if open. The floppy slot requires grid power.
2. **Insert / Eject Floppy** – Media slot on the device window. Drag a Zork floppy onto the drop box: the item leaves inventory, `ModData.zosFloppy` is set (one disk; eject first to change titles), and `transmitModData`. Right-click ejects (no power needed) and returns the item to inventory, or drops it at the player's feet if inv is full. Eject during Zork aborts the session back to `C:\>`. Pickup or dismantle dumps any inserted floppy on the square. Insert requires grid power.
3. **ZOS 6.2 shell** – The terminal boots to a `ZOS 6.2 / Copyright (C) 1985-1993 Knox Computing Corp.` banner and a `C:\>` prompt. Supported commands: `dir`, `cd`, `type`, `a:`, `c:`, `zork`, `zork2`, `zork3`, `exit`. Anything else prints `Bad command or file name`.
4. **A: drive** – Ready when `zosFloppy` is set (disk is in the computer). Otherwise `a:` / `dir` on A: print `Not ready reading drive A` / `Insert a disk into drive A`. `dir` shows one exe: `ZORK.EXE` / `ZORK2.EXE` / `ZORK3.EXE` matching the inserted title.
5. **Playing Zork** – Media **Play** (vanilla label) is the only way to open the CRT. Play needs grid power, the PC turned on, and an inserted disk; otherwise the button stays greyed out. Play types `a:` then `zork` / `zork2` / `zork3` for the inserted disk into the prompt, one character at a time, with a pause between commands. Typing those commands by hand still works once the CRT is open. Wrong exe name is `Bad command or file name`. The world keeps running (not a timed action); the window is modeless. `QUIT` returns to the ZOS prompt; `RESTART` resets the story.
6. **Save/restore** – In-game `SAVE`/`RESTORE` persist Z-machine state on that computer's `ModData` as `zosZork1Save` / `zosZork2Save` / `zosZork3Save`.
7. **Close rules** – The terminal closes if the player walks away from the computer, is shoved off the tile, or the computer loses power. While game speed is 0 the CRT stays open but rejects input (unfocus / non-editable); Device Options, Turn On, and Play do not act until unpaused.
8. **Mood** – Playing Zork reduces boredom/unhappiness over time via `player:getStats():add(CharacterStat.BOREDOM, amt)` / `CharacterStat.UNHAPPINESS`, matching the vanilla TV/radio rate.

## Constraints (By Design)

- Z-machine v3 only (Zork I/II/III). Desktop Computers stay ordinary `IsoObject`s; no new world object class, `DeviceData`, or `IsoWaveSignal`.
- Floppy item leaves inventory while inserted and returns on eject (or drops on the ground if inv is full / the computer is picked up); insert selects which title A: runs.
- Inventory icon is a custom 5.25\" floppy sprite (`Item_FloppyZork1.png`), reused for all three titles. World model stays vanilla `Disk`. No CRT texture effects in v1.
- Single-player first: the Z-machine VM and terminal UI run client-side; loot spawning is server-authoritative.
- Story files are baked into generated Lua modules at build time, not read from disk at runtime.

## Technical

- Game build: 42.20 (`versionMin=42.20`), single versioned folder.
- Kahlua (Lua 5.1): no `bit32`; bitwise ops go through a small `ZosBit` module.
- Stories (MIT, [historicalsource](https://github.com/historicalsource)):
  - Zork I `zork1.z3` r119 / serial 880429, 86,838 bytes, sha1 `c4f162274869b5433e4b9dfa7ee770fc3b789525`
  - Zork II `zork2.z3` r63 / serial 860811, 92,524 bytes, sha1 `6e5415ace76ad235a307a5d4a2e88a8980b9f193`
  - Zork III `zork3.z3` r25 / serial 860811, 87,984 bytes, sha1 `0340b09fe05cf3ba0f01c04a7699236e15ab2aed`
- Regenerate with `tools/bake_zork.sh 1|2|3`.
