function wzPrint(data, msg)
    print("(" .. tostring(data.id) .. ") " .. msg)
end

function wzIsValidZombie(zombie)
    return (not isClient() or not zombie:isRemoteZombie()) and not zombie:isDead() and zombie:isExistInTheWorld()
end

local destructive, indoorDestructive
function wzSetDestructive(d, id)
    destructive = d
    indoorDestructive = id
end

local hordeDestructive, hordeIndoorDestructive
function wzSetHordeDestructive(d, id)
    hordeDestructive = d
    hordeIndoorDestructive = id
end

local function isDestructive(zombie, inHorde)
    return (inHorde and hordeDestructive and (not hordeIndoorDestructive or not zombie:isOutside())) or
        (not inHorde and destructive and (not indoorDestructive or not zombie:isOutside()))
end

function wzDoPath(zombie, pos, zPos, inHorde)
    if isDestructive(zombie, inHorde) then
        zombie:pathToSound(math.floor(pos.x), math.floor(pos.y), zPos)
    else
        zombie:pathToLocation(math.floor(pos.x), math.floor(pos.y), zPos)
    end
end

local fIdx, hordeTarget
function wzDoHordePath(zData, zombiePos, zPos)
    hordeTarget = zData.targetPos or zombiePos
    fIdx = 0
    while fIdx < zData.followers:size() do
        wzDoPath(zData.followers:next().ref.zed, hordeTarget:addRandNoZero(SandboxVars.ZombieConfig.RallyGroupRadius), zPos, true)
        fIdx = fIdx + 1
    end
end

-- appears to be a consistent index across zeds, so, should be fine?
local speedIdx, speedError
function wzGetZombieSpeed(zombie)
    if speedIdx == nil then
        for i = 0, getNumClassFields(zombie) - 1 do
            if tostring(getClassField(zombie, i)) == "public int zombie.characters.IsoZombie.speedType" then
                speedIdx = i
                break
            end
        end
    end

    local field = getClassField(zombie, speedIdx)
    if tostring(field) ~= "public int zombie.characters.IsoZombie.speedType" then
        if not speedError then
            getPlayer():addLineChatElement("wzGetZombieSpeed: inconsistent index for speedType")
            speedError = true
        end

        return 2
    end

    return (zombie:isCrawling() and 5) or getClassFieldVal(zombie, field)
end

function wzIsMatchingSpeed(zombieA, zombieB)
    return not SandboxVars.WanderingZombies.GroupBySpeed or wzGetZombieSpeed(zombieA) == wzGetZombieSpeed(zombieB)
end
