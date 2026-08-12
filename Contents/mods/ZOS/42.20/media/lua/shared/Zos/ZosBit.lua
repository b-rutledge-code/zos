--[[
    ZosBit - bitwise ops for 16-bit values without bitwise operators.

    Kahlua is Lua 5.1: no bit32 module and no & | ~ << >> operators. These
    run off nibble lookup tables so the VM's and/or/not opcodes stay cheap.
    Everything here must also parse on modern Lua so the headless harness in
    tests/ runs the same files the game does.
]]

ZosBit = {}

local POW2 = { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536 }

local AND_NIBBLE = {}
local OR_NIBBLE = {}
local XOR_NIBBLE = {}

for a = 0, 15 do
    AND_NIBBLE[a] = {}
    OR_NIBBLE[a] = {}
    XOR_NIBBLE[a] = {}
    for b = 0, 15 do
        local resAnd, resOr, resXor = 0, 0, 0
        local x, y, bit = a, b, 1
        for _ = 1, 4 do
            local xb = x % 2
            local yb = y % 2
            if xb == 1 and yb == 1 then resAnd = resAnd + bit end
            if xb == 1 or yb == 1 then resOr = resOr + bit end
            if xb ~= yb then resXor = resXor + bit end
            x = math.floor(x / 2)
            y = math.floor(y / 2)
            bit = bit * 2
        end
        AND_NIBBLE[a][b] = resAnd
        OR_NIBBLE[a][b] = resOr
        XOR_NIBBLE[a][b] = resXor
    end
end

local function applyNibbles(tbl, a, b)
    local result = 0
    local scale = 1
    for _ = 1, 4 do
        result = result + tbl[a % 16][b % 16] * scale
        a = math.floor(a / 16)
        b = math.floor(b / 16)
        scale = scale * 16
    end
    return result
end

function ZosBit.band(a, b)
    return applyNibbles(AND_NIBBLE, a, b)
end

function ZosBit.bor(a, b)
    return applyNibbles(OR_NIBBLE, a, b)
end

function ZosBit.bxor(a, b)
    return applyNibbles(XOR_NIBBLE, a, b)
end

-- One's complement within 16 bits.
function ZosBit.bnot(a)
    return 65535 - a % 65536
end

function ZosBit.lshift(a, n)
    return math.floor(a * POW2[n + 1]) % 65536
end

function ZosBit.rshift(a, n)
    return math.floor(a / POW2[n + 1])
end

-- Bit n (0 = least significant) of a, as 0 or 1.
function ZosBit.getBit(a, n)
    return math.floor(a / POW2[n + 1]) % 2
end

function ZosBit.setBit(a, n)
    if ZosBit.getBit(a, n) == 1 then
        return a
    end
    return a + POW2[n + 1]
end

function ZosBit.clearBit(a, n)
    if ZosBit.getBit(a, n) == 0 then
        return a
    end
    return a - POW2[n + 1]
end
