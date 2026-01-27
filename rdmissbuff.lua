-- Current for Shattering of Ro 
-- Author: Noobjuice

local mq = require('mq')
local ImGui = require('ImGui')
local Actors = require('actors')

-- Animation texture constants
local EQ_ICON_OFFSET = 500
local animMini = nil  -- Will be initialized after ImGui starts
local animInitialized = false

-- Configuration
local mailboxName = "BuffTracker"
local actor
local myName = mq.TLO.Me.CleanName()

-- GUI State
local showGUI = true
local openGUI = true
local showMainUI = false  -- Track main window visibility (false = minimized)

-- Window flags for mini button
local buttonWinFlags = bit32.bor(
    ImGuiWindowFlags.NoTitleBar,
    ImGuiWindowFlags.NoResize,
    ImGuiWindowFlags.NoScrollbar,
    ImGuiWindowFlags.NoScrollWithMouse,
    ImGuiWindowFlags.AlwaysAutoResize
)

-- Data storage
local allCharacterBuffs = {}  -- Stores missing buffs for all characters

-- Buff definitions with class requirements
local buffChecks = {
    {name = "Spirit of Lost Legends", class = "shm", includeClasses = nil, excludeClasses = nil},
    {name = "Mammoth's Unity", class = "shm", includeClasses = nil, excludeClasses = nil},
    {name = "Preeminent Unity", class = "shm", includeClasses = nil, excludeClasses = nil},
    {name = "Spirit's Focusing XIV", class = "shm", includeClasses = nil, excludeClasses = {"ENC", "CLR", "MAG", "NEC", "WIZ", "PAL"}},
    {name = "Spirit of Tala'Tak", class = "shm", includeClasses = nil, excludeClasses = nil},
    {name = "Benediction of Faith", class = "clr", includeClasses = nil, excludeClasses = nil},
    {name = "Symbol of Sharosh", class = "clr", includeClasses = nil, excludeClasses = nil},
    {name = "Talisman of Perseverance XV", class = "shm", includeClasses = nil, excludeClasses = nil},
    {name = "Ward of Eminence", class = "clr", includeClasses = nil, excludeClasses = nil},
    {name = "Grovewood Blessing", class = "dru", includeClasses = nil, excludeClasses = {"CLR"}},
    {name = "Illusion Benefit Greater Jann", class = "item", includeClasses = nil, excludeClasses = nil},
    {name = "Familiar: Candlefolk", class = "item", includeClasses = nil, excludeClasses = nil},
    {name = "Geomantra", class = "item", includeClasses = nil, excludeClasses = nil},
    {name = "Voice of Clairvoyance XVIII", class = "enc", includeClasses = nil, excludeClasses = {"WAR", "BER", "MNK", "ROG", "NEC"}},
    {name = "Hastening of Elluria", class = "enc", includeClasses = nil, excludeClasses = {"DRU", "MAG", "NEC", "WIZ"}},
    {name = "Night's Eternal Terror", class = "enc", includeClasses = nil, excludeClasses = nil},
    {name = "Spiritual Enlightenment XVII", class = "bst", includeClasses = nil, excludeClasses = nil},
    {name = "Shared Merciless Ferocity", class = "bst", includeClasses = nil, excludeClasses = nil},
    {name = "Circle of Fireskin XVI", class = "mag", includeClasses = nil, excludeClasses = nil},
    {name = "Arbor Stalker's Enrichment", class = "rng", includeClasses = nil, excludeClasses = nil},
}

-- Helper function to check if current class should see this buff
local function shouldShowBuff(buff)
    local myClass = mq.TLO.Me.Class.ShortName()
    
    -- Check exclude list first (if excluded, don't show)
    if buff.excludeClasses then
        for _, class in ipairs(buff.excludeClasses) do
            if myClass == class then
                return false  -- Excluded, don't show this buff
            end
        end
    end
    
    -- Check include list (if specified, must be in the list)
    if buff.includeClasses then
        for _, class in ipairs(buff.includeClasses) do
            if myClass == class then
                return true  -- Included, show this buff
            end
        end
        return false  -- Include list specified but not in it
    end
    
    -- No filters specified, show to all classes
    return true
end

-- Function to get missing buffs
local function getMissingBuffs()
    local missingBuffs = {}
    
    for _, buff in ipairs(buffChecks) do
        -- Check if this buff should be shown to our class
        if shouldShowBuff(buff) then
            -- Check if we're missing this buff
            if not mq.TLO.Me.Buff(buff.name).ID() then
                table.insert(missingBuffs, buff)
            end
        end
    end
    
    return missingBuffs
end

-- Register Actor for buff communication
local function RegisterActors()
    actor = Actors.register(mailboxName, function(message)
        if not message() then return end
        local received_message = message()
        local who = received_message.Sender or "Unknown"
        local missingBuffs = received_message.MissingBuffs or {}
        local zone = received_message.Zone or "Unknown"
        local switch = received_message.Switch or nil

        -- Handle window switching
        if switch then
            if switch == myName then
                mq.cmd("/foreground")
            end
            return
        end

        -- Update buff data for this character
        allCharacterBuffs[who] = {
            missingBuffs = missingBuffs,
            zone = zone,
            timestamp = os.time()
        }

        -- Clean up old data (remove characters not seen for 30 seconds)
        local now = os.time()
        for char, data in pairs(allCharacterBuffs) do
            if (now - data.timestamp) > 30 then
                allCharacterBuffs[char] = nil
            end
        end
    end)
end

-- Function to broadcast missing buffs
local function broadcastMissingBuffs()
    local missingBuffs = getMissingBuffs()
    local zone = mq.TLO.Zone.ShortName() or "Unknown"
    
    actor:send({ mailbox = mailboxName }, { 
        MissingBuffs = missingBuffs, 
        Sender = myName,
        Zone = zone
    })
end

-- Render mini button (collapsible icon)
local function renderMiniButton()
    -- Lazy initialization of texture (must be done after ImGui starts)
    if not animInitialized then
        local success, result = pcall(function()
            return mq.FindTextureAnimation("A_DragItem")
        end)
        if success and result then
            animMini = result
        else
            -- Fallback: use string-based texture reference
            animMini = "A_DragItem"
        end
        animInitialized = true
    end
    
    -- Don't pass close button parameter - mini button should always be visible
    if ImGui.Begin("Missing Buffs##Mini", nil, buttonWinFlags) then
        local cursorPosX, cursorPosY = ImGui.GetCursorScreenPos()
        
        -- Try to draw the texture
        local success, err = pcall(function()
            if type(animMini) == "string" then
                ImGui.DrawTextureAnimation(animMini, 2256 - EQ_ICON_OFFSET, 34, 34)
            else
                animMini:SetTextureCell(2256 - EQ_ICON_OFFSET)
                ImGui.DrawTextureAnimation(animMini, 34, 34)
            end
        end)
        
        if not success then
            -- Fallback: Just show a colored button
            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.2, 0.6, 0.2, 1.0))
            ImGui.Button("M##MiniBtn", ImVec2(34, 34))
            ImGui.PopStyleColor()
        end
        
        ImGui.SetCursorScreenPos(cursorPosX, cursorPosY)
        
        -- Invisible button overlay
        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0, 0, 0, 0))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.5, 0.5, 0, 0.5))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0, 0, 0, 0))
        
        if ImGui.Button("##MissingBuffBtn", ImVec2(34, 34)) then
            showMainUI = not showMainUI
        end
        
        ImGui.PopStyleColor(3)
    end
    
    ImGui.End()
