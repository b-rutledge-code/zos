# ZOS – Design Notes

## Why "ZOS"

Project Zomboid is set in 1993. A generic in-universe DOS clone ("Zomboid
Operating System", Knox Computing Corp., 1985-1993) gives every desktop
computer a period-appropriate boot sequence without pretending to be a real
historical OS. It is deliberately "thin" -- flavor text and a handful of DOS
commands, not a simulated filesystem or general-purpose computer.

## Why a floppy, not preinstalled

Finding Zork floppies as loot turns booting ZOS into a small treasure hunt
(electronics stores, bookstores, desks, bedrooms, university) rather than
making every computer an instant Zork terminal. It also gives the `A:` drive
a reason to exist in the fake DOS shell.

## Why insert on the computer

DOS A: holds one disk. Device Options opens a ValuTech-style device window
(General / Power / Media). The Media slot is an `ISItemDropBox` like a VCR:
drag a Zork floppy in (it leaves inventory), right-click to eject (spring-loaded,
no power; returns to inv or drops at feet if full), **Play** to type `a:` then
the matching zork command on the CRT. Pickup/dismantle dumps the disk on the
square. `ModData.zosFloppy` records which title is in the slot. Turn On /
Turn Off switch the PC (`ModData.zosOn`, LED); only **Play** opens the CRT.
Insert and Play require grid power; Play also requires the PC on.

## Why bake the story file into Lua

Kahlua (PZ's Lua 5.1) doesn't have a clean binary file-read path for mod
`media/` assets at runtime that's worth depending on. Baking each `.z3` into
a generated Lua module of numeric chunk tables sidesteps runtime file I/O and
Kahlua parser/memory risk. The bake script pins source URL, content sha1,
byte length, and header version/release/serial.

## Scope discipline

The interpreter is Z-machine v3 (Zork I/II/III). V4+ Infocom, other games, and
a real filesystem stay out of scope -- see the plan's Out of scope / Deferred
section.
