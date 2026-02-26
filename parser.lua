--[[
DPS and Heal parser. 

By: Noobjuice
]]
local mq = require('mq')
local imgui = require('ImGui')
local iam = require('ImAnim')

local guiOpen = true
local running = true
local myName = ""
local transparentMode = false
local topTenMode = false

local CLASS_COLORS = {
    default  = IM_COL32(100, 200, 220, 255),
    warrior  = IM_COL32(200, 140, 56,  255),
    cleric   = IM_COL32(240, 240, 150, 255),
    paladin  = IM_COL32(180, 180, 220, 255),
    ranger   = IM_COL32(100, 180, 80,  255),
    shadow   = IM_COL32(120, 60,  160, 255),
    druid    = IM_COL32(200, 150, 80,  255),
    monk     = IM_COL32(200, 120, 80,  255),
    bard     = IM_COL32(150, 80,  200, 255),
    rogue    = IM_COL32(200, 200, 50,  255),
    shaman   = IM_COL32(80,  200, 160, 255),
    necro    = IM_COL32(180, 60,  60,  255),
    wizard   = IM_COL32(80,  130, 220, 255),
    mage     = IM_COL32(220, 100, 60,  255),
    enchant  = IM_COL32(180, 120, 200, 255),
    beast    = IM_COL32(180, 160, 100, 255),
    berserke = IM_COL32(220, 80,  80,  255),
}

-- Bar colors for ranked positions
local BAR_COLORS = {
    IM_COL32(91,  194, 231, 255),  -- #1 cyan
    IM_COL32(100, 220, 180, 255),  -- #2 teal
    IM_COL32(130, 200, 140, 255),  -- #3 green-teal
    IM_COL32(160, 180, 120, 255),  -- #4 olive
    IM_COL32(190, 160, 100, 255),  -- #5 gold-ish
    IM_COL32(200, 140, 100, 255),  -- #6
    IM_COL32(180, 120, 140, 255),  -- #7
    IM_COL32(160, 120, 200, 255),  -- #8 purple
}
local BAR_BG = IM_COL32(40, 40, 50, 180)

local HEAL_BAR_COLORS = {
    IM_COL32(80,  220, 120, 255),  -- #1 green
    IM_COL32(100, 200, 150, 255),  -- #2
    IM_COL32(120, 180, 160, 255),  -- #3
    IM_COL32(140, 160, 170, 255),  -- #4
    IM_COL32(160, 150, 180, 255),  -- #5
}

local currentFight = nil

local fightHistory = {}
local MAX_HISTORY = 50

local animState = {}

local function getAnimState(name)
    if not animState[name] then
        animState[name] = {
            displayDmg = 0,
            displayHeal = 0,
            alpha = 0,
            enterTime = os.clock(),
        }
    end
    return animState[name]
end

local function newPlayerData()
    return {
        totalDmg   = 0,
        meleeDmg   = 0,
        spellDmg   = 0,
        dsDmg      = 0,
        hits       = 0,
        firstHit   = nil,
        lastHit    = nil,
        hasPets    = false,
    }
end

local function newHealerData()
    return {
        totalHealed = 0,
        heals       = 0,
        overhealed  = 0,
        firstHeal   = nil,
        lastHeal    = nil,
    }
end

local function newFight(targetName, targetID)
    return {
        targetName = targetName or "Unknown",
        targetID   = targetID or 0,
        startTime  = os.clock(),
        endTime    = nil,
        players    = {},
        healers    = {},
        totalDmg   = 0,
        totalHeals = 0,
    }
end

local function archiveCurrentFight()
    if not currentFight then return end
    if currentFight.totalDmg == 0 and currentFight.totalHeals == 0 then
        currentFight = nil
        return
    end
    currentFight.endTime = os.clock()
    table.insert(fightHistory, 1, currentFight)
    if #fightHistory > MAX_HISTORY then
        table.remove(fightHistory)
    end
    currentFight = nil
