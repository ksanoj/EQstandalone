--[[
/warrotation on|off - Enable or disable the war tank rotation.


]]

---@type MQ
local mq = require('mq')
local ImGui = require('ImGui')
math.randomseed(os.time())

-- === GLOBAL CONTROL VARIABLES ===
-- Toggle to start/stop all rotations
local rotationOn = false
local buffsOn = false
local meleeDisabled = false  -- Disable melee attacks (for raid mechanics)
local isPaused = false  -- Global pause toggle

-- CAMP FEATURE
local campOn = false
local campAnchor = {x = 0, y = 0, z = 0}
local campDistance = 10

-- MAIN MOB FEATURE
local mainMobOn = false

-- Advanced UI Configuration
local myName = mq.TLO.Me.CleanName()
local showMainUI = true
local openGUI = true
local mainWindowFlags = bit32.bor(ImGuiWindowFlags.None)
local buttonWinFlags = bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoCollapse)
local animMini = mq.FindTextureAnimation("A_SpellGems")
local EQ_ICON_OFFSET = 500

-- Settings
local settings = {
    showUI = true,
}

-- === PERFORMANCE OPTIMIZATION: STATE CACHING SYSTEM ===
local gameState = {
    lastUpdate = 0,
    updateInterval = 0.1, -- 100ms
    
    -- Cached values
    inCombat = false,
    hasTarget = false,
    targetType = nil,
    targetID = 0,
    targetPctHPs = 100,
    isInvisible = false,
    activeDisc = "",
    activeDiscID = 0,
    isSitting = false,
    
    -- Position data
    myX = 0, myY = 0, myZ = 0,
    
    -- Buff/Song states
    buffs = {},
    songs = {},
}

local function updateGameState()
    local now = os.clock()
    if now - gameState.lastUpdate < gameState.updateInterval then
        return false -- No update needed
    end
    
    gameState.lastUpdate = now
    gameState.inCombat = mq.TLO.Me.Combat() or false
    gameState.isSitting = mq.TLO.Me.Sitting() or false
    
    local target = mq.TLO.Target
    gameState.hasTarget = target() ~= nil
    if gameState.hasTarget then
        gameState.targetType = target.Type() or "Unknown"
        gameState.targetID = target.ID() or 0
        gameState.targetPctHPs = target.PctHPs() or 100
    else
        gameState.targetType = nil
        gameState.targetID = 0
        gameState.targetPctHPs = 100
    end
    
    gameState.isInvisible = (mq.TLO.Me.Invis() or false) or 
                           (mq.TLO.Me.InvisToUndead and mq.TLO.Me.InvisToUndead() or false) or 
                           (mq.TLO.Me.InvisToAnimals and mq.TLO.Me.InvisToAnimals() or false)
    
    local disc = mq.TLO.Me.ActiveDisc
    gameState.activeDisc = disc.Name() or ""
    gameState.activeDiscID = disc.ID() or 0
    
    gameState.myX = mq.TLO.Me.X() or 0
    gameState.myY = mq.TLO.Me.Y() or 0
    gameState.myZ = mq.TLO.Me.Z() or 0
    
    return true -- State was updated
end

-- === PERFORMANCE OPTIMIZATION: ABILITY CACHE SYSTEM ===
local abilityCooldowns = {
    lastUpdate = 0,
    updateInterval = 0.5, -- Update every 500ms
    cache = {}
}

-- Track all abilities we need to monitor
local trackedAbilities = {
    -- Disciplines
    {name="Flash of Anger", type="disc"},
    {name="Brightfeld's Onslaught Discipline Rk. II", type="disc"},
    {name="Perforate", type="disc"},
    {name="Final Stand Discipline VI Rk. II", type="disc"},
    {name="Bracing Defense X Rk. II", type="disc"},
    {name="Throat Jab", type="disc"},
    {name="Provoke XIX Rk. II", type="disc"},
    {name="Mortimus' Roar Rk. II", type="disc"},
    {name="Distressing Shout Rk. II", type="disc"},
    {name="Cyclone Blades XIV Rk. II", type="disc"},
    {name="Shield Split Rk. II", type="disc"},
    {name="Decisive Strike Rk. II", type="disc"},
    {name="End of the Line Rk. III", type="disc"},
    {name="Field Armorer X Rk. II", type="disc"},
    {name="Reciprocal Shield", type="disc"},
    {name="Fortitude Discipline", type="disc"},
    -- AA abilities
    {name="Gut Punch", type="aa"},
    {name="Knee Strike", type="aa"},
    {name="Blast of Anger", type="aa"},
    {name="Warlord's Fury", type="aa"},
    {name="Warlord's Grasp", type="aa"},
    {name="Projection of Fury", type="aa"},
    {name="Battle Leap", type="aa"},
    {name="Warlord's Bravery", type="aa"},
    -- Items
    {name="Gladiator's Plate Chestguard of War", type="item"},
    {name="Legionnaire Breastplate of the Shackled", type="item"},
    {name="Orb of the Sky", type="item"},
}

local function parseCooldownInternal(cd)
    if type(cd) == "number" then return cd end
    if cd == nil or cd == "" or cd == "Ready" then return 0 end
    local n = tonumber(cd)
    return n or 0
end

local function getCooldownSecondsInternal(name, type)
    if type == "disc" then
        return parseCooldownInternal(mq.TLO.Me.CombatAbilityTimer(name)())
    elseif type == "aa" then
        return parseCooldownInternal(mq.TLO.Me.AltAbilityTimer(name)())
    elseif type == "item" then
        local item = mq.TLO.FindItem(name)
        return parseCooldownInternal(item() and item.TimerReady() or 0)
    elseif type == "spell" then
        return parseCooldownInternal(mq.TLO.Me.SpellInCooldown(name)())
    end
    return 0
end

local function updateAbilityCooldowns()
    local now = os.clock()
    if now - abilityCooldowns.lastUpdate < abilityCooldowns.updateInterval then
        return false
    end
    
    abilityCooldowns.lastUpdate = now
    
    -- Batch update all abilities at once
    for _, ability in ipairs(trackedAbilities) do
        local cooldown = getCooldownSecondsInternal(ability.name, ability.type)
        abilityCooldowns.cache[ability.name] = {
            cooldown = cooldown,
            ready = cooldown == 0,
            timestamp = now
        }
    end
    
    return true
end

local function isAbilityCachedReady(name)
    local cached = abilityCooldowns.cache[name]
    if cached then
        return cached.ready
    end
    -- Fallback to direct check if not cached (for performance when available)
    local directReady = mq.TLO.Me.CombatAbilityReady(name)()
    return directReady
end

local function getCachedCooldown(name)
    local cached = abilityCooldowns.cache[name]
    if cached then
        return cached.cooldown
    end
    return 9999 -- High value if not cached
end

-- === PERFORMANCE OPTIMIZATION: EARLY EXIT SYSTEM ===
local function shouldSkipRotations()
    -- Skip everything if invisible or not ready - use direct checks for critical decisions
    local isInvis = (mq.TLO.Me.Invis() or false) or 
                    (mq.TLO.Me.InvisToUndead and mq.TLO.Me.InvisToUndead() or false) or 
                    (mq.TLO.Me.InvisToAnimals and mq.TLO.Me.InvisToAnimals() or false)
    
    if isInvis then return "invisible" end
    if not rotationOn then return "disabled" end
    
    return false
