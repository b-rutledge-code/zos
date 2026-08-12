--[[
    ZosFloppies - one catalog for insert, A: dir, launch, and per-title saves.
]]

ZosFloppies = {
    {
        item = "Zos.FloppyZork1",
        storyName = "ZosStoryZork1",
        dirLine = "ZORK     EXE",
        cmd = "zork",
        saveKey = "zosZork1Save",
        exeName = "ZORK.EXE",
    },
    {
        item = "Zos.FloppyZork2",
        storyName = "ZosStoryZork2",
        dirLine = "ZORK2    EXE",
        cmd = "zork2",
        saveKey = "zosZork2Save",
        exeName = "ZORK2.EXE",
    },
    {
        item = "Zos.FloppyZork3",
        storyName = "ZosStoryZork3",
        dirLine = "ZORK3    EXE",
        cmd = "zork3",
        saveKey = "zosZork3Save",
        exeName = "ZORK3.EXE",
    },
}

function ZosFloppies.byItem(itemType)
    if itemType == nil then
        return nil
    end
    for i = 1, #ZosFloppies do
        if ZosFloppies[i].item == itemType then
            return ZosFloppies[i]
        end
    end
    return nil
end

function ZosFloppies.byCmd(cmd)
    if cmd == nil then
        return nil
    end
    for i = 1, #ZosFloppies do
        if ZosFloppies[i].cmd == cmd then
            return ZosFloppies[i]
        end
    end
    return nil
end

function ZosFloppies.insertedType(computer)
    if computer == nil or computer.getModData == nil then
        return nil
    end
    return computer:getModData().zosFloppy
end

function ZosFloppies.inserted(computer)
    return ZosFloppies.byItem(ZosFloppies.insertedType(computer))
end

function ZosFloppies.playerHas(player, itemType)
    if player == nil or itemType == nil then
        return false
    end
    local inv = player:getInventory()
    return inv ~= nil and inv:containsTypeRecurse(itemType)
end

function ZosFloppies.driveReady(computer)
    return ZosFloppies.inserted(computer) ~= nil
end

function ZosFloppies.clearInserted(computer)
    if computer == nil or computer.getModData == nil then
        return nil
    end
    local md = computer:getModData()
    local itemType = md.zosFloppy
    md.zosFloppy = nil
    return itemType
end

function ZosFloppies.itemWeight(itemType)
    if itemType == nil or getScriptManager == nil then
        return 0.2
    end
    local script = getScriptManager():getItem(itemType)
    if script ~= nil and script.getActualWeight then
        return script:getActualWeight()
    end
    return 0.2
end

function ZosFloppies.dropOnSquare(square, itemType)
    if square == nil or itemType == nil then
        return
    end
    square:AddWorldInventoryItem(itemType, 0.5, 0.5, 0)
end

function ZosFloppies.giveOrDrop(player, itemType, fallbackSquare)
    if itemType == nil then
        return
    end
    local inv = player ~= nil and player:getInventory() or nil
    if inv ~= nil and inv:hasRoomFor(player, ZosFloppies.itemWeight(itemType)) then
        inv:AddItem(itemType)
        return
    end
    local square = (player ~= nil and player:getCurrentSquare()) or fallbackSquare
    ZosFloppies.dropOnSquare(square, itemType)
end

function ZosFloppies.story(title)
    if title == nil then
        return nil
    end
    return _G[title.storyName]
end
