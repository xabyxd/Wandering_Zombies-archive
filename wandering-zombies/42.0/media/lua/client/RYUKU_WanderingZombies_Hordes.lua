if isServer() then return end

require "RYUKU_WanderingZombies_LinkedList"
require "RYUKU_WanderingZombies_Utility"

-- Waiting / Leaders --

local hordeWaiting = WZLinkedList:new("waiting")
local hordeLeaders = WZLinkedList:new("leaders")

function wzGetNumLeaders()
    return hordeLeaders:size()
end

function wzGetNumWaiting()
    return hordeWaiting:size()
end

function wzAddWaiting(zombie, zData)
    if zData.isWaiting then return wzPrint(zData, "wzAddWaiting, got waiting?") end
    if zData.isLeader then return wzPrint(zData, "wzAddWaiting, got leader?") end
    if zData.leader ~= nil then return wzPrint(zData, "wzAddWaiting, got follower?") end

    zData.link = hordeWaiting:push({
        zed = zombie,
        data = zData
    })

    zData.isWaiting = true
end

function wzRemoveWaiting(zData)
    if not zData.isWaiting then return wzPrint(zData, "wzRemoveWaiting, not waiting?") end
    if zData.isLeader then return wzPrint(zData, "wzRemoveWaiting, got leader?") end
    if zData.leader ~= nil then return wzPrint(zData, "wzRemoveWaiting, got follower?") end
    if zData.link == nil then return wzPrint(zData, "wzRemoveWaiting, link missing?") end

    hordeWaiting:remove(zData.link)
    zData.isWaiting = false
    zData.link = nil
end

function wzAddLeader(zombie, zData)
    if zData.isWaiting then return wzPrint(zData, "wzAddLeader, got waiting?") end
    if zData.isLeader then return wzPrint(zData, "wzAddLeader, got leader?") end
    if zData.leader ~= nil then return wzPrint(zData, "wzAddLeader, got follower?") end

    zData.link = hordeLeaders:push({
        zed = zombie,
        data = zData
    })

    zData.isLeader = true
end

function wzRemoveLeader(zData)
    if zData.isWaiting then return wzPrint(zData, "wzRemoveLeader, got waiting?") end
    if not zData.isLeader then return wzPrint(zData, "wzRemoveLeader, not leader?") end
    if zData.leader ~= nil then return wzPrint(zData, "wzRemoveLeader, got follower?") end
    if zData.link == nil then return wzPrint(zData, "wzRemoveLeader, link missing?") end

    hordeLeaders:remove(zData.link)
    zData.isLeader = false
    zData.link = nil
end

-- Followers --

function wzAddFollower(leader, lData, zombie, zData)
    if lData.isWaiting then return wzPrint(lData, "wzAddFollower, leader waiting?") end
    if not lData.isLeader then return wzPrint(lData, "wzAddFollower, leader is not leader?") end
    if lData.leader ~= nil then return wzPrint(lData, "wzAddFollower, leader is a follower?") end

    if zData.isWaiting then return wzPrint(lData, "wzAddFollower, follower waiting?") end
    if zData.isLeader then return wzPrint(lData, "wzAddFollower, follower is leader?") end
    if zData.leader ~= nil then return wzPrint(lData, "wzAddFollower, follower is a follower?") end

    if lData.followers == nil then lData.followers = WZLinkedList:new("followers") end
    zData.link = lData.followers:push({
        zed = zombie,
        data = zData
    })

    zData.leader = leader
end

function wzRemoveFollower(zData)
    if zData.isWaiting then return wzPrint(zData, "wzRemoveFollower, got waiting?") end
    if zData.isLeader then return wzPrint(zData, "wzRemoveFollower, got leader?") end
    if zData.leader == nil then return wzPrint(zData, "wzRemoveFollower, no leader?") end

    zData.leader = nil
    zData.link.list:remove(zData.link)
    zData.link = nil
end

function wzMoveFollowers(fromData, toZombie, toData, toPos, toZ)
    local follower
    while fromData.followers:size() > 0 do
        follower = fromData.followers:next()
        wzRemoveFollower(follower.ref.data)

        wzAddFollower(toZombie, toData, follower.ref.zed, follower.ref.data)
        wzDoPath(follower.ref.zed, toPos, toZ, true)
    end
end

-- Horde Creation / Merging Loop -

function wzDoHordeLoop(list, fn, startLink)
    if list:size() < ((startLink and 1) or 2) then return end

    local idx = (startLink and 0) or nil

    startLink = startLink or list:next()
    local startPos = WZVector:new(startLink.ref.zed)
    local startZ = startLink.ref.zed:getZ()
    local startData = startLink.ref.data

    local nextLink = list:next()
    local nextPos = WZVector:new(nextLink.ref.zed)
    local nextZ = nextLink.ref.zed:getZ()
    local nextData = nextLink.ref.data

    local startMs = getTimeInMillis()
    while ((idx ~= nil and idx < list:size()) or (idx == nil and nextLink ~= startLink)) and getTimeInMillis() - startMs <= 1 do
        if not fn(startLink, startPos, startZ, startData, nextLink, nextPos, nextZ, nextData) then
            break
        end

        if idx ~= nil then idx = idx + 1 end
        if list:size() > 0 then
            nextLink = list:next()
            nextPos = WZVector:new(nextLink.ref.zed)
            nextZ = nextLink.ref.zed:getZ()
            nextData = nextLink.ref.data
        end
    end