end

local function shouldSkipCombatRotations()
    local skip = shouldSkipRotations()
    if skip then return skip end
    
    -- Skip combat rotations if not in combat with valid target - use direct checks
    local inCombat = mq.TLO.Me.Combat() or false
    local target = mq.TLO.Target
    local hasTarget = target() ~= nil
    local targetType = hasTarget and (target.Type() or "Unknown") or nil
    
    if not inCombat or not hasTarget or targetType ~= "NPC" then
        return "no_combat"
    end
    
    return false
end

-- === PERFORMANCE OPTIMIZATION: ADAPTIVE TIMING ===
local function getOptimalLoopDelay()
    -- Adaptive timing based on combat state
    if not gameState.inCombat then
        return 2000 -- 2 seconds when idle
    elseif gameState.activeDiscID > 0 then
        return 200 -- 200ms during active discipline
    else
        return 100 -- 100ms in active combat
    end
end

-- === Robust cooldown parser ===
local function parseCooldown(cd)
    if type(cd) == "number" then return cd end
    if cd == nil or cd == "" or cd == "Ready" then return 0 end
    local n = tonumber(cd)
    return n or 0
end

-- Variables moved to top of file for proper scoping
local mainMobID = 0
local mainMobName = ""
local mainMobRadius = 50
local lastMainMobCheck = 0

-- AUTO TARGET FEATURE
local autoTargetOn = false
local autoTargetName = "a_small_zelniak00"
local autoTargetRange = 50
local autoTargetNameLocked = false
local lastAutoTargetCheck = 0

-- === ROTATION UPTIME TIMER ===
local rotationStartTime = 0
local rotationElapsedTime = 0
local function formatElapsed(sec)
    local min = math.floor(sec / 60)
    local sec = math.floor(sec % 60)
    return string.format("%02d:%02d", min, sec)
end

-- === BUFF SECTION ===
local buffCooldowns = {}
local buffState = {
    always = {},
    safeonly = {
        {name="Call of Sky", type="item", exec="Orb of the Sky"},
        {name="Champion's Aura", type="disc", exec="champion's aura"},
    }
}

-- Combat buffs/songs that should be maintained during combat
local combatBuffs = {
    {name="Commanding Voice", type="song", exec="commanding", checkType="song"},
    {name="Imperator's Command", type="song", exec="aa", aaID=2011, checkType="song", partial=true},
}
-- === OPTIMIZED STATE FUNCTIONS ===
local function hasBuff(buffName)
    -- Check cached buffs first, fallback to direct TLO call
    if gameState.buffs[buffName] ~= nil then
        return gameState.buffs[buffName]
    end
    -- Direct fallback (will be cached on next update)
    return mq.TLO.Me.Buff(buffName)() ~= nil or mq.TLO.Me.Song(buffName)() ~= nil
end

local function isInCombat()
    return gameState.inCombat
end

local function isInvisible()
    return gameState.isInvisible
end

-- Update buff cache for frequently checked buffs
local function updateBuffCache()
    local frequentBuffs = {
        "Call of Sky",
        "Champion's Aura",
        "Bloodlust Aura",
        "End of the Line Rk. III",
        "Reciprocal Shielding 1",
        "Guardian's Bravery",
        "Roaring Shield",
        "Field Armorer X Rk. II"
    }
    
    for _, buffName in ipairs(frequentBuffs) do
        gameState.buffs[buffName] = mq.TLO.Me.Buff(buffName)() ~= nil or mq.TLO.Me.Song(buffName)() ~= nil
    end
end

local function buffRotation()
    -- Early exit optimizations
    if not buffsOn then return end
    if isInCombat() or isInvisible() then return end
    
    for _, buff in ipairs(buffState.safeonly) do
        if not hasBuff(buff.name) then
            local now = os.clock()
            local last = buffCooldowns[buff.name] or 0
            if now - last > 2 then
                if buff.type == "item" then
                    -- Use cached ability state if available
                    if isAbilityCachedReady(buff.exec) or 
                       (mq.TLO.FindItem(buff.exec)() and parseCooldown(mq.TLO.FindItem(buff.exec).TimerReady()) == 0) then
                        mq.cmdf('/useitem "%s"', buff.exec)
                        buffCooldowns[buff.name] = now
                    end
                elseif buff.type == "disc" then
                    -- Use cached ability state if available
                    if isAbilityCachedReady(buff.name) or mq.TLO.Me.CombatAbilityReady(buff.name)() then
                        mq.cmdf('/disc %s', buff.exec)
                        buffCooldowns[buff.name] = now
                    end
                end
            end
        end
    end
end

