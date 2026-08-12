--[[
    Zork II SAVE then RESTORE must return to Inside the Barrow.
    Run from the mod root: lua tests/test_save_zork2.lua
]]

local scriptPath = arg[0] or "tests/test_save_zork2.lua"
local scriptDir = string.match(scriptPath, "^(.*)[/\\][^/\\]+$") or "."
local sharedDir = scriptDir .. "/../Contents/mods/ZOS/42.20/media/lua/shared/Zos/"

dofile(sharedDir .. "ZosBit.lua")
dofile(sharedDir .. "ZosZText.lua")
dofile(sharedDir .. "ZosZObject.lua")
dofile(sharedDir .. "ZosZDict.lua")
dofile(sharedDir .. "ZosZMachine.lua")
dofile(sharedDir .. "ZosZSave.lua")
dofile(sharedDir .. "ZosStoryZork2.lua")

local saveBlob = nil
local vm = assert(ZosZMachine.new(ZosStoryZork2, 1))
vm.saveHandler = function(blob)
    saveBlob = blob
    return true
end
vm.restoreHandler = function()
    return saveBlob
end

local function pump()
    local st = ZosZMachine.run(vm, 400000)
    ZosZMachine.drainText(vm)
    if vm.error then
        error(vm.error)
    end
    return st
end

local function cmd(line)
    assert(ZosZMachine.provideInput(vm, line))
    return pump()
end

assert(pump() == "input")
assert(ZosZMachine.statusLine(vm).room == "Inside the Barrow")
cmd("save")
assert(saveBlob ~= nil and #saveBlob > 100, "save produced no blob")

cmd("south")
assert(ZosZMachine.statusLine(vm).room == "Narrow Tunnel")

cmd("restore")
assert(ZosZMachine.statusLine(vm).room == "Inside the Barrow")
assert(ZosZMachine.statusLine(vm).moves == 0)

cmd("look")
assert(ZosZMachine.statusLine(vm).room == "Inside the Barrow")

print(string.format("ok: zork2 save %d hex chars, restore Inside the Barrow", #saveBlob))
