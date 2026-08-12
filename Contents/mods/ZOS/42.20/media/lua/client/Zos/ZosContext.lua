--[[
    ZosContext - Device Options opens the device window. Floppy insert/eject
    and Turn On/Off live on that window. Grid power is required for the CRT
    and Play; eject is mechanical (no power). Pickup/dismantle dumps any
    inserted floppy on the square.
]]

require "ISUI/ISWorldObjectContextMenu"
require "TimedActions/ISBaseTimedAction"

ZosContext = ZosContext or {}

local ZosOpenDeviceAction = ISBaseTimedAction:derive("ZosOpenDeviceAction")

function ZosOpenDeviceAction:isValid()
    return self.computer ~= nil and self.computer:getSquare() ~= nil
end

function ZosOpenDeviceAction:update()
end

function ZosOpenDeviceAction:start()
end

function ZosOpenDeviceAction:complete()
    return true
end

function ZosOpenDeviceAction:perform()
    ZosDeviceWindow.activate(self.character, self.computer)
    ISBaseTimedAction.perform(self)
end

function ZosOpenDeviceAction:getDuration()
    return 1
end

function ZosOpenDeviceAction:new(character, computer)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.computer = computer
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = 1
    return o
end

local ZosOpenTerminalAction = ISBaseTimedAction:derive("ZosOpenTerminalAction")

function ZosOpenTerminalAction:isValid()
    return self.computer ~= nil and self.computer:getSquare() ~= nil
end

function ZosOpenTerminalAction:update()
end

function ZosOpenTerminalAction:start()
end

function ZosOpenTerminalAction:complete()
    return true
end

function ZosOpenTerminalAction:perform()
    ZosTerminal.open(self.character, self.computer, self.autoPlay)
    ISBaseTimedAction.perform(self)
end

function ZosOpenTerminalAction:getDuration()
    return 1
end

function ZosOpenTerminalAction:new(character, computer, autoPlay)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.computer = computer
    o.autoPlay = autoPlay and true or false
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = 1
    return o
end

local ZosFloppyAction = ISBaseTimedAction:derive("ZosFloppyAction")

function ZosFloppyAction:isValid()
    if self.computer == nil or self.computer:getSquare() == nil then
        return false
    end
    if self.item ~= nil then
        return self.item:getContainer() ~= nil
    end
    return ZosFloppies.insertedType(self.computer) ~= nil
end

function ZosFloppyAction:update()
end

function ZosFloppyAction:start()
end

function ZosFloppyAction:complete()
    return true
end

function ZosFloppyAction:perform()
    local md = self.computer:getModData()
    if self.item == nil then
        local itemType = ZosFloppies.clearInserted(self.computer)
        ZosFloppies.giveOrDrop(self.character, itemType, self.computer:getSquare())
        print("ZOS: ejected floppy")
        ZosTerminal.onFloppyEjected(self.computer)
    else
        local container = self.item:getContainer()
        if container ~= nil then
            container:Remove(self.item)
        end
        md.zosFloppy = self.item:getFullType()
        print("ZOS: inserted " .. tostring(md.zosFloppy))
    end
    self.computer:transmitModData()
    ISBaseTimedAction.perform(self)
end

function ZosFloppyAction:getDuration()
    return 1
end

function ZosFloppyAction:new(character, computer, item)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.computer = computer
    o.item = item
    o.stopOnWalk = false
    o.stopOnRun = false
    o.maxTime = 1
    return o
end

local function isComputerObject(obj)
    if not obj or not obj.getProperties then return false end
    local props = obj:getProperties()
    if not props then return false end
    return props:has("CustomName") and props:get("CustomName") == "Computer"
        and props:has("GroupName") and props:get("GroupName") == "Desktop"
end

local function findComputerOnSquare(square)
    if not square then return nil end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if isComputerObject(obj) then
            return obj
        end
    end
    return nil
end

local function squareFromWorldObjects(worldobjects)
    if not worldobjects then return nil end
    for _, obj in ipairs(worldobjects) do
        if obj and obj.getSquare then
            local sq = obj:getSquare()
            if sq then return sq end
        end
    end
    return nil
end

function ZosContext.isComputerPowered(square)
    return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