-- Check if combat buff/song should be activated
local function shouldActivateCombatBuff(buff)
    -- Must be in combat and rotation on
    if not rotationOn then return false end
    if not isInCombat() then return false end
    
    -- Don't activate if sitting, feigning, or invisible
    if gameState.isSitting then return false end
    if mq.TLO.Me.Feigning() then return false end
    if isInvisible() then return false end
    
    -- Check if we already have the buff/song
    if buff.checkType == "song" then
        -- Check for song (like Commanding Voice or Imperator's Command)
        -- MQ automatically matches base name to any ranked/suffixed version
        if mq.TLO.Me.Song(buff.name).ID() then
            return false
        end
    else
        -- Check for buff
        if hasBuff(buff.name) then
            return false
        end
    end
    
    return true
end

-- Activate a combat buff/song
local function activateCombatBuff(buff)
    -- Special handling for Commanding Voice
    if buff.name == "Commanding Voice" then
        mq.cmd('/disc commanding')
        return true
    end
    
    -- Special handling for Imperator's Command
    if buff.name == "Imperator's Command" then
        mq.cmdf('/alt act %d', buff.aaID)
        return true
    end
    
    -- Generic handling
    if buff.exec == "aa" and buff.aaID then
        mq.cmdf('/alt act %d', buff.aaID)
    else
        mq.cmdf('/disc %s', buff.exec)
    end
    return true
end

-- Maintain combat buffs/songs
local function maintainCombatBuffs()
    -- Early exit if not in combat or rotation off
    if not rotationOn then return end
    if not isInCombat() then return end
    
    -- Check and refresh each combat buff
    for _, buff in ipairs(combatBuffs) do
        if shouldActivateCombatBuff(buff) then
            activateCombatBuff(buff)
            mq.delay(100) -- Small delay between actions
        end
    end
end

-- === UNIFIED COOLDOWN FUNCTION ===
local function getCooldownSeconds(name, type)
    if type == "disc" then
        return parseCooldown(mq.TLO.Me.CombatAbilityTimer(name)())
    elseif type == "aa" then
        return parseCooldown(mq.TLO.Me.AltAbilityTimer(name)())
    elseif type == "item" then
        local item = mq.TLO.FindItem(name)
        return parseCooldown(item() and item.TimerReady() or 0)
    elseif type == "spell" then
        return parseCooldown(mq.TLO.Me.SpellInCooldown(name)())
    end
    return 0
end

-- FLASH OF ANGER DISC LOGIC
local flashDiscName = "Flash of Anger"
local flashDiscExec = "flash"
local flashDiscCooldown = 91
local flashLastUseTime = 0
local function isFlashDiscReady()
    return isAbilityCachedReady(flashDiscName) or mq.TLO.Me.CombatAbilityReady(flashDiscName)()
end

local function useFlashDisc()
    if isFlashDiscReady() then
        mq.cmdf('/disc %s', flashDiscExec)
        flashLastUseTime = os.clock()
        return true
    end
    return false
end

local function handleFlashDiscAuto()
    -- Early exit optimizations - original logic: rotationOn only
    local skip = shouldSkipRotations()
    if skip then return end
    
    if flashLastUseTime == 0 and isFlashDiscReady() then
        useFlashDisc()
    elseif flashLastUseTime > 0 and isFlashDiscReady() then
        local since = os.clock() - flashLastUseTime
        if since >= flashDiscCooldown then
            useFlashDisc()
        end
    end
end

-- MAIN DISC ROTATION
local mainDiscState = {
    index = 1,
    nextDiscTime = 0,
    discs = {
        {name="Brightfeld's Onslaught Discipline Rk. II", exec="brightfeld"},
        {name="Perforate", exec="perforate"},
        {name="Final Stand Discipline VI Rk. II", exec="final stand discipline vi"},
        {name="Bracing Defense X Rk. II", exec="bracing defense x"},
        {name="Final Stand Discipline VI Rk. II", exec="final stand discipline vi"},
    },
}
local discRetryCount = 0
local function discReady(name)
    -- Prioritize direct TLO call like original, use cache as backup
    local directReady = mq.TLO.Me.CombatAbilityReady(name)()
    
    return directReady
end

local function getAbilityCooldown(name)
    return getCachedCooldown(name)
end

local function isDiscActive()
    -- Use direct TLO call like original - disc state changes need immediate detection
    local discID = mq.TLO.Me.ActiveDisc.ID()
    local directActive = (discID and discID > 0) or false
    
    return directActive
end

local function mainDiscRotation()
    -- Early exit optimizations - only check basic rotation state
    local skip = shouldSkipRotations()
    if skip then return end
    if os.clock() < mainDiscState.nextDiscTime then return end
    if isDiscActive() then return end
    
    local current = mainDiscState.discs[mainDiscState.index]
    
    if not discReady(current.name) then
        discRetryCount = 0
        mainDiscState.index = (mainDiscState.index % #mainDiscState.discs) + 1
        return
    end
    
    mq.cmdf('/disc %s', current.exec)
    mainDiscState.nextDiscTime = os.clock() + 2
    mq.delay(50)
    
    if isDiscActive() then
        discRetryCount = 0
        mainDiscState.index = (mainDiscState.index % #mainDiscState.discs) + 1
    else
        discRetryCount = discRetryCount + 1
        if discRetryCount >= 3 then
            discRetryCount = 0
            mainDiscState.index = (mainDiscState.index % #mainDiscState.discs) + 1
        end
    end
end

-- AGGRO ROTATION
local aggroState = {
    abilities = {
        {name="Gut Punch", exec="3732", type="aa"},
        {name="Knee Strike", exec="801", type="aa"},
        {name="Blast of Anger", exec="3646", type="aa"},
        {name="Warlord's Fury", exec="688", type="aa"},
        {name="Warlord's Grasp", exec="2002", type="aa"},
        {name="Projection of Fury", exec="3213", type="aa"},
        {name="Throat Jab", exec="throat", type="disc"},
        {name="Provoke XIX Rk. II", exec="provoke xix", type="disc"},
        {name="Mortimus' Roar Rk. II", exec="mortimus", type="disc"},
        {name="Distressing Shout Rk. II", exec="distressing", type="disc"},
    },
}
local nextAggroMashTime = 0
local function isAbilityReady(name, type)
    -- Use cached values first
    if isAbilityCachedReady(name) then
        return true
    end
    
    -- Fallback to direct TLO calls
    if type == "disc" then
        return mq.TLO.Me.CombatAbilityReady(name)()
    elseif type == "aa" then
        return mq.TLO.Me.AltAbilityReady(name)()
    end
    return false
end

local function inCombatWithTarget()
    return gameState.inCombat and gameState.hasTarget and gameState.targetType == "NPC"
end

local function aggroRotation()
    -- Early exit optimizations
    local skip = shouldSkipCombatRotations()
    if skip then return end
    if os.clock() < nextAggroMashTime then 
        return 
    end
    if not inCombatWithTarget() then 
        print(string.format("[DEBUG] aggroRotation: not in combat with target. inCombat=%s, hasTarget=%s, targetType=%s", 
            tostring(gameState.inCombat), tostring(gameState.hasTarget), tostring(gameState.targetType)))
        return 
    end
    
    for _, current in ipairs(aggroState.abilities) do
        if isAbilityReady(current.name, current.type) then
            if current.type == "disc" then
                mq.cmdf('/disc %s', current.exec)
            elseif current.type == "aa" then
                mq.cmdf('/alt activate %s', current.exec)
            end
        end
    end
    nextAggroMashTime = os.clock() + (0.5 + math.random() * 0.2)
end

-- DPS ROTATION
local dpsState = {
    nextCastTime = 0,
    abilities = {
        -- Cyclone Blades is instant and should be mashed whenever ready.
        -- Use a tiny backoff to prevent command spam in laggy ticks.
        {name="Cyclone Blades XIV Rk. II", exec="Cyclone Blades XIV", type="disc", postDelay=0.2},
        {name="Battle Leap", exec="611", type="aa"},
        {name="Shield Split Rk. II", exec="shield split", type="disc"},
        {name="Decisive Strike Rk. II", exec="decisive", type="disc", minHP=20},
    },
}
local function isAttackingNpc()
    return gameState.inCombat and gameState.hasTarget and gameState.targetType == "NPC"
end

local function onlyOneNpcWithin25()
    local count = mq.TLO.SpawnCount('npc radius 25')()
    return (count and count <= 1) or false
end

local function dpsRotation()
    -- Early exit optimizations
    local skip = shouldSkipCombatRotations()
    if skip then return end
    if os.clock() < dpsState.nextCastTime then return end
    if not isAttackingNpc() then return end

    -- Priority scan (MNK-style “mash when ready”):
    -- avoids long gaps where Cyclone is ready but the round-robin index isn’t on it.
    for _, current in ipairs(dpsState.abilities) do
        if current.soloOnly and not onlyOneNpcWithin25() then
            goto continue
        end
        if current.minHP then
            if gameState.targetPctHPs <= current.minHP then
                goto continue
            end
        end
        if isAbilityReady(current.name, current.type) then
            if current.type == "disc" then
                mq.cmdf('/disc %s', current.exec)
            elseif current.type == "aa" then
                mq.cmdf('/alt activate %s', current.exec)
            end
            dpsState.nextCastTime = os.clock() + (current.postDelay or 1.0)
            return
        end
        ::continue::
    end
end

-- END OF THE LINE, CHESTGUARD, LEGIONNAIRE, RECIPROCAL LOGIC
local endlineDiscName = "End of the Line Rk. III"
local endlineDiscExec = "end"
local endlineSongName = "End of the Line Rk. III"
local endlineDiscCooldown = 300
local endlineLastUseTime = 0
local function getEndlineSongTimeLeft()
    local song = mq.TLO.Me.Song(endlineSongName)
    return song() and song.Duration.TotalSeconds() or 0
end
local function isEndlineDiscReady()
    return isAbilityCachedReady(endlineDiscName) or mq.TLO.Me.CombatAbilityReady(endlineDiscName)()
end

local function useEndlineDisc()
    if isEndlineDiscReady() then
        mq.cmdf('/disc %s', endlineDiscExec)
        endlineLastUseTime = os.clock()
        return true
    end
    return false
end

local function handleEndlineAuto()
    -- Early exit optimizations - original logic: rotationOn + rotationStartTime > 0
    local skip = shouldSkipRotations()
    if skip or rotationStartTime == 0 then return end
    
    if endlineLastUseTime == 0 and isEndlineDiscReady() then
        useEndlineDisc()
    elseif endlineLastUseTime > 0 and isEndlineDiscReady() then
        local since = os.clock() - endlineLastUseTime
        if since >= endlineDiscCooldown then
            useEndlineDisc()
        end
    end
end

local fieldBulwarkNextCheck = 0
local function checkFieldBulwark()
    -- Early exit optimizations - original logic: rotationOn only
    local skip = shouldSkipRotations()
    if skip then return end
    if os.clock() < fieldBulwarkNextCheck then return end
    
    fieldBulwarkNextCheck = os.clock() + 2.0
    local abilityName = "Field Armorer X Rk. II"
    
    -- Use cached buff state and ability readiness
    if not hasBuff(abilityName) and 
       (isAbilityCachedReady(abilityName) or mq.TLO.Me.CombatAbilityReady(abilityName)()) then
        mq.cmdf('/disc %s', abilityName)
    end
end

-- RECIPROCAL SHIELD
local reciprocalName = "Reciprocal Shield"
local reciprocalExec = "reciprocal"
local reciprocalBuffName = "Reciprocal Shielding 1"
local reciprocalCooldown = 300
local reciprocalLastCastTime = 0
local function getReciprocalBuffTimeLeft()
    local buff = mq.TLO.Me.Buff(reciprocalBuffName)
    return buff() and buff.Duration.TotalSeconds() or 0
end
local function castReciprocalIfReady()
    if isAbilityCachedReady(reciprocalName) or mq.TLO.Me.CombatAbilityReady(reciprocalName)() then
        mq.cmdf('/disc %s', reciprocalExec)
        reciprocalLastCastTime = os.clock()
        return true
    end
    return false
end
local function onStartRotation()
    reciprocalLastCastTime = 0
    chestguardLastUseTime = 0
    legionnaireLastUseTime = 0
    endlineLastUseTime = 0
    
    -- Force immediate cache update when starting rotation
    abilityCooldowns.lastUpdate = 0  -- Force cache refresh
    updateAbilityCooldowns()
    updateGameState()
    
    castReciprocalIfReady()
end
local function handleReciprocalAuto()
    -- Early exit optimizations
    local skip = shouldSkipRotations()
    if skip then return end
    
    if isAbilityCachedReady(reciprocalName) or mq.TLO.Me.CombatAbilityReady(reciprocalName)() then
        castReciprocalIfReady()
    end
end

-- CHESTGUARD & LEGIONNAIRE LOGIC
local chestguardItemName = "Gladiator's Plate Chestguard of War"
local chestguardCooldown = 300
local chestguardLastUseTime = 0
local chestguardBuffName = "Guardian's Bravery"
local chestguardStartDelay = 60
local function getChestguardBuffTimeLeft()
    local buff = mq.TLO.Me.Buff(chestguardBuffName)
    return buff() and buff.Duration.TotalSeconds() or 0
end
local function isChestguardReady()
    -- Use cached ability state if available
    if isAbilityCachedReady(chestguardItemName) then
        return true
    end
    -- Fallback to direct check
    local item = mq.TLO.FindItem(chestguardItemName)
    return item() ~= nil and parseCooldown(item.TimerReady()) == 0
end
local function useChestguard()
    if isChestguardReady() then
        mq.cmdf('/useitem "%s"', chestguardItemName)
        chestguardLastUseTime = os.clock()
        return true
    end
    return false
end

local legionnaireItemName = "Legionnaire Breastplate of the Shackled"
local legionnaireCooldown = 600
local legionnaireLastUseTime = 0
local legionnaireBuffName = "Roaring Shield"
local function getLegionnaireBuffTimeLeft()
    local buff = mq.TLO.Me.Buff(legionnaireBuffName)
    return buff() and buff.Duration.TotalSeconds() or 0
end
local function isLegionnaireReady()
    -- Use cached ability state if available
    if isAbilityCachedReady(legionnaireItemName) then
        return true
    end
    -- Fallback to direct check
    local item = mq.TLO.FindItem(legionnaireItemName)
    return item() ~= nil and parseCooldown(item.TimerReady()) == 0
end
local function useLegionnaire()
    if isLegionnaireReady() then
        mq.cmdf('/useitem "%s"', legionnaireItemName)
        legionnaireLastUseTime = os.clock()
        return true
    end
    return false
end

local function handleChestguardAuto()
    -- Early exit optimizations
    local skip = shouldSkipRotations()
    if skip or rotationStartTime == 0 then return end
    
    local timeSinceRotation = os.clock() - rotationStartTime
    if chestguardLastUseTime == 0 and timeSinceRotation >= chestguardStartDelay then
        useChestguard()
        useLegionnaire()
    else
        if chestguardLastUseTime > 0 and isChestguardReady() then
            useChestguard()
        end
        if legionnaireLastUseTime > 0 and isLegionnaireReady() then
            useLegionnaire()
        end
    end
end

-- === AE TANK BUTTON LOGIC (uses flag for thread safety) ===
local aeTankDiscName = "Fortitude Discipline"
local aeTankDiscExec = "fortitude"
local aeTankAAID = 110
local aeTankRequested = false

local function isAETankReady()
    -- Use cached states where possible
    local discReady = isAbilityCachedReady(aeTankDiscName) or mq.TLO.Me.CombatAbilityReady(aeTankDiscName)()
    local aaReady = mq.TLO.Me.AltAbilityReady(aeTankAAID)() -- AA not commonly cached
    return discReady and aaReady
end

local function doAETank()
    if isDiscActive() then
        mq.cmd('/stopdisc')
        mq.delay(200)
    end
    mq.cmdf('/disc %s', aeTankDiscExec)
    mq.delay(100)
    mq.cmdf('/alt act %d', aeTankAAID)
end

-- === CAMP FEATURE FUNCTIONS ===
local function setCampAnchor()
    -- Use cached position data
    campAnchor.x = gameState.myX
    campAnchor.y = gameState.myY  
    campAnchor.z = gameState.myZ
    printf("[WarriorTank] Camp anchor set at: %.2f, %.2f, %.2f", campAnchor.x, campAnchor.y, campAnchor.z)
end

local function getDistanceFromCamp()
    -- Use cached position data
    local myX = gameState.myX
    local myY = gameState.myY
    local myZ = gameState.myZ
    
    local dx = myX - campAnchor.x
    local dy = myY - campAnchor.y
    local dz = myZ - campAnchor.z
    
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function returnToCamp()
    if not campOn then return end
    
    local distance = getDistanceFromCamp()
    local campDist = tonumber(campDistance) or 10
    if distance >= campDist then
        -- Use /nav loc to return to camp
        mq.cmdf('/nav loc %.2f %.2f %.2f', campAnchor.y, campAnchor.x, campAnchor.z)
        printf("[WarriorTank] Returning to camp (distance: %.2f)", distance)
    end
end

-- === MAIN MOB FEATURE FUNCTIONS ===
local function setMainMob()
    local target = mq.TLO.Target
    if target() and target.Type() == "NPC" then
        mainMobID = target.ID()
        mainMobName = target.Name() or "Unknown"
        mainMobOn = true
        printf("[WarriorTank] Main Mob set to: %s (ID: %d)", mainMobName, mainMobID)
        return true
    else
        printf("[WarriorTank] No valid NPC target to set as Main Mob")
        return false
    end
end

-- Set main mob by name (for text triggers)
local function setMainMobByName(mobName)
    if not mobName or mobName == "" then
        printf("[WarriorTank] Invalid mob name provided")
        return false
    end
    
    -- Method 1: Try exact spawn search with quotes
    local spawn = mq.TLO.Spawn(string.format('npc "%s"', mobName))
    if spawn() and spawn.Type() == "NPC" then
        mainMobID = spawn.ID()
        mainMobName = spawn.Name() or "Unknown"
        mainMobOn = true
        printf("[WarriorTank] Main Mob set to: %s (ID: %d)", mainMobName, mainMobID)
        return true
    end
    
    -- Method 2: Try partial name match without quotes (more lenient like /target)
    spawn = mq.TLO.Spawn(string.format('npc %s', mobName))
    if spawn() and spawn.Type() == "NPC" then
        mainMobID = spawn.ID()
        mainMobName = spawn.Name() or "Unknown"
        mainMobOn = true
        printf("[WarriorTank] Main Mob set to: %s (ID: %d)", mainMobName, mainMobID)
        return true
    end
    
    -- Method 3: Try targeting and use that
    mq.cmdf('/target "%s"', mobName)
    mq.delay(300) -- Wait for target to complete
    
    local target = mq.TLO.Target
    if target() and target.Type() == "NPC" then
        mainMobID = target.ID()
        mainMobName = target.Name() or "Unknown"
        mainMobOn = true
        printf("[WarriorTank] Main Mob set to: %s (ID: %d)", mainMobName, mainMobID)
        return true
    end
    
    printf("[WarriorTank] Could not find NPC: %s", mobName)
    return false
end

local function clearMainMob()
    mainMobOn = false
    mainMobID = 0
    mainMobName = ""
    printf("[WarriorTank] Main Mob cleared")
end

local function getDistanceToMob(mobID)
    local spawn = mq.TLO.Spawn(mobID)
    if not spawn() then return 999 end
    
    local myX = tonumber(mq.TLO.Me.X()) or 0
    local myY = tonumber(mq.TLO.Me.Y()) or 0
    local myZ = tonumber(mq.TLO.Me.Z()) or 0
    
    local mobX = tonumber(spawn.X()) or 0
    local mobY = tonumber(spawn.Y()) or 0
    local mobZ = tonumber(spawn.Z()) or 0
    
    local dx = myX - mobX
    local dy = myY - mobY
    local dz = myZ - mobZ
    
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function checkMainMob()
    if not mainMobOn or mainMobID == 0 then return end
    
    local now = os.clock()
    if now - lastMainMobCheck < 0.5 then return end -- Check every 500ms
    lastMainMobCheck = now
    
    local spawn = mq.TLO.Spawn(mainMobID)
    if not spawn() then
        printf("[WarriorTank] Main Mob (ID: %d) no longer exists, clearing", mainMobID)
        clearMainMob()
        return
    end
    
    local distance = getDistanceToMob(mainMobID)
    if distance <= mainMobRadius then
        -- Stand up if sitting
        if mq.TLO.Me.Sitting() then
            mq.cmd('/stand')
            mq.delay(100) -- Brief delay for stand animation
        end
        
        -- Check if we're already targeting the main mob
        local currentTarget = mq.TLO.Target
        if not currentTarget() or currentTarget.ID() ~= mainMobID then
            mq.cmdf('/target id %d', mainMobID)
            mq.delay(100) -- Brief delay to ensure target is set
        end
        
        -- Face the mob and turn on attack (check for melee disable first)
        mq.cmd('/face fast')
        if not mq.TLO.Me.Combat() then
            -- Check if melee has been disabled (raid mechanics like Quilled Coat)
            if not meleeDisabled then
                mq.cmd('/attack on')
            end
        elseif mq.TLO.Me.Combat() and meleeDisabled then
            -- If already attacking and melee gets disabled, stop attack
            mq.cmd('/attack off')
        end
    end
end

-- === AUTO TARGET FEATURE FUNCTIONS ===
local function findNearbyMobByName(mobName, maxRange)
    -- Search for mobs within range that match the name
    local myX = tonumber(mq.TLO.Me.X()) or 0
    local myY = tonumber(mq.TLO.Me.Y()) or 0
    local myZ = tonumber(mq.TLO.Me.Z()) or 0
    
    -- Try to find the mob by name within range
    local spawn = mq.TLO.SpawnCount(string.format('npc radius %d "%s"', maxRange, mobName))
    if spawn() and spawn() > 0 then
        -- Get the first matching spawn
        local mob = mq.TLO.NearestSpawn(string.format('npc "%s"', mobName))
        if mob() then
            local mobX = tonumber(mob.X()) or 0
            local mobY = tonumber(mob.Y()) or 0
            local mobZ = tonumber(mob.Z()) or 0
            
            local dx = myX - mobX
            local dy = myY - mobY
            local dz = myZ - mobZ
            local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
            
            if distance <= maxRange then
                return mob, distance
            end
        end
    end
    
    return nil, 999
end

local function checkAutoTarget()
    if not autoTargetOn or autoTargetName == "" then return end
    
    local now = os.clock()
    if now - lastAutoTargetCheck < 0.5 then return end -- Check every 500ms
    lastAutoTargetCheck = now
    
    local mob, distance = findNearbyMobByName(autoTargetName, autoTargetRange)
    if mob then
        local currentTarget = mq.TLO.Target
        
        -- Only target if we don't already have the correct target
        if not currentTarget() or currentTarget.Name() ~= autoTargetName then
            mq.cmdf('/target "%s"', autoTargetName)
            printf("[WarriorTank] Auto-targeting %s at distance %.1f", autoTargetName, distance)
            mq.delay(50) -- Brief delay to ensure target is set
        end
        
        -- Face and attack if we have the right target
        if currentTarget() and currentTarget.Name() == autoTargetName then
            mq.cmd('/face fast')
            if not mq.TLO.Me.Combat() then
                -- Check for melee disable before attacking
                if not meleeDisabled then
                    mq.cmd('/attack on')
                end
            elseif mq.TLO.Me.Combat() and meleeDisabled then
                -- If already attacking and melee gets disabled, stop attack
                mq.cmd('/attack off')
            end
            
            -- Start tank rotation if not already running
            if not rotationOn then
                rotationOn = true
                onStartRotation()
                rotationStartTime = os.clock()
                rotationElapsedTime = 0
                chestguardLastUseTime = 0
                legionnaireLastUseTime = 0
                endlineLastUseTime = 0
                printf("[WarriorTank] Auto-started rotation for %s", autoTargetName)
            end
        end
    end
end

-- === GUI CACHING SYSTEM ===
local guiCache = {
    lastUpdate = 0,
    updateInterval = 0.5, -- Update GUI data every 500ms
    discData = {},
    spa451Data = {},
    spa197Data = {},
    spa168Data = {}
}

local function updateGUICache()
    local now = os.clock()
    if now - guiCache.lastUpdate < guiCache.updateInterval then
        return false
    end
    
    guiCache.lastUpdate = now
    
    -- Only update cache if the functions exist (defined later in file)
    -- These will be populated when the GUI actually renders
    -- This prevents dependency issues during initialization
    
    return true
end

-- === MAIN DISC GUI HELPERS (ALL DISCS) ===

local function getAllMainDiscs()
    local list = {}
    for i, d in ipairs(mainDiscState.discs) do
        -- Use cached cooldown data when available
        local cd = getCachedCooldown(d.name)
        if cd == 9999 then
            cd = tonumber(mq.TLO.Me.CombatAbilityTimer(d.name).TotalSeconds()) or 9999
        end
        table.insert(list, {
            name = d.name,
            ready = cd == 0,
            cd = cd,
            idx = i,
        })
    end
    return list
end

local function colorForCooldown(cd)
    if cd == 0 then return 0, 1, 0, 1      -- Green for ready
    elseif cd < 10 then return 1, 1, 0, 1  -- Yellow for <10s
    else return 1, 0, 0, 1                 -- Red otherwise
    end
end

local function renderAllMainDiscs(activeName)
    ImGui.Text("Main Disc Rotation:")
    ImGui.Indent()
    
    -- Use cached data if available, otherwise get fresh data
    local discs = guiCache.discData
    if not discs or #discs == 0 then
        discs = getAllMainDiscs()
    end
    
    for _, entry in ipairs(discs) do
        local highlight = (activeName and entry.name == activeName)
        if highlight then ImGui.PushStyleColor(ImGuiCol.Text, 0, 0.7, 1, 1) end
        if entry.ready then
            ImGui.TextColored(0, 1, 0, 1, string.format("%d. %s [Ready]", entry.idx, entry.name))
        else
            ImGui.TextColored(1, 0, 0, 1, string.format("%d. %s [Not Ready]", entry.idx, entry.name))
        end
        if highlight then ImGui.PopStyleColor() end
    end
    ImGui.Unindent()
end

-- === SPA451 SECTION ===
local function getSpa451Abilities()
    local abilities = {
        {
            name = "Reciprocal Shield",
            type = "disc",
        },
        {
            name = "Legionnaire Breastplate of the Shackled",
            type = "item",
        }
    }
    local out = {}
    for i, ab in ipairs(abilities) do
        -- Use cached cooldown data when available
        local cd = getCachedCooldown(ab.name)
        if cd == 9999 then
            -- Fallback to direct TLO calls
            if ab.type == "disc" then
                cd = tonumber(mq.TLO.Me.CombatAbilityTimer(ab.name).TotalSeconds()) or 9999
            elseif ab.type == "item" then
                local item = mq.TLO.FindItem(ab.name)
                cd = tonumber(item() and item.TimerReady() or 9999)
            else
                cd = 9999
            end
        end
        table.insert(out, {
            idx = i,
            name = ab.name,
            cd = cd,
            ready = cd == 0,
        })
    end
    return out
end

local function renderSpa451Section()
    ImGui.Separator()
    ImGui.Text("SPA451:  Absorbs damage off the top of high melee hits")
    ImGui.Indent()
    
    -- Use cached data if available, otherwise get fresh data
    local abilities = guiCache.spa451Data
    if not abilities or #abilities == 0 then
        abilities = getSpa451Abilities()
    end
    
    for _, entry in ipairs(abilities) do
        if entry.ready then
            ImGui.TextColored(0, 1, 0, 1, string.format("%d. %s [Ready]", entry.idx, entry.name))
        else
            ImGui.TextColored(1, 0, 0, 1, string.format("%d. %s [Not Ready]", entry.idx, entry.name))
        end
    end
    ImGui.Unindent()
end

-- === SPA197 SECTION ===
local function getSpa197Abilities()
    local abilities = {
        {
            name = "Gladiator's Plate Chestguard of War",
            type = "item",
        },
        {
            name = "Warlord's Bravery",
            type = "aa",
        }
    }
    local out = {}
    for i, ab in ipairs(abilities) do
        -- Use cached cooldown data when available
        local cd = getCachedCooldown(ab.name)
        if cd == 9999 then
            -- Fallback to direct TLO calls
            if ab.type == "item" then
                local item = mq.TLO.FindItem(ab.name)
                cd = tonumber(item() and item.TimerReady() or 9999)
            elseif ab.type == "aa" then
                cd = tonumber(mq.TLO.Me.AltAbilityTimer(ab.name).TotalSeconds()) or 9999
            else
                cd = 9999
            end
        end
        table.insert(out, {
            idx = i,
            name = ab.name,
            cd = cd,
            ready = cd == 0,
        })
    end
    return out
end

local function renderSpa197Section()
    ImGui.Separator()
    ImGui.Text("SPA197:  Reduces the total damage of incoming melee")
    ImGui.Indent()
    
    -- Use cached data if available, otherwise get fresh data
    local abilities = guiCache.spa197Data
    if not abilities or #abilities == 0 then
        abilities = getSpa197Abilities()
    end
    
    for _, entry in ipairs(abilities) do
        if entry.ready then
            ImGui.TextColored(0, 1, 0, 1, string.format("%d. %s [Ready]", entry.idx, entry.name))
        else
            ImGui.TextColored(1, 0, 0, 1, string.format("%d. %s [Not Ready]", entry.idx, entry.name))
        end
    end
    ImGui.Unindent()
end

-- === SPA168 SECTION ===
local function getSpa168Abilities()
    local abilities = {
        {
            name = "End of the Line Rk. III",
            type = "disc",
        }
    }
    local out = {}
    for i, ab in ipairs(abilities) do
        -- Use cached cooldown data when available
        local cd = getCachedCooldown(ab.name)
        if cd == 9999 then
            -- Fallback to direct TLO calls
            if ab.type == "disc" then
                cd = tonumber(mq.TLO.Me.CombatAbilityTimer(ab.name).TotalSeconds()) or 9999
            else
                cd = 9999
            end
        end
        table.insert(out, {
            idx = i,
            name = ab.name,
            cd = cd,
            ready = cd == 0,
        })
    end
    return out
end

local function renderSpa168Section()
    ImGui.Separator()
    ImGui.Text("SPA168:  Reduces random portion of incoming melee")
    ImGui.Indent()
    
    -- Use cached data if available, otherwise get fresh data
    local abilities = guiCache.spa168Data
    if not abilities or #abilities == 0 then
        abilities = getSpa168Abilities()
    end
    for _, entry in ipairs(abilities) do
        if entry.ready then
            ImGui.TextColored(0, 1, 0, 1, string.format("%d. %s [Ready]", entry.idx, entry.name))
        else
            ImGui.TextColored(1, 0, 0, 1, string.format("%d. %s [Not Ready]", entry.idx, entry.name))
        end
    end
    ImGui.Unindent()
end

-- Render mini button (collapsible icon)
local function renderMiniButton()
    local openBtn, showBtn = ImGui.Begin("Warrior Tank##Mini", true, buttonWinFlags)
    if not openBtn then
        showBtn = false
    end
    
    if showBtn then
        local cursorPosX, cursorPosY = ImGui.GetCursorScreenPos()
        -- Use warrior/tank appropriate icon
        animMini:SetTextureCell(2871 - EQ_ICON_OFFSET)  -- Warrior tank icon
        ImGui.DrawTextureAnimation(animMini, 34, 34, true)
        ImGui.SetCursorScreenPos(cursorPosX, cursorPosY)
        
        -- Invisible button overlay
        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0, 0, 0, 0))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.5, 0.5, 0, 0.5))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0, 0, 0, 0))
        
        if ImGui.Button("##WarriorTankBtn", ImVec2(34, 34)) then
            settings.showUI = not settings.showUI
            showMainUI = settings.showUI
        end
        
        ImGui.PopStyleColor(3)
    end
    
    -- Tooltip
    if ImGui.IsWindowHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Warrior Tank Bot")
        ImGui.Text("Left-click to toggle UI")
        ImGui.Text("Right-click for options")
        ImGui.EndTooltip()
    end
    
    -- Context menu for options
    if ImGui.BeginPopupContextWindow("WarriorTankContext") then
        if ImGui.MenuItem("Close Bot") then
            openGUI = false
        end
        ImGui.EndPopup()
    end
    
    ImGui.End()