end

-- GUI rendering function
local function drawGUI()
    -- Always show mini button (even if showGUI is false)
    renderMiniButton()
    
    if not showGUI then return end
    
    -- Only show main window if not minimized
    if not showMainUI then return end
    
    -- Check if anyone has missing buffs
    local hasAnyMissingBuffs = false
    local myMissingBuffs = getMissingBuffs()
    
    -- Check own missing buffs
    if #myMissingBuffs > 0 then
        hasAnyMissingBuffs = true
    end
    
    -- Check other characters' missing buffs
    for _, data in pairs(allCharacterBuffs) do
        if #data.missingBuffs > 0 then
            hasAnyMissingBuffs = true
            break
        end
    end
    
    -- Only show window if there are missing buffs
    if not hasAnyMissingBuffs then return end
    
    local open, show = ImGui.Begin('Missing Buffs - All Characters##' .. myName, true, 
        bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoDecoration))
    
    if not open then
        showGUI = false
        return
    end
    
    if show then
        -- Calculate total missing buffs (only count what we actually display)
        local totalMissing = #myMissingBuffs
        for char, data in pairs(allCharacterBuffs) do
            if char ~= myName then  -- Only count other characters, not self
                totalMissing = totalMissing + #data.missingBuffs
            end
        end
        
        ImGui.Text("Missing Buffs - All Characters (" .. totalMissing .. " total)")
        ImGui.Separator()
        
        -- Show own missing buffs first
        if #myMissingBuffs > 0 then
            ImGui.Text(myName .. " (" .. (mq.TLO.Zone.ShortName() or "Unknown") .. "):")
            for _, buff in ipairs(myMissingBuffs) do
                ImGui.Text("  " .. buff.name .. " [" .. buff.class .. "]")
            end
            if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
                -- Self-click doesn't need to switch windows
            end
            ImGui.Separator()
        end
        
        -- Show other characters' missing buffs (exclude self)
        for char, data in pairs(allCharacterBuffs) do
            if char ~= myName and #data.missingBuffs > 0 then
                ImGui.Text(char .. " (" .. data.zone .. "):")
                if ImGui.IsItemHovered() and ImGui.IsMouseReleased(0) then
                    actor:send({ mailbox = mailboxName }, { Sender = myName, Switch = char })
                end
                
                for _, buff in ipairs(data.missingBuffs) do
                    ImGui.Text("  " .. buff.name .. " [" .. buff.class .. "]")
                end
                ImGui.Separator()
            end
        end
    end
    
    ImGui.End()
end

-- Toggle function for external control
local function toggleGUI()
    showGUI = not showGUI
end

-- Main loop
local function main()
    print("Missing Buff Monitor with Multi-Character Support started")
    print("Monitoring " .. #buffChecks .. " different buffs across all characters")
    
    -- Register actors for communication
    RegisterActors()
    
    mq.imgui.init('MissingBuffGUI', drawGUI)
    
    local lastBroadcast = 0
    local lastGUIUpdate = 0
    
    while openGUI do
        mq.doevents()  -- Process actor messages
        
        local now = os.time()
        
        -- Broadcast missing buffs every 5 seconds
        if (now - lastBroadcast) >= 5 then
            broadcastMissingBuffs()
            lastBroadcast = now
            lastGUIUpdate = now  -- Update GUI when we broadcast new data
        end
        
        -- Only update GUI every second (when data might have changed from other actors)
        if (now - lastGUIUpdate) >= 1 then
            lastGUIUpdate = now
        end
        
        mq.delay(500)  -- Reduce main loop frequency to 2 times per second
    end
    
    print("Missing Buff Monitor stopped")
end

-- Start the monitor
main()
