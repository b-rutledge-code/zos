--[[
    Release-facing debug toggle. Keep false for Workshop.
]]

Zos = Zos or {}
Zos.debugMode = false

function Zos.debug(fmt, ...)
    if not Zos.debugMode then
        return
    end
    if fmt == nil then
        return
    end
    if select("#", ...) > 0 then
        print(string.format(fmt, ...))
    else
        print(tostring(fmt))
    end
end