end

-- === GUI ===
local function renderMainUI()
    if not showMainUI then return end
    
    local open, show = ImGui.Begin('Warrior Tank Bot##Main', true, 
        bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoDecoration))
    
    if not open then 
        settings.showUI = false
        showMainUI = false
        return
    end
    
    if show then
    -- PAUSE BUTTON (Top Right Corner)
    local windowWidth = ImGui.GetWindowWidth()
    local pauseBtnWidth = 100
    local cursorPosX = ImGui.GetCursorPosX()
    ImGui.SetCursorPosX(windowWidth - pauseBtnWidth - 10)
    
    local pauseBtnColor = isPaused and {1, 0.5, 0, 1} or {0, 0.7, 0, 1}
    ImGui.PushStyleColor(ImGuiCol.Button, pauseBtnColor[1], pauseBtnColor[2], pauseBtnColor[3], pauseBtnColor[4])
    local pauseBtnLabel = isPaused and "UNPAUSE" or "PAUSE"
    if ImGui.Button(pauseBtnLabel, pauseBtnWidth, 0) then
        isPaused = not isPaused
        printf(isPaused and "[WarriorTank] Script PAUSED" or "[WarriorTank] Script UNPAUSED")
    end
    ImGui.PopStyleColor()
    
    -- Reset cursor position for the rest of the UI
    ImGui.SetCursorPosX(cursorPosX)
    
    if rotationOn and rotationStartTime > 0 then
        rotationElapsedTime = os.clock() - rotationStartTime
    end
    local text = string.format("Rotation Uptime: %s", formatElapsed(rotationElapsedTime))
    ImGui.Text(text)
    ImGui.Separator()

    local activeDisc = mq.TLO.Me.ActiveDisc.Name() or ""

    -- Button row
    if ImGui.Button(rotationOn and "Stop Rotation" or "Start Rotation") then
        rotationOn = not rotationOn
        if rotationOn then
            onStartRotation()
            rotationStartTime = os.clock()
            rotationElapsedTime = 0
            chestguardLastUseTime = 0
            legionnaireLastUseTime = 0
            endlineLastUseTime = 0
        else
            rotationElapsedTime = 0
            rotationStartTime = 0
            reciprocalLastCastTime = 0
            chestguardLastUseTime = 0
            legionnaireLastUseTime = 0
            endlineLastUseTime = 0
        end
        printf(rotationOn and "[WarriorTank] Rotation started." or "[WarriorTank] Rotation stopped.")
    end
    ImGui.SameLine()
    if ImGui.Button(buffsOn and "Buffs Active" or "Buffs Deactivated") then
        buffsOn = not buffsOn
        printf(buffsOn and "[WarriorTank] Buffs activated." or "[WarriorTank] Buffs deactivated.")
    end
    
    -- AE TANK BUTTON (smaller, next to buffs button)
    ImGui.SameLine()
    ImGui.BeginDisabled(not isAETankReady())
    if ImGui.Button("AE TANK", 70, 0) then
        aeTankRequested = true
    end
    ImGui.EndDisabled()

    -- AUTO TARGET SECTION (LEFT SIDE)
    local autoTargetBtnLabel = autoTargetOn and "AUTO TARGET ON" or "AUTO TARGET OFF"
    if ImGui.Button(autoTargetBtnLabel) then
        autoTargetOn = not autoTargetOn
        printf(autoTargetOn and "[WarriorTank] Auto Target activated." or "[WarriorTank] Auto Target deactivated.")
    end
    
    -- Target name label above the input box
    ImGui.Text("Target Name:")
    
    -- Auto target name input with lock checkbox
    ImGui.BeginDisabled(autoTargetNameLocked)
    ImGui.PushItemWidth(160)
    autoTargetName = ImGui.InputText("##AutoTargetName", autoTargetName)
    ImGui.PopItemWidth()
    ImGui.EndDisabled()
    
    -- Lock checkbox next to the input
    ImGui.SameLine()
    autoTargetNameLocked = ImGui.Checkbox("Lock", autoTargetNameLocked)
    
    -- Range slider
    ImGui.PushItemWidth(200)
    autoTargetRange = ImGui.SliderInt("##AutoTargetRange", autoTargetRange, 0, 100)
    ImGui.PopItemWidth()
    
    -- Label for the range slider
    ImGui.Text(string.format("Range: %d", autoTargetRange))

    -- CAMP BUTTON
    local btnWidth = 120
    local campBtnLabel = campOn and "CAMP ON" or "CAMP OFF"
    if ImGui.Button(campBtnLabel, btnWidth, 0) then
        campOn = not campOn
        if campOn then
            setCampAnchor()
        end
        printf(campOn and "[WarriorTank] Camp activated." or "[WarriorTank] Camp deactivated.")
    end

    -- CAMP RADIUS SLIDER
    ImGui.PushItemWidth(btnWidth)
    campDistance = ImGui.SliderInt("##CampRadius", campDistance, 0, 50)
    ImGui.PopItemWidth()
    
    -- Label for the slider
    ImGui.Text(string.format("Camp Radius: %d", campDistance))

    -- MAIN MOB SECTION
    local mainMobBtnLabel = mainMobOn and "CLEAR MAIN MOB" or "SET MAIN MOB"
    if ImGui.Button(mainMobBtnLabel, btnWidth, 0) then
        if mainMobOn then
            clearMainMob()
        else
            setMainMob()
        end
    end
    
    -- Show main mob info if set
    if mainMobOn and mainMobID > 0 then
        ImGui.Text(string.format("Main Mob: %s", mainMobName))
        
        -- Show distance if mob exists
        local spawn = mq.TLO.Spawn(mainMobID)
        if spawn() then
            local distance = getDistanceToMob(mainMobID)
            local distColor = distance <= mainMobRadius and {0, 1, 0, 1} or {1, 0, 0, 1}
            ImGui.TextColored(distColor[1], distColor[2], distColor[3], distColor[4], 
                string.format("Distance: %.1f", distance))
        else
            ImGui.TextColored(1, 0, 0, 1, "Mob not found!")
        end
    end

    ImGui.Separator()
    ImGui.Text("Main Disc Rotation Status:")
    renderAllMainDiscs(activeDisc)
    renderSpa451Section()
    renderSpa197Section()
    renderSpa168Section()
    ImGui.Separator()
    end
    
    ImGui.End()