end

local function ensureFight()
    if not currentFight then
        local tgtName = mq.TLO.Target.CleanName() or "Unknown"
        local tgtID = mq.TLO.Target.ID() or 0
        currentFight = newFight(tgtName, tgtID)
    end
    return currentFight
end

local function getPlayerInFight(fight, name)
    if not fight.players[name] then
        fight.players[name] = newPlayerData()
    end
    return fight.players[name]
end

local function getHealerInFight(fight, name)
    if not fight.healers[name] then
        fight.healers[name] = newHealerData()
    end
    return fight.healers[name]
end

local function recordMeleeDamage(attackerName, dmg, isPet)
    local fight = ensureFight()
    local player = getPlayerInFight(fight, attackerName)
    local now = os.clock()
    player.totalDmg = player.totalDmg + dmg
    player.meleeDmg = player.meleeDmg + dmg
    player.hits = player.hits + 1
    player.firstHit = player.firstHit or now
    player.lastHit = now
    if isPet then player.hasPets = true end
    fight.totalDmg = fight.totalDmg + dmg
end

local function recordSpellDamage(attackerName, dmg, isPet)
    local fight = ensureFight()
    local player = getPlayerInFight(fight, attackerName)
    local now = os.clock()
    player.totalDmg = player.totalDmg + dmg
    player.spellDmg = player.spellDmg + dmg
    player.hits = player.hits + 1
    player.firstHit = player.firstHit or now
    player.lastHit = now
    if isPet then player.hasPets = true end
    fight.totalDmg = fight.totalDmg + dmg
end

local function recordDsDamage(attackerName, dmg)
    local fight = ensureFight()
    local player = getPlayerInFight(fight, attackerName)
    local now = os.clock()
    player.totalDmg = player.totalDmg + dmg
    player.dsDmg = player.dsDmg + dmg
    player.hits = player.hits + 1
    player.firstHit = player.firstHit or now
    player.lastHit = now
    fight.totalDmg = fight.totalDmg + dmg
end

local function recordHeal(healerName, amount, overheal)
    local fight = ensureFight()
    local healer = getHealerInFight(fight, healerName)
    local now = os.clock()
    healer.totalHealed = healer.totalHealed + amount
    healer.heals = healer.heals + 1
    healer.overhealed = healer.overhealed + (overheal or 0)
    healer.firstHeal = healer.firstHeal or now
    healer.lastHeal = now
    fight.totalHeals = fight.totalHeals + amount
end

local function parseDmg(s)
    if not s then return 0 end
    return tonumber(s:match("%d+")) or 0
end

local function petOwner(name)
    if not name then return nil end
    return name:match("^(.+)`s pet$")
        or name:match("^(.+)´s pet$")
        or name:match("^(.+)'s pet$")
        or name:match("^(.+)'s pet$")
end

local function onOtherMelee(line, attacker, verb, target, dmgStr)
    if not attacker or not dmgStr then return end
    if attacker == "You" then return end
    local dmg = parseDmg(dmgStr)
    if dmg <= 0 then return end
    local owner = petOwner(attacker)
    if owner then
        recordMeleeDamage(owner, dmg, true)
    else
        recordMeleeDamage(attacker, dmg, false)
    end
end

local function onSelfMelee(line, verb, target, dmgStr)
    if not dmgStr then return end
    local dmg = parseDmg(dmgStr)
    if dmg <= 0 then return end
    recordMeleeDamage(myName, dmg, false)
end

local function onOtherSpell(line, attacker, target, dmgStr, dmgType, spellName)
    if not attacker or not dmgStr then return end
    if attacker == "You" then return end
    local dmg = parseDmg(dmgStr)
    if dmg <= 0 then return end
    local owner = petOwner(attacker)
    if owner then
        recordSpellDamage(owner, dmg, true)
    else
        recordSpellDamage(attacker, dmg, false)
    end
