require 'OptionScreens/SandboxOptions'
require 'OptionScreens/ServerSettingsScreen'
require 'ISUI/AdminPanel/ISServerSandboxOptionsUI'

local function hideCheckboxes(panel)
    for k, v in pairs(panel.controls) do
        if string.find(k, "WZS") then
            v:setVisible(false)
        end
    end

    local children = panel:getChildren()
    for k, v in pairs(children) do
        if v.name == "" and v.Type == "ISLabel" then
            v:setVisible(false)
        end
    end
end

local function sharedCreatePanel(self, page, fn)
    local panel = fn(self, page)
    if string.find(page.name, "Wandering Zombies") == nil then return panel end

    hideCheckboxes(panel)
    return panel
end

-- solo hook
local old_soloCreatePanel = SandboxOptionsScreen.createPanel
local function soloCreatePanel(self, page)
    return sharedCreatePanel(self, page, old_soloCreatePanel)
end

SandboxOptionsScreen.createPanel = soloCreatePanel

-- admin panel hook
local old_adminCreatePanel = ISServerSandboxOptionsUI.createPanel
local function adminCreatePanel(self, page)
    return sharedCreatePanel(self, page, old_adminCreatePanel)
end

ISServerSandboxOptionsUI.createPanel = adminCreatePanel

-- host hook
local old_aboutToShow = ServerSettingsScreen.aboutToShow
local function aboutToShow(self)
    old_aboutToShow(self)

    for k, v in pairs(self.pageEdit.listbox.items) do
        if string.find(v.text, "Wandering Zombies") then
            hideCheckboxes(v.item.panel)
        end
    end
end

ServerSettingsScreen.aboutToShow = aboutToShow