end

-- Main render function called by ImGui
local function renderUI()
    if openGUI then
        renderMiniButton()
        renderMainUI()
    end
end

-- === COMMAND HANDLERS ===
local function cmdStopMelee()
    meleeDisabled = true
    printf("[WarriorTank] Melee attacks DISABLED")
    if mq.TLO.Me.Combat() then
        mq.cmd('/attack off')
    end
end

local function cmdStartMelee()
    meleeDisabled = false
    printf("[WarriorTank] Melee attacks ENABLED")
end

-- === TEXT TRIGGER HANDLERS ===
-- Handler for rdsetmainmob text trigger
-- Expected format: "rdsetmainmob WarriorName MobName"
local function handleSetMainMobTrigger(line)
    if not line then return end
    
    -- Parse the command: rdsetmainmob <warrior_name> <mob_name>
    local pattern = "rdsetmainmob%s+(%S+)%s+(.+)"
    local targetWarrior, mobName = line:match(pattern)
    
    if not targetWarrior or not mobName then
        return -- Not a valid rdsetmainmob command
    end
    
    -- Check if this warrior is the target
    if targetWarrior:lower() ~= myName:lower() then
        return -- Command is for a different warrior
    end
    
    -- Set the main mob by name
    printf("[WarriorTank] Received rdsetmainmob command for mob: %s", mobName)
    setMainMobByName(mobName)
