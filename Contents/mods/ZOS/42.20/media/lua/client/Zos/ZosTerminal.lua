--[[
    ZosTerminal - a CRT in a vanilla-style panel frame.

    Inventory-grey border, no title bar or close button: the screen is still
    a black rectangle with monospace green text. Closes via `exit`, walking
    away, or power loss.
]]

require "ISUI/ISPanel"
require "ISUI/ISRichTextPanel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISLabel"

ZosTerminal = ISPanel:derive("ZosTerminal")
ZosTerminal.instance = nil

local TERM_W = 640
local TERM_H = 420
local PAD = 16
local ROW_GAP = 4
local FONT = UIFont.Code
local GREEN = { r = 0.25, g = 0.95, b = 0.35 }
local BLACK = { r = 0.0, g = 0.01, b = 0.0, a = 1.0 }
local ADJACENT_RANGE = 1.8
-- Narrowest the typing area may get before a long story prompt is pushed up
-- into the scrollback instead of eating the input row.
local MIN_ENTRY_W = 140
local BOOT_LINES = {
    "ZOS 6.2",
    "Copyright (C) 1985-1993 Knox Computing Corp.",
    "",
}
local TYPE_CHAR_TICKS = 1
local TYPE_PAUSE_TICKS = 8
local TYPE_BOOT_TICKS = 6

local function lineHeight()
    return getTextManager():getFontHeight(FONT)
end

function ZosTerminal:initialise()
    ISPanel.initialise(self)
end

function ZosTerminal:createChildren()
    local rowH = lineHeight()
    self.rowH = rowH
    local outputH = self.height - PAD * 2 - rowH - ROW_GAP

    self.output = ISRichTextPanel:new(PAD, PAD, self.width - PAD * 2, outputH)
    self.output:initialise()
    self.output:instantiate()
    self.output.autosetheight = false
    self.output.clip = true
    self.output.background = false
    self.output.defaultFont = FONT
    self.output.maxLineWidth = self.width - PAD * 2
    self.output:setMargins(0, 0, 0, 0)
    self.output.zosTerminal = self
    self.output.onMouseDown = ZosTerminal.onChildMouseDown
    self:addChild(self.output)

    local inputY = PAD + outputH + ROW_GAP
    self.promptLabel = ISLabel:new(PAD, inputY, rowH, "", GREEN.r, GREEN.g, GREEN.b, 1, FONT, true)
    self.promptLabel:initialise()
    self:addChild(self.promptLabel)

    local entryX = PAD + self.promptLabel.width
    self.entry = ISTextEntryBox:new("", entryX, inputY, self.width - entryX - PAD, rowH)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.font = FONT
    self.entry.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.entry.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.entry:setTextRGBA(GREEN.r, GREEN.g, GREEN.b, 1)
    self.entry.zosTerminal = self
    self.entry.onCommandEntered = ZosTerminal.onCommandEntered
    self.entry.onOtherKey = ZosTerminal.onOtherKey
    self:addChild(self.entry)

    self:layoutRows()
end

-- The scrollback gives up its top row to the status bar while Zork is running.
function ZosTerminal:layoutRows()
    local rowH = self.rowH
    local top = PAD
    if self.showStatus then
        top = PAD + rowH + ROW_GAP
    end
    local outputH = self.height - top - PAD - rowH - ROW_GAP
    local inputY = top + outputH + ROW_GAP

    self.output:setY(top)
    self.output:setHeight(outputH)
    self.promptLabel:setY(inputY)
    self.entry:setY(inputY)
end

-- Cached rather than read per frame: the room name is a Z-string that has to
-- be decoded, and only a finished turn can change it.
function ZosTerminal:refreshStatus()
    local inZork = self.shell ~= nil and self.shell.inZork and self.shell.zorkVm ~= nil
    if not inZork then
        if self.showStatus then
            self.showStatus = false
            self:layoutRows()
        end
        return
    end

    local status = ZosZMachine.statusLine(self.shell.zorkVm)
    self.statusLeft = status.room
    self.statusRight = string.format("Score: %d   Moves: %d", status.score, status.moves)
    if not self.showStatus then
        self.showStatus = true
        self:layoutRows()
    end
end

function ZosTerminal:refocus()
    self:bringToTop()
    if self.entry then
        self.entry:focus()
    end
end

-- Clicks land on the scrollback or the input row, not the parent panel, so
-- those children have to hand focus back after you click off the CRT.
function ZosTerminal.onChildMouseDown(child, x, y)
    local term = child.zosTerminal
    if term then
        term:refocus()
    end
    return true
