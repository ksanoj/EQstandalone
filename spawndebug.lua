-- Made for debugging events, stores spawns detected within a radius.
local mq = require('mq')
require('ImGui')

local config = {
    radius = 50,
    minRadius = 0,
    maxRadius = 150,
}

local state = {
    spawns = {}, -- List of detected spawns {id, name, distance, timestamp}
    knownSpawns = {}, 
    pollThread = nil,
}

local function echo(msg)
    mq.cmdf('/echo [SpawnDebug] %s', msg)
end

local function safe_coro_resume(thread)
    if not thread then return false end
    
    local status = coroutine.status(thread)
    if status == "dead" then return false end
    
    local ok, err = coroutine.resume(thread)
    if not ok and err then 
        echo(string.format("Coroutine error: %s", tostring(err)))
    end
    return ok
end

local function pollSpawnsThread()
    while true do

        local spawnCount = mq.TLO.SpawnCount(string.format('npc radius %d', config.radius))()
        
        if spawnCount and spawnCount > 0 then

            for i = 1, spawnCount do
                local spawn = mq.TLO.NearestSpawn(i, string.format('npc radius %d', config.radius))
                
                if spawn and spawn.ID() then
                    local spawnID = spawn.ID()
                    
                    if not state.knownSpawns[spawnID] then
                        local spawnName = spawn.Name() or "Unknown"  
                        local distance = spawn.Distance() or 0
                        
                        table.insert(state.spawns, {
                            id = spawnID,
                            name = spawnName,
                            distance = string.format("%.1f", distance),
                            timestamp = os.date("%H:%M:%S"),
                        })
                        
                        state.knownSpawns[spawnID] = true
                    end
                end
            end
        end
        
        mq.delay(500) 
    end
end

local function drawGui()
    local open = true
    open = ImGui.Begin("Spawn Debug", open)
    
    if not open then
        mq.exit()
    end
    
    ImGui.Text("Detection Radius:")
    ImGui.SameLine()
    local newRadius = ImGui.SliderInt("##radius", config.radius, config.minRadius, config.maxRadius)
    if newRadius ~= config.radius then
        config.radius = newRadius
    end
    
    ImGui.SameLine()
    if ImGui.Button("Clear") then
        state.spawns = {}
        state.knownSpawns = {}
        echo("Spawn list cleared")
    end
    
    ImGui.Separator()
    
    ImGui.Text(string.format("Spawns Detected: %d", #state.spawns))
    ImGui.Separator()
    
    if ImGui.BeginTable("SpawnTable", 5, ImGuiTableFlags.Borders + ImGuiTableFlags.RowBg + ImGuiTableFlags.ScrollY) then
        ImGui.TableSetupColumn("ID", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn("Copy", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch)
        ImGui.TableSetupColumn("Distance", ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableSetupColumn("Time", ImGuiTableColumnFlags.WidthFixed, 70)
        ImGui.TableSetupScrollFreeze(0, 1)
        ImGui.TableHeadersRow()
        
        for i = #state.spawns, 1, -1 do
            local spawn = state.spawns[i]
            ImGui.TableNextRow()
            
            ImGui.TableSetColumnIndex(0)
            ImGui.Text(tostring(spawn.id))
            
            ImGui.TableSetColumnIndex(1)
            if ImGui.SmallButton("Copy##" .. i) then
                ImGui.SetClipboardText(spawn.name)
            end
            
            ImGui.TableSetColumnIndex(2)
            ImGui.Text(spawn.name)
            
            ImGui.TableSetColumnIndex(3)
            ImGui.Text(spawn.distance)
            
            ImGui.TableSetColumnIndex(4)
            ImGui.Text(spawn.timestamp)
        end
        
        ImGui.EndTable()
    end
    
    ImGui.End()
end

echo("SpawnDebug started")
echo(string.format("Monitoring spawns within %d units", config.radius))

mq.imgui.init('SpawnDebugUI', drawGui)
state.pollThread = coroutine.create(pollSpawnsThread)
safe_coro_resume(state.pollThread)

while true do
    if state.pollThread and coroutine.status(state.pollThread) == "suspended" then
        safe_coro_resume(state.pollThread)
    end
    
    mq.delay(100)
end