end

-- Register MQ event for text triggers
mq.event('rdsetmainmob', '#*#rdsetmainmob#*#', handleSetMainMobTrigger)

-- Command handler for /warrotation
local function cmdWarRotation(...)
    local args = {...}
    local action = args[1] and args[1]:lower() or nil
    
    if action == "on" then
        if not rotationOn then
            rotationOn = true
            onStartRotation()
            rotationStartTime = os.clock()
            rotationElapsedTime = 0
            chestguardLastUseTime = 0
            legionnaireLastUseTime = 0
            endlineLastUseTime = 0
            printf("[WarriorTank] Rotation started.")
        else
            printf("[WarriorTank] Rotation already running.")
        end
    elseif action == "off" then
        if rotationOn then
            rotationOn = false
            rotationElapsedTime = 0
            rotationStartTime = 0
            reciprocalLastCastTime = 0
            chestguardLastUseTime = 0
            legionnaireLastUseTime = 0
            endlineLastUseTime = 0
            printf("[WarriorTank] Rotation stopped.")
        else
            printf("[WarriorTank] Rotation already stopped.")
        end
    else
        printf("[WarriorTank] Usage: /warrotation on|off")
        printf("[WarriorTank] Current status: %s", rotationOn and "ON" or "OFF")
    end
end

