--[[
    Headless Zork I runner for the ZOS Z-machine.

    Loads the same shared Lua the mod ships and drives it outside Project
    Zomboid, so opcode work is a shell loop instead of a game restart.

    Usage, from the mod root:
        lua tests/run_zork.lua                          boot Zork I, stop at the prompt
        lua tests/run_zork.lua --zork2 --status         boot Zork II
        lua tests/run_zork.lua --zork3 "look"
        lua tests/run_zork.lua "open mailbox" "read leaflet"
        echo "n" | lua tests/run_zork.lua               commands on stdin

    Any commands left after the arguments are read from stdin, so the runner
    is also usable interactively. ZOS_SEED fixes the story's RNG.
]]

local scriptPath = arg[0] or "tests/run_zork.lua"
local scriptDir = string.match(scriptPath, "^(.*)[/\\][^/\\]+$") or "."
local sharedDir = scriptDir .. "/../Contents/mods/ZOS/42.20/media/lua/shared/Zos/"

dofile(sharedDir .. "ZosBit.lua")
dofile(sharedDir .. "ZosZText.lua")
dofile(sharedDir .. "ZosZObject.lua")
dofile(sharedDir .. "ZosZDict.lua")
dofile(sharedDir .. "ZosZMachine.lua")
dofile(sharedDir .. "ZosZSave.lua")
dofile(sharedDir .. "ZosStoryZork1.lua")
dofile(sharedDir .. "ZosStoryZork2.lua")
dofile(sharedDir .. "ZosStoryZork3.lua")

local STEP_SLICE = 100000
local STEP_CEILING = 20000000

local commands = {}
local showStatus = false
local story = ZosStoryZork1
for i = 1, #arg do
    if arg[i] == "--status" then
        showStatus = true
    elseif arg[i] == "--zork2" then
        story = ZosStoryZork2
    elseif arg[i] == "--zork3" then
        story = ZosStoryZork3
    else
        commands[#commands + 1] = arg[i]
    end
end

local vm, err = ZosZMachine.new(story, tonumber(os.getenv("ZOS_SEED")) or 1)
if vm == nil then
    io.stderr:write("ZosZMachine.new failed: " .. tostring(err) .. "\n")
    os.exit(1)
end

local saveBlob = nil
vm.saveHandler = function(blob)
    saveBlob = blob
    return true
end
vm.restoreHandler = function()
    return saveBlob
end

local function flush()
    local lines, partial = ZosZMachine.drainLines(vm)
    for i = 1, #lines do
        io.write(lines[i], "\n")
    end
    if partial ~= "" then
        io.write(partial)
    end
    io.flush()
end

-- Runs in slices so a runaway story shows up as a ceiling hit, not a hang.
local function pump()
    while true do
        local status = ZosZMachine.run(vm, STEP_SLICE)
        flush()
        if status ~= "yield" then
            return status
        end
        if vm.instructions > STEP_CEILING then
            io.stderr:write(string.format("\nstopped after %d instructions at 0x%X\n", vm.instructions, vm.pc))
            return "ceiling"
        end
    end
end

local function reportStatusLine()
    if not showStatus then
        return
    end
    local status = ZosZMachine.statusLine(vm)
    io.write(string.format("\n[status: %s | Score: %d | Moves: %d]\n", status.room, status.score, status.moves))
end

local nextCommand = 1
local function readCommand()
    if nextCommand <= #commands then
        local command = commands[nextCommand]
        nextCommand = nextCommand + 1
        return command
    end
    return io.read("*l")
end

local status = pump()
reportStatusLine()

while status == "input" do
    local command = readCommand()
    if command == nil then
        io.write("\n")
        break
    end
    io.write(command, "\n")
    ZosZMachine.provideInput(vm, command)
    status = pump()
    reportStatusLine()
end

io.write("\n")
if vm.error ~= nil then
    io.stderr:write("VM fault: " .. vm.error .. "\n")
    io.stderr:write(string.format("after %d instructions\n", vm.instructions))
    os.exit(1)
end
if status == "ceiling" then
    os.exit(1)
end
io.write(string.format("[%d instructions executed]\n", vm.instructions))
