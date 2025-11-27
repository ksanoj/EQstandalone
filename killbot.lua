-- killbot.lua v2.0 - Lua conversion of killbot.mac by Rogue601

-- This script farms specific mobs defined in farm.ini in the lua directory
-- Requires MQ2Nav with valid mesh
--
-- Usage: /lua run killbot

local mq = require('mq')
local ImGui = require('ImGui')

local config = {
    debugOn = false,
    iniFilename = 'farm.ini',
    searchRadius = 500,
    searchRadiusZ = 500,
    navDistance = 30,
    stickDistance = 8,
    loopDelay = 100,
    scanDelay = 5000,
}

local state = {
    activeMobID = 0,
    findMobList = {},
    running = true,
    initialized = false,
    showGUI = true,
    radiusInputText = '500',
    guiOpen = true,
}





local function echo(msg)
    print(string.format('[Killbot] %s', msg))
end

local function debug(msg)
    if config.debugOn then
        print(string.format('[DEBUG] %s', msg))
    end
end

local function setChatTitle(title)
    mq.cmdf('/setchattitle %s', title)
end





local function loadMobListFromINI()
    local iniPath = string.format('%s/%s', mq.luaDir, config.iniFilename)
    

    local currentZone = mq.TLO.Zone.ShortName()
    if not currentZone then
        echo('ERROR: Could not determine current zone')
        return false
    end
    
    echo(string.format('Loading mob list for zone [%s] from %s', currentZone, config.iniFilename))
    

    local mobList = {}
    local mobCount = 0
    

    local iniFile = mq.TLO.Ini.File(iniPath)
    if not iniFile() then
        echo(string.format('ERROR: Could not load INI file: %s', iniPath))
        return false
    end
    

    local sectionData = iniFile.Section(currentZone)
    if not sectionData() then
        echo(string.format('WARNING: No section found for zone [%s] in %s', currentZone, config.iniFilename))
        return false
    end
    
    local file = io.open(iniPath, 'r')
    if not file then
        echo(string.format('ERROR: Could not open INI file: %s', iniPath))
        return false
    end
    
    local inSection = false
    for line in file:lines() do
        line = line:match('^%s*(.-)%s*$')
        

        if line:match('^%[(.+)%]$') then
            local section = line:match('^%[(.+)%]$')
            inSection = (section == currentZone)
        elseif inSection and line ~= '' and not line:match('^[;#]') then

            local key, value = line:match('^([^=]+)=(.+)$')
            if key and value then
                key = key:match('^%s*(.-)%s*$')
                value = value:match('^%s*(.-)%s*$')
                

                if value == '1' then
                    table.insert(mobList, key)
                    mobCount = mobCount + 1
                    debug(string.format('Added mob to hunt list: %s', key))
                end
            end
        end
    end
    file:close()
    
    if mobCount == 0 then
        echo(string.format('WARNING: No mobs enabled (value=1) for zone [%s]', currentZone))
        return false
    end
    
    echo(string.format('Found %d mob(s) to hunt in this zone:', mobCount))
    for i, mobName in ipairs(mobList) do
        echo(string.format('  %d. %s', i, mobName))
    end
    
    state.findMobList = mobList
    return true
end





local function findClosestMob()
    if #state.findMobList == 0 then
        return 0
    end
    
    local closestMobID = 0
    local closestMobDistance = 99999
    

    for _, mobName in ipairs(state.findMobList) do

        local searchQuery = string.format('npc targetable radius %d zradius %d %s', 
            config.searchRadius, config.searchRadiusZ, mobName)
        
        local spawn = mq.TLO.NearestSpawn(searchQuery)
        if spawn and spawn.ID() then
            local checkMobID = spawn.ID()
            local checkMobDistance = spawn.Distance() or 99999
            
            if checkMobDistance < closestMobDistance and checkMobID > 0 then
                closestMobID = checkMobID
                closestMobDistance = checkMobDistance
            end
            
            debug(string.format('FindMob: "%s" ID:%d Distance:%.1f (closest: %d @ %.1f)', 
                mobName, checkMobID, checkMobDistance, closestMobID, closestMobDistance))
        end
    end
    
    return closestMobID
end

local function findMob()
    debug('FindMob: Searching for targets...')
    
    local mobID = findClosestMob()
    
    if mobID > 0 then
        state.activeMobID = mobID
        local spawn = mq.TLO.Spawn(mobID)
        if spawn and spawn.CleanName() then
            debug(string.format('FindMob: Found %s (ID:%d)', spawn.CleanName(), mobID))
        end
    else
        setChatTitle('Scanning for Targets')
        echo('FindMob: Nothing found, waiting 5 seconds...')
        mq.delay(config.scanDelay)
    end
end





local function navToMob()
    if state.activeMobID == 0 then return end
    

    if mq.TLO.Navigation.Active() then
        return
    end
    
    local spawn = mq.TLO.Spawn(state.activeMobID)
    if not spawn or not spawn.ID() then
        state.activeMobID = 0
        return
    end
    
    local mobName = spawn.CleanName() or 'Unknown'
    local distance = spawn.Distance() or 0
    
    debug(string.format('NavMob: Tracking "%s" ID:%d Distance:%.1f', mobName, state.activeMobID, distance))
    setChatTitle(string.format('Tracking %s', mobName))
    
    mq.cmdf('/nav id %d', state.activeMobID)
end