end

local function onSelfSpell(line, target, dmgStr, dmgType, spellName)
    if not dmgStr then return end
    local dmg = parseDmg(dmgStr)
    if dmg <= 0 then return end
    recordSpellDamage(myName, dmg, false)
end

local function onPetMelee(line, owner, verb, target, dmgStr)
    if not owner or not dmgStr then return end
    local dmg = parseDmg(dmgStr)
    if dmg <= 0 then return end
    recordMeleeDamage(owner, dmg, true)
end

local function onPetSpell(line, owner, target, dmgStr, dmgType, spellName)
    if not owner or not dmgStr then return end
    local dmg = parseDmg(dmgStr)
    if dmg <= 0 then return end
    recordSpellDamage(owner, dmg, true)
end

local function onDsThorns(line, target, owner, dmgStr)
    if not owner or not dmgStr then return end
    local dmg = parseDmg(dmgStr)
    if dmg <= 0 then return end
    recordDsDamage(owner, dmg)
end

local function onOtherHeal(line, healer, target, actualStr, totalStr)
    if not healer or not actualStr then return end
    if healer == "You" then return end
    local actual = parseDmg(actualStr)
    local total = parseDmg(totalStr)
    if actual <= 0 and total <= 0 then return end
    local healAmt = math.max(actual, 1)
    local overheal = (total > 0) and (total - actual) or 0
    recordHeal(healer, healAmt, overheal)
end

local function onSelfHeal(line, target, actualStr, totalStr)
    if not actualStr then return end
    local actual = parseDmg(actualStr)
    local total = parseDmg(totalStr)
    if actual <= 0 and total <= 0 then return end
    local healAmt = math.max(actual, 1)
    local overheal = (total > 0) and (total - actual) or 0
    recordHeal(myName, healAmt, overheal)
end

local function onOtherHoT(line, healer, target, actualStr, totalStr)
    if healer == "You" then return end
    onOtherHeal(line, healer, target, actualStr, totalStr)
end

local function onMobSlain(line, mob, killer)
    if currentFight and currentFight.targetName then
        if mob and string.find(string.lower(mob), string.lower(currentFight.targetName), 1, true) then
            archiveCurrentFight()
        end
    end
end

local function onSelfSlain(line, mob)
    archiveCurrentFight()
end

local function registerEvents()
    mq.event('dps_other_melee', '#1# #2# #3# for #4# points of damage#*#', onOtherMelee)

    mq.event('dps_self_melee', 'You #1# #2# for #3# points of damage#*#', onSelfMelee)

    mq.event('dps_other_spell', '#1# hit #2# for #3# points of #4# damage by #5##*#', onOtherSpell)

    mq.event('dps_self_spell', 'You hit #1# for #2# points of #3# damage by #4##*#', onSelfSpell)

    mq.event('dps_pet_melee', '#1#`s pet #2# #3# for #4# points of damage#*#', onPetMelee)
    mq.event('dps_pet_melee2', '#1#´s pet #2# #3# for #4# points of damage#*#', onPetMelee)

    mq.event('dps_pet_spell', '#1#`s pet hit #2# for #3# points of #4# damage by #5##*#', onPetSpell)
    mq.event('dps_pet_spell2', '#1#´s pet hit #2# for #3# points of #4# damage by #5##*#', onPetSpell)

    mq.event('dps_ds_thorns', '#1# is pierced by #2#\'s thorns for #3# points of non-melee damage#*#', onDsThorns)

    mq.event('dps_other_heal', '#1# healed #2# for #3# (#4#) hit points#*#', onOtherHeal)

    mq.event('dps_self_heal', 'You healed #1# for #2# (#3#) hit points#*#', onSelfHeal)

    mq.event('dps_other_hot', '#1# healed #2# over time for #3# (#4#) hit points#*#', onOtherHoT)

    mq.event('dps_mob_slain', '#1# has been slain by #2#!', onMobSlain)
    mq.event('dps_self_slain', 'You have slain #1#!', onSelfSlain)
