if isServer() then return end

WZVector = {}

function WZVector:add(vec)
    self.x = self.x + vec.x
    self.y = self.y + vec.y

    return self
end

local rDist, rx, ry
local function getRand(start, range, vec)
    rDist = ZombRand(start, range + 1)
    rx = ZombRand(start, rDist + 1)
    ry = rDist - rx

    if ZombRand(2) == 0 then rx = -rx end
    if ZombRand(2) == 0 then ry = -ry end
    return vec.x + rx, vec.y + ry
end

function WZVector:addRand(range)
    self.x, self.y = getRand(0, range, self)
    return self
end

function WZVector:addRandNoZero(range)
    local wzVec = WZVector:copy(self)
    wzVec.x, wzVec.y = getRand(1, range, wzVec)

    return wzVec
end

function WZVector:sub(vec)
    local wzVec = WZVector:copy(self)
    wzVec.x = wzVec.x - vec.x
    wzVec.y = wzVec.y - vec.y

    return wzVec
end

function WZVector:mult(amount)
    self.x = self.x * amount
    self.y = self.y * amount
    return self
end

function WZVector:mag()
    return math.sqrt((self.x * self.x) + (self.y * self.y))
end

function WZVector:normal()
    local wzVec = WZVector:copy(self)
    local mag = self:mag()

    wzVec.x = wzVec.x / mag
    wzVec.y = wzVec.y / mag
    return wzVec
end

function WZVector:distanceTo(zedOrVec)
    if type(zedOrVec) == "userdata" then return self:sub(WZVector:new(zedOrVec)):mag() end
    return self:sub(zedOrVec):mag()
end

function WZVector:moveTo(normalVec, dist)
    return self:add(normalVec:mult(dist))
end

function WZVector:new(obj)
    local wzVec = {}
    setmetatable(wzVec, self)
    self.__index = self

    wzVec.x = obj:getX()
    wzVec.y = obj:getY()
    return wzVec
end

function WZVector:copy(vec)
    local wzVec = {}
    setmetatable(wzVec, self)
    self.__index = self

    wzVec.x = vec.x
    wzVec.y = vec.y
    return wzVec
end

function WZVector:tostring()
    return "x: " .. tostring(self.x) .. ", y: " .. tostring(self.y)
end
