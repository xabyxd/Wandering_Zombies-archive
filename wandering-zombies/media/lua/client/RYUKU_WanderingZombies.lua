if isServer() then return end

require "RYUKU_WanderingZombies_Vector"
require "RYUKU_WanderingZombies_SandboxVars"
require "RYUKU_WanderingZombies_Hordes"

-- Calm Before The Storm --
-- this will need to be adjusted when the data is synced between all clients

local cbtsData, phaseTime
local function getInCooldownPhase()
   if cbtsData == nil then
        cbtsData = (ModData.exists("CBTS_Data") and ModData.get("CBTS_Data")) or nil

        -- global mod data persisting after removal of mod.. messy
        -- mods should just be assigned a table based on their id, and the table should be nuked when the mod is removed..
        -- or CBTS needs an 'uninstall' function
        if cbtsData ~= nil and (SandboxVars.CBTS == nil or not getActivatedMods():contains("CBTS")) then
            cbtsData = false
        end
    end

    if cbtsData ~= nil and cbtsData ~= false then
        phaseTime = (SandboxVars.CBTS.RandomDurationFlag and cbtsData.RandomCooldownPhaseDuration) or
            (SandboxVars.CBTS.CooldownPhaseDuration * 60)
        
        return cbtsData.Counter < phaseTime
    end

    return true
end

-- pathing --

local function getStateIsMoving(zombie)
    return zombie:getCurrentStateName() == "PathFindState2" or
        zombie:getCurrentStateName() == "ClimbOverFenceState" or
        zombie:getCurrentStateName() == "ClimbThroughWindowState"
end

-- closest players --

local allPlayers, closestPlayers, player, playerPos, cpDiff, cpDist, newPlayer, didInsert
local function getClosestPlayers(zombiePos)
    allPlayers = IsoPlayer:getPlayers()
    if allPlayers == nil or allPlayers:size() < 1 then return nil end

    closestPlayers = {}
    for i = 0, allPlayers:size() - 1 do
        player = allPlayers:get(i)

        if player ~= nil then
            playerPos = WZVector:new(player)
            cpDiff = playerPos:sub(zombiePos)
            cpDist = cpDiff:mag()
            
            -- dist is capped to stop zeds too far away pathing to players they shouldn't
            if cpDist <= 150 then
                newPlayer = {
                    pos = playerPos,
                    zpos = player:getZ(),
                    age = player:getHoursSurvived(),
                    dist = cpDist,
                    diff = cpDiff
                }

                -- sort by lowest distance
                didInsert = false
                for k, v in ipairs(closestPlayers) do
                    if v.dist > cpDist then
                        table.insert(closestPlayers, k, newPlayer)
                        didInsert = true
                        break
                    end
                end

                if not didInsert then table.insert(closestPlayers, newPlayer) end
            end
        end
    end

    return closestPlayers
end

local function getClosestAgedPlayer()
    for _, v in ipairs(closestPlayers) do
        if v.age >= SandboxVars.WanderingZombies.HoursSurvived then
            return v
        end
    end

    return nil
end

-- grab zombies --

local zedIdCount = 0
local zombies, zData, vehicle
local function OnZombieUpdate(zombie)
    if zombies == nil then zombies = WZLinkedList:new("zombies") end

    -- only care about zeds we control
    if isClient() and zombie:isRemoteZombie() then return end

    -- ignore zeds while in a moving vehicle
    vehicle = getPlayer():getVehicle()
    if vehicle ~= nil and not vehicle:isAtRest() then return end

    -- due to OnZombieDead, OnHitZombie, etc being called after the construction of a IsoDeadBody
    -- getModData() can not be used to store "complex" data structures without causing a stack overflow (LuaManager:copyTable)
    -- so, we need to store the data used by Wandering Zombies in a different manner

    -- isExistInTheWorld is throwing errors?
    -- so delaying once..
    local modData = zombie:getModData()
    if modData.rwzDelay == nil then
        modData.rwzDelay = true
    elseif modData.rwzDelay == true then
        -- add new zombies to the list
        zombies:push({
            zed = zombie,
            data = {
                ticks = 0,
                homing = false,
                isLeader = false,
                id = zedIdCount,
            }
        })

        zedIdCount = zedIdCount + 1
        modData.rwzDelay = false
    end
end

Events.OnZombieUpdate.Add(OnZombieUpdate)

-- update logic --

local startMs, zCount, nextLink, zombie, zombiePos
local closestAgedPlayer, targetPos, zPos, maxTravel, tsvDiff, tsvDist
local gridSquare

