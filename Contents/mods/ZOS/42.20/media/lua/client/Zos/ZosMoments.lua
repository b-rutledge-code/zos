--[[
    Pre-mapped Zork story moments → media-style perk XP (50 * amount).
    Once per moment id per character+title (blocks RESTART farming).
]]

ZosMoments = ZosMoments or {}

local XP_PER_UNIT = 50

-- titleCmd "zork" | "zork2" | "zork3"
local MOMENTS = {
    {
        id = "troll",
        title = "zork",
        perk = "LongBlade",
        amount = 2,
        matchAny = {
            "troll breathes his last",
            "poor troll, he dies",
            "carcass has disappeared",
        },
        matchAlso = { "troll" },
    },
    {
        id = "maze_clear",
        title = "zork",
        perk = "Lightfoot",
        amount = 1,
        mazeClear = true,
    },
    {
        id = "grate",
        title = "zork",
        perk = "Maintenance",
        amount = 1,
        matchAny = { "the grate is unlocked", "pile of leaves falls onto your head" },
    },
    {
        id = "painting",
        title = "zork",
        perk = "PlantScavenging",
        amount = 1,
        room = "Gallery",
        scoreUp = true,
    },
    {
        id = "climb",
        title = "zork",
        perk = "Nimble",
        amount = 1,
        enterRoomAny = { "Up a Tree", "Studio" },
    },
    {
        id = "dam_bolt",
        title = "zork",
        perk = "Electricity",
        amount = 2,
        matchAny = { "the sluice gates open and water pours through the dam" },
    },
    {
        id = "screwdriver",
        title = "zork",
        perk = "Maintenance",
        amount = 1,
        room = "Maintenance Room",
        takeScrewdriver = true,
    },
    {
        id = "machine",
        title = "zork",
        perk = "Electricity",
        amount = 1,
        room = "Machine Room",
        matchAny = { "the lid opens, revealing", "enormous diamond" },
    },
    {
        id = "cyclops",
        title = "zork",
        perk = "Nimble",
        amount = 1,
        matchAny = {
            "cyclops, hearing the name of his father's deadly nemesis",
            "flees the room by knocking down the wall",
        },
    },
    {
        id = "thief",
        title = "zork",
        perk = "SmallBlade",
        amount = 2,
        matchAny = {
            "curtains for the thief",
            "thief breathes his last",
            "as the thief dies",
        },
    },
    {
        id = "complete1",
        title = "zork",
        perk = "Electricity",
        amount = 2,
        scoreAtLeast = 350,
    },
    {
        id = "complete2",
        title = "zork2",
        perk = "Electricity",
        amount = 2,
        scoreAtLeast = 400,
    },
}

local function perkEnum(name)
    if Perks == nil then
        return nil
    end
    return Perks[name]
end

local function claimsTable(player)
    local md = player:getModData()
    if md.zosXpClaimed == nil then
        md.zosXpClaimed = {}
    end
    return md.zosXpClaimed
end

local function isClaimed(player, titleCmd, momentId)
    local all = claimsTable(player)
    local forTitle = all[titleCmd]
    return forTitle ~= nil and forTitle[momentId] == true
end

local function setClaimed(player, titleCmd, momentId)
    local all = claimsTable(player)
    if all[titleCmd] == nil then
        all[titleCmd] = {}
    end
    all[titleCmd][momentId] = true
end

local function linesJoined(lines)
    if lines == nil then
        return ""
    end
    local parts = {}
    for i = 1, #lines do
        parts[#parts + 1] = tostring(lines[i])
    end
    return string.lower(table.concat(parts, "\n"))
end

local function containsAny(haystack, needles)
    if needles == nil then
        return false
    end
    for i = 1, #needles do
        if string.find(haystack, string.lower(needles[i]), 1, true) then
            return true
        end
    end
    return false
end

local function isMazeRoom(room)
    if room == nil then
        return false
    end
    return string.find(room, "Maze", 1, true) ~= nil
end

local function perkDisplayName(perk)
    local key = perk:getName()
    if key == nil then
        return tostring(perk)
    end
    -- perk:getName() is a translation key; VHS uses getText("IGUI_perks_…").
    local translated = getText(key)
    if translated ~= nil and translated ~= "" then
        return translated
    end
    return key
end

local function grant(player, moment)
    local perk = perkEnum(moment.perk)
    if perk == nil then
        return false
    end
    if SandboxVars ~= nil and SandboxVars.LevelForMediaXPCutoff ~= nil then
        if player:getPerkLevel(perk) >= SandboxVars.LevelForMediaXPCutoff then
            return false
        end
    end
    local xp = XP_PER_UNIT * (moment.amount or 1)
    local oldXp = player:getXp():getXP(perk)
    addXp(player, perk, xp)
    local newXp = player:getXp():getXP(perk)
    -- Match VHS (ISRadioInteractions.doSkill): perk label + up arrow in good color.
    if oldXp ~= newXp then
        HaloTextHelper.addTextWithArrow(
            player,
            perkDisplayName(perk),
            "[br/]",
            true,
            HaloTextHelper.getGoodColor()
        )
    end
    print(string.format("ZOS: moment %s → %s +%d XP (halo)", moment.id, moment.perk, xp))
    return true
end

local function matchesMoment(moment, prev, curr, text, session)
    if moment.scoreAtLeast ~= nil then
        return curr.score ~= nil and curr.score >= moment.scoreAtLeast
            and (prev == nil or prev.score == nil or prev.score < moment.scoreAtLeast)
    end

    if moment.mazeClear then
        if session == nil or not session.wasInMaze then
            return false
        end
        local room = curr.room or ""
        return not isMazeRoom(room) and room ~= ""
    end

    if moment.takeScrewdriver then
        if curr.room ~= moment.room then
            return false
        end
        return containsAny(text, { "screwdriver" }) and containsAny(text, { "taken", "ok." })
    end

    if moment.enterRoomAny ~= nil then
        local room = curr.room or ""
        local prevRoom = prev and prev.room or ""
        if room == prevRoom then
            return false
        end
        for i = 1, #moment.enterRoomAny do
            if room == moment.enterRoomAny[i] then
                return true
            end
        end
        return false
    end

    if moment.room ~= nil and curr.room ~= moment.room then
        return false
    end

    if moment.scoreUp then
        if prev == nil or curr.score == nil or prev.score == nil then
            return false
        end
        if not (curr.score > prev.score) then
            return false
        end
    end

    if moment.matchAny ~= nil then
        if not containsAny(text, moment.matchAny) then
            return false
        end
    end

    if moment.matchAlso ~= nil then
        if not containsAny(text, moment.matchAlso) then
            return false
        end
    end

    return moment.matchAny ~= nil or moment.scoreUp == true or moment.room ~= nil
end

--- Call after a Zork turn. session holds { wasInMaze = bool } for maze clear.
function ZosMoments.evaluate(player, titleCmd, prevStatus, currStatus, lines, session)
    if player == nil or titleCmd == nil or currStatus == nil then
        return
    end

    if session ~= nil then
        if isMazeRoom(currStatus.room) then
            session.wasInMaze = true
        end
    end

    local text = linesJoined(lines)
    for i = 1, #MOMENTS do
        local moment = MOMENTS[i]
        if moment.title == titleCmd and not isClaimed(player, titleCmd, moment.id) then
            if matchesMoment(moment, prevStatus, currStatus, text, session) then
                if grant(player, moment) then
                    setClaimed(player, titleCmd, moment.id)
                end
            end
        end
    end
end

function ZosMoments.newSession()
    return { wasInMaze = false }
end
