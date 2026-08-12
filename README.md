# ZOS

A Project Zomboid mod: use a powered desktop computer to boot "ZOS 6.2", a
flavor 1993 DOS-like shell, find Zork I/II/III floppy disks in the world, and
play the real Infocom trilogy from an in-game terminal.

## Features

- Right-click a Desktop Computer → **Device Options** (same as TV/radio)
- Insert a Zork floppy in the Media slot (one title in A: at a time); **Play** types `a:` then the matching exe
- Fake DOS shell: `dir`, `cd`, `type`, `a:`, `c:`, `zork`, `zork2`, `zork3`, `exit`
- Find ZORK I / II / III floppies (electronics stores, bookstores, desks, bedrooms, university)
- Runs the official MIT-licensed Zork I r119, Zork II r63, and Zork III r25 story files through a Lua Z-machine v3 interpreter
- Closes the terminal if the computer loses power or you walk away

## Installation

1. Subscribe to the mod on the Steam Workshop (once published), or copy `Contents/mods/ZOS/` into `~/Zomboid/mods/ZOS/` for local testing
2. Enable the mod in your game's mod list
3. Start a new game or load an existing save

## Usage

1. Find a Desktop Computer (offices, homes)
2. Find a Zork floppy (see spawn locations above)
3. Right-click → **Device Options**
4. Drag the floppy into Media and hit **Play** (needs power)

## Attribution

Zork I, II, and III are (c) Infocom / Activision. Story files are MIT-licensed
from [historicalsource/zork1](https://github.com/historicalsource/zork1),
[zork2](https://github.com/historicalsource/zork2), and
[zork3](https://github.com/historicalsource/zork3). See `third_party/zork1/`,
`third_party/zork2/`, and `third_party/zork3/`.
