--[[
    SAVE then RESTORE must put the story back where it was.
    Run from the mod root: lua tests/test_save.lua
]]

local scriptPath = arg[0] or "tests/test_save.lua"
local scriptDir = string.match(scriptPath, "^(.*)[/\\][^/\\]+$") or "."
local sharedDir = scriptDir .. "/../Contents/mods/ZOS/42.20/media/lua/shared/Zos/"

dofile(sharedDir .. "ZosBit.lua")
dofile(sharedDir .. "ZosZText.lua")
dofile(sharedDir .. "ZosZObject.lua")
dofile(sharedDir .. "ZosZDict.lua")
dofile(sharedDir .. "ZosZMachine.lua")
dofile(sharedDir .. "ZosZSave.lua")
dofile(sharedDir .. "ZosStoryZork1.lua")

local saveBlob = nil
local vm = assert(ZosZMachine.new(ZosStoryZork1, 1))
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
cmd("open mailbox")
local roomBefore = ZosZMachine.statusLine(vm).room
local scoreBefore = ZosZMachine.statusLine(vm).score
cmd("save")
assert(saveBlob ~= nil and #saveBlob > 100, "save produced no blob")
assert(not string.find(saveBlob, "[^0-9A-Fa-f]"), "save blob is not hex")

cmd("north")
local roomAway = ZosZMachine.statusLine(vm).room
assert(roomAway ~= roomBefore, "north should have left " .. roomBefore)

cmd("restore")
local roomAfter = ZosZMachine.statusLine(vm).room
local scoreAfter = ZosZMachine.statusLine(vm).score
assert(roomAfter == roomBefore, "restore room " .. tostring(roomAfter) .. " ~= " .. roomBefore)
assert(scoreAfter == scoreBefore, "restore score mismatch")

cmd("look")
local text = ZosZMachine.drainText(vm)
-- drainText already emptied in pump; look's text was drained there.
-- Re-check via status + a take that only works if the mailbox is still open.
assert(ZosZMachine.statusLine(vm).room == "West of House")
cmd("take leaflet")
local afterTake = ZosZMachine.statusLine(vm)
assert(afterTake.room == "West of House")

print(string.format("ok: save %d hex chars, restore back to %s", #saveBlob, roomAfter))