end

local function unregisterEvents()
    mq.unevent('dps_other_melee')
    mq.unevent('dps_self_melee')
    mq.unevent('dps_other_spell')
    mq.unevent('dps_self_spell')
    mq.unevent('dps_pet_melee')
    mq.unevent('dps_pet_spell')
    mq.unevent('dps_ds_thorns')
    mq.unevent('dps_other_heal')
    mq.unevent('dps_self_heal')
    mq.unevent('dps_other_hot')
    mq.unevent('dps_mob_slain')
    mq.unevent('dps_self_slain')
end

local lastTargetID = 0
local lastTargetName = ""

local function checkTargetChange()
    local tgtID = mq.TLO.Target.ID() or 0
    local tgtName = mq.TLO.Target.CleanName() or ""
    local tgtType = mq.TLO.Target.Type() or ""
    local tgtDead = mq.TLO.Target.Dead()

    if currentFight and tgtDead and tgtID == currentFight.targetID and tgtID > 0 then
        archiveCurrentFight()
        lastTargetID = 0
        lastTargetName = ""
        return
    end

    if tgtID ~= lastTargetID and tgtID > 0 then
        if tgtType == "NPC" or tgtType == "NPC Corpse" then
            if currentFight and currentFight.totalDmg > 0 then
                archiveCurrentFight()
            elseif currentFight then
                currentFight = nil
            end
            if tgtType == "NPC" and not tgtDead then
                currentFight = newFight(tgtName, tgtID)
            end
        end
        lastTargetID = tgtID
        lastTargetName = tgtName
    elseif tgtID == 0 and lastTargetID ~= 0 then
        lastTargetID = 0
        lastTargetName = ""
    end
end

local function formatNumber(n)
    if n >= 1000000000 then
        return string.format("%.1fB", n / 1000000000)
    elseif n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(math.floor(n))
end

local function formatDPS(dmg, elapsed)
    if elapsed <= 0 then return "0" end
    return formatNumber(dmg / elapsed)
end

local function formatTime(seconds)
    if seconds < 60 then
        return string.format("%.0fs", seconds)
    elseif seconds < 3600 then
        return string.format("%dm %ds", math.floor(seconds / 60), math.floor(seconds % 60))
    else
        return string.format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
    end
end