local function killMob()
    if state.activeMobID == 0 then return end
    
    local spawn = mq.TLO.Spawn(state.activeMobID)
    if not spawn or not spawn.ID() then
        state.activeMobID = 0
        return
    end
    
    local mobName = spawn.CleanName() or 'Unknown'
    debug(string.format('KillMob: Killing %s (ID:%d)', mobName, state.activeMobID))
    

    mq.cmdf('/target id %d', state.activeMobID)
    mq.delay(100)
    
    local target = mq.TLO.Target
    if target and target.ID() and target.Type() == 'NPC' then

        mq.cmd('/nav stop')
        mq.cmdf('/stick %d uw', config.stickDistance)
        setChatTitle(string.format('Killing %s', target.CleanName() or 'Unknown'))
        mq.cmd('/attack on')
        

        while target.ID() and mq.TLO.Me.Combat() and target.Type() == 'NPC' do
            mq.delay(100)
            mq.doevents()
            debug('KillMob: Combat loop active')
            

            if not target.ID() then
                break
            end
        end
        

        debug('KillMob: Combat ended')
    else

        state.activeMobID = 0
    end
    

    if target and target.Type() == 'Corpse' then
        debug('KillMob: Clearing corpse target')
        mq.cmd('/target clear')
        state.activeMobID = 0
    end
end





local function initializeBot()
    echo('====================================')
    echo(string.format('Search radius: %d', config.searchRadius))
    echo(string.format('Configuration file: %s', config.iniFilename))
    echo('====================================')
    

    if not loadMobListFromINI() then
        echo('ERROR: Failed to load mob list from INI file')
        return false
    end
    

    debug('Initializing Nav mesh...')
    mq.cmd('/nav reload')
    

    debug('Clearing XTarget list...')
    mq.cmd('/xtar remove')
    
    echo('Initialization complete!')
    echo('====================================')
    
    return true
end

local function initialize()
    echo('Killbot v2.0 - Lua Edition')
    echo('====================================')
    echo('Waiting for user input...')
    

    return true
end





local function drawRadiusDialog()
    if not state.showGUI then return end
    
    state.guiOpen, state.showGUI = ImGui.Begin('Killbot Control Panel', state.guiOpen, ImGuiWindowFlags.AlwaysAutoResize)
    
    if state.showGUI then

        ImGui.Text('Status:')
        ImGui.SameLine()
        if state.initialized then
            ImGui.TextColored(0, 1, 0, 1, 'Running')
        else
            ImGui.TextColored(1, 1, 0, 1, 'Waiting for Start')
        end
        
        ImGui.Separator()
        ImGui.Spacing()
        

        ImGui.Text('Search Radius:')
        ImGui.SameLine()
        ImGui.SetNextItemWidth(150)
        state.radiusInputText = ImGui.InputText('##radius', state.radiusInputText, ImGuiInputTextFlags.CharsDecimal)
        
        ImGui.Spacing()
        

        if not state.initialized then
            if ImGui.Button('Start Hunting', 200, 30) then
                local radius = tonumber(state.radiusInputText)
                if radius and radius > 0 then
                    config.searchRadius = radius
                    echo(string.format('Search radius set to: %d', radius))
                else
                    echo(string.format('Invalid input, using default radius: %d', config.searchRadius))
                end
                

                if initializeBot() then
                    state.initialized = true
                end
            end
        else
            if ImGui.Button('Stop Hunting', 200, 30) then
                echo('Stopping killbot...')
                state.activeMobID = 0
                mq.cmd('/nav stop')
                mq.cmd('/attack off')
                state.initialized = false
                setChatTitle('MQ2')
            end
        end
        
        ImGui.Spacing()
        
        if ImGui.Button('Reload farm.ini', 200, 25) then
            echo('Reloading farm.ini...')
            if loadMobListFromINI() then
                echo('farm.ini reloaded successfully!')
            else
                echo('Failed to reload farm.ini')
            end
        end
        
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        

        ImGui.Text(string.format('Current Zone: %s', mq.TLO.Zone.ShortName() or 'Unknown'))
        ImGui.Text(string.format('Mobs in List: %d', #state.findMobList))
        ImGui.Text(string.format('Active Mob ID: %d', state.activeMobID))
        
        ImGui.Spacing()
        
        if ImGui.Button('Exit Script', 200, 25) then
            echo('Killbot shutdown by user')
            state.running = false
            state.showGUI = false
        end
        
        ImGui.End()
    end
end





local function mainLoop()
    while state.running do
        mq.doevents()
        

        if state.initialized then

            local xTarget = mq.TLO.Me.XTarget(1)
            local xTargetID = xTarget and xTarget.ID() or 0
            


            if state.activeMobID == 0 and xTargetID > 0 then
                debug(string.format('AGROED: XTarget[1] ID:%d detected', xTargetID))
                state.activeMobID = xTargetID
                


            elseif state.activeMobID == 0 and xTargetID == 0 then
                debug('MainLoop: No active target, searching...')
                findMob()
                


            else
                local spawn = mq.TLO.Spawn(state.activeMobID)
                if spawn and spawn.ID() then
                    local distance = spawn.Distance() or 0
                    
                    if distance > config.navDistance then

                        if xTargetID > 0 and state.activeMobID ~= xTargetID then
                            mq.cmd('/nav stop')
                            state.activeMobID = xTargetID
                            debug(string.format('MainLoop: Switching to agroed mob ID:%d', xTargetID))
                        else
                            navToMob()
                        end
                        


                    else
                        killMob()
                    end
                else

                    state.activeMobID = 0
                end
            end
            

            mq.delay(config.loopDelay)
        else

            mq.delay(50)
        end
    end
end

local function cleanup()
    echo('Shutting down...')
    setChatTitle('MQ2')
    mq.cmd('/nav stop')
    mq.cmd('/stick off')
    mq.cmd('/attack off')
    echo('Killbot stopped.')
end





local function main()

    mq.imgui.init('KillbotRadiusDialog', drawRadiusDialog)
    
    if not initialize() then
        echo('Initialization failed, exiting.')
        return
    end
    

    mainLoop()
    

    cleanup()
end


main()