end

-- Horde Creation --

local function createHorde(startLink, startPos, startZ, startData, nextLink, nextPos, nextZ, nextData)
    -- if leader, make sure we don't exceed the Rally Group Size
    if startData.followers ~= nil and SandboxVars.ZombieConfig.RallyGroupSize > 0 and
        startData.followers:size() >= SandboxVars.ZombieConfig.RallyGroupSize
    then
        return false
    end

    -- don't allow zombies of differing speeds to group up
    if not wzIsMatchingSpeed(startLink.ref.zed, nextLink.ref.zed) then
        return true
    end

    -- as long as zombies are close enough, and share the same z height, group them together
    if startPos:distanceTo(nextPos) <= SandboxVars.ZombieConfig.RallyTravelDistance and startZ == nextZ then
        -- remove the start zombie from the waiting list
        if startData.isWaiting then wzRemoveWaiting(startData) end

        -- if the start zombie is not a leader, make them one
        if not startData.isLeader then wzAddLeader(startLink.ref.zed, startData) end

        -- remove the follower from the waiting list
        wzRemoveWaiting(nextData)

        -- add them as a follower
        wzAddFollower(startLink.ref.zed, startData, nextLink.ref.zed, nextData)

        -- order the follower to path
        wzDoPath(nextLink.ref.zed, startData.targetPos or startPos, startZ, true)

        if SandboxVars.ZombieConfig.RallyGroupSize > 0 and startData.followers:size() >= SandboxVars.ZombieConfig.RallyGroupSize then
            return false
        end
    end

    return true
end

-- Horde Merging --

local function isMergeExpired(zData)
    return not zData.mergeTime or
        getTimeInMillis() - zData.mergeTime >= 0
end

local function mergeHorde(startLink, startPos, startZ, startData, nextLink, nextPos, nextZ, nextData)
    -- skip start leader if not ready to merge
    if not isMergeExpired(startData) then
        return false
    end

    -- skip next leader if not ready to merge
    if not isMergeExpired(nextData) then
        return true
    end

    -- don't allow zombies of differing speeds to group up
    if not wzIsMatchingSpeed(startLink.ref.zed, nextLink.ref.zed) then
        return true
    end

    -- as long as leaders are close enough, and share the same z height, merge the hordes
    if startPos:distanceTo(nextPos) <= SandboxVars.ZombieConfig.RallyTravelDistance and startZ == nextZ then

        local targetLink = startLink
        local targetData = startData
        local targetPos = startData.targetPos or startPos
        local targetZ = startZ
        local fromLink = nextLink
        local fromData = nextData

        -- merge the smaller horde into the larger one
        if startData.followers:size() < nextData.followers:size() then
            targetLink = nextLink
            targetData = nextData
            targetPos = nextData.targetPos or nextPos
            targetZ = nextZ
            fromLink = startLink
            fromData = startData
        end
        
        -- move the merging followers
        wzMoveFollowers(fromData, targetLink.ref.zed, targetData, targetPos, targetZ)

        -- remove the merging leader from the leader list
        wzRemoveLeader(fromData)

        -- add the merging leader to the follower list
        wzAddFollower(targetLink.ref.zed, targetData, fromLink.ref.zed, fromData)

        -- order the merging leader to path
        wzDoPath(fromLink.ref.zed, targetPos, targetZ, true)

        -- update the merge time
        targetData.mergeTime = getTimeInMillis() + targetData.followers:size() * SandboxVars.WanderingZombies.MergeCooldown
        return false
    end

    return true
end

-- Horde Update --

function wzHordeUpdate()
    wzDoHordeLoop(hordeWaiting, createHorde)
    if SandboxVars.WanderingZombies.Merge then wzDoHordeLoop(hordeLeaders, mergeHorde)
    elseif hordeLeaders:size() > 0 then wzDoHordeLoop(hordeWaiting, createHorde, hordeLeaders:next()) end
end

-- Reset Horde --

function wzResetHorde(zData)
    if zData.isLeader then
        -- if zombie is a leader, remove from leaders and release followers
        while zData.followers:size() > 0 do
            wzRemoveFollower(zData.followers:next().ref.data)
        end

        wzRemoveLeader(zData)
    elseif zData.leader ~= nil then
        -- if zombie is a follower, remove from followers
        wzRemoveFollower(zData)
    elseif zData.isWaiting then
        -- if zombie is waiting, remove from waiting list
        wzRemoveWaiting(zData)
    end
end

-- Allowed Zombie Speeds --

function wzIsSpeedAllowed(zombie)
    local speed = wzGetZombieSpeed(zombie)
    return (speed == 1 and SandboxVars.WanderingZombies.AllowSprinters) or
        (speed == 2 and SandboxVars.WanderingZombies.AllowFastShamblers) or
        (speed == 3 and SandboxVars.WanderingZombies.AllowShamblers) or
        (speed == 5 and SandboxVars.WanderingZombies.AllowCrawlers)
end
