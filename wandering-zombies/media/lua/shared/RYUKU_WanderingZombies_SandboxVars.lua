require "RYUKU_WanderingZombies_Utility"

WZSandboxVars = {}

-- tick tracking for a timer --

WZCurrentTick = 0
local function EveryTick()
    WZCurrentTick = WZCurrentTick + 1
end

WZHordeCurrentTick = 0
local function HordeEveryTick()
    WZHordeCurrentTick = WZHordeCurrentTick + 1
end

-- time stamps --

function wzIsTimeElapsed(tk)
    if WZSandboxVars[tk .. "StampEnd"] == nil then return true end
    return getGameTime():getCalender():getTimeInMillis() >= WZSandboxVars[tk .. "StampEnd"]
end

function wzIsTimeNow(key, horde)
    if horde then key = "Horde" .. key end
    if WZSandboxVars[key .. "StampStart"] == nil then return false end

    local time = getGameTime():getCalender():getTimeInMillis()
    return time >= WZSandboxVars[key .. "StampStart"] and time < WZSandboxVars[key .. "StampEnd"]
end

-- random sandbox vars --

local function getRandomSandboxVar(key, newDay, current, minMax)
    -- dropdowns that control whether values are static or randomised are prefixed with 'Dropdown'
    if SandboxVars.WanderingZombies["Dropdown" .. key] == 2 then
        if newDay then
            local result = ZombRand(minMax.min, minMax.max + 1)

            -- support for ranges that span midnight
            if minMax.order and result > 23 then result = result - 24 end
            return result
        end

        return current
    else
        local val = SandboxVars.WanderingZombies[key]
        if val ~= nil then return val end

        return SandboxVars.WanderingZombies["Max" .. key]
    end
end

local function getRandomMinMaxSandboxVar(key, min, max, order)
    -- min/max share the same name as the option they're related to, only prefixed with 'Min' and 'Max'
    local minMax = {
        min = math.max(min, SandboxVars.WanderingZombies["Min" .. key]),
        max = math.min(max, SandboxVars.WanderingZombies["Max" .. key])
    }

    -- support for ranges that span midnight
    if order then
        if minMax.min > minMax.max then
            minMax.max = minMax.max + 24
            minMax.order = true
        end
    elseif minMax.min > minMax.max then
        local t = minMax.min
        minMax.min = minMax.max
        minMax.max = t
    end

    return minMax
end

-- counter / destructive update --

local lastCounters = {}
local function update()
    for k, v in pairs({ Counter = EveryTick, HordeCounter = HordeEveryTick }) do
        if WZSandboxVars[k] ~= lastCounters[k] then
            if lastCounters[k] ~= nil then
                if lastCounters[k] == 2 then Events.OnTick.Remove(v) end
                if lastCounters[k] == 3 then Events.EveryOneMinute.Remove(v) end
                if lastCounters[k] == 4 then Events.EveryTenMinutes.Remove(v) end
                if lastCounters[k] == 5 then Events.EveryHours.Remove(v) end
            end

            if WZSandboxVars[k] == 2 then Events.OnTick.Add(v) end
            if WZSandboxVars[k] == 3 then Events.EveryOneMinute.Add(v) end
            if WZSandboxVars[k] == 4 then Events.EveryTenMinutes.Add(v) end
            if WZSandboxVars[k] == 5 then Events.EveryHours.Add(v) end
        end

        lastCounters[k] = WZSandboxVars[k]
    end

    wzSetDestructive(WZSandboxVars.Destructive, WZSandboxVars.IndoorDestruction)
    wzSetHordeDestructive(WZSandboxVars.HordeDestructive, WZSandboxVars.HordeIndoorDestruction)
end

-- client update --

local function OnServerCommand(module, command, args)
    if module ~= "WanderingZombies" then return end
    if command ~= "WZSandboxVarsUpdate" then return end

    WZSandboxVars = args
    update()
end

if isClient() and not isCoopHost() then Events.OnServerCommand.Add(OnServerCommand) end

-- host / server / singleplayer update --

local lastDay
local sharedVars = {
    Destructive = {
        fn = function(lvar, hvar, newDay)
            if lvar == 3 then
                if newDay then
                    WZSandboxVars.Destructive = ZombRand(2) == 0
                    WZSandboxVars.IndoorDestruction = ZombRand(2) == 0
                end
            else
                WZSandboxVars.Destructive = lvar < 3
                WZSandboxVars.IndoorDestruction = lvar == 2
            end

            if hvar == 3 then
                if newDay then
                    WZSandboxVars.HordeDestructive = ZombRand(2) == 0
                    WZSandboxVars.HordeIndoorDestruction = ZombRand(2) == 0
                end
            else
                WZSandboxVars.HordeDestructive = hvar < 3
                WZSandboxVars.HordeIndoorDestruction = hvar == 2
            end
        end
    },
    MaxTravel = { minMax = { min = 10, max = 100 }},
    Counter = { minMax = { min = 1, max = 5 }},
    NumTicks = { minMax = { min = 1, max = 9999999 }},
    RandTicks = { minMax = { min = 0, max = 9999999 }},
    StartHour = "",
    WanderChance = { rand = true, min = 0, max = 100 },
    HomingStartHour = "",
    ToPlayers = { rand = true, min = 0, max = 100 },
    Radius = { rand = true, min = 0, max = 90 },
    RadiusInterrupt = {
        fn = function(lvar, hvar, newDay)
            if lvar == 3 then
                if newDay then WZSandboxVars.RadiusInterrupt = ZombRand(2) == 0 end
            else
                WZSandboxVars.RadiusInterrupt = lvar == 1
            end

            if hvar == 3 then
                if newDay then WZSandboxVars.HordeRadiusInterrupt = ZombRand(2) == 0 end
            else
                WZSandboxVars.HordeRadiusInterrupt = hvar == 1
            end
        end
    },
    FleeStartHour = "",
    FleePlayers = { rand = true, min = 0, max = 100 },
    FleeRadius = { rand = true, min = 0, max = 90 }
}