-- Bind slash commands
mq.bind('/stopmelee', cmdStopMelee)
mq.bind('/startmelee', cmdStartMelee)
mq.bind('/warrotation', cmdWarRotation)

-- Debug command to test song detection
mq.bind('/testsong', function()
    printf("=== Testing Song Detection ===")
    local songCount = mq.TLO.Me.Song.Count() or 0
    printf("Total songs active: %d", songCount)
    
    if songCount > 0 then
        for i = 1, songCount do
            local song = mq.TLO.Me.Song(i)
            if song and song.Name() then
                local songName = song.Name()
                printf("Song %d: [%s]", i, songName)
                
                -- Test if it matches Imperator's Command
                local result = string.find(songName, "Imperator's Command", 1, true)
                printf("  string.find result: %s", tostring(result))
                if result then
                    printf("  -> MATCHES Imperator's Command!")
                end
            else
                printf("Song %d: NIL or no name", i)
            end
        end
    else
        printf("No songs active")
    end
    
    -- Also test direct TLO access
    printf("--- Direct TLO Tests ---")
    local imperator = mq.TLO.Me.Song("Imperator's Command X")
    printf("Me.Song('Imperator's Command X').ID(): %s", tostring(imperator.ID()))
    
    local imperator2 = mq.TLO.Me.Song("Imperator's Command")
    printf("Me.Song('Imperator's Command').ID(): %s", tostring(imperator2.ID()))
    
    printf("===========================")
end)