end

function ZosTerminal:prerender()
    self:drawRectStatic(0, 0, self.width, self.height, BLACK.a, BLACK.r, BLACK.g, BLACK.b)
    -- Same 0.4 grey frame inventory and ISCollapsableWindow use.
    self:drawRectBorderStatic(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    if not self.showStatus then
        return
    end

    -- Reverse video, the way a v3 interpreter draws its status line.
    local barW = self.width - PAD * 2
    self:drawRect(PAD, PAD, barW, self.rowH, 1, GREEN.r, GREEN.g, GREEN.b)
    self:drawText(self.statusLeft or "", PAD + 4, PAD, BLACK.r, BLACK.g, BLACK.b, 1, FONT)
    local right = self.statusRight or ""
    local rightW = getTextManager():MeasureStringX(FONT, right)
    self:drawText(right, PAD + barW - 4 - rightW, PAD, BLACK.r, BLACK.g, BLACK.b, 1, FONT)
end

function ZosTerminal:onMouseDown(x, y)
    self:refocus()
    return true
end

function ZosTerminal:appendLine(text)
    table.insert(self.lines, text or "")
    self:refreshOutput()
end

function ZosTerminal:refreshOutput()
    local buf = {}
    for _, line in ipairs(self.lines) do
        local safe = line
        if safe == "" then safe = " " end
        buf[#buf + 1] = safe .. " <LINE> "
    end
    self.output:setText(table.concat(buf))
    self.output:paginate()
    local overflow = self.output:getScrollHeight() - self.output.height
    if overflow > 0 then
        self.output:setYScroll(-overflow)
    else
        self.output:setYScroll(0)
    end
end

-- Zork's yes/no prompts are a whole question with no newline after them. Split
-- the question off at its trailing ">" so it scrolls by as text and only the
-- ">" holds the input row.
local function splitPrompt(text)
    for i = #text, 1, -1 do
        if string.sub(text, i, i) == ">" then
            if i > 1 then
                return string.trim(string.sub(text, 1, i - 1)), string.sub(text, i)
            end
            return nil, text
        end
    end
    return nil, text
end

function ZosTerminal:refreshPrompt()
    local text = self.shell and self.shell:prompt() or ""
    local room = self.width - PAD * 2 - MIN_ENTRY_W

    if getTextManager():MeasureStringX(FONT, text) > room then
        local carried, rest = splitPrompt(text)
        if carried ~= nil then
            text = rest
            if carried ~= self.carriedPrompt then
                self.carriedPrompt = carried
                self:appendLine(carried)
            end
        end
    else
        self.carriedPrompt = nil
    end

    self.promptText = text
    self.promptLabel:setName(text)
    local entryX = PAD + self.promptLabel.width
    self.entry:setX(entryX)
    self.entry:setWidth(self.width - entryX - PAD)
end

function ZosTerminal:playInsertedFloppy(initialWait)
    if self.shell == nil or self.shell.inZork or self.typeScript ~= nil then
        return
    end
    self.entry:setText("")
    local wait = initialWait or TYPE_PAUSE_TICKS
    if self.shell.drive ~= "A" then
        self.typeScript = {
            text = "a:",
            charIndex = 0,
            wait = wait,
            phase = "type",
            thenPlay = true,
        }
        return
    end
    local title = self.shell:insertedTitle()
    if title == nil then
        return
    end
    self.typeScript = {
        text = title.cmd,
        charIndex = 0,
        wait = wait,
        phase = "type",
        thenPlay = false,
    }
end

function ZosTerminal:updateTypeScript()
    local s = self.typeScript
    if s == nil or self.shell == nil then
        return
    end
    s.wait = s.wait - 1
    if s.wait > 0 then
        return
    end
    if s.phase == "type" then
        s.charIndex = s.charIndex + 1
        self.entry:setText(string.sub(s.text, 1, s.charIndex))
        self.entry:focus()
        if s.charIndex >= #s.text then
            s.phase = "submit"
            s.wait = TYPE_PAUSE_TICKS
        else
            s.wait = TYPE_CHAR_TICKS
        end
        return
    end
    if s.phase == "submit" then
        local text = self.entry:getText()
        local thenPlay = s.thenPlay
        self.entry:setText("")
        self.typeScript = nil
        self:submitLine(text)
        if thenPlay and self.shell ~= nil and self.shell.drive == "A" and not self.shell.inZork then
            local title = self.shell:insertedTitle()
            if title ~= nil then
                self.typeScript = {
                    text = title.cmd,
                    charIndex = 0,
                    wait = TYPE_PAUSE_TICKS,
                    phase = "type",
                    thenPlay = false,
                }
            end
        end
    end
end

function ZosTerminal:submitLine(text)
    self:appendLine((self.promptText or "") .. text)
    local result = self.shell:execute(text)
    for _, line in ipairs(result.lines or {}) do
        self:appendLine(line)
    end

    if result.closeTerminal then
        self:close()
        return
    end

    -- DOS output gets a blank line to breathe; Zork writes its own spacing.
    local inZork = self.shell.inZork
    self:refreshStatus()
    self:refreshPrompt()
    if not inZork then
        self:appendLine("")
    end
end

function ZosTerminal.onCommandEntered(entryBox)
    local term = entryBox.zosTerminal
    if not term then return end
    if term.typeScript ~= nil then return end
    local text = entryBox:getText()
    entryBox:setText("")
    term:submitLine(text)
end

function ZosTerminal.onOtherKey(entryBox, key)
    if key == Keyboard.KEY_ESCAPE then
        local term = entryBox.zosTerminal
        if term then
            term.typeScript = nil
        end
        entryBox:setText("")
    end
end

function ZosTerminal:close()
    self:setVisible(false)
    self:removeFromUIManager()
    self.player = nil
    self.computer = nil
    self.shell = nil
    self.showStatus = false
    self.typeScript = nil
end

function ZosTerminal.isOpenFor(computer)
    local term = ZosTerminal.instance
    return term ~= nil and term:getIsVisible() and term.computer == computer
end

function ZosTerminal.closeFor(computer)
    if ZosTerminal.isOpenFor(computer) then
        ZosTerminal.instance:close()
    end
end

function ZosTerminal.onFloppyEjected(computer)
    local term = ZosTerminal.instance
    if term == nil or not term:getIsVisible() or term.computer ~= computer then
        return
    end
    term.typeScript = nil
    if term.entry ~= nil then
        term.entry:setText("")
    end
    local shell = term.shell
    if shell == nil then
        return
    end
    if shell.inZork then
        local exeName = shell.zorkTitle and shell.zorkTitle.exeName or "ZORK.EXE"
        shell:leaveZork()
        shell.drive = "C"
        shell.dir = nil
        term:appendLine(exeName .. " aborted")
        term:appendLine("Not ready reading drive A")
        term:appendLine("Insert a disk into drive A")
        term:appendLine("")
        term:refreshStatus()
        term:refreshPrompt()
        term.entry:focus()
        return
    end
    if shell.drive == "A" then
        shell.drive = "C"
        shell.dir = nil
        term:refreshPrompt()
        term.entry:focus()
    end
end

function ZosTerminal:update()
    ISPanel.update(self)
    if not self:getIsVisible() then return end
    self:updateTypeScript()
    if not self.player or not self.computer or self.player:isDead() then
        self:close()
        return
    end
    local sq = self.computer:getSquare()
    if not sq then
        self:close()
        return
    end
    local dx = math.abs(sq:getX() + 0.5 - self.player:getX())
    local dy = math.abs(sq:getY() + 0.5 - self.player:getY())
    local powered = sq:haveElectricity() or (sq:hasGridPower() and sq:getRoom() ~= nil)
    if dx > ADJACENT_RANGE or dy > ADJACENT_RANGE or not powered then
        self:close()
    end
end

function ZosTerminal:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.moveWithMouse = false
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    o.lines = {}
    return o
end

function ZosTerminal.open(player, computerObj, autoPlay)
    local term = ZosTerminal.instance
    if not term then
        local sw = getCore():getScreenWidth()
        local sh = getCore():getScreenHeight()
        term = ZosTerminal:new((sw - TERM_W) / 2, (sh - TERM_H) / 2, TERM_W, TERM_H)
        term:initialise()
        term:instantiate()
        ZosTerminal.instance = term
    end

    term.player = player
    term.computer = computerObj
    term.shell = ZosShell:new(player, computerObj)
    term.lines = {}
    term.carriedPrompt = nil
    term.showStatus = false
    term.typeScript = nil
    term:layoutRows()

    for _, line in ipairs(BOOT_LINES) do
        table.insert(term.lines, line)
    end
    term:refreshOutput()
    term:refreshPrompt()
    term.entry:setText("")

    term:addToUIManager()
    term:setVisible(true)
    term:bringToTop()
    term.entry:focus()
    if autoPlay then
        term:playInsertedFloppy(TYPE_BOOT_TICKS)
    end
    return term
end