local function getBarColor(rank)
    return BAR_COLORS[math.min(rank, #BAR_COLORS)] or BAR_COLORS[#BAR_COLORS]
end

local function getHealBarColor(rank)
    return HEAL_BAR_COLORS[math.min(rank, #HEAL_BAR_COLORS)] or HEAL_BAR_COLORS[#HEAL_BAR_COLORS]
end

local function ColorAlpha(col, a)
    return bit32.bor(bit32.band(col, 0x00ffffff), bit32.lshift(math.floor(a), 24))
end

local function getSortedPlayers(fight)
    if not fight then return {} end
    local list = {}
    for name, data in pairs(fight.players) do
        table.insert(list, { name = name, data = data })
    end
    table.sort(list, function(a, b) return a.data.totalDmg > b.data.totalDmg end)
    return list
end

local function getSortedHealers(fight)
    if not fight then return {} end
    local list = {}
    for name, data in pairs(fight.healers) do
        table.insert(list, { name = name, data = data })
    end
    table.sort(list, function(a, b) return a.data.totalHealed > b.data.totalHealed end)
    return list
end

local BAR_HEIGHT = 18
local BAR_WIDTH_MAX = 300
local WINDOW_FLAGS = bit32.bor(ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoScrollbar)

local function GetSafeDeltaTime()
    local dt = ImGui.GetIO().DeltaTime
    if dt <= 0 then dt = 1.0 / 60.0 end
    if dt > 0.1 then dt = 0.1 end
    return dt
end

local function drawDPSBar(dl, posX, posY, width, maxWidth, height, color, alpha)
    local barCol = ColorAlpha(color, math.floor(alpha * 200))
    local bgCol  = ColorAlpha(BAR_BG, math.floor(alpha * 180))
    dl:AddRectFilled(
        ImVec2(posX, posY),
        ImVec2(posX + maxWidth, posY + height),
        bgCol, 3.0
    )
    if width > 0 then
        dl:AddRectFilled(
            ImVec2(posX, posY),
            ImVec2(posX + width, posY + height),
            barCol, 3.0
        )
    end
end

local function renderGUI()
    if not guiOpen then return end

    local isTransparent = transparentMode

    if isTransparent then
        ImGui.PushStyleColor(ImGuiCol.WindowBg, 0, 0, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.Border, 0, 0, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.ChildBg, 0, 0, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0, 0, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.Header, 0, 0, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.3, 0.3, 0.3, 0.3)
        ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0.3, 0.3, 0.3, 0.4)
        ImGui.PushStyleColor(ImGuiCol.Separator, 0.5, 0.5, 0.5, 0.3)
    end

    ImGui.SetNextWindowSize(380, 500, ImGuiCond.FirstUseEver)
    local winFlags = WINDOW_FLAGS
    if isTransparent then
        winFlags = bit32.bor(winFlags, ImGuiWindowFlags.NoBackground)
    end
    local open, show = ImGui.Begin("DPS Parser##Main", guiOpen, winFlags)
    guiOpen = open
    if not show then
        ImGui.End()
        if isTransparent then ImGui.PopStyleColor(8) end
        return
    end

    local dt = GetSafeDeltaTime()
    local dl = ImGui.GetWindowDrawList()
    local now = os.clock()

    ImGui.PushStyleColor(ImGuiCol.Text, 0.36, 0.76, 0.91, 1.0)
    ImGui.Text("DPS Parser")
    ImGui.PopStyleColor()
    ImGui.SameLine(0, 10)

    if ImGui.SmallButton("Reset") then
        currentFight = nil
        fightHistory = {}
        animState = {}
    end
    ImGui.SameLine(0, 10)
    if ImGui.SmallButton("End Fight") then
        archiveCurrentFight()
    end
    ImGui.SameLine(0, 10)
    topTenMode = ImGui.Checkbox("Top 10", topTenMode)

    ImGui.SameLine(ImGui.GetWindowWidth() - 30)
    if transparentMode then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.36, 0.76, 0.91, 0.8)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 0.6)
    end
    if ImGui.SmallButton(transparentMode and "T##transp" or "O##transp") then
        transparentMode = not transparentMode
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(transparentMode and "Click: Opaque mode" or "Click: Transparent mode")
        ImGui.EndTooltip()
    end
    ImGui.PopStyleColor()

    ImGui.Separator()

    local fight = currentFight
    local elapsed = 0
    if fight then
        elapsed = now - fight.startTime
        local tgtHP = mq.TLO.Target.PctHPs() or 0
        ImGui.Text("Target:")
        ImGui.SameLine(0, 4)
        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.85, 0.3, 1.0)
        ImGui.Text(fight.targetName)
        ImGui.PopStyleColor()
        ImGui.SameLine(0, 10)

        if tgtHP > 0 then
            local hpR = 1.0 - (tgtHP / 100.0)
            ImGui.PushStyleColor(ImGuiCol.Text, hpR, 1.0 - hpR * 0.5, 0.2, 1.0)
            ImGui.Text(string.format("%d%%", tgtHP))
            ImGui.PopStyleColor()
        end

        ImGui.Text(string.format("Total: %s  |  DPS: %s  |  Time: %s",
            formatNumber(fight.totalDmg),
            formatDPS(fight.totalDmg, elapsed),
            formatTime(elapsed)
        ))
    else
        ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
        ImGui.Text("No active fight. Target an NPC to begin.")
        ImGui.PopStyleColor()
    end

    ImGui.Separator()

    if fight and fight.totalDmg > 0 then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.36, 0.76, 0.91, 1.0)
        ImGui.Text("Damage")
        ImGui.PopStyleColor()

        local sorted = getSortedPlayers(fight)
        local topDmg = (sorted[1] and sorted[1].data.totalDmg) or 1
        local contentWidth = ImGui.GetContentRegionAvail()
        local barMax = math.max(contentWidth - 10, 100)

        local maxDPS = topTenMode and math.min(#sorted, 10) or #sorted
        for rank = 1, maxDPS do
            local entry = sorted[rank]
            local name = entry.data.hasPets and (entry.name .. " + Pets") or entry.name
            local data = entry.data
            local anim = getAnimState(entry.name)

            local lerpSpeed = 8.0
            local diff = data.totalDmg - anim.displayDmg
            if math.abs(diff) < 1 then
                anim.displayDmg = data.totalDmg
            else
                local t = 1.0 - math.exp(-lerpSpeed * dt)
                anim.displayDmg = anim.displayDmg + diff * t
            end

            local age = now - anim.enterTime
            anim.alpha = math.min(1.0, iam.EvalPreset(IamEaseType.OutCubic, math.min(age * 2.0, 1.0)))

            local ratio = anim.displayDmg / math.max(topDmg, 1)
            local barW = ratio * barMax

            local cx, cy = ImGui.GetCursorScreenPos()
            drawDPSBar(dl, cx, cy, barW, barMax, BAR_HEIGHT, getBarColor(rank), anim.alpha)

            local alpha255 = math.floor(anim.alpha * 255)
            local textCol = ColorAlpha(IM_COL32(255, 255, 255, 255), alpha255)
            local playerDPS = formatDPS(data.totalDmg, elapsed)

            dl:AddText(ImVec2(cx + 4, cy + 1), textCol,
                string.format("%s", name))
            local rightText = string.format("%s  %s/s", formatNumber(data.totalDmg), playerDPS)
            local textW = #rightText * 7
            dl:AddText(ImVec2(cx + barMax - textW - 4, cy + 1), textCol, rightText)

            ImGui.Dummy(barMax, BAR_HEIGHT + 2)
        end
    end

    ImGui.Separator()

    if ImGui.CollapsingHeader("Heal Parser") then
        if fight and fight.totalHeals > 0 then
            local healSorted = getSortedHealers(fight)
            local topHeal = (healSorted[1] and healSorted[1].data.totalHealed) or 1
            local contentWidth2 = ImGui.GetContentRegionAvail()
            local healBarMax = math.max(contentWidth2 - 10, 100)

            ImGui.Text(string.format("Total Healed: %s  |  HPS: %s",
                formatNumber(fight.totalHeals),
                formatDPS(fight.totalHeals, elapsed)
            ))

            local maxHealers = topTenMode and math.min(#healSorted, 10) or #healSorted
            for rank = 1, maxHealers do
                local entry = healSorted[rank]
                local name = entry.name
                local data = entry.data
                local anim = getAnimState("heal_" .. name)

                local diff = data.totalHealed - anim.displayHeal
                if math.abs(diff) < 1 then
                    anim.displayHeal = data.totalHealed
                else
                    local t = 1.0 - math.exp(-8.0 * dt)
                    anim.displayHeal = anim.displayHeal + diff * t
                end

                local age = now - anim.enterTime
                anim.alpha = math.min(1.0, iam.EvalPreset(IamEaseType.OutCubic, math.min(age * 2.0, 1.0)))

                local ratio = anim.displayHeal / math.max(topHeal, 1)
                local barW = ratio * healBarMax

                local cx, cy = ImGui.GetCursorScreenPos()
                drawDPSBar(dl, cx, cy, barW, healBarMax, BAR_HEIGHT, getHealBarColor(rank), anim.alpha)

                local alpha255 = math.floor(anim.alpha * 255)
                local textCol = ColorAlpha(IM_COL32(255, 255, 255, 255), alpha255)
                local healerHPS = formatDPS(data.totalHealed, elapsed)

                dl:AddText(ImVec2(cx + 4, cy + 1), textCol, name)
                local rightText = string.format("%s  %s/s", formatNumber(data.totalHealed), healerHPS)
                local textW = #rightText * 7
                dl:AddText(ImVec2(cx + healBarMax - textW - 4, cy + 1), textCol, rightText)

                ImGui.Dummy(healBarMax, BAR_HEIGHT + 2)
            end
        else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
            ImGui.Text("No healing data yet.")
            ImGui.PopStyleColor()
        end
    end

    ImGui.Separator()

    if ImGui.CollapsingHeader("Fight History") then
        if #fightHistory == 0 then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1.0)
            ImGui.Text("No completed fights yet.")
            ImGui.PopStyleColor()
        else
            for i, hist in ipairs(fightHistory) do
                local duration = (hist.endTime or now) - hist.startTime
                local headerText = string.format("%s  |  %s  |  %s  |  %s/s",
                    hist.targetName,
                    formatTime(duration),
                    formatNumber(hist.totalDmg),
                    formatDPS(hist.totalDmg, duration)
                )

                if ImGui.TreeNode(string.format("%s##fight_%d", headerText, i)) then
                    local sorted = getSortedPlayers(hist)
                    for rank, entry in ipairs(sorted) do
                        local displayName = entry.data.hasPets and (entry.name .. " + Pets") or entry.name
                        local pctOfTotal = (hist.totalDmg > 0) and (entry.data.totalDmg / hist.totalDmg * 100) or 0
                        local pDPS = formatDPS(entry.data.totalDmg, duration)
                        ImGui.Text(string.format("  %d. %s - %s (%s/s) %.1f%%",
                            rank, displayName, formatNumber(entry.data.totalDmg), pDPS, pctOfTotal))
                    end

                    if hist.totalHeals > 0 then
                        ImGui.Separator()
                        ImGui.PushStyleColor(ImGuiCol.Text, 0.3, 0.86, 0.47, 1.0)
                        ImGui.Text("  Heals:")
                        ImGui.PopStyleColor()
                        local healSorted = getSortedHealers(hist)
                        for rank, entry in ipairs(healSorted) do
                            local hps = formatDPS(entry.data.totalHealed, duration)
                            ImGui.Text(string.format("    %d. %s - %s (%s/s)",
                                rank, entry.name, formatNumber(entry.data.totalHealed), hps))
                        end
                    end

                    ImGui.TreePop()
                end
            end
        end
    end

    ImGui.End()

    if isTransparent then ImGui.PopStyleColor(8) end
end

local function cmdToggle()
    guiOpen = not guiOpen
    print(string.format("\ay[DPS Parser]\ax Window %s", guiOpen and "shown" or "hidden"))
end

local function cmdReset()
    currentFight = nil
    fightHistory = {}
    animState = {}
    print("\ay[DPS Parser]\ax All data cleared.")
end

local function main()
    myName = mq.TLO.Me.Name() or "Unknown"
    print(string.format("\ay[DPS Parser]\ax Loaded for %s. Commands: /dps (toggle), /dpsreset (clear)", myName))

    registerEvents()
    mq.bind('/dps', cmdToggle)
    mq.bind('/dpsreset', cmdReset)
    mq.imgui.init('DPSParser', renderGUI)

    while running do
        if not guiOpen then
            running = false
            break
        end

        mq.doevents()
        checkTargetChange()
        mq.delay(50)
    end

    unregisterEvents()
    mq.unbind('/dps')
    mq.unbind('/dpsreset')
    mq.imgui.destroy('DPSParser')
    print("\ay[DPS Parser]\ax Unloaded.")
end

main()