local function WZSandboxVarsUpdate()
    local currentDay = getGameTime():getDay()
    local newDay = currentDay ~= lastDay

    -- settings that are configurable separately for loners and hordes
    local hKey
    for k, v in pairs(sharedVars) do
        hKey = "Horde" .. k

        if v.fn ~= nil then
            v.fn(SandboxVars.WanderingZombies[k], SandboxVars.WanderingZombies[hKey], newDay)
        elseif string.find(k, "StartHour") ~= nil then
            -- time values should only be randomised if they have elapsed
            -- creates timestamps using PZCalender
            -- whenever the difference between the current time and expected time is zero, it takes effect immediately
            -- when starting/loading a game, it takes effect immediately -- todo? save/load the values
            -- multiple periods of activity in a single day is possible
            -- multiple periods of activity can chain together to form a "single" longer period of activity, for example:
            -- Start Hour Min 18, Max 6, Total Hours 12 can result in a 24 hour period of activity

            local thKey, timeToHour
            local timeMs = getGameTime():getCalender():getTimeInMillis()
            local currentTime = math.floor(getGameTime():getTimeOfDay())
            for tk, _ in pairs({ [k] = false, [hKey] = true }) do
                if wzIsTimeElapsed(tk) then
                    thKey = tk:gsub("StartHour", "TotalHours")
                    WZSandboxVars[tk] = getRandomSandboxVar(tk, true, WZSandboxVars[tk], getRandomMinMaxSandboxVar(tk, 0, 23, true))
                    WZSandboxVars[thKey] = getRandomSandboxVar(thKey, true, WZSandboxVars[thKey], getRandomMinMaxSandboxVar(thKey, 0, 24))

                    timeToHour = WZSandboxVars[tk] - currentTime
                    if timeToHour ~= 0 then
                        if lastDay == nil then timeToHour = 24 - timeToHour
                        else timeToHour = 24 + timeToHour end

                        if timeToHour > 24 then timeToHour = timeToHour - 24 end
                        if lastDay == nil then timeToHour = -timeToHour end
                    end

                    WZSandboxVars[tk .. "StampStart"] = timeMs + timeToHour * 3600000
                    WZSandboxVars[tk .. "StampEnd"] = WZSandboxVars[tk .. "StampStart"] + WZSandboxVars[thKey] * 3600000
                end
            end
        else
            WZSandboxVars[k] = getRandomSandboxVar(k, newDay, WZSandboxVars[k], (v.rand and getRandomMinMaxSandboxVar(k, v.min, v.max)) or v.minMax)
            WZSandboxVars[hKey] = getRandomSandboxVar(hKey, newDay, WZSandboxVars[hKey],
                (v.rand and getRandomMinMaxSandboxVar(hKey, v.min, v.max)) or v.minMax
            )
        end
    end

    update()

    WZSandboxVars.HordesEnabled = SandboxVars.WanderingZombies.Hordes
    WZSandboxVars.UpdateZedLimit = SandboxVars.WanderingZombies.UpdateZedLimit
    WZSandboxVars.UpdateMsLimit = SandboxVars.WanderingZombies.UpdateMsLimit

    lastDay = currentDay

    if isServer() or isCoopHost() then sendServerCommand("WanderingZombies", "WZSandboxVarsUpdate", WZSandboxVars) end
end

if isServer() or isCoopHost() or not isClient() then Events.EveryOneMinute.Add(WZSandboxVarsUpdate) end

-- retrieve the appropriate variable based on whether zombie is a leader or not
function wzGetSandboxVar(key, horde)
    if horde then return WZSandboxVars["Horde" .. key] end
    return WZSandboxVars[key]
end

-- update ticks
function wzUpdateTicks(zData)
    if zData.isLeader then
        zData.ticks = WZHordeCurrentTick + WZSandboxVars.HordeNumTicks + ZombRand(0, WZSandboxVars.HordeRandTicks + 1) +
            math.floor(zData.followers:size() * SandboxVars.WanderingZombies.FollowerTicks)
    else
        zData.ticks = WZCurrentTick + WZSandboxVars.NumTicks + ZombRand(0, WZSandboxVars.RandTicks + 1)
    end
end

-- determine if zed is ready to move
function wzIsReadyMove(zData)
    local ticks = WZCurrentTick
    if zData.isLeader then ticks = WZHordeCurrentTick end

    return wzGetSandboxVar("Counter", zData.isLeader) == 1 or ticks - zData.ticks >= 0
end
