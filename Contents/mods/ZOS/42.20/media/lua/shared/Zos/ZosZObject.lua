--[[
    ZosZObject - the v3 object tree.

    Layout: the object table opens with 31 property-default words, then one
    9-byte entry per object -- 4 attribute bytes (attribute 0 is the most
    significant bit of the first), then parent/sibling/child as single bytes,
    then the address of the property table.

    A property table is a length byte (short name, in words), the name's
    Z-string, then properties in descending number order. Each property is a
    size byte -- 32 * (length - 1) + number -- followed by its data, and a
    size byte of 0 ends the table.

    See the Z-Machine Standard, section 12.
]]

ZosZObject = {}

local ENTRY_SIZE = 9
local DEFAULTS_WORDS = 31
local PARENT_OFFSET = 4
local SIBLING_OFFSET = 5
local CHILD_OFFSET = 6
local PROPS_OFFSET = 7

local function entryAddr(vm, obj)
    return vm.objBase + DEFAULTS_WORDS * 2 + (obj - 1) * ENTRY_SIZE
end

ZosZObject.entryAddr = entryAddr

function ZosZObject.getParent(vm, obj)
    if obj == 0 then return 0 end
    return ZosZMachine.readByte(vm, entryAddr(vm, obj) + PARENT_OFFSET)
end

function ZosZObject.getSibling(vm, obj)
    if obj == 0 then return 0 end
    return ZosZMachine.readByte(vm, entryAddr(vm, obj) + SIBLING_OFFSET)
end

function ZosZObject.getChild(vm, obj)
    if obj == 0 then return 0 end
    return ZosZMachine.readByte(vm, entryAddr(vm, obj) + CHILD_OFFSET)
end

function ZosZObject.setParent(vm, obj, value)
    ZosZMachine.writeByte(vm, entryAddr(vm, obj) + PARENT_OFFSET, value)
end

function ZosZObject.setSibling(vm, obj, value)
    ZosZMachine.writeByte(vm, entryAddr(vm, obj) + SIBLING_OFFSET, value)
end

function ZosZObject.setChild(vm, obj, value)
    ZosZMachine.writeByte(vm, entryAddr(vm, obj) + CHILD_OFFSET, value)
end

local function attrLocation(vm, obj, attr)
    local byteAddr = entryAddr(vm, obj) + math.floor(attr / 8)
    local bit = 7 - attr % 8
    return byteAddr, bit
end

function ZosZObject.testAttr(vm, obj, attr)
    if obj == 0 then return false end
    local byteAddr, bit = attrLocation(vm, obj, attr)
    return ZosBit.getBit(ZosZMachine.readByte(vm, byteAddr), bit) == 1
end

function ZosZObject.setAttr(vm, obj, attr)
    if obj == 0 then return end
    local byteAddr, bit = attrLocation(vm, obj, attr)
    local value = ZosZMachine.readByte(vm, byteAddr)
    ZosZMachine.writeByte(vm, byteAddr, ZosBit.setBit(value, bit))
end

function ZosZObject.clearAttr(vm, obj, attr)
    if obj == 0 then return end
    local byteAddr, bit = attrLocation(vm, obj, attr)
    local value = ZosZMachine.readByte(vm, byteAddr)
    ZosZMachine.writeByte(vm, byteAddr, ZosBit.clearBit(value, bit))
end

local function propTableAddr(vm, obj)
    return ZosZMachine.readWord(vm, entryAddr(vm, obj) + PROPS_OFFSET)
end

function ZosZObject.getName(vm, obj)
    if obj == 0 then return "" end
    local addr = propTableAddr(vm, obj)
    local nameWords = ZosZMachine.readByte(vm, addr)
    if nameWords == 0 then return "" end
    local name = ZosZText.decode(vm, addr + 1)
    return name
end

-- Address of the first property's size byte.
local function firstPropAddr(vm, obj)
    local addr = propTableAddr(vm, obj)
    return addr + 1 + ZosZMachine.readByte(vm, addr) * 2
end

local function propNumber(sizeByte)
    return sizeByte % 32
end

local function propLength(sizeByte)
    return math.floor(sizeByte / 32) + 1
end

-- Address of a property's data, or 0 when the object lacks that property.
function ZosZObject.getPropAddr(vm, obj, prop)
    if obj == 0 then return 0 end
    local at = firstPropAddr(vm, obj)
    while true do
        local size = ZosZMachine.readByte(vm, at)
        if size == 0 then return 0 end
        local num = propNumber(size)
        local len = propLength(size)
        if num == prop then
            return at + 1
        end
        if num < prop then
            return 0
        end
        at = at + 1 + len
    end
end

-- Length of the property whose data starts at dataAddr.
function ZosZObject.getPropLenAt(vm, dataAddr)
    if dataAddr == 0 then return 0 end
    return propLength(ZosZMachine.readByte(vm, dataAddr - 1))
end

function ZosZObject.getProp(vm, obj, prop)
    local dataAddr = ZosZObject.getPropAddr(vm, obj, prop)
    if dataAddr == 0 then
        return ZosZMachine.readWord(vm, vm.objBase + (prop - 1) * 2)
    end
    if ZosZObject.getPropLenAt(vm, dataAddr) == 1 then
        return ZosZMachine.readByte(vm, dataAddr)
    end
    return ZosZMachine.readWord(vm, dataAddr)
end

function ZosZObject.putProp(vm, obj, prop, value)
    local dataAddr = ZosZObject.getPropAddr(vm, obj, prop)
    if dataAddr == 0 then
        ZosZMachine.fail(vm, string.format("put_prop: object %d has no property %d", obj, prop))
        return
    end
    if ZosZObject.getPropLenAt(vm, dataAddr) == 1 then
        ZosZMachine.writeByte(vm, dataAddr, value % 256)
    else
        ZosZMachine.writeWord(vm, dataAddr, value % 65536)
    end
end

-- Property number after prop, or the first property when prop is 0.
function ZosZObject.getNextProp(vm, obj, prop)
    if obj == 0 then return 0 end
    local at = firstPropAddr(vm, obj)
    if prop == 0 then
        return propNumber(ZosZMachine.readByte(vm, at))
    end
    while true do
        local size = ZosZMachine.readByte(vm, at)
        if size == 0 then return 0 end
        local num = propNumber(size)
        at = at + 1 + propLength(size)
        if num == prop then
            return propNumber(ZosZMachine.readByte(vm, at))
        end
        if num < prop then
            return 0
        end
    end
end

function ZosZObject.removeObj(vm, obj)
    if obj == 0 then return end
    local parent = ZosZObject.getParent(vm, obj)
    if parent == 0 then return end

    local sibling = ZosZObject.getSibling(vm, obj)
    local first = ZosZObject.getChild(vm, parent)
    if first == obj then
        ZosZObject.setChild(vm, parent, sibling)
    else
        local prev = first
        while prev ~= 0 and ZosZObject.getSibling(vm, prev) ~= obj do
            prev = ZosZObject.getSibling(vm, prev)
        end
        if prev ~= 0 then
            ZosZObject.setSibling(vm, prev, sibling)
        end
    end

    ZosZObject.setParent(vm, obj, 0)
    ZosZObject.setSibling(vm, obj, 0)
end

function ZosZObject.insertObj(vm, obj, dest)
    if obj == 0 or dest == 0 then return end
    ZosZObject.removeObj(vm, obj)
    ZosZObject.setSibling(vm, obj, ZosZObject.getChild(vm, dest))
    ZosZObject.setChild(vm, dest, obj)
    ZosZObject.setParent(vm, obj, dest)
end
