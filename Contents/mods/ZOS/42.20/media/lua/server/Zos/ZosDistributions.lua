--[[
    ZosDistributions - places Zork I/II/III floppies into existing procedural
    loot lists (electronics, bookstores, desks, bedrooms, university), at
    roughly Disc_Retail's rarity for a desk/bedroom find.

    Uses OnGameBoot, same pattern as other mods in this workspace, since
    ProceduralDistributions.list only exists once the base game has built it.
]]

local FLOPPY_ITEMS = {
    "Zos.FloppyZork1",
    "Zos.FloppyZork2",
    "Zos.FloppyZork3",
}

local function addFloppyToList(listName, item, weight)
    local list = ProceduralDistributions.list[listName]
    if not list or not list.items then return end
    table.insert(list.items, item)
    table.insert(list.items, weight)
end

local function initZosDistributions()
    if not ProceduralDistributions or not ProceduralDistributions.list then return end

    for i = 1, #FLOPPY_ITEMS do
        local item = FLOPPY_ITEMS[i]
        addFloppyToList("ElectronicStoreComputers", item, 4)
        addFloppyToList("BookstoreComputer", item, 4)
        addFloppyToList("DeskGeneric", item, 2)
        addFloppyToList("BedroomDresser", item, 2)
        addFloppyToList("UniversityDesk_Business", item, 2)
    end
end

Events.OnGameBoot.Add(initZosDistributions)
