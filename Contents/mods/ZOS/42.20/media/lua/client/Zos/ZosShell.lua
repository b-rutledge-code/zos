--[[
    ZosShell - fake DOS state machine for the ZOS 6.2 terminal.

    Owns cwd/drive state and turns a typed line into output lines. Knows
    nothing about UI; ZosTerminal drives it and renders what it returns.

    A: is ready when that computer has a floppy in the Media slot.
    Once a Zork exe runs, lines go to the Z-machine and prompt() reports the
    prompt the story itself printed.
]]

ZosShell = {}
ZosShell.__index = ZosShell

-- A Zork turn is on the order of a couple of thousand instructions, so the
-- slice is sized to finish one outright; the ceiling is what a story stuck in
-- a loop trips instead of freezing the game.
local ZORK_STEP_SLICE = 200000
local ZORK_STEP_CEILING = 5000000
local ZORK_PROMPT = ">"

local C_ROOT_DIR = {
    "GAMES        <DIR>",
    "WORK         <DIR>",
    "AUTOEXEC ZOS",
    "README   TXT",
}

local README_TEXT = {
    "ZOS 6.2 -- Knox Computing Corp.",
    "",
    "This system is provided as-is. No warranty, express or implied.",
    "See your dealer for support.",
}

local AUTOEXEC_TEXT = {
    "@ECHO OFF",
    "PROMPT $P$G",
    "PATH C:\\",
}

local function copyLines(t)
    local r = {}
    for i, v in ipairs(t) do
        r[i] = v
    end
    return r
end

function ZosShell:new(player, computer)
    local o = setmetatable({}, self)
    o.player = player
    o.computer = computer
    o.drive = "C"
    o.dir = nil -- nil = root; otherwise "GAMES" or "WORK"
    o.inZork = false
    o.zorkVm = nil
    o.zorkPrompt = nil
    o.zorkTitle = nil
    return o
end

function ZosShell:insertedTitle()
    return ZosFloppies.inserted(self.computer)
end

function ZosShell:driveReady()
    return ZosFloppies.driveReady(self.computer)
end

function ZosShell:prompt()
    if self.inZork then
        return self.zorkPrompt or ZORK_PROMPT
    end
    if self.dir then
        return self.drive .. ":\\" .. self.dir .. ">"
    end
    return self.drive .. ":\\>"
end

function ZosShell:listDir()
    if self.drive == "A" then
        if not self:driveReady() then
            return { "Not ready reading drive A", "Insert a disk into drive A" }
        end
        local title = self:insertedTitle()
        return { title.dirLine }
    end
    if self.dir == nil then
        return copyLines(C_ROOT_DIR)
    end
    return {}
end

function ZosShell:changeDir(arg)
    if self.drive == "A" then
        return { "Invalid directory" }
    end
    if not arg then
        return {}
    end
    local upper = string.upper(arg)
    if upper == ".." or upper == "\\" then
        self.dir = nil
        return {}
    end
    if self.dir == nil and (upper == "GAMES" or upper == "WORK") then
        self.dir = upper
        return {}
    end
    return { "Invalid directory" }
end

function ZosShell:typeFile(arg)
    if not arg or self.drive ~= "C" or self.dir ~= nil then
        return { "File not found" }
    end
    local upper = string.upper(arg)
    if upper == "README.TXT" or upper == "README" then
        return copyLines(README_TEXT)
    end
    if upper == "AUTOEXEC.ZOS" or upper == "AUTOEXEC" then
        return copyLines(AUTOEXEC_TEXT)
    end
    return { "File not found" }
end

function ZosShell:switchDrive(target)
    if target == "A" then
        if not self:driveReady() then
            return { "Not ready reading drive A", "Insert a disk into drive A" }
        end
        self.drive = "A"
        self.dir = nil
        return {}
    end
    self.drive = "C"
    self.dir = nil
    return {}
end

local function driveLetter(cmd)
    if cmd == nil then
        return nil
    end
    return string.match(cmd, "^([ac]):\\?$")
end

function ZosShell:leaveZork()
    self.inZork = false
    self.zorkVm = nil
    self.zorkPrompt = nil
    self.zorkTitle = nil
end

