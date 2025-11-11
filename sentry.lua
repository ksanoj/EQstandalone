
local mq = require('mq')
local ImGui = require('ImGui')


local scriptEnabled = false
local lastAttackTime = 0
local attackInterval = 2 -- seconds
local attackDistance = 200 -- default attack distance
local running = true -- Controls the main loop

local function findNearestNpc(radius)
    local nearest = nil
    local nearestDist = radius + 1
    for i = 1, mq.TLO.SpawnCount('npc')() do
        local spawn = mq.TLO.Spawn(string.format('npc %d', i))
        if spawn() and spawn.Distance() <= radius and not spawn.Dead() then
            if spawn.Distance() < nearestDist then
                nearest = spawn
                nearestDist = spawn.Distance()
            end
        end
    end
    return nearest
end

local function petAttackTick()
    if not scriptEnabled then return end
    local now = os.clock()
    if now - lastAttackTime < attackInterval then return end

    local target = findNearestNpc(attackDistance)
    if target then
        mq.cmd(string.format('/target id %d', target.ID()))
        mq.delay(200)
        mq.cmd('/pet attack')
        lastAttackTime = now
    end
end

local function renderGUI()
    ImGui.Begin("Pet Auto Attack")
    local changed
    scriptEnabled, changed = ImGui.Checkbox("Enable Pet Attack", scriptEnabled)
    attackDistance = ImGui.SliderInt("Attack Distance", attackDistance, 0, 400)
    ImGui.Text("Status: " .. (scriptEnabled and "ON" or "OFF"))
    ImGui.Text("Current Distance: " .. attackDistance)
    if ImGui.Button("Stop Script") then
        running = false
    end
    ImGui.End()
end


mq.imgui.init('PetAutoAttackGUI', renderGUI)


while running do
    petAttackTick()
    mq.delay(100)
end
