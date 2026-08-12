--[[
    Zork III SAVE then RESTORE must return to Endless Stair.
    Run from the mod root: lua tests/test_save_zork3.lua
]]

local scriptPath = arg[0] or "tests/test_save_zork3.lua"
local scriptDir = string.match(scriptPath, "^(.*)[/\\][^/\\]+$") or "."
local sharedDir = scriptDir .. "/../Contents/mods/ZOS/42.20/media/lua/shared/Zos/"

dofile(sharedDir .. "ZosBit.lua")
dofile(sharedDir .. "ZosZText.lua")
dofile(sharedDir .. "ZosZObject.lua")
dofile(sharedDir .. "ZosZDict.lua")
dofile(sharedDir .. "ZosZMachine.lua")
dofile(sharedDir .. "ZosZSave.lua")
dofile(sharedDir .. "ZosStoryZork3.lua")

local saveBlob = nil
local vm = assert(ZosZMachine.new(ZosStoryZork3, 1))
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
assert(ZosZMachine.statusLine(vm).room == "Endless Stair")
cmd("save")
assert(saveBlob ~= nil and #saveBlob > 100, "save produced no blob")

cmd("south")
assert(ZosZMachine.statusLine(vm).room == "Junction")

cmd("restore")
assert(ZosZMachine.statusLine(vm).room == "Endless Stair")
assert(ZosZMachine.statusLine(vm).moves == 0)

cmd("look")
assert(ZosZMachine.statusLine(vm).room == "Endless Stair")

print(string.format("ok: zork3 save %d hex chars, restore Endless Stair", #saveBlob))