-- Initialize UI animations and ImGui system
local function initializeUI()
    animMini = mq.FindTextureAnimation('A_SpellGems')
    openGUI = true
    showMainUI = settings.showUI
    mq.imgui.init("WarriorTankUI", renderUI)
end

-- Initialize the UI
initializeUI()

-- === OPTIMIZED MAIN LOOP ===
while true do
    -- Process MQ events (for text triggers)
    mq.doevents()
    
    -- Check pause state first - skip everything if paused
    if isPaused then
        mq.delay(500)  -- Longer delay when paused to reduce CPU usage
        goto continue
    end
    
    -- Update cached game state first
    updateGameState()
    updateAbilityCooldowns() 
    updateBuffCache()
    updateGUICache()
    
    -- Early exit if invisible
    if isInvisible() then
        mq.delay(getOptimalLoopDelay())
        goto continue
    end
    
    -- Combat rotations with early exits
    if rotationOn then
        maintainCombatBuffs()  -- Maintain combat buffs/songs first
        mainDiscRotation()
        aggroRotation()
        dpsRotation()
        handleEndlineAuto()
        checkFieldBulwark()
        handleReciprocalAuto()
        handleChestguardAuto()
        handleFlashDiscAuto()
    end
    
    -- Buff system
    if buffsOn then
        buffRotation()
    end
    
    -- CAMP FEATURE
    if campOn then
        returnToCamp()
    end
    
    -- MAIN MOB FEATURE
    if mainMobOn then
        checkMainMob()
    end
    
    -- AUTO TARGET FEATURE
    if autoTargetOn then
        checkAutoTarget()
    end
    
    -- AE TANK main thread safe
    if aeTankRequested then
        doAETank()
        aeTankRequested = false
    end
    
    -- Adaptive delay based on current state
    mq.delay(getOptimalLoopDelay())
    
    ::continue::
end
