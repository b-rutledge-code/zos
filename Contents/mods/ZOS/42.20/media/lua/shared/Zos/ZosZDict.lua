--[[
    ZosZDict - dictionary lookup and sread tokenizing for v3.

    The dictionary header lists word separators, then the entry length and
    entry count; entries follow, sorted by their encoded text. A v3 entry
    starts with 4 bytes holding 6 Z-characters, so lookup encodes the typed
    word the same way and binary searches on those two words.

    See the Z-Machine Standard, sections 13 and 15.
]]

ZosZDict = {}

local ALPHABET_0 = "abcdefghijklmnopqrstuvwxyz"
local ALPHABET_2 = "0123456789.,!?_#'\"/\\-:()"
local PAD_ZCHAR = 5
local V3_ZCHARS = 6

local function header(vm)
    local base = vm.dictBase
    local sepCount = ZosZMachine.readByte(vm, base)
    local lengthAddr = base + 1 + sepCount
    return {
        base = base,
        sepCount = sepCount,
        sepAddr = base + 1,
        entryLength = ZosZMachine.readByte(vm, lengthAddr),
        entryCount = ZosZMachine.readWord(vm, lengthAddr + 1),
        entriesAddr = lengthAddr + 3,
    }
end

ZosZDict.header = header

function ZosZDict.isSeparator(vm, char)
    local head = header(vm)
    for i = 0, head.sepCount - 1 do
        if ZosZMachine.readByte(vm, head.sepAddr + i) == string.byte(char) then
            return true
        end
    end
    return false
end

-- Encodes a word into the 6 Z-characters a v3 entry holds, returned as the
-- two 16-bit words those pack into.
function ZosZDict.encodeWord(word)
    local zchars = {}
    local count = 0
    local lower = string.lower(word)

    for i = 1, #lower do
        if count >= V3_ZCHARS then break end
        local char = string.sub(lower, i, i)
        local a0 = string.find(ALPHABET_0, char, 1, true)
        if a0 then
            count = count + 1
            zchars[count] = a0 + 5
        else
            local a2 = string.find(ALPHABET_2, char, 1, true)
            if a2 then
                count = count + 1
                zchars[count] = 5
                if count < V3_ZCHARS then
                    count = count + 1
                    zchars[count] = a2 + 7
                end
            else
                -- Anything outside both alphabets goes through the ZSCII escape.
                local code = string.byte(char)
                count = count + 1
                zchars[count] = 5
                if count < V3_ZCHARS then
                    count = count + 1
                    zchars[count] = 6
                end
                if count < V3_ZCHARS then
                    count = count + 1
                    zchars[count] = math.floor(code / 32)
                end
                if count < V3_ZCHARS then
                    count = count + 1
                    zchars[count] = code % 32
                end
            end
        end
    end

    for i = count + 1, V3_ZCHARS do
        zchars[i] = PAD_ZCHAR
    end

    local word1 = zchars[1] * 1024 + zchars[2] * 32 + zchars[3]
    local word2 = zchars[4] * 1024 + zchars[5] * 32 + zchars[6] + 32768
    return word1, word2
end

-- Address of the dictionary entry for word, or 0 when it is not in there.
function ZosZDict.lookup(vm, word)
    local head = header(vm)
    local target1, target2 = ZosZDict.encodeWord(word)

    local low = 0
    local high = head.entryCount - 1
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local addr = head.entriesAddr + mid * head.entryLength
        local entry1 = ZosZMachine.readWord(vm, addr)
        local entry2 = ZosZMachine.readWord(vm, addr + 2)
        if entry1 == target1 and entry2 == target2 then
            return addr
        end
        if entry1 < target1 or (entry1 == target1 and entry2 < target2) then
            low = mid + 1
        else
            high = mid - 1
        end
    end

    return 0
end

-- Splits the text buffer written by sread into { text, position } tokens.
-- Position is the offset of the word's first letter within the text buffer.
function ZosZDict.splitInput(vm, textAddr)
    local head = header(vm)
    local separators = {}
    for i = 0, head.sepCount - 1 do
        separators[ZosZMachine.readByte(vm, head.sepAddr + i)] = true
    end

    local tokens = {}
    local count = 0
    local current = nil
    local currentStart = 0
    local at = textAddr + 1

    while true do
        local code = ZosZMachine.readByte(vm, at)
        if code == 0 then break end
        local char = string.char(code)
        if char == " " then
            if current then
                count = count + 1
                tokens[count] = { text = current, position = currentStart }
                current = nil
            end
        elseif separators[code] then
            if current then
                count = count + 1
                tokens[count] = { text = current, position = currentStart }
                current = nil
            end
            count = count + 1
            tokens[count] = { text = char, position = at - textAddr }
        else
            if not current then
                current = char
                currentStart = at - textAddr
            else
                current = current .. char
            end
        end
        at = at + 1
    end

    if current then
        count = count + 1
        tokens[count] = { text = current, position = currentStart }
    end

    return tokens
end

-- Fills the parse buffer: max words at byte 0, word count at byte 1, then
-- 4 bytes per word (dictionary address, letter count, buffer position).
function ZosZDict.tokenize(vm, textAddr, parseAddr)
    if parseAddr == 0 then return end

    local tokens = ZosZDict.splitInput(vm, textAddr)
    local maxWords = ZosZMachine.readByte(vm, parseAddr)
    local stored = 0

    for i = 1, #tokens do
        if stored >= maxWords then break end
        local token = tokens[i]
        local entry = ZosZDict.lookup(vm, token.text)
        local at = parseAddr + 2 + stored * 4
        ZosZMachine.writeWord(vm, at, entry)
        ZosZMachine.writeByte(vm, at + 2, #token.text)
        ZosZMachine.writeByte(vm, at + 3, token.position)
        stored = stored + 1
    end

    ZosZMachine.writeByte(vm, parseAddr + 1, stored)
end