local msgTimer
local function WZUpdate(ticks)
    if zombies == nil or WZSandboxVars.Counter == nil then return end

    -- zed processing
    startMs = getTimeInMillis()
    zCount = 0
    while zCount < zombies:size() and zCount < WZSandboxVars.UpdateZedLimit and getTimeInMillis() - startMs <= WZSandboxVars.UpdateMsLimit do
        -- keep pulling zombies until we get one that is valid
        nextLink = zombies:next()
        zombie = nextLink.ref.zed
        zData = nextLink.ref.data

        while not wzIsValidZombie(zombie) do
            zombies:remove(nextLink)
            if WZSandboxVars.HordesEnabled then wzResetHorde(zData) end

            nextLink.ref = nil
            zombie:getModData().rwzDelay = nil

            if zombies:size() == 0 or getTimeInMillis() - startMs > WZSandboxVars.UpdateMsLimit then
                zCount = zombies:size()
                break
            end

            nextLink = zombies:next()
            zombie = nextLink.ref.zed
            zData = nextLink.ref.data
        end

        if zCount == zombies:size() then break end

        zombiePos = WZVector:new(zombie)
        zCount = zCount + 1

        -- dirty trick to use 'break' as 'continue'
        while true do
            -- if not within user configured hours or not in cooldown phase, do nothing
            if not getInCooldownPhase() or
                (not wzIsTimeNow("StartHour", zData.isLeader) and
                not wzIsTimeNow("HomingStartHour", zData.isLeader) and
                not wzIsTimeNow("FleeStartHour", zData.isLeader))
            then
                wzUpdateTicks(zData)
                break
            end

            -- if zombie has any target, skip it
            if zombie:getTarget() or zombie:getThumpTarget() or zombie:getEatBodyTarget() then
                -- remove zombies that have any target from hordes
                if WZSandboxVars.HordesEnabled then wzResetHorde(zData) end

                wzUpdateTicks(zData)
                break
            end

            -- if zombie is alerted, or recently alerted, skip it
            if zombie:getCurrentStateName() == "ZombieTurnAlerted" or (zData.soundTime ~= nil and getTimeInMillis() - zData.soundTime < 0) then
                -- remove zombies that are alerted from hordes to prevent horde pathing from interrupting
                if WZSandboxVars.HordesEnabled then wzResetHorde(zData) end

                -- ignore alerted zombies for a minute
                if zData.soundTime == nil then zData.soundTime = getTimeInMillis() + 60000 end

                wzUpdateTicks(zData)
                break
            else
                zData.soundTime = nil
            end

            -- if hordes are enabled, execute the horde logic
            -- otherwise if zombie has any horde data, reset it
            if WZSandboxVars.HordesEnabled then
                if zData.leader ~= nil then
                    -- if zombie has a leader, if they're no longer close enough, don't share the same speed or have changed
                    -- to a speed that is not allowed in hordes, reset them
                    if zombiePos:distanceTo(zData.leader) > SandboxVars.ZombieConfig.RallyTravelDistance or
                        not wzIsMatchingSpeed(zombie, zData.leader) or not wzIsSpeedAllowed(zombie)
                    then
                        wzResetHorde(zData)
                    end

                    wzUpdateTicks(zData)
                    break
                elseif zData.isLeader then
                    -- reset the leader if their speed is not allowed for hordes or they don't have any followers
                    if not wzIsSpeedAllowed(zombie) or zData.followers == nil or zData.followers:size() < 1 then
                        wzResetHorde(zData)
                        break
                    end
                elseif not zData.isWaiting and zombie:isOutside() and wzIsSpeedAllowed(zombie) then
                    -- add to waiting list if zombie is not waiting, is outside and speed is allowed for hordes
                    wzAddWaiting(zombie, zData)
                    break
                end
            elseif zData.leader ~= nil or zData.isLeader or zData.isWaiting then
                wzResetHorde(zData)
                break
            end

            -- if zombie is moving, has a path, or is climbing
            -- check to see if we need to adjust it's path or interrupt it's movement
            closestPlayers = nil
            zPos = zombie:getZ()
            if zombie:isMoving() or zombie:hasPath() or zombie:isClimbing() then
                if zData.targetPos ~= nil then
                    -- if enabled, try to prevent zeds from pathing outside the active area around a player
                    if SandboxVars.WanderingZombies.TryStopVirtual then
                        getClosestPlayers(zombiePos)
                        if #closestPlayers > 0 then
                            tsvDiff = closestPlayers[1].pos:sub(zData.targetPos)
                            tsvDist = tsvDiff:mag()
        
                            -- push targetPos towards the player
                            if tsvDist >= 95 then
                                zData.targetPos:moveTo(
                                    tsvDiff:normal(),
                                    (tsvDist - 95) + ZombRand(0, wzGetSandboxVar("MaxTravel", zData.isLeader))
                                )

                                wzDoPath(zombie, zData.targetPos, zPos, zData.isLeader)
                                if zData.isLeader then wzDoHordePath(zData, zombiePos, zPos) end

                                wzUpdateTicks(zData)
                                break
                            end
                        end
                    end

                    if not zData.homing or not wzGetSandboxVar("RadiusInterrupt", zData.isLeader) then
                        -- if zed is not homing or interrupts are disabled, don't interrupt
                        wzUpdateTicks(zData)
                        break
                    else
                        -- if homing zed is outside radius, don't interrupt
                        if closestPlayers == nil then getClosestPlayers(zombiePos) end
                        if #closestPlayers > 0 and closestPlayers[1].dist > wzGetSandboxVar("Radius", zData.isLeader) then
                            wzUpdateTicks(zData)
                            break
                        end

                        zData.targetPos = nil
                        wzDoPath(zombie, zombiePos, zPos, zData.isLeader)
                        if zData.isLeader then wzDoHordePath(zData, zombiePos, zPos) end
                        break
                    end
                end
            elseif getStateIsMoving(zombie) and zData.targetPos ~= nil then
                break
            end

            -- pathfind if set to always or the ticks have elapsed
            zData.targetPos = nil
            targetPos = nil
            maxTravel = wzGetSandboxVar("MaxTravel", zData.isLeader)
            if wzIsReadyMove(zData) then
                -- if inside flee radius, move away from the player
                -- otherwise home in on the nearest player
                -- failing that, wander randomly

                if closestPlayers == nil then getClosestPlayers(zombiePos) end
                closestAgedPlayer = getClosestAgedPlayer(closestPlayers)

                zData.homing = false
                if #closestPlayers > 0 and closestPlayers[1].dist < wzGetSandboxVar("FleeRadius", zData.isLeader) and
                    wzIsTimeNow("FleeStartHour", zData.isLeader) and ZombRand(100) < wzGetSandboxVar("FleePlayers", zData.isLeader)
                then
                    -- reverse the vector subtraction to point to the zombie
                    targetPos = zombiePos:moveTo(
                        zombiePos:sub(closestPlayers[1].pos):normal(), ZombRand(0, maxTravel)
                    )

                    zPos = ZombRand(0, 4)
                elseif closestAgedPlayer ~= nil and closestAgedPlayer.dist > wzGetSandboxVar("Radius", zData.isLeader) and
                    wzIsTimeNow("HomingStartHour", zData.isLeader) and ZombRand(100) < wzGetSandboxVar("ToPlayers", zData.isLeader)
                then
                    -- move the zombie position towards the player
                    -- limit by max travel or distance to player, whichever is smaller
                    targetPos = zombiePos:moveTo(
                        closestAgedPlayer.diff:addRand(20):normal(),
                        ZombRand(0, math.min(maxTravel, math.floor(closestAgedPlayer.dist)))
                    )

                    zData.homing = true

                    -- set the zpos to a random value, using the player's zpos as the limit
                    zPos = ZombRand(0, math.floor(closestAgedPlayer.zpos))
                elseif wzIsTimeNow("StartHour", zData.isLeader) and ZombRand(100) < wzGetSandboxVar("WanderChance", zData.isLeader) then
                    targetPos = zombiePos:addRand(maxTravel)
                    zPos = ZombRand(0, 4)
                end

                wzUpdateTicks(zData)
            end

            if targetPos == nil then break end

            if zPos > 0 then
                gridSquare = zombie:getCell():getGridSquare(math.floor(targetPos.x), math.floor(targetPos.y), zPos)
                if not gridSquare or not gridSquare:isSolidFloor() then
                    zPos = 0
                end
            end

            zData.targetPos = targetPos
            wzDoPath(zombie, targetPos, zPos, zData.isLeader)
            if zData.isLeader then wzDoHordePath(zData, targetPos, zPos) end
            break
        end
    end

    if msgTimer == nil or getTimeInMillis() - msgTimer >= 10000 then
        msgTimer = getTimeInMillis()
        print(
            "zombies: " .. tostring(zombies:size()) .. "[" .. tostring(zCount) .. "]" ..
            ", hordeLeaders: " .. tostring(wzGetNumLeaders()) ..
            ", hordeWaiting: " .. tostring(wzGetNumWaiting())
        )
    end

    if WZSandboxVars.HordesEnabled and getInCooldownPhase() then wzHordeUpdate() end
end

Events.OnTick.Add(WZUpdate)
