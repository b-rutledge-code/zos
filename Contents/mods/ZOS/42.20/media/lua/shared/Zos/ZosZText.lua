--[[
    ZosZText - Z-string decoding for Z-machine v3.

    Text is packed 3 five-bit Z-characters per 16-bit word, top bit of the
    word marking the last word of a string. Z-chars 1-3 expand abbreviations,
    4 and 5 shift the next character into alphabet A1/A2, and A2's char 6
    escapes to a 10-bit ZSCII code built from the next two Z-chars.

    See the Z-Machine Standard, section 3.
]]

ZosZText = {}

local ALPHABET_0 = "abcdefghijklmnopqrstuvwxyz"
local ALPHABET_1 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
-- A2 Z-chars 8..31; 6 is the ZSCII escape and 7 is newline, both special-cased.
local ALPHABET_2 = "0123456789.,!?_#'\"/\\-:()"

local STATE_NORMAL = 0
local STATE_ABBREV = 1
local STATE_ZSCII_HIGH = 2
local STATE_ZSCII_LOW = 3

-- ZSCII code to output character (Zork I stays inside plain ASCII).
local function zsciiToChar(code)
    if code == 13 then
        return "\n"
    end
    if code >= 32 and code <= 126 then
        return string.char(code)
    end
    if code == 0 then
        return ""
    end
    return "?"
end

ZosZText.zsciiToChar = zsciiToChar

local function alphabetChar(alphabet, z)
    if alphabet == 0 then
        return string.sub(ALPHABET_0, z - 5, z - 5)
    end
    if alphabet == 1 then
        return string.sub(ALPHABET_1, z - 5, z - 5)
    end
    if z == 7 then
        return "\n"
    end
    return string.sub(ALPHABET_2, z - 7, z - 7)
end

-- Decodes the string at addr. Returns the text and the address just past it.
-- Abbreviations cannot nest, so expansion recurses with allowAbbrev = false.
function ZosZText.decode(vm, addr, allowAbbrev)
    if allowAbbrev == nil then
        allowAbbrev = true
    end

    local out = {}
    local count = 0
    local alphabet = 0
    local state = STATE_NORMAL
    local abbrevKind = 0
    local zsciiHigh = 0
    local at = addr

    while true do
        local word = ZosZMachine.readWord(vm, at)
        at = at + 2

        local zchars = {
            math.floor(word / 1024) % 32,
            math.floor(word / 32) % 32,
            word % 32,
        }

        for i = 1, 3 do
            local z = zchars[i]

            if state == STATE_ABBREV then
                state = STATE_NORMAL
                if allowAbbrev then
                    local index = 32 * (abbrevKind - 1) + z
                    local tableBase = ZosZMachine.readWord(vm, 0x18)
                    local target = ZosZMachine.readWord(vm, tableBase + index * 2) * 2
                    count = count + 1
                    out[count] = ZosZText.decode(vm, target, false)
                end
            elseif state == STATE_ZSCII_HIGH then
                zsciiHigh = z
                state = STATE_ZSCII_LOW
            elseif state == STATE_ZSCII_LOW then
                state = STATE_NORMAL
                count = count + 1
                out[count] = zsciiToChar(zsciiHigh * 32 + z)
            elseif z == 0 then
                count = count + 1
                out[count] = " "
                alphabet = 0
            elseif z <= 3 then
                abbrevKind = z
                state = STATE_ABBREV
            elseif z == 4 then
                alphabet = 1
            elseif z == 5 then
                alphabet = 2
            elseif alphabet == 2 and z == 6 then
                state = STATE_ZSCII_HIGH
                alphabet = 0
            else
                count = count + 1
                out[count] = alphabetChar(alphabet, z)
                alphabet = 0
            end
        end

        if word >= 32768 then
            break
        end
    end

    return table.concat(out), at
end
