local mq = require('mq')
local ImGui = require('ImGui')
local iam = require('ImAnim')

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
    guiOpen = true,
    botStatus = "IDLE",
}

local animState = {}
local FLASH_DURATION = 0.3
local CIRCLE_RADIUS = 28
local CHARW = 7
local LINEH = 13
local windowFadeStart = os.clock()

local function getAnim(key)
    if not animState[key] then
        animState[key] = { enterTime = os.clock(), lastClickTime = 0 }
    end
    return animState[key]
end

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

local STATUS_COLORS = {
    IDLE     = { 0.40, 0.40, 0.50 },
    SCANNING = { 0.20, 0.55, 0.80 },
    TRACKING = { 0.85, 0.65, 0.10 },
    COMBAT   = { 0.90, 0.20, 0.15 },
}

local function distanceColor(dist)
    if dist < 50 then
        return IM_COL32(30, 200, 30, 230)
    elseif dist < 150 then
        return IM_COL32(220, 180, 30, 230)
    else
        return IM_COL32(220, 60, 40, 230)
    end
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
    echo('Killbot v3.0 - ImAnim Edition')
    echo('====================================')
    return true
end

local function drawCircleButton(key, label1, label2, baseR, baseG, baseB, onClick, tooltip)
    local now = os.clock()
    local anim = getAnim(key)

    local cr, cg, cb = baseR, baseG, baseB
    local alpha = 1.0

    local age = now - anim.enterTime
    local fadeIn = iam.EvalPreset(IamEaseType.OutCubic, math.min(age * 2.0, 1.0))
    alpha = fadeIn

    local clickAge = now - anim.lastClickTime
    local flashT = 0
    if clickAge < FLASH_DURATION then
        flashT = 1.0 - iam.EvalPreset(IamEaseType.OutQuad, clickAge / FLASH_DURATION)
    end

    cr = cr + flashT * (1.0 - cr)
    cg = cg + flashT * (1.0 - cg)
    cb = cb + flashT * (1.0 - cb)

    local sx, sy = ImGui.GetCursorScreenPos()
    local diameter = CIRCLE_RADIUS * 2
    local clicked = ImGui.InvisibleButton(key, diameter, diameter)
    local hovered = ImGui.IsItemHovered()

    if hovered then
        cr = math.min(cr + 0.15, 1.0)
        cg = math.min(cg + 0.15, 1.0)
        cb = math.min(cb + 0.15, 1.0)
    end

    local dl = ImGui.GetWindowDrawList()
    local cx = sx + CIRCLE_RADIUS
    local cy = sy + CIRCLE_RADIUS
    local center = ImVec2(cx, cy)

    local circleCol = IM_COL32(
        math.floor(cr * 255),
        math.floor(cg * 255),
        math.floor(cb * 255),
        math.floor(alpha * 255)
    )
    dl:AddCircleFilled(center, CIRCLE_RADIUS, circleCol, 32)

    local outlineA = hovered and 160 or 80
    local outlineCol = IM_COL32(255, 255, 255, math.floor(alpha * outlineA / 255))
    dl:AddCircle(center, CIRCLE_RADIUS, outlineCol, 32, 1.5)

    local textA = math.floor(alpha * 255)
    local textCol = IM_COL32(255, 255, 255, textA)
    local w1 = #label1 * CHARW
    local w2 = #label2 * CHARW
    dl:AddText(ImVec2(cx - w1 / 2, cy - LINEH + 1), textCol, label1)
    dl:AddText(ImVec2(cx - w2 / 2, cy + 1), textCol, label2)

    if clicked and onClick then
        anim.lastClickTime = now
        onClick()
    end

    if hovered and tooltip then
        ImGui.BeginTooltip()
        ImGui.Text(tooltip)
        ImGui.EndTooltip()
    end
end

