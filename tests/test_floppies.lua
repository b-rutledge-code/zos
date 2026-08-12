--[[
    Floppy catalog: item, exe command, and save key stay aligned.
    Run from the mod root: lua tests/test_floppies.lua
]]

local scriptPath = arg[0] or "tests/test_floppies.lua"
local scriptDir = string.match(scriptPath, "^(.*)[/\\][^/\\]+$") or "."
local sharedDir = scriptDir .. "/../Contents/mods/ZOS/42.20/media/lua/shared/Zos/"

dofile(sharedDir .. "ZosFloppies.lua")

assert(#ZosFloppies == 3)
assert(ZosFloppies.byItem("Zos.FloppyZork1").cmd == "zork")
assert(ZosFloppies.byItem("Zos.FloppyZork2").cmd == "zork2")
assert(ZosFloppies.byItem("Zos.FloppyZork3").cmd == "zork3")
assert(ZosFloppies.byCmd("zork2").saveKey == "zosZork2Save")
assert(ZosFloppies.byCmd("zork3").dirLine == "ZORK3    EXE")
assert(ZosFloppies.byItem("Zos.FloppyNope") == nil)
assert(ZosFloppies.byCmd("doom") == nil)

print("ok: floppy catalog zork / zork2 / zork3")
