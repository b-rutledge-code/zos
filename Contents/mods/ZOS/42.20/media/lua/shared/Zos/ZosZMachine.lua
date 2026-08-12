--[[
    ZosZMachine - a Z-machine v3 interpreter.

    Memory: dynamic memory (below the header's static base) is copied into a
    0-indexed byte table so it can be written; static and high memory are read
    from the baked 1024-byte chunks. Kahlua's string.byte returns 0 for
    indexes past 64KB, so a single concatenated story string is not safe.

    Control: run() executes instructions until it hits `sread`, the story
    quits, an opcode is missing, or the step budget runs out. On `sread` it
    records the buffers and returns "input" with the PC already past the
    instruction, so provideInput() + another run() resumes. No coroutines, so
    the caller keeps control of the game loop.

    Written against the Z-Machine Standard 1.1. Everything here is plain
    Lua 5.1 so the same file runs in Kahlua and in tests/.
]]

ZosZMachine = {}

local DEFAULT_STEP_BUDGET = 400000
local RNG_MODULUS = 2147483647
local RNG_MULTIPLIER = 16807

local TYPE_LARGE = 0
local TYPE_SMALL = 1
local TYPE_VARIABLE = 2
local TYPE_OMITTED = 3

local TYPE_DIVISORS = { 64, 16, 4, 1 }

local OP0 = {}
local OP1 = {}
local OP2 = {}
local OPVAR = {}

local readVar, writeVar, readVarIndirect, writeVarIndirect
local pushStack, popStack
local fetchStoreVar, callRoutine, returnFromRoutine, branch
local emit, toSigned

--=========================================================================
-- Memory
--=========================================================================

local CHUNK = 1024

local function wrap8(n)
    n = n % 256
    if n < 0 then
        n = n + 256
    end
    return n
end

local function wrap16(n)
    n = n % 65536
    if n < 0 then
        n = n + 65536
    end
    return n
end

function ZosZMachine.fail(vm, message)
    vm.halted = true
    vm.error = message
    print("ZOS: " .. message)
end

-- Always reads the baked story, never dynamic overlays. Chunks are 1024-entry
-- number tables: Kahlua's string.byte is not safe on strings that contain NUL.
local function readStoryByte(vm, addr)
    if addr < 0 or addr >= vm.storyLength then
        return nil
    end
    local chunkIdx = math.floor(addr / CHUNK) + 1
    local off = addr - (chunkIdx - 1) * CHUNK + 1
    local chunk = vm.chunks[chunkIdx]
    if chunk == nil then
        return nil
    end
    if type(chunk) == "string" then
        return string.byte(chunk, off)
    end
    return chunk[off]
end

function ZosZMachine.readByte(vm, addr)
    if addr < vm.staticBase then
        local value = vm.dyn[addr]
        if value == nil then
            ZosZMachine.fail(vm, string.format("read from bad address 0x%X", addr))
            return 0
        end
        return value
    end
    local value = readStoryByte(vm, addr)
    if value == nil then
        ZosZMachine.fail(vm, string.format("read past end of story at 0x%X", addr))
        return 0
    end
    return value
end

function ZosZMachine.readWord(vm, addr)
    return ZosZMachine.readByte(vm, addr) * 256 + ZosZMachine.readByte(vm, addr + 1)
end

function ZosZMachine.writeByte(vm, addr, value)
    if addr < 0 or addr >= vm.staticBase then
        ZosZMachine.fail(vm, string.format("write outside dynamic memory at 0x%X", addr))
        return
    end
    vm.dyn[addr] = wrap8(value)
end

function ZosZMachine.writeWord(vm, addr, value)
    value = wrap16(value)
    ZosZMachine.writeByte(vm, addr, math.floor(value / 256))
    ZosZMachine.writeByte(vm, addr + 1, wrap8(value))
end

--=========================================================================
-- Construction
--=========================================================================

local function normaliseSeed(seed)
    local value = math.floor(math.abs(seed or 1)) % (RNG_MODULUS - 1)
    if value == 0 then
        value = 1
    end
    return value
end

-- Loads dynamic memory and clears the machine back to its start state. Used
-- both at construction and by the restart opcode, which keeps any output the
-- caller has not drained yet.
function ZosZMachine.reset(vm, seed)
    local dyn = {}
    for addr = 0, vm.staticBase - 1 do
        dyn[addr] = readStoryByte(vm, addr)
    end
    vm.dyn = dyn

    -- Flags1: status line available, no screen splitting, fixed-pitch font.
    local flags = dyn[0x01]
    flags = ZosBit.clearBit(flags, 4)
    flags = ZosBit.clearBit(flags, 5)
    flags = ZosBit.clearBit(flags, 6)
    dyn[0x01] = flags

    vm.pc = vm.initialPC
    vm.stack = {}
    vm.sp = 0
    vm.frames = { { locals = {}, retPC = 0, storeVar = nil, stackBase = 0 } }
    vm.frameCount = 1
    vm.out = vm.out or {}
    vm.outCount = vm.outCount or 0
    vm.halted = false
    vm.quit = false
    vm.error = nil
    vm.pendingRead = nil
    vm.statusRequested = false
    vm.instructions = 0
    if seed ~= nil or vm.rng == nil then
        vm.rng = normaliseSeed(seed)
    end
end

local function unpackStory(story)
    if type(story) == "table" and story.chunks ~= nil then
        return story.chunks, story.length
    end
    if type(story) == "string" then
        local chunks = {}
        local n = 0
        for i = 1, #story, CHUNK do
            n = n + 1
            chunks[n] = string.sub(story, i, i + CHUNK - 1)
        end
        return chunks, #story
    end
    return nil, nil
end

-- Returns a machine for a baked story table (or a raw story string), or nil plus a message.
function ZosZMachine.new(story, seed)
    local chunks, length = unpackStory(story)
    if chunks == nil or length == nil or length < 64 then
        return nil, "story data missing or too short"
    end

    local vm = {}
    vm.chunks = chunks
    vm.storyLength = length

    local function rawByte(addr)
        return readStoryByte(vm, addr) or 0
    end
    local function rawWord(addr)
        return rawByte(addr) * 256 + rawByte(addr + 1)
    end

    local version = rawByte(0x00)
    if version ~= 3 then
        return nil, "story is Z-machine version " .. version .. ", this interpreter is v3 only"
    end

    vm.version = version
    vm.highBase = rawWord(0x04)
    vm.initialPC = rawWord(0x06)
    print(string.format("ZOS: header v=%d pc=0x%X static=0x%X dict=0x%X",
        version, vm.initialPC, rawWord(0x0E), rawWord(0x08)))
    vm.dictBase = rawWord(0x08)
    vm.objBase = rawWord(0x0A)
    vm.globalsBase = rawWord(0x0C)
    vm.staticBase = rawWord(0x0E)
    vm.abbrevBase = rawWord(0x18)
    vm.fileLength = rawWord(0x1A) * 2
    vm.checksum = rawWord(0x1C)
    vm.release = rawWord(0x02)

    ZosZMachine.reset(vm, seed or 1)
    return vm
end

--=========================================================================
-- Stack, variables, output
--=========================================================================

pushStack = function(vm, value)
    vm.sp = vm.sp + 1
    vm.stack[vm.sp] = value % 65536
end

popStack = function(vm)
    if vm.sp <= 0 then
        ZosZMachine.fail(vm, "stack underflow")
        return 0
    end
    local value = vm.stack[vm.sp]
    vm.sp = vm.sp - 1
    return value
end

readVar = function(vm, number)
    if number == 0 then
        return popStack(vm)
    end
    if number < 16 then
        local value = vm.frames[vm.frameCount].locals[number]
        if value == nil then
            ZosZMachine.fail(vm, "read of local " .. number .. " which this routine does not have")
            return 0
        end
        return value
    end
    return ZosZMachine.readWord(vm, vm.globalsBase + (number - 16) * 2)
end

writeVar = function(vm, number, value)
    value = value % 65536
    if number == 0 then
        pushStack(vm, value)
        return
    end
    if number < 16 then
        vm.frames[vm.frameCount].locals[number] = value
        return
    end
    ZosZMachine.writeWord(vm, vm.globalsBase + (number - 16) * 2, value)
end

-- Indirect references (load/store/inc/dec/pull) read and write the top of
-- the stack in place rather than popping and pushing it.
readVarIndirect = function(vm, number)
    if number ~= 0 then
        return readVar(vm, number)
    end
    if vm.sp <= 0 then
        ZosZMachine.fail(vm, "indirect read of empty stack")
        return 0
    end
    return vm.stack[vm.sp]
end

writeVarIndirect = function(vm, number, value)
    if number ~= 0 then
        writeVar(vm, number, value)
        return
    end
    if vm.sp <= 0 then
        pushStack(vm, value)
        return
    end
    vm.stack[vm.sp] = value % 65536
end

emit = function(vm, text)
    vm.outCount = vm.outCount + 1
    vm.out[vm.outCount] = text
end

toSigned = function(value)
    if value >= 32768 then
        return value - 65536
    end
    return value
end

--=========================================================================
-- Instruction plumbing
--=========================================================================

local function fetchOperand(vm, opType)
    if opType == TYPE_LARGE then
        local value = ZosZMachine.readWord(vm, vm.pc)
        vm.pc = vm.pc + 2
        return value
    end
    if opType == TYPE_SMALL then
        local value = ZosZMachine.readByte(vm, vm.pc)
        vm.pc = vm.pc + 1
        return value
    end
    local number = ZosZMachine.readByte(vm, vm.pc)
    vm.pc = vm.pc + 1
    return readVar(vm, number)
end

fetchStoreVar = function(vm)
    local number = ZosZMachine.readByte(vm, vm.pc)
    vm.pc = vm.pc + 1
    return number
end

returnFromRoutine = function(vm, value)
    if vm.frameCount <= 1 then
        vm.halted = true
        vm.quit = true
        return
    end
    local frame = vm.frames[vm.frameCount]
    vm.frames[vm.frameCount] = nil
    vm.frameCount = vm.frameCount - 1
    vm.sp = frame.stackBase
    vm.pc = frame.retPC
    if frame.storeVar ~= nil then
        writeVar(vm, frame.storeVar, value)
    end
end

callRoutine = function(vm, packedAddr, args, argCount, storeVar)
    if packedAddr == 0 then
        if storeVar ~= nil then
            writeVar(vm, storeVar, 0)
        end
        return
    end

    local addr = packedAddr * 2
    local localCount = ZosZMachine.readByte(vm, addr)
    addr = addr + 1
    if localCount > 15 then
        ZosZMachine.fail(vm, string.format("routine at 0x%X claims %d locals", packedAddr * 2, localCount))
        return
    end

    local locals = {}
    for i = 1, localCount do
        locals[i] = ZosZMachine.readWord(vm, addr)
        addr = addr + 2
    end
    for i = 1, argCount do
        if i <= localCount then
            locals[i] = args[i]
        end
    end

    vm.frameCount = vm.frameCount + 1
    vm.frames[vm.frameCount] = {
        locals = locals,
        retPC = vm.pc,
        storeVar = storeVar,
        stackBase = vm.sp,
    }
    vm.pc = addr
end

-- Branch data is 1 byte when bit 6 is set (offset 0-63), otherwise a 14-bit
-- signed offset across 2 bytes. Offsets 0 and 1 mean "return false/true".
-- Save reads the branch bytes first so the snapshot's PC is already past
-- this instruction; a later restore drops you on the success path.
local function readBranch(vm)
    local first = ZosZMachine.readByte(vm, vm.pc)
    vm.pc = vm.pc + 1
    local spec = { branchOnTrue = first >= 128 }
    if math.floor(first / 64) % 2 == 1 then
        spec.offset = first % 64
    else
        local second = ZosZMachine.readByte(vm, vm.pc)
        vm.pc = vm.pc + 1
        spec.offset = (first % 64) * 256 + second
        if spec.offset >= 8192 then
            spec.offset = spec.offset - 16384
        end
    end
    return spec
end

local function applyBranch(vm, spec, condition)
    if condition ~= spec.branchOnTrue then
        return
    end
    if spec.offset == 0 then
        returnFromRoutine(vm, 0)
    elseif spec.offset == 1 then
        returnFromRoutine(vm, 1)
    else
        vm.pc = vm.pc + spec.offset - 2
    end
end

branch = function(vm, condition)
    applyBranch(vm, readBranch(vm), condition)
end

-- Z-machine division truncates toward zero, unlike Lua's floor division.
local function truncDiv(a, b)
    local quotient = a / b
    if quotient >= 0 then
        return math.floor(quotient)
    end
    return -math.floor(-quotient)
end

--=========================================================================
-- 2OP
--=========================================================================

OP2[1] = function(vm, ops, count) -- je
    local equal = false
    for i = 2, count do
        if ops[i] == ops[1] then
            equal = true
        end
    end
    branch(vm, equal)
end

OP2[2] = function(vm, ops) -- jl
    branch(vm, toSigned(ops[1]) < toSigned(ops[2]))
end

OP2[3] = function(vm, ops) -- jg
    branch(vm, toSigned(ops[1]) > toSigned(ops[2]))
end

OP2[4] = function(vm, ops) -- dec_chk
    local value = toSigned(readVarIndirect(vm, ops[1])) - 1
    writeVarIndirect(vm, ops[1], value % 65536)
    branch(vm, value < toSigned(ops[2]))
end

OP2[5] = function(vm, ops) -- inc_chk
    local value = toSigned(readVarIndirect(vm, ops[1])) + 1
    writeVarIndirect(vm, ops[1], value % 65536)
    branch(vm, value > toSigned(ops[2]))
end

OP2[6] = function(vm, ops) -- jin
    branch(vm, ZosZObject.getParent(vm, ops[1]) == ops[2])
end

OP2[7] = function(vm, ops) -- test
    branch(vm, ZosBit.band(ops[1], ops[2]) == ops[2])
end

OP2[8] = function(vm, ops) -- or
    writeVar(vm, fetchStoreVar(vm), ZosBit.bor(ops[1], ops[2]))
end

OP2[9] = function(vm, ops) -- and
    writeVar(vm, fetchStoreVar(vm), ZosBit.band(ops[1], ops[2]))
end

OP2[10] = function(vm, ops) -- test_attr
    branch(vm, ZosZObject.testAttr(vm, ops[1], ops[2]))
end

OP2[11] = function(vm, ops) -- set_attr
    ZosZObject.setAttr(vm, ops[1], ops[2])
end

OP2[12] = function(vm, ops) -- clear_attr
    ZosZObject.clearAttr(vm, ops[1], ops[2])
end

OP2[13] = function(vm, ops) -- store
    writeVarIndirect(vm, ops[1], ops[2])
end

OP2[14] = function(vm, ops) -- insert_obj
    ZosZObject.insertObj(vm, ops[1], ops[2])
end

OP2[15] = function(vm, ops) -- loadw
    local addr = ops[1] + toSigned(ops[2]) * 2
    writeVar(vm, fetchStoreVar(vm), ZosZMachine.readWord(vm, addr))
end

OP2[16] = function(vm, ops) -- loadb
    local addr = ops[1] + toSigned(ops[2])
    writeVar(vm, fetchStoreVar(vm), ZosZMachine.readByte(vm, addr))
end

OP2[17] = function(vm, ops) -- get_prop
    writeVar(vm, fetchStoreVar(vm), ZosZObject.getProp(vm, ops[1], ops[2]))
end

OP2[18] = function(vm, ops) -- get_prop_addr
    writeVar(vm, fetchStoreVar(vm), ZosZObject.getPropAddr(vm, ops[1], ops[2]))
end

OP2[19] = function(vm, ops) -- get_next_prop
    writeVar(vm, fetchStoreVar(vm), ZosZObject.getNextProp(vm, ops[1], ops[2]))
end

OP2[20] = function(vm, ops) -- add
    writeVar(vm, fetchStoreVar(vm), (toSigned(ops[1]) + toSigned(ops[2])) % 65536)
end

OP2[21] = function(vm, ops) -- sub
    writeVar(vm, fetchStoreVar(vm), (toSigned(ops[1]) - toSigned(ops[2])) % 65536)
end

OP2[22] = function(vm, ops) -- mul
    writeVar(vm, fetchStoreVar(vm), (toSigned(ops[1]) * toSigned(ops[2])) % 65536)
end

OP2[23] = function(vm, ops) -- div
    local divisor = toSigned(ops[2])
    if divisor == 0 then
        ZosZMachine.fail(vm, "division by zero")
        return
    end
    writeVar(vm, fetchStoreVar(vm), truncDiv(toSigned(ops[1]), divisor) % 65536)
end

OP2[24] = function(vm, ops) -- mod
    local divisor = toSigned(ops[2])
    if divisor == 0 then
        ZosZMachine.fail(vm, "division by zero")
        return
    end
    local dividend = toSigned(ops[1])
    writeVar(vm, fetchStoreVar(vm), (dividend - truncDiv(dividend, divisor) * divisor) % 65536)
end

--=========================================================================
-- 1OP
--=========================================================================

OP1[0] = function(vm, a) -- jz
    branch(vm, a == 0)
end

OP1[1] = function(vm, a) -- get_sibling
    local sibling = ZosZObject.getSibling(vm, a)
    writeVar(vm, fetchStoreVar(vm), sibling)
    branch(vm, sibling ~= 0)
end

OP1[2] = function(vm, a) -- get_child
    local child = ZosZObject.getChild(vm, a)
    writeVar(vm, fetchStoreVar(vm), child)
    branch(vm, child ~= 0)
end

OP1[3] = function(vm, a) -- get_parent
    writeVar(vm, fetchStoreVar(vm), ZosZObject.getParent(vm, a))
end

OP1[4] = function(vm, a) -- get_prop_len
    writeVar(vm, fetchStoreVar(vm), ZosZObject.getPropLenAt(vm, a))
end

OP1[5] = function(vm, a) -- inc
    writeVarIndirect(vm, a, (toSigned(readVarIndirect(vm, a)) + 1) % 65536)
end

OP1[6] = function(vm, a) -- dec
    writeVarIndirect(vm, a, (toSigned(readVarIndirect(vm, a)) - 1) % 65536)
end

OP1[7] = function(vm, a) -- print_addr
    emit(vm, ZosZText.decode(vm, a))
end

OP1[9] = function(vm, a) -- remove_obj
    ZosZObject.removeObj(vm, a)
end

OP1[10] = function(vm, a) -- print_obj
    emit(vm, ZosZObject.getName(vm, a))
end

OP1[11] = function(vm, a) -- ret
    returnFromRoutine(vm, a)
end

OP1[12] = function(vm, a) -- jump
    vm.pc = vm.pc + toSigned(a) - 2
end

OP1[13] = function(vm, a) -- print_paddr
    emit(vm, ZosZText.decode(vm, a * 2))
end

OP1[14] = function(vm, a) -- load
    writeVar(vm, fetchStoreVar(vm), readVarIndirect(vm, a))
end

OP1[15] = function(vm, a) -- not
    writeVar(vm, fetchStoreVar(vm), ZosBit.bnot(a))
end

--=========================================================================
-- 0OP
--=========================================================================

OP0[0] = function(vm) -- rtrue
    returnFromRoutine(vm, 1)
end

OP0[1] = function(vm) -- rfalse
    returnFromRoutine(vm, 0)
end

OP0[2] = function(vm) -- print
    local text, nextAddr = ZosZText.decode(vm, vm.pc)
    emit(vm, text)
    vm.pc = nextAddr
end

OP0[3] = function(vm) -- print_ret
    local text, nextAddr = ZosZText.decode(vm, vm.pc)
    emit(vm, text)
    emit(vm, "\n")
    vm.pc = nextAddr
    returnFromRoutine(vm, 1)
end

OP0[4] = function() -- nop
end

OP0[5] = function(vm) -- save
    local spec = readBranch(vm)
    local blob = ZosZSave.encode(vm)
    local ok = blob ~= nil and vm.saveHandler ~= nil and vm.saveHandler(blob)
    applyBranch(vm, spec, ok)
end

OP0[6] = function(vm) -- restore
    local spec = readBranch(vm)
    local blob = vm.restoreHandler and vm.restoreHandler()
    if blob ~= nil and ZosZSave.apply(vm, blob) then
        return
    end
    applyBranch(vm, spec, false)
end

OP0[7] = function(vm) -- restart
    ZosZMachine.reset(vm)
end

OP0[8] = function(vm) -- ret_popped
    returnFromRoutine(vm, popStack(vm))
end

OP0[9] = function(vm) -- pop
    popStack(vm)
end

OP0[10] = function(vm) -- quit
    vm.halted = true
    vm.quit = true
end

OP0[11] = function(vm) -- new_line
    emit(vm, "\n")
end

OP0[12] = function(vm) -- show_status
    vm.statusRequested = true
end

OP0[13] = function(vm) -- verify
    local sum = 0
    for addr = 0x40, vm.fileLength - 1 do
        sum = sum + (readStoryByte(vm, addr) or 0)
    end
    branch(vm, wrap16(sum) == vm.checksum)
end

--=========================================================================
-- VAR
--=========================================================================

OPVAR[0] = function(vm, ops, count) -- call
    local args = {}
    for i = 2, count do
        args[i - 1] = ops[i]
    end
    local storeVar = fetchStoreVar(vm)
    callRoutine(vm, ops[1], args, count - 1, storeVar)
end

OPVAR[1] = function(vm, ops) -- storew
    ZosZMachine.writeWord(vm, ops[1] + toSigned(ops[2]) * 2, ops[3])
end

OPVAR[2] = function(vm, ops) -- storeb
    ZosZMachine.writeByte(vm, ops[1] + toSigned(ops[2]), ops[3])
end

OPVAR[3] = function(vm, ops) -- put_prop
    ZosZObject.putProp(vm, ops[1], ops[2], ops[3])
end

-- sread: hand control back to the caller. The PC already sits past this
-- instruction, so provideInput() then run() picks up where the story left off.
OPVAR[4] = function(vm, ops, count) -- sread
    vm.statusRequested = true
    vm.pendingRead = {
        text = ops[1],
        parse = ops[2] or 0,
    }
end

OPVAR[5] = function(vm, ops) -- print_char
    emit(vm, ZosZText.zsciiToChar(ops[1]))
end

OPVAR[6] = function(vm, ops) -- print_num
    emit(vm, string.format("%d", toSigned(ops[1])))
end

OPVAR[7] = function(vm, ops) -- random
    local storeVar = fetchStoreVar(vm)
    local range = toSigned(ops[1])
    if range > 0 then
        vm.rng = (RNG_MULTIPLIER * vm.rng) % RNG_MODULUS
        local roll = math.floor(vm.rng / RNG_MODULUS * range) + 1
        if roll > range then
            roll = range
        end
        writeVar(vm, storeVar, roll)
    elseif range < 0 then
        vm.rng = normaliseSeed(-range)
        writeVar(vm, storeVar, 0)
    else
        vm.rng = normaliseSeed(vm.rng * 3 + 7)
        writeVar(vm, storeVar, 0)
    end
end

OPVAR[8] = function(vm, ops) -- push
    pushStack(vm, ops[1])
end

OPVAR[9] = function(vm, ops) -- pull
    writeVarIndirect(vm, ops[1], popStack(vm))
end

--=========================================================================
-- Decode and run
--=========================================================================

local function step(vm)
    local opcodeAddr = vm.pc
    local opByte = ZosZMachine.readByte(vm, opcodeAddr)
    vm.pc = opcodeAddr + 1
    vm.instructions = vm.instructions + 1

    if opByte < 0x80 then
        -- Long form: 2OP, bits 6 and 5 pick small constant or variable.
        local firstType = TYPE_SMALL
        if math.floor(opByte / 64) % 2 == 1 then
            firstType = TYPE_VARIABLE
        end
        local secondType = TYPE_SMALL
        if math.floor(opByte / 32) % 2 == 1 then
            secondType = TYPE_VARIABLE
        end
        local first = fetchOperand(vm, firstType)
        local second = fetchOperand(vm, secondType)
        local handler = OP2[opByte % 32]
        if handler == nil then
            ZosZMachine.fail(vm, string.format("unimplemented 2OP opcode 0x%02X at 0x%X", opByte, opcodeAddr))
            return
        end
        handler(vm, { first, second }, 2)
    elseif opByte < 0xB0 then
        -- Short form: 1OP, bits 5-4 give the operand type.
        local operand = fetchOperand(vm, math.floor(opByte / 16) % 4)
        local handler = OP1[opByte % 16]
        if handler == nil then
            ZosZMachine.fail(vm, string.format("unimplemented 1OP opcode 0x%02X at 0x%X", opByte, opcodeAddr))
            return
        end
        handler(vm, operand)
    elseif opByte < 0xC0 then
        -- Short form with the operand omitted: 0OP.
        local handler = OP0[opByte % 16]
        if handler == nil then
            ZosZMachine.fail(vm, string.format("unimplemented 0OP opcode 0x%02X at 0x%X", opByte, opcodeAddr))
            return
        end
        handler(vm)
    else
        -- Variable form: a types byte holds four 2-bit operand types.
        local types = ZosZMachine.readByte(vm, vm.pc)
        vm.pc = vm.pc + 1
        local ops = {}
        local count = 0
        for i = 1, 4 do
            local opType = math.floor(types / TYPE_DIVISORS[i]) % 4
            if opType == TYPE_OMITTED then
                break
            end
            count = count + 1
            ops[count] = fetchOperand(vm, opType)
        end

        local handler
        if opByte < 0xE0 then
            handler = OP2[opByte % 32]
        else
            handler = OPVAR[opByte % 32]
        end
        if handler == nil then
            ZosZMachine.fail(vm, string.format("unimplemented opcode 0x%02X at 0x%X", opByte, opcodeAddr))
            return
        end
        handler(vm, ops, count)
    end
end

ZosZMachine.step = step

-- Runs up to stepBudget instructions. Returns "input" when the story wants a
-- command, "halted" when it has stopped (vm.error says why, if it was a
-- fault), or "yield" when the budget ran out and there is more to do.
function ZosZMachine.run(vm, stepBudget)
    if vm.halted then
        return "halted"
    end
    if vm.pendingRead ~= nil then
        return "input"
    end

    local budget = stepBudget or DEFAULT_STEP_BUDGET
    local executed = 0
    while executed < budget do
        step(vm)
        executed = executed + 1
        if vm.halted then
            return "halted"
        end
        if vm.pendingRead ~= nil then
            return "input"
        end
    end
    return "yield"
end

-- Answers the story's pending sread: lowercases the line into the text
-- buffer and fills the parse buffer from the dictionary.
function ZosZMachine.provideInput(vm, line)
    local pending = vm.pendingRead
    if pending == nil then
        return false
    end
    vm.pendingRead = nil

    local textAddr = pending.text
    local capacity = ZosZMachine.readByte(vm, textAddr) - 1
    local text = string.lower(line or "")
    if #text > capacity then
        text = string.sub(text, 1, capacity)
    end

    for i = 1, #text do
        ZosZMachine.writeByte(vm, textAddr + i, string.byte(text, i))
    end
    ZosZMachine.writeByte(vm, textAddr + #text + 1, 0)

    ZosZDict.tokenize(vm, textAddr, pending.parse)
    return true
end

-- Everything the story has printed since the last drain.
function ZosZMachine.drainText(vm)
    if vm.outCount == 0 then
        return ""
    end
    local text = table.concat(vm.out)
    vm.out = {}
    vm.outCount = 0
    return text
end

-- Drained output split for a line-based screen. Returns the complete lines
-- plus whatever trailing text had no newline yet (the story's own prompt).
function ZosZMachine.drainLines(vm)
    local text = ZosZMachine.drainText(vm)
    local lines = {}
    local count = 0
    local from = 1

    while true do
        local at = string.find(text, "\n", from, true)
        if at == nil then
            break
        end
        count = count + 1
        lines[count] = string.sub(text, from, at - 1)
        from = at + 1
    end

    return lines, string.sub(text, from)
end

-- The v3 status line: the interpreter draws this, so it reads globals 0-2.
function ZosZMachine.statusLine(vm)
    local room = ZosZMachine.readWord(vm, vm.globalsBase)
    return {
        room = ZosZObject.getName(vm, room),
        score = toSigned(ZosZMachine.readWord(vm, vm.globalsBase + 2)),
        moves = ZosZMachine.readWord(vm, vm.globalsBase + 4),
    }
end