local function drawStatusBar()
    local now = os.clock()
    local colors = STATUS_COLORS[state.botStatus] or STATUS_COLORS.IDLE
    local cr, cg, cb = colors[1], colors[2], colors[3]

    if state.botStatus == "COMBAT" or state.botStatus == "TRACKING" then
        local pulse = 0.5 + 0.5 * math.sin(now * 3.0)
        cr = cr + pulse * 0.15
        cg = cg + pulse * 0.15
        cb = cb + pulse * 0.15
    end

    local width = ImGui.GetContentRegionAvail()
    local barH = 24
    local sx, sy = ImGui.GetCursorScreenPos()
    local dl = ImGui.GetWindowDrawList()

    local bgCol = IM_COL32(
        math.floor(cr * 180),
        math.floor(cg * 180),
        math.floor(cb * 180),
        200
    )
    dl:AddRectFilled(ImVec2(sx, sy), ImVec2(sx + width, sy + barH), bgCol, 4)

    dl:AddRect(ImVec2(sx, sy), ImVec2(sx + width, sy + barH),
        IM_COL32(255, 255, 255, 60), 4, 0, 1.0)

    local statusText = state.botStatus
    local tw = #statusText * CHARW
    dl:AddText(
        ImVec2(sx + (width - tw) / 2, sy + (barH - LINEH) / 2),
        IM_COL32(255, 255, 255, 230),
        statusText
    )

    ImGui.Dummy(width, barH)
end

local function drawActiveTarget()
    if state.activeMobID == 0 then return end

    local spawn = mq.TLO.Spawn(state.activeMobID)
    if not spawn or not spawn.ID() then return end

    local mobName = spawn.CleanName() or "Unknown"
    local distance = spawn.Distance() or 0
    local hp = spawn.PctHPs() or 0

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    local sx, sy = ImGui.GetCursorScreenPos()
    local dl = ImGui.GetWindowDrawList()
    local width = ImGui.GetContentRegionAvail()

    local barH = 38
    dl:AddRectFilled(ImVec2(sx, sy), ImVec2(sx + width, sy + barH),
        IM_COL32(40, 40, 55, 200), 4)

    local hpFrac = math.max(0, math.min(hp / 100.0, 1.0))
    local hpR = math.floor((1.0 - hpFrac) * 220)
    local hpG = math.floor(hpFrac * 180)
    dl:AddRectFilled(ImVec2(sx + 2, sy + 2), ImVec2(sx + 2 + (width - 4) * hpFrac, sy + barH - 2),
        IM_COL32(hpR, hpG, 30, 160), 3)

    dl:AddText(ImVec2(sx + 8, sy + 4),
        IM_COL32(255, 255, 255, 230), mobName)

    local hpStr = string.format("%d%%", hp)
    dl:AddText(ImVec2(sx + 8, sy + 20),
        IM_COL32(200, 200, 200, 200), hpStr)

    local badgeR = 14
    local badgeCx = sx + width - badgeR - 6
    local badgeCy = sy + barH / 2
    local dCol = distanceColor(distance)
    dl:AddCircleFilled(ImVec2(badgeCx, badgeCy), badgeR, dCol, 16)
    dl:AddCircle(ImVec2(badgeCx, badgeCy), badgeR,
        IM_COL32(255, 255, 255, 80), 16, 1.0)

    local distStr = string.format("%d", math.floor(distance))
    local dw = #distStr * 6
    dl:AddText(ImVec2(badgeCx - dw / 2, badgeCy - 6),
        IM_COL32(255, 255, 255, 240), distStr)

    ImGui.Dummy(width, barH)
end

local function drawMobList()
    if #state.findMobList == 0 then return end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    local dl = ImGui.GetWindowDrawList()
    local width = ImGui.GetContentRegionAvail()
    local barH = 22

    for i, mobName in ipairs(state.findMobList) do
        local sx, sy = ImGui.GetCursorScreenPos()

        local isActive = false
        if state.activeMobID > 0 then
            local spawn = mq.TLO.Spawn(state.activeMobID)
            if spawn and spawn.CleanName() == mobName then
                isActive = true
            end
        end

        local bgCol
        if isActive then
            bgCol = IM_COL32(80, 160, 80, 180)
        elseif i % 2 == 0 then
            bgCol = IM_COL32(45, 45, 60, 160)
        else
            bgCol = IM_COL32(35, 35, 50, 160)
        end

        dl:AddRectFilled(ImVec2(sx, sy), ImVec2(sx + width, sy + barH), bgCol, 3)

        local idxStr = string.format("%d.", i)
        dl:AddText(ImVec2(sx + 6, sy + 4),
            IM_COL32(160, 160, 180, 200), idxStr)

        dl:AddText(ImVec2(sx + 26, sy + 4),
            IM_COL32(255, 255, 255, isActive and 255 or 200), mobName)

        if isActive then
            dl:AddCircleFilled(ImVec2(sx + width - 10, sy + barH / 2),
                4, IM_COL32(80, 255, 80, 230), 12)
        end

        ImGui.Dummy(width, barH)
    end
