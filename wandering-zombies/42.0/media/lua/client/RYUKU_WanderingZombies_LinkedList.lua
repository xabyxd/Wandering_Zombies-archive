if isServer() then return end

WZLinkedList = {}

function WZLinkedList:size()
    return self._size
end

function WZLinkedList:next()
    if self.current == nil then
        self.current = self.first
    else
        self.current = self.current.next or self.current
    end

    return self.current
end

function WZLinkedList:prev()
    if self.current == nil then
        self.current = self.first
    else
        self.current = self.current.prev
    end

    return self.current
end

function WZLinkedList:push(o)
    local lt = {
        list = self,
        ref = o
    }

    if self.first == nil then
        self.first = lt
        self.last = lt
    else
        lt.next = self.first
        lt.prev = self.last

        self.last.next = lt
        self.last = lt

        self.first.prev = lt
    end

    self._size = self._size + 1
    return self.last
end

function WZLinkedList:pushIfNotExist(o)
    if self._size == 0 then
        return self:push(o)
    elseif self._size == 1 and self.first.ref ~= o then
        return self:push(o)
    end

    local element = self.first
    while true do
        if element.ref == o then return nil end
        element = element.next
        if element == self.first then return self:push(o) end
    end
end

function WZLinkedList:remove(lt)
    if self._size > 1 then
        lt.prev.next = lt.next
        lt.next.prev = lt.prev

        if self.current == lt then self.current = lt.prev end

        if self.first == lt then
            self.first = lt.next
        elseif self.last == lt then
            self.last = lt.prev
        end
    else
        self.first = nil
        self.last = nil
        self.current = nil
    end

    self._size = self._size - 1
end

function WZLinkedList:new(name)
    local wzList = {}
    setmetatable(wzList, self)
    self.__index = self

    wzList._size = 0
    wzList.name = name
    return wzList
end