end

-- Same gate vanilla menus use (inventory, vehicles, hotbar).
function ZosContext.isGamePaused()
    local speeds = UIManager.getSpeedControls()
    return speeds ~= nil and speeds:getCurrentGameSpeed() == 0
end

function ZosContext.isDeviceOn(computer)
    if computer == nil or computer.getModData == nil then
        return false
    end
    return computer:getModData().zosOn == true
end

function ZosContext.setDeviceOn(computer, on)
    if computer == nil or computer.getModData == nil then
        return
    end
    local md = computer:getModData()
    if on then
        md.zosOn = true
    else
        md.zosOn = nil
    end
    computer:transmitModData()
end

local function queueWalkThen(player, computerObj, action)
    if not luautils.walkAdjObject(player, computerObj, false) then return end
    ISTimedActionQueue.add(action)
end

function ZosContext.openDevice(player, computerObj)
    if not player or not computerObj then return end
    if ZosContext.isGamePaused() then return end
    queueWalkThen(player, computerObj, ZosOpenDeviceAction:new(player, computerObj))
end

function ZosContext.openTerminal(player, computerObj, autoPlay)
    if not player or not computerObj then return end
    if ZosContext.isGamePaused() then return end
    queueWalkThen(player, computerObj, ZosOpenTerminalAction:new(player, computerObj, autoPlay))
end

function ZosContext.openOrFocusTerminal(player, computerObj, autoPlay)
    if not player or not computerObj then return end
    if ZosContext.isGamePaused() then return end
    if ZosTerminal.isOpenFor(computerObj) then
        if autoPlay then
            ZosTerminal.instance:playInsertedFloppy()
        end
        return
    end
    local square = computerObj:getSquare()
    if square == nil then return end
    local dx = math.abs(square:getX() + 0.5 - player:getX())
    local dy = math.abs(square:getY() + 0.5 - player:getY())
    if dx <= 1.6 and dy <= 1.6 then
        ZosTerminal.open(player, computerObj, autoPlay)
        return
    end
    ZosContext.openTerminal(player, computerObj, autoPlay)
end

function ZosContext.insertFloppy(player, computerObj, item)
    if not player or not computerObj or not item then return end
    queueWalkThen(player, computerObj, ZosFloppyAction:new(player, computerObj, item))
end

function ZosContext.ejectFloppy(player, computerObj)
    if not player or not computerObj then return end
    queueWalkThen(player, computerObj, ZosFloppyAction:new(player, computerObj, nil))
end

local function onUseComputer(computerObj, playerNum)
    local player = getSpecificPlayer(playerNum)
    ZosContext.openDevice(player, computerObj)
end

local function fillComputerMenu(playerNum, context, worldobjects, test)
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.Test then return true end
    if ZosContext.isGamePaused() then return end

    local square = squareFromWorldObjects(worldobjects)
    local computerObj = findComputerOnSquare(square)
    if not computerObj then return end

    if test then return true end

    context:addOption(getText("IGUI_DeviceOptions"), computerObj, onUseComputer, playerNum)
end

Events.OnFillWorldObjectContextMenu.Add(fillComputerMenu)

local function onComputerRemoved(obj)
    if not isComputerObject(obj) then
        return
    end
    local itemType = ZosFloppies.clearInserted(obj)
    if itemType ~= nil then
        ZosFloppies.dropOnSquare(obj:getSquare(), itemType)
        print("ZOS: dumped floppy on square (" .. tostring(itemType) .. ")")
    end
    ZosTerminal.closeFor(obj)
    ZosDeviceWindow.closeFor(obj)
end

Events.OnObjectAboutToBeRemoved.Add(onComputerRemoved)

Events.OnGameStart.Add(function()
    local n1 = ZosStoryZork1 and ZosStoryZork1.chunks and #ZosStoryZork1.chunks or 0
    local n2 = ZosStoryZork2 and ZosStoryZork2.chunks and #ZosStoryZork2.chunks or 0
    local n3 = ZosStoryZork3 and ZosStoryZork3.chunks and #ZosStoryZork3.chunks or 0
    print(string.format("ZOS: client start, story chunks I=%d II=%d III=%d", n1, n2, n3))
end)