end

local function drawGUI()
    if not state.showGUI then return end

    local winAge = os.clock() - windowFadeStart
    local winAlpha = iam.EvalPreset(IamEaseType.OutCubic, math.min(winAge * 1.5, 1.0))
    ImGui.PushStyleVar(ImGuiStyleVar.Alpha, winAlpha)

    ImGui.PushStyleColor(ImGuiCol.WindowBg, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.Border, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ChildBg, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.Separator, 0, 0, 0, 0)

    state.guiOpen, state.showGUI = ImGui.Begin('Killbot v3.0##KillbotMain', state.guiOpen,
        bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoBackground, ImGuiWindowFlags.NoTitleBar))

    if state.showGUI then
        drawStatusBar()

        ImGui.Spacing()

        if not state.initialized then
            drawCircleButton("StartBtn", "Start", "Hunt",
                0.15, 0.65, 0.30,
                function()
                    echo(string.format('Search radius: %d', config.searchRadius))
                    if initializeBot() then
                        state.initialized = true
                        state.botStatus = "SCANNING"
                    end
                end,
                "Start hunting mobs from farm.ini")
        else
            drawCircleButton("StopBtn", "Stop", "Hunt",
                0.75, 0.20, 0.20,
                function()
                    echo('Stopping killbot...')
                    state.activeMobID = 0
                    mq.cmd('/nav stop')
                    mq.cmd('/attack off')
                    state.initialized = false
                    state.botStatus = "IDLE"
                    setChatTitle('MQ2')
                end,
                "Stop hunting")
        end

        ImGui.SameLine(0, 10)

        drawCircleButton("ReloadBtn", "Reload", "INI",
            0.20, 0.50, 0.75,
            function()
                echo('Reloading farm.ini...')
                if loadMobListFromINI() then
                    echo('farm.ini reloaded successfully!')
                else
                    echo('Failed to reload farm.ini')
                end
            end,
            "Reload farm.ini mob list")

        ImGui.SameLine(0, 10)

        drawCircleButton("ExitBtn", "Exit", "Bot",
            0.55, 0.35, 0.55,
            function()
                echo('Killbot shutdown by user')
                state.running = false
                state.showGUI = false
            end,
            "Exit killbot script")

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        ImGui.Text("Search Radius:")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(160)
        config.searchRadius = ImGui.SliderInt("##radius", config.searchRadius, 50, 2000)

        drawActiveTarget()

        drawMobList()

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        local zoneName = mq.TLO.Zone.ShortName() or "Unknown"
        ImGui.TextColored(0.5, 0.5, 0.6, 1.0, string.format("Zone: %s  |  Mobs: %d",
            zoneName, #state.findMobList))
    end

    ImGui.End()
    ImGui.PopStyleColor(5)
    ImGui.PopStyleVar()
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
                state.botStatus = "COMBAT"

            elseif state.activeMobID == 0 and xTargetID == 0 then
                state.botStatus = "SCANNING"
                debug('MainLoop: No active target, searching...')
                findMob()

            else
                local spawn = mq.TLO.Spawn(state.activeMobID)
                if spawn and spawn.ID() then
                    local distance = spawn.Distance() or 0

                    if distance > config.navDistance then
                        state.botStatus = "TRACKING"
                        if xTargetID > 0 and state.activeMobID ~= xTargetID then
                            mq.cmd('/nav stop')
                            state.activeMobID = xTargetID
                            state.botStatus = "COMBAT"
                            debug(string.format('MainLoop: Switching to agroed mob ID:%d', xTargetID))
                        else
                            navToMob()
                        end
                    else
                        state.botStatus = "COMBAT"
                        killMob()
                    end
                else
                    state.activeMobID = 0
                    state.botStatus = "SCANNING"
                end
            end

            mq.delay(config.loopDelay)
        else
            state.botStatus = "IDLE"
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
    mq.imgui.init('KillbotGUI', drawGUI)

    if not initialize() then
        echo('Initialization failed, exiting.')
        return
    end

    mainLoop()
    cleanup()
end

main()
