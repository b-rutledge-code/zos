--[[
    Soft green IsoLightSource on a Desktop Computer square while the PC is
    on and powered. Also swaps to vanilla lit frames (76–79). Client-side;
    no DeviceData.
]]

ZosCrtLight = ZosCrtLight or {}

-- key "x:y:z" -> { computer = IsoObject, light = IsoLightSource|nil }
local entries = {}

local LIGHT_R = 0.3
local LIGHT_G = 1.0
local LIGHT_B = 0.4
local LIGHT_RADIUS = 3
local TICK_INTERVAL = 30

-- Vanilla unused lit Desktop frames (S/E/N/W).
local OFF_TO_ON = {
    ["appliances_com_01_72"] = "appliances_com_01_76", -- S
    ["appliances_com_01_73"] = "appliances_com_01_77", -- E
    ["appliances_com_01_74"] = "appliances_com_01_78", -- N
    ["appliances_com_01_75"] = "appliances_com_01_79", -- W
}
local ON_TO_OFF = {
    ["appliances_com_01_76"] = "appliances_com_01_72",
    ["appliances_com_01_77"] = "appliances_com_01_73",
    ["appliances_com_01_78"] = "appliances_com_01_74",
    ["appliances_com_01_79"] = "appliances_com_01_75",
}

local tickCounter = 0

local function squareKey(square)
    return string.format("%d:%d:%d", square:getX(), square:getY(), square:getZ())
end

local function spriteName(computer)
    if computer == nil or computer.getSprite == nil then
        return nil
    end
    local sprite = computer:getSprite()
    if sprite == nil or sprite.getName == nil then
        return nil
    end
    return sprite:getName()
end

local function setComputerSprite(computer, name)
    if computer == nil or name == nil then
        return
    end
    local sprite = getSprite(name)
    if sprite == nil then
        return
    end
    computer:setSprite(sprite)
    computer:DirtySlice()
    if computer.transmitUpdatedSprite ~= nil then
        computer:transmitUpdatedSprite()
    elseif isClient() then
        computer:transmitUpdatedSpriteToServer()
    elseif isServer() then
        computer:transmitUpdatedSpriteToClients()
    end
end

--- Swap between off (72–75) and lit (76–79) by facing.
local function applyScreen(computer, lit)
    local name = spriteName(computer)
    if name == nil then
        return
    end
    local target
    if lit then
        target = OFF_TO_ON[name] or (ON_TO_OFF[name] and name) or nil
    else
        target = ON_TO_OFF[name] or (OFF_TO_ON[name] and name) or nil
    end
    if target == nil or target == name then
        return
    end
    setComputerSprite(computer, target)
end

local function removeLight(entry)
    if entry == nil or entry.light == nil then
        return
    end
    local cell = getCell()
    if cell ~= nil then
        entry.light:setActive(false)
        cell:removeLamppost(entry.light)
    end
    entry.light = nil
end

local function removeEntry(key)
    local entry = entries[key]
    if entry == nil then
        return
    end
    if entry.computer ~= nil then
        applyScreen(entry.computer, false)
    end
    removeLight(entry)
    entries[key] = nil
end

local function ensureLight(entry, square)
    if entry.light ~= nil then
        return
    end
    local light = IsoLightSource.new(
        square:getX(),
        square:getY(),
        square:getZ(),
        LIGHT_R,
        LIGHT_G,
        LIGHT_B,
        LIGHT_RADIUS
    )
    light:setActive(true)
    getCell():addLamppost(light)
    entry.light = light
end

--- Keep lamppost + lit sprite in sync with zosOn + power.
function ZosCrtLight.sync(computer)
    if computer == nil or computer.getSquare == nil then
        return
    end
    local square = computer:getSquare()
    if square == nil then
        return
    end
    local key = squareKey(square)
    if not ZosContext.isDeviceOn(computer) then
        applyScreen(computer, false)
        removeEntry(key)
        return
    end
    local entry = entries[key]
    if entry == nil then
        entry = { computer = computer, light = nil }
        entries[key] = entry
    else
        entry.computer = computer
    end
    if ZosContext.isComputerPowered(square) then
        ensureLight(entry, square)
        applyScreen(computer, true)
    else
        removeLight(entry)
        applyScreen(computer, false)
    end
end

function ZosCrtLight.remove(computer)
    if computer == nil then
        return
    end
    applyScreen(computer, false)
    if computer.getSquare ~= nil then
        local square = computer:getSquare()
        if square ~= nil then
            local key = squareKey(square)
            local entry = entries[key]
            if entry ~= nil then
                removeLight(entry)
                entries[key] = nil
            end
            return
        end
    end
    for key, entry in pairs(entries) do
        if entry.computer == computer then
            removeLight(entry)
            entries[key] = nil
            return
        end
    end
end

local function onLoadSquare(square)
    if square == nil then
        return
    end
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if ZosContext.isDesktopComputer(obj) and ZosContext.isDeviceOn(obj) then
            ZosCrtLight.sync(obj)
        end
    end
end

local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter < TICK_INTERVAL then
        return
    end
    tickCounter = 0
    local stale = {}
    for key, entry in pairs(entries) do
        local computer = entry.computer
        if computer == nil or computer.getSquare == nil or computer:getSquare() == nil then
            table.insert(stale, key)
        else
            ZosCrtLight.sync(computer)
        end
    end
    for i = 1, #stale do
        removeEntry(stale[i])
    end
end

Events.LoadGridsquare.Add(onLoadSquare)
Events.OnTick.Add(onTick)
