--[[
    ZosDeviceWindow - ValuTech-style collapsable device window for Desktop
    Computers. General / Power / Media (floppy drop). Turn On switches the PC
    on (LED); Play opens the CRT. Turn Off switches off and closes the CRT.
]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISPanel"
require "RadioCom/RadioWindowModules/RWMElement"
require "RadioCom/ISUIRadio/ISLedLight"
require "RadioCom/ISUIRadio/ISItemDropBox"

ZosDeviceWindow = ISCollapsableWindow:derive("ZosDeviceWindow")
ZosDeviceWindow.instances = {}

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10
local CLOSE_DIST = 10
local FLOPPY_TEX = "media/textures/Item_FloppyZork1.png"

local function isPowered(computer)
    if computer == nil or computer.getSquare == nil then
        return false
    end
    local square = computer:getSquare()
    if square == nil then
        return false
    end
    return square:haveElectricity() or (square:hasGridPower() and square:getRoom() ~= nil)
end

local function computerTitle(obj)
    if obj ~= nil and obj.getProperties ~= nil then
        local props = obj:getProperties()
        if props ~= nil and props:has("GroupName") and props:has("CustomName") then
            return tostring(props:get("GroupName")) .. " " .. tostring(props:get("CustomName"))
        end
    end
    return getText("IGUI_Zos_DesktopComputer")
end

-- General -----------------------------------------------------------------

local ZosDeviceGeneral = ISPanel:derive("ZosDeviceGeneral")

function ZosDeviceGeneral:initialise()
    ISPanel.initialise(self)
end

function ZosDeviceGeneral:createChildren()
    self:setHeight(UI_BORDER_SPACING * 2 + BUTTON_HGT)
end

function ZosDeviceGeneral:clear()
    self.player = nil
    self.device = nil
    self.itemTexture = nil
end

function ZosDeviceGeneral:readFromObject(player, device)
    self.player = player
    self.device = device
    self.itemTexture = nil
    if device ~= nil and device.getSprite ~= nil and device:getSprite() ~= nil and device:getSprite():getName() then
        self.itemTexture = getTexture(device:getSprite():getName())
    end
    return true
end

function ZosDeviceGeneral:prerender()
    ISPanel.prerender(self)
end

function ZosDeviceGeneral:render()
    ISPanel.render(self)
    if self.itemTexture then
        self:drawRect(UI_BORDER_SPACING + 1, UI_BORDER_SPACING + 1, BUTTON_HGT, BUTTON_HGT, 1.0, 0.0, 0.0, 0.0)
        self:drawRectBorder(UI_BORDER_SPACING + 1, UI_BORDER_SPACING + 1, BUTTON_HGT, BUTTON_HGT, 1.0, 0.8, 0.8, 0.8)
        self:drawTextureScaledAspect2(self.itemTexture, UI_BORDER_SPACING + 3, UI_BORDER_SPACING + 3, BUTTON_HGT - 4, BUTTON_HGT - 4, 1.0, 1.0, 1.0, 1.0)
    end
    local x = UI_BORDER_SPACING + BUTTON_HGT + UI_BORDER_SPACING + 1
    local y = (self.height - FONT_HGT_SMALL) / 2
    self:drawText(getText("IGUI_Zos_System") .. ":   " .. getText("IGUI_Zos_Version"), x, y, 1, 1, 1, 1, UIFont.Small)
end

function ZosDeviceGeneral:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.0 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return o
end

-- Power -------------------------------------------------------------------

local ZosDevicePower = ISPanel:derive("ZosDevicePower")

function ZosDevicePower:initialise()
    ISPanel.initialise(self)
end

function ZosDevicePower:createChildren()
    self:setHeight(UI_BORDER_SPACING * 2 + BUTTON_HGT + 2)

    self.led = ISLedLight:new(UI_BORDER_SPACING + 1, (self.height - UI_BORDER_SPACING * 2) / 2, UI_BORDER_SPACING * 2, UI_BORDER_SPACING * 2)
    self.led:initialise()
    self.led:setLedColor(1, 0, 1, 0)
    self.led:setLedColorOff(1, 0, 0.3, 0)
    self:addChild(self.led)

    local buttonW = UI_BORDER_SPACING * 2 + math.max(
        getTextManager():MeasureStringX(UIFont.Small, getText("ContextMenu_Turn_Off")),
        getTextManager():MeasureStringX(UIFont.Small, getText("ContextMenu_Turn_On"))
    )
    self.toggleButton = ISButton:new(self.led:getX() + self.led:getWidth() + UI_BORDER_SPACING, UI_BORDER_SPACING + 1, buttonW, BUTTON_HGT, getText("ContextMenu_Turn_On"), self, ZosDevicePower.onToggle)
    self.toggleButton:initialise()
    self.toggleButton.backgroundColor = { r = 0, g = 0, b = 0, a = 0.0 }
    self.toggleButton.backgroundColorMouseOver = { r = 1.0, g = 1.0, b = 1.0, a = 0.1 }
    self.toggleButton.borderColor = { r = 1.0, g = 1.0, b = 1.0, a = 0.3 }
    self.toggleButton:setSound("activate", nil)
    self:addChild(self.toggleButton)
end

function ZosDevicePower:clear()
    self.player = nil
    self.device = nil
end

function ZosDevicePower:readFromObject(player, device)
    self.player = player
    self.device = device
    return true
end

function ZosDevicePower:onToggle()
    if self.player == nil or self.device == nil then
        return
    end
    if ZosContext.isGamePaused() then
        return
    end
    if ZosContext.isDeviceOn(self.device) then
        ZosContext.setDeviceOn(self.device, false)
        ZosTerminal.closeFor(self.device)
        return
    end
    if not isPowered(self.device) then
        return
    end
    ZosContext.setDeviceOn(self.device, true)
end

function ZosDevicePower:update()
    ISPanel.update(self)
    if self.device == nil then
        return
    end
    local on = ZosContext.isDeviceOn(self.device)
    self.led:setLedIsOn(on)
    if on then
        self.toggleButton:setTitle(getText("ContextMenu_Turn_Off"))
        -- Stay visually enabled while paused; onToggle ignores clicks at speed 0.
        self.toggleButton:setEnable(true)
    else
        self.toggleButton:setTitle(getText("ContextMenu_Turn_On"))
        self.toggleButton:setEnable(isPowered(self.device))
    end
end

function ZosDevicePower:prerender()
    ISPanel.prerender(self)
end

function ZosDevicePower:render()
    ISPanel.render(self)
    if self.device == nil then
        return
    end
    local x = self.toggleButton:getX() + self.toggleButton:getWidth() + UI_BORDER_SPACING
    local y = (self.height - FONT_HGT_SMALL) / 2
    if isPowered(self.device) then
        local c = getCore():getGoodHighlitedColor()
        self:drawText(getText("IGUI_RadioPowerNearby"), x, y, c:getR(), c:getG(), c:getB(), 1, UIFont.Small)
    else
        local c = getCore():getBadHighlitedColor()
        self:drawText(getText("IGUI_RadioRequiresPowerNearby"), x, y, c:getR(), c:getG(), c:getB(), 1, UIFont.Small)
    end
end

function ZosDevicePower:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.0 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return o
end

-- Media -------------------------------------------------------------------

local ZosDeviceMedia = ISPanel:derive("ZosDeviceMedia")

function ZosDeviceMedia:initialise()
    ISPanel.initialise(self)
end

function ZosDeviceMedia:createChildren()
    local y = UI_BORDER_SPACING + 1
    self.itemDropBox = ISItemDropBox:new(UI_BORDER_SPACING + 1, y, BUTTON_HGT, BUTTON_HGT, false, self, ZosDeviceMedia.addFloppy, ZosDeviceMedia.removeFloppy, ZosDeviceMedia.verifyItem, nil)
    self.itemDropBox:initialise()
    self.itemDropBox:setBackDropTex(getTexture(FLOPPY_TEX), 0.4, 1, 1, 1)
    self.itemDropBox:setDoBackDropTex(true)
    self.itemDropBox:setToolTip(true, getText("IGUI_Zos_DragFloppy"))
    self.itemDropBox.toolTipTextItem = getText("IGUI_Zos_EjectHint")
    self.itemDropBox.toolTipTextLocked = getText("IGUI_RadioRequiresPowerNearby")
    self:addChild(self.itemDropBox)

    self.playButton = ISButton:new(self.itemDropBox:getRight() + UI_BORDER_SPACING, y, self.width - self.itemDropBox:getRight() - UI_BORDER_SPACING * 2 - 1, BUTTON_HGT, getText("IGUI_media_play"), self, ZosDeviceMedia.onPlay)
    self.playButton:initialise()
    self.playButton.backgroundColor = { r = 0, g = 0, b = 0, a = 0.0 }
    self.playButton.backgroundColorMouseOver = { r = 1.0, g = 1.0, b = 1.0, a = 0.1 }
    self.playButton.borderColor = { r = 1.0, g = 1.0, b = 1.0, a = 0.3 }
    self.playButton:setSound("activate", nil)
    self:addChild(self.playButton)

    self:setHeight(self.playButton:getY() + self.playButton:getHeight() + UI_BORDER_SPACING + 1)
end

function ZosDeviceMedia:clear()
    self.player = nil
    self.device = nil
end

function ZosDeviceMedia:readFromObject(player, device)
    self.player = player
    self.device = device
    if self.itemDropBox ~= nil then
        self.itemDropBox.mouseEnabled = true
    end
    return true
end

function ZosDeviceMedia:verifyItem(item)
    if item == nil or item.getFullType == nil then
        return false
    end
    return ZosFloppies.byItem(item:getFullType()) ~= nil
end

function ZosDeviceMedia:addFloppy(items)
    if self.player == nil or self.device == nil or items == nil or items[1] == nil then
        return
    end
    if not isPowered(self.device) then
        return
    end
    local item = items[1]
    if not self:verifyItem(item) then
        return
    end
    ZosContext.insertFloppy(self.player, self.device, item)
end

function ZosDeviceMedia:removeFloppy()
    self:onEject()
end

function ZosDeviceMedia:onEject()
    if self.player == nil or self.device == nil then
        return
    end
    if ZosFloppies.insertedType(self.device) == nil then
        return
    end
    ZosContext.ejectFloppy(self.player, self.device)
end

function ZosDeviceMedia:onPlay()
    if self.player == nil or self.device == nil then
        return
    end
    if ZosContext.isGamePaused() then
        return
    end
    if not isPowered(self.device) then
        return
    end
    if not ZosContext.isDeviceOn(self.device) then
        return
    end
    if ZosFloppies.insertedType(self.device) == nil then
        return
    end
    ZosContext.openOrFocusTerminal(self.player, self.device, true)
end

function ZosDeviceMedia:update()
    ISPanel.update(self)
    if self.device == nil then
        return
    end
    local powered = isPowered(self.device)
    local deviceOn = ZosContext.isDeviceOn(self.device)
    local inserted = ZosFloppies.insertedType(self.device)
    self.itemDropBox.isLocked = not powered and inserted == nil
    if inserted ~= nil then
        self.itemDropBox:setStoredItemFake(getTexture(FLOPPY_TEX))
    else
        self.itemDropBox:setStoredItemFake(nil)
    end
    local termOpen = ZosTerminal.isOpenFor(self.device)
    local inZork = termOpen and ZosTerminal.instance.shell ~= nil and ZosTerminal.instance.shell.inZork
    local typing = termOpen and ZosTerminal.instance.typeScript ~= nil
    -- Pause is handled in onPlay (no red disabled border); setEnable is for real gates only.
    self.playButton:setEnable(powered and deviceOn and inserted ~= nil and not inZork and not typing)
end

function ZosDeviceMedia:prerender()
    ISPanel.prerender(self)
end

function ZosDeviceMedia:render()
    ISPanel.render(self)
end

function ZosDeviceMedia:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.0 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return o
end

-- Window ------------------------------------------------------------------

function ZosDeviceWindow.activate(player, computer)
    if ZosContext.isGamePaused() then
        return nil
    end
    local playerNum = player:getPlayerNum()
    local window = ZosDeviceWindow.instances[playerNum]
    if window == nil then
        window = ZosDeviceWindow:new(100, 100, 250 + (getCore():getOptionFontSizeReal() * 50), 500, player)
        window:initialise()
        window:instantiate()
        if playerNum == 0 then
            ISLayoutManager.RegisterWindow("zoscomputer", ISCollapsableWindow, window)
        end
        ZosDeviceWindow.instances[playerNum] = window
    end
    window:readFromObject(player, computer)
    window:addToUIManager()
    window:setVisible(true)
    return window
end

function ZosDeviceWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

function ZosDeviceWindow:addModule(modulePanel, moduleName)
    local module = {}
    module.enabled = true
    module.element = RWMElement:new(0, 0, self.width, 0, modulePanel, moduleName, self)
    table.insert(self.modules, module)
    self:addChild(module.element)
end

function ZosDeviceWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:addModule(ZosDeviceGeneral:new(0, 0, self.width, 0), getText("IGUI_RadioGeneral"))
    self:addModule(ZosDevicePower:new(0, 0, self.width, 0), getText("IGUI_RadioPower"))
    self:addModule(ZosDeviceMedia:new(0, 0, self.width, 0), getText("IGUI_RadioMedia"))
end

function ZosDeviceWindow:readFromObject(player, computer)
    self:clear()
    self.player = player
    self.device = computer
    self.title = computerTitle(computer)
    for i = 1, #self.modules do
        self.modules[i].enabled = self.modules[i].element:readFromObject(self.player, self.device, nil, "IsoObject")
        self.modules[i].element:setVisible(self.modules[i].enabled)
    end
end

function ZosDeviceWindow:clear()
    self.player = nil
    self.device = nil
    for i = 1, #self.modules do
        self.modules[i].enabled = false
        self.modules[i].element:clear()
    end
end

function ZosDeviceWindow.closeFor(computer)
    for _, window in pairs(ZosDeviceWindow.instances) do
        if window ~= nil and window.device == computer then
            window:close()
        end
    end
end

function ZosDeviceWindow:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    self:clear()
end

function ZosDeviceWindow:update()
    ISCollapsableWindow.update(self)
    if not self:getIsVisible() then
        return
    end
    if self.player == nil or self.device == nil or self.player:isDead() then
        self:close()
        return
    end
    local square = self.device:getSquare()
    if square == nil then
        self:close()
        return
    end
    local dx = math.abs(square:getX() + 0.5 - self.player:getX())
    local dy = math.abs(square:getY() + 0.5 - self.player:getY())
    if dx > CLOSE_DIST or dy > CLOSE_DIST then
        self:close()
    end
end

function ZosDeviceWindow:prerender()
    ISUIElement.stayOnSplitScreen(self, self.playerNum)
    ISCollapsableWindow.prerender(self)
    local y = self:titleBarHeight() + 1
    for i = 1, #self.modules do
        if self.modules[i].enabled then
            self.modules[i].element:setY(y)
            y = y + self.modules[i].element:getHeight() + 1
        else
            self.modules[i].element:setVisible(false)
        end
    end
    self:setHeight(y)
end

function ZosDeviceWindow:render()
    ISCollapsableWindow.render(self)
end

function ZosDeviceWindow:new(x, y, width, height, player)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.playerNum = player:getPlayerNum()
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
    o.anchorLeft = true
    o.anchorRight = false
    o.anchorTop = true
    o.anchorBottom = false
    o.pin = true
    o.isCollapsed = false
    o.collapseCounter = 0
    o.title = getText("IGUI_Zos_DesktopComputer")
    o.resizable = false
    o.drawFrame = true
    o.device = nil
    o.modules = {}
    return o
end
