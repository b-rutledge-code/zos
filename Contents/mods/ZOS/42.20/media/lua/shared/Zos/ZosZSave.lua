--[[
    ZosZSave - pack a V3 machine into a hex string for IsoObject ModData.

    Hex, not a binary Lua string: Kahlua's string.byte is not safe on NULs,
    and ModData has to survive a world save. The blob is ASCII 0-9A-F only.
]]

ZosZSave = {}

local FORMAT = 1

local function wrap8(n)
    n = n % 256
    if n < 0 then n = n + 256 end
    return n
end

local function wrap16(n)
    n = n % 65536
    if n < 0 then n = n + 65536 end
    return n
end

local function newWriter()
    local parts = {}
    local n = 0
    local w = {}

    function w.u8(v)
        n = n + 1
        parts[n] = string.format("%02X", wrap8(v))
    end

    function w.u16(v)
        n = n + 1
        parts[n] = string.format("%04X", wrap16(v))
    end

    function w.u32(v)
        v = math.floor(v)
        if v < 0 then v = 0 end
        n = n + 1
        parts[n] = string.format("%08X", v)
    end

    function w.finish()
        return table.concat(parts)
    end

    return w
end

local function hexNibble(code)
    if code >= 48 and code <= 57 then
        return code - 48
    end
    if code >= 65 and code <= 70 then
        return code - 55
    end
    if code >= 97 and code <= 102 then
        return code - 87
    end
    return nil
end

local function newReader(blob)
    if type(blob) ~= "string" or #blob < 8 then
        return nil
    end
    local at = 1
    local r = {}

    local function take(hexChars)
        if at + hexChars - 1 > #blob then
            return nil
        end
        local value = 0
        for i = 0, hexChars - 1 do
            local nibble = hexNibble(string.byte(blob, at + i))
            if nibble == nil then
                return nil
            end
            value = value * 16 + nibble
        end
        at = at + hexChars
        return value
    end

    function r.u8()
        return take(2)
    end

    function r.u16()
        return take(4)
    end

    function r.u32()
        return take(8)
    end

    function r.eof()
        return at > #blob
    end

    return r
end

local function localCount(frame)
    local n = 0
    if frame.locals == nil then
        return 0
    end
    while frame.locals[n + 1] ~= nil do
        n = n + 1
    end
    return n
end

function ZosZSave.encode(vm)
    if vm == nil or vm.dyn == nil then
        return nil
    end

    local w = newWriter()
    w.u8(90)  -- Z
    w.u8(79)  -- O
    w.u8(83)  -- S
    w.u8(49)  -- 1
    w.u16(FORMAT)
    w.u16(vm.release)
    w.u16(vm.checksum)
    w.u32(vm.storyLength)
    w.u16(vm.staticBase)
    w.u32(vm.pc)
    w.u16(vm.sp)
    w.u16(vm.frameCount)
    w.u32(vm.rng or 1)

    for addr = 0, vm.staticBase - 1 do
        w.u8(vm.dyn[addr] or 0)
    end

    w.u16(vm.sp)
    for i = 1, vm.sp do
        w.u16(vm.stack[i] or 0)
    end

    for i = 1, vm.frameCount do
        local frame = vm.frames[i]
        local n = localCount(frame)
        w.u8(n)
        for li = 1, n do
            w.u16(frame.locals[li] or 0)
        end
        w.u32(frame.retPC or 0)
        if frame.storeVar == nil then
            w.u16(65535)
        else
            w.u16(frame.storeVar)
        end
        w.u16(frame.stackBase or 0)
    end

    return w.finish()
end

function ZosZSave.decode(blob)
    local r = newReader(blob)
    if r == nil then
        return nil
    end
    if r.u8() ~= 90 or r.u8() ~= 79 or r.u8() ~= 83 or r.u8() ~= 49 then
        return nil
    end
    if r.u16() ~= FORMAT then
        return nil
    end

    local state = {}
    state.release = r.u16()
    state.checksum = r.u16()
    state.storyLength = r.u32()
    state.staticBase = r.u16()
    state.pc = r.u32()
    state.sp = r.u16()
    state.frameCount = r.u16()
    state.rng = r.u32()
    if state.release == nil or state.rng == nil then
        return nil
    end

    state.dyn = {}
    for addr = 0, state.staticBase - 1 do
        local b = r.u8()
        if b == nil then
            return nil
        end
        state.dyn[addr] = b
    end

    local stackLen = r.u16()
    if stackLen == nil or stackLen ~= state.sp then
        return nil
    end
    state.stack = {}
    for i = 1, state.sp do
        local word = r.u16()
        if word == nil then
            return nil
        end
        state.stack[i] = word
    end

    state.frames = {}
    for i = 1, state.frameCount do
        local n = r.u8()
        if n == nil or n > 15 then
            return nil
        end
        local locals = {}
        for li = 1, n do
            local word = r.u16()
            if word == nil then
                return nil
            end
            locals[li] = word
        end
        local retPC = r.u32()
        local storeVar = r.u16()
        local stackBase = r.u16()
        if retPC == nil or storeVar == nil or stackBase == nil then
            return nil
        end
        local frame = {
            locals = locals,
            retPC = retPC,
            stackBase = stackBase,
        }
        if storeVar ~= 65535 then
            frame.storeVar = storeVar
        end
        state.frames[i] = frame
    end

    return state
end

function ZosZSave.apply(vm, blob)
    local state = ZosZSave.decode(blob)
    if state == nil then
        return false
    end
    if state.release ~= vm.release or state.checksum ~= vm.checksum then
        return false
    end
    if state.storyLength ~= vm.storyLength or state.staticBase ~= vm.staticBase then
        return false
    end

    vm.dyn = state.dyn
    vm.stack = state.stack
    vm.frames = state.frames
    vm.pc = state.pc
    vm.sp = state.sp
    vm.frameCount = state.frameCount
    vm.rng = state.rng
    vm.halted = false
    vm.quit = false
    vm.error = nil
    vm.pendingRead = nil
    vm.out = {}
    vm.outCount = 0
    vm.statusRequested = true
    return true
end