-- Runs the story until it wants a command or stops, collecting what it
-- printed. Text with no newline after it is the story's own prompt, so that
-- becomes the shell prompt rather than a line of transcript.
function ZosShell:pumpZork()
    local vm = self.zorkVm
    local title = self.zorkTitle
    local exeName = title and title.exeName or "ZORK.EXE"
    local out = {}

    while true do
        local status = ZosZMachine.run(vm, ZORK_STEP_SLICE)
        local lines, partial = ZosZMachine.drainLines(vm)
        for i = 1, #lines do
            out[#out + 1] = lines[i]
        end

        if status == "input" then
            if partial ~= "" then
                self.zorkPrompt = partial
            end
            print(string.format("ZOS: waiting for input after %d instructions", vm.instructions))
            return out
        end

        if partial ~= "" then
            out[#out + 1] = partial
        end

        if status == "halted" then
            local fault = vm.error
            self:leaveZork()
            if fault ~= nil then
                out[#out + 1] = ""
                out[#out + 1] = exeName .. " terminated: " .. fault
            end
            return out
        end

        if vm.instructions > ZORK_STEP_CEILING then
            self:leaveZork()
            out[#out + 1] = ""
            out[#out + 1] = exeName .. " stopped responding."
            return out
        end
    end
end

function ZosShell:launchZork(cmd)
    local title = ZosFloppies.byCmd(cmd)
    if self.drive ~= "A" or title == nil or not self:driveReady() then
        return { lines = { "Bad command or file name" } }
    end
    local inserted = self:insertedTitle()
    if inserted == nil or inserted.item ~= title.item then
        return { lines = { "Bad command or file name" } }
    end

    local story = ZosFloppies.story(title)
    if story == nil then
        return { lines = { title.exeName .. " failed to load: story missing" } }
    end

    print(string.format("ZOS: launching %s r%d, %d bytes, %d chunks",
        title.cmd, story.release, story.length, #story.chunks))
    local vm, err = ZosZMachine.new(story, ZombRand(2147483646) + 1)
    if vm == nil then
        print("ZOS: load failed: " .. tostring(err))
        return { lines = { title.exeName .. " failed to load: " .. tostring(err) } }
    end
    print(string.format("ZOS: loaded, initial PC 0x%X", vm.initialPC))

    local computer = self.computer
    local saveKey = title.saveKey
    vm.saveHandler = function(blob)
        if computer == nil or blob == nil then
            return false
        end
        local md = computer:getModData()
        md[saveKey] = blob
        computer:transmitModData()
        print("ZOS: saved " .. #blob .. " hex chars to " .. saveKey)
        return true
    end
    vm.restoreHandler = function()
        if computer == nil then
            return nil
        end
        local blob = computer:getModData()[saveKey]
        if blob ~= nil then
            print("ZOS: restoring " .. #blob .. " hex chars from " .. saveKey)
        end
        return blob
    end

    self.zorkVm = vm
    self.zorkTitle = title
    self.inZork = true
    self.zorkPrompt = ZORK_PROMPT
    return { lines = self:pumpZork() }
end

-- QUIT, RESTART and SAVE are the story's own commands, so a turn ending with
-- the machine halted is what drops the player back to the DOS prompt.
function ZosShell:executeZork(rawLine)
    print("ZOS: > " .. tostring(rawLine))
    local exeName = self.zorkTitle and self.zorkTitle.exeName or "ZORK.EXE"
    if not ZosZMachine.provideInput(self.zorkVm, rawLine or "") then
        print("ZOS: not accepting input")
        self:leaveZork()
        return { lines = { exeName .. " is not accepting input." } }
    end
    local lines = self:pumpZork()
    if not self.inZork then
        print("ZOS: left zork")
    end
    return { lines = lines }
end

function ZosShell:execute(rawLine)
    if self.inZork then
        return self:executeZork(rawLine)
    end

    local trimmed = string.trim(rawLine or "")
    if trimmed == "" then
        return { lines = {} }
    end

    local parts = luautils.split(trimmed, " ")
    local cmd = string.lower(parts[1])
    local arg = parts[2]

    local drive = driveLetter(cmd)
    if drive then
        return { lines = self:switchDrive(string.upper(drive)) }
    end

    if cmd == "dir" then
        return { lines = self:listDir() }
    elseif cmd == "cd" then
        return { lines = self:changeDir(arg) }
    elseif cmd == "type" then
        return { lines = self:typeFile(arg) }
    elseif ZosFloppies.byCmd(cmd) ~= nil then
        return self:launchZork(cmd)
    elseif cmd == "exit" then
        return { lines = {}, closeTerminal = true }
    else
        return { lines = { "Bad command or file name" } }
    end
end
