-- JujutsuAdaptiveCombat v1.15.11
-- First-click target arming, native skills, native sprint/dash, bounded matchup learning, universal instant 3-M1 jump downslam, and event-driven reactive defense.

if game.PlaceId ~= 9391468976 then
    warn("[JAC] Wrong place: " .. tostring(game.PlaceId))
    return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

local env = getgenv()
-- Compile every dependency before retiring the active controller.
local pvpModules = {}
for _, name in ipairs({"combos", "dynamic", "panel", "movement", "moveset_data"}) do
    local chunk, err = loadstring((readfile("pvp/" .. name .. ".luau"):gsub("^" .. string.char(239,187,191), "")), "@pvp/" .. name)
    assert(chunk, err)
    pvpModules[name] = chunk()
    assert(name == "moveset_data" or type(pvpModules[name].new) == "function", "Invalid PvP module: " .. name)
end
local previousController=env.JujutsuAdaptiveCombat
if previousController and previousController.placeId==game.PlaceId and previousController.pvp
    and previousController.pvp.modules.moveset_data then
    local data=pvpModules.moveset_data
    for id,bucket in pairs(previousController.pvp.modules.moveset_data.animationTimings or {}) do
        for _,sample in ipairs(bucket.samples or {}) do
            if bucket.moveName and type(bucket.maxContactDistance)=="number" then
                data.recordContact(bucket.moveName,id,sample,bucket.maxContactDistance,bucket.source,bucket.opponent,bucket.speed)
            else
                data.recordTiming(id,sample,bucket.source,bucket.opponent,bucket.speed)
            end
        end
    end
end
if type(env.JujutsuAdaptiveCombat) == "table" and type(env.JujutsuAdaptiveCombat.Stop) == "function" then
    pcall(env.JujutsuAdaptiveCombat.Stop)
end

local controller = {
    version = "1.16.6",
    placeId = game.PlaceId,
    jobId = game.JobId,
    enabled = true,
    running = true,
    armed = false,
    gamemode = "FFA",
    gamemodeSub = nil,
    teamName = "None",
    inLobby = false,
    lastBeamQTEAt = 0,
    acquireUntil = 0,
    moveIntent = nil,
    sustainedSpecialSteering = nil,
    targetProgress = nil,
    activeCounter = nil,
    lastOffenseMove = nil,
    recentOffenseMoves = {},
    target = nil,
    connections = {},
    targetConnections = {},
    busy = false,
    comboBusy = false,
    comboSerial = 0,
    comboRequested = false,
    comboStartLastM1 = 0,
    lastConsumedM1 = 0,
    downCharacter = nil,
    wasDown = false,
    getUpRequest = nil,
    nextComboAt = 0,
    nextThink = 0,
    lastActionAt = 0,
    lastDashAt = 0,
    lastDashRequestAt = 0,
    dashPending = nil,
    dashRetryAt = 0,
    dashFailures = {},
    dashBlockedUntil = {},
    chaseObservers = {},
    moveObservers = {},
    pendingMove = nil,
    recentEntry = nil,
    finisherCommitUntil = 0,
    lastDownslamAt = 0,
    lastDownslamTarget = nil,
    steeringUntil = 0,
    lastForwardDashAt = 0,
    lastSpecialAt = 0,
    specialFollowupUntil = 0,
    specialApproachPending = nil,
    lostTargetAt = 0,
    side = 1,
    movementPatternTarget = nil,
    movementPatternUntil = 0,
    movementPatternSign = 1,
    pathTarget = nil,
    pathWaypoints = nil,
    pathIndex = 2,
    nextPathAt = 0,
    pathBusy = false,
    pathRequestSerial = 0,
    movementPatternStyle = 0,
    pendingEvadeUntil = 0,
    pendingThreat = nil,
    pendingThreatKind = nil,
    bodyAlign = nil,
    bodyAttachment = nil,
    bodyAttachmentOwned = false,
    bodyOriginalAutoRotate = nil,
    bodyHumanoid = nil,
    targetGeneration = 0,
    escapeUntil = 0,
    escapeDirection = nil,
    bodyFaceUntil = 0,
    finisherTarget = nil,
    finisherUntil = 0,
    moveRequestedAt = {},
    thinkBusy = false,
    recoveryRequest = nil,
    recoverySerial = 0,
    observedSkill = nil,
    loadout = nil,
    blockActive = false,
    blockSerial = 0,
    lastBlockAt = 0,
    blockStartedAt = 0,
    blockLastThreatAt = 0,
    blockRearmAt = 0,
    blockToken = nil,
    completedBlockToken = nil,
    manualDashPriorityUntil = 0,
    manualDashBufferedUntil = 0,
    bodyFaceSerial = 0,
    microStepSerial = 0,
    lastDamageAt = 0,
    lastMissLogAt = 0,
    lastManualLogAt = 0,
    lastTelemetryAt = 0,
    lastIntelSaveAt = 0,
    telemetryState = {},
    specialThreats = {},
    animationBound = {},
    animationLastSeen = {},
    combatTrace = {},
    intelEvents = {},
    knowledge = {},
    loadoutCoverage = {},
    lastOurMove = nil,
    actionSerial = 0,
    matchups = {},
    history = {},
    config = {
        -- A clicked opponent owns offense, defense and heading until explicitly changed.
        focusOnly = true,
        autoReacquire = true, reacquireDistance = 45,
        acquireDistance = 300,
        acquireGrace = 1.5,
        engageDistance = 5.2,
        retainDistance = 350,
        attackDistance = 12.5,
        unknownAttackDistance = 24,
        airVariantAttackDistance = 32,
        targetedAttackDistance = 28,
        aimedAttackDistance = 55,
        movementAttackDistance = 24,
        hybridAttackDistance = 45,
        shadowApproachMinDistance = 18,
        shadowApproachMaxDistance = 58,
        threatDistance = 14,
        rangedThreatDistance = 60,
        facingAcquireDot = 0.05,
        evadeBuffer = 0.9,
        blockGap = 0.21,
        blockBaseDuration = 0.18,
        blockQuietTime = 0.08,
        blockMaxDuration = 0.38,
        blockRearmGap = 0.16,
        escapeFacingDuration = 0.42,
        moveRequestGap = 0.4,
        specialReserveGap = 0.78,
        specialFollowupGap = 1.15,
        dashRequestGap = 0.72,
        holdReleaseDelay = 0.24,
        earthquakePerfectHold = 0.85,
        recoveryWindow = 1.4,
        recoveryDistance = 10,
        combatMovementPriority = false,
        bodyFaceDuration = 0.28,
        bodyTrackDistance = 350,
        microStepDuration = 0.16,
        telemetryInterval = 0.1,
        telemetryRadius = 10000,
        telemetryMaxCandidates = 32,
        maxTrace = 900,
        maxIntelEvents = 500,
        chaseMinDistance = 13,
        chaseMaxDistance = 29,
        lateralApproachMinDistance = 1e9, -- no lateral arcs: go straight at the target
        lateralApproachMaxDistance = 29,
        lateralApproachTravel = 22,
        tacticalMoveDuration = 0.26,
        tacticalPatternMin = 0.34,
        tacticalPatternMax = 0.72,
        decisionInterval = 0.020,
        actionGap = 0.09,
        m1Range = 7.0,
        -- Target switching: only near rivals, held for a while (studs / seconds).
        switchMaxDistance = 35,
        switchMargin = 8,
        switchHold = 3,
        -- Fast skill sequence by hotbar slot (keys 1-4), e.g. 2,1,3,4 after the M1s.
        comboSequence = { 2, 1, 3, 4 }, -- boss default for movesets without a guide entry
        -- Per-moveset slot order from public guides (twinfinite Gojo combos, progameguides):
        -- Gojo: Lapse Blue(1) > Rapid Punches(3) > Twofold Kick(4) > Reversal Red(2).
        -- Vessel/Itadori: Cursed Strikes(1) > Crushing Blow(2), then the rest.
        comboSequenceByMoveset = {
            Charles = { 1, 4, 2, 3 },
            Yuki = { 2, 3, 1, 4 },
            Kurourushi = { 1, 2, 3, 4 },
            Gojo = { 1, 3, 4, 2 },
            Itadori = { 1, 2, 3, 4 },
            Sukuna = { 3, 1, 2, 4 },
            Heian = { 3, 1, 2, 4 },
            Naoya = { 1, 3, 2, 4 },
            Choso = { 2, 3, 1, 4 },
            Mahito = { 1, 3, 2, 4 },
            Hakari = { 1, 3, 4, 2 },
            Todo = { 2, 1, 4, 3 },
            Nanami = { 1, 2, 3, 4 },
            Reggie = { 1, 2, 3, 4 },
            MeiMei = { 1, 2, 3, 4 },
            Mechamaru = { 1, 2, 3, 4 },
            Megumi = { 3, 1, 2, 4 },
            Ryu = { 1, 3, 4, 2 },
            Yuta = { 2, 1, 3, 4 },
            Haruta = { 1, 2, 4, 3 },
            Locust = { 1, 3, 2, 4 },
            Goku = { 2, 3, 1, 4 },
        },
        -- Role of each hotbar slot in the breathless chain: close (melee), push
        -- (knockback / separa), ranged. Chain = close -> push -> lateral dash -> ranged -> R.
        -- Roles come from evidence/combo-chains.json; only Gojo/Itadori names are confirmed.
        comboRoleByMoveset = {
            Gojo = { [1]="close", [2]="push", [3]="close", [4]="close" },
            Itadori = { [1]="close", [2]="close", [3]="close", [4]="push" },
            Charles = { [1]="close", [4]="ranged" }, -- Shut Up! (2) and Eye Catching (3) are counters, not chain links
            Yuki = { [1]="push", [2]="close", [3]="close", [4]="close" },
            Kurourushi = { [1]="close", [2]="close", [3]="push", [4]="ranged" },
            Sukuna = { [1]="close", [2]="close", [3]="ranged", [4]="close" },
            Heian = { [1]="close", [2]="close", [3]="push", [4]="close" },
            Choso = { [1]="ranged", [2]="push", [3]="close" },
            Hakari = { [1]="close", [2]="ranged", [3]="close", [4]="close" },
            Todo = { [1]="close", [2]="close", [3]="ranged", [4]="push" },
            Reggie = { [1]="close", [4]="ranged" },
            MeiMei = { [1]="push", [2]="ranged", [3]="ranged", [4]="ranged" },
            Mechamaru = { [1]="close", [2]="ranged", [3]="close" },
            Megumi = { [1]="ranged", [2]="close", [3]="push", [4]="ranged" },
            Ryu = { [1]="ranged", [2]="push", [3]="close", [4]="ranged" },
            Haruta = { [1]="close", [2]="close", [3]="push", [4]="close" },
            Locust = { [1]="close", [2]="ranged", [3]="close", [4]="push" },
            Goku = { [1]="ranged", [2]="push", [3]="close", [4]="ranged" },
        },
        m1Gap = 0.025,
        m1RetryGap = 0.025,
        getUpWindow = 1.25,
        -- Ragdoll lasts ~1.05 s per level; stand up locally after ~70% of it.
        ragdollRelease = 0.72,
        m1ReadyTimeout = 1.35,
        nextM1ChainGap = 0.2,
        sideDashGap = 0.92,
        forwardDashGap = 3.2,
        resultWindow = 1.15,
        maxHistory = 512,
        poorMoveMinUses = 3,
        poorMoveHitRate = 0.38,
    },
}
controller.pvp = { stage = 3, requestedEnabled = true, paused = false, modules = pvpModules }
env.JujutsuAdaptiveCombat = controller

local intelPath = "JujutsuAdaptiveCombat/opponent_knowledge.json"
pcall(function()
    if type(isfile) == "function" and isfile(intelPath) then
        local decoded = HttpService:JSONDecode(readfile(intelPath))
        if type(decoded) == "table" then
            controller.knowledge = type(decoded.knowledge) == "table" and decoded.knowledge or {}
            controller.matchups = type(decoded.matchups) == "table" and decoded.matchups or {}
            controller.loadoutCoverage = type(decoded.loadoutCoverage) == "table" and decoded.loadoutCoverage or {}
            for signature, entry in pairs(controller.loadoutCoverage) do
                if type(entry) ~= "table" or type(entry.slots) ~= "table" or next(entry.slots) == nil then
                    controller.loadoutCoverage[signature] = nil
                end
            end
        end
    end
end)

local counterNames = {
    ["manji kick"] = true,
    ["door guard"] = true,
    ["parry"] = true,
    ["head splitter"] = true,
    ["supernova"] = true,
    ["brothers"] = true,
    ["domain amplification"] = true,
    ["vengeance"] = true,
    ["i had no idea.."] = true,
    ["shut up!"] = true,
    ["eye catching"] = true,
    ["foresight"] = true,
    ["miracle"] = true,
}

local moveRules = {
    -- Charles (Aspiring Mangaka): Eye Catching is a counter, Sacrilege a ~20 stud spear dash.
    ["despair"] = { range = 8.5, priority = 1, comboPreferred = true },
    ["shut up!"] = { range = 7.5, priority = 2 },
    ["sacrilege"] = { range = 20, priority = 3 },
    ["cursed strikes"] = { range = 7.8, priority = 1, comboPreferred = true },
    ["crushing blow"] = { range = 8.2, priority = 2, comboPreferred = true },
    ["divergent fist"] = { range = 6.8, priority = 3, useTwice = 0.34, comboPreferred = true },
    ["manji kick"] = { range = 7.5 },
    -- Earthquake's native variant window is 0.75-0.90s; the center is the
    -- reliable release point and corresponds to the second shockwave.
    ["earthquake"] = { holdDuration = 0.85, perfectPhase = "Crush2" },
    ["rabbit escape"] = { range = 40 },
    ["divine dog: totality"] = { range = 60, priority = 1 },
    ["blind rage"] = { range = 38, priority = 2 },
    ["sky distortion"] = { range = 55, priority = 1 },
    ["thin ice breaker"] = { range = 16, priority = 3, comboPreferred = true },
    -- Kurourushi tactical assignments
    ["festering strikes"] = { range = 8.2, priority = 2, comboPreferred = true },
    ["chokehold"] = { range = 7.8, priority = 1, comboPreferred = true },
    ["detach"] = { range = 9.0, priority = 3 },
    ["roach swarm"] = { range = 35.0, priority = 4 },
    -- Megumi tactical skills
    ["nue"] = { range = 38.0, priority = 2 },
    ["toad"] = { range = 24.0, priority = 3, comboPreferred = true },
    ["shadow swarm"] = { range = 18.0, priority = 2, comboPreferred = true },
    ["great serpent"] = { range = 26.0, priority = 3 },
    ["max elephant"] = { range = 38.0, priority = 1 },
    -- Hakari tactical skills
    ["rough energy"] = { range = 8.5, priority = 2, comboPreferred = true },
    ["stockpile"] = { range = 9.0, priority = 1, comboPreferred = true },
    -- Choso tactical skills
    ["blood edge"] = { range = 8.0, priority = 2, comboPreferred = true },
    ["supernova"] = { range = 14.0, priority = 3, comboPreferred = true },
    -- Gojo tactical skills
    ["rapid punches"] = { range = 8.0, priority = 2, comboPreferred = true },
    -- Hiromi tactical skills
    ["execution"] = { range = 8.0, priority = 1, comboPreferred = true },
    -- Heian tactical skills
    ["cleave"] = { range = 8.5, priority = 1, comboPreferred = true },
    ["dismantle"] = { range = 25.0, priority = 2 },
    -- Nanami tactical skills
    ["ratio technique"] = { range = 8.0, priority = 1, comboPreferred = true },
    -- Mahito tactical skills
    ["soul fire"] = { range = 8.0, priority = 2, comboPreferred = true },
    -- Ryu tactical skills (Sniper lasers and combo brawling)
    ["granite blast"] = { range = 65.0, priority = 1, holdDuration = 0.68, perfectPhase = "FireHard" },
    ["unsatisfied"] = { range = 18.0, priority = 2, comboPreferred = true },
    ["second helping"] = { range = 35.0, priority = 3 },
    ["appetizer"] = { range = 8.5, priority = 4, comboPreferred = true },
    -- Mechamaru tactical skills (Cannons and Ki lasers)
    ["ultra cannon"] = { range = 65.0, priority = 1, holdDuration = 0.65 },
    ["miracle cannon"] = { range = 65.0, priority = 1 },
    ["kamehameha"] = { range = 65.0, priority = 1, holdDuration = 0.65 },
    ["ki spam"] = { range = 45.0, priority = 2 },
}

-- Megumi's summons have distinct jobs. They are not interchangeable buttons:
-- close pressure belongs to M1, while summons create an entry or catch movement.
local megumiPurposeRules = {
    ["rabbit escape"] = { min = 12, max = 40, role = "cover" },
    ["nue"] = { min = 14, max = 44, role = "ranged_pressure" },
    ["toad"] = { min = 7.5, max = 27, role = "catch" },
    ["divine dog: totality"] = { min = 13, max = 60, role = "pursuit" },
    ["max elephant"] = { min = 12, max = 42, role = "ranged_pressure" },
    ["great serpent"] = { min = 8, max = 30, role = "catch" },
    ["shadow swarm"] = { min = 6, max = 22, role = "close_setup" },
}

local mostlyMeleeMovesets = {
    Itadori = true,
    Hakari = true,
    Todo = true,
    Yuki = true,
    Naoya = true,
    Nanami = true,
    Locust = true,
    Haruta = true,
    Mahito = true,
    Hiromi = true,
    Charles = true,
    Kurourushi = true,
    Heian = true,
    Reggie = true,
}

local rangedMovesets = {
    Gojo = true,
    Megumi = true,
    Choso = true,
    Uro = true,
    MeiMei = true,
    Mechamaru = true,
    Ryu = true,
}

local characterMelee3Durations = {
    Hiromi = 0.433,
    Itadori = 0.350,
    Gojo = 0.350,
    Yuta = 0.350,
    Hakari = 0.350,
    Choso = 0.350,
    Nanami = 0.350,
    Naoya = 0.350,
    Heian = 0.350,
    Sukuna = 0.350,
    Charles = 0.350,
    Mechamaru = 0.350,
    Megumi = 0.333,
    Todo = 0.333,
    Mahito = 0.333,
    Uro = 0.333,
    Yuki = 0.333,
    Locust = 0.333,
    MeiMei = 0.333,
    Kurourushi = 0.333,
    Ryu = 0.333,
    Reggie = 0.333,
    Haruta = 0.350,
    Hanami = 0.350,
}

local function now()
    return workspace:GetServerTimeNow()
end

local function disconnectAll()
    for _, connection in ipairs(controller.connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(controller.connections)
    if clearTargetEvents then clearTargetEvents() end
end

local function log(kind, data)
    local entry = {
        t = now(),
        kind = kind,
        data = data,
    }
    table.insert(controller.history, entry)
    if #controller.history > controller.config.maxHistory then
        table.remove(controller.history, 1)
    end
end

local function characterParts(model)
    if typeof(model)~="Instance" or not model:IsA("Model") or not model.Parent then
        return nil
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
        return nil
    end
    return humanoid, root
end

local function localParts()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end
    local humanoid, root = characterParts(character)
    if not humanoid then
        return nil
    end
    return character, humanoid, root
end

local function distanceTo(model)
    local _, _, localRoot = localParts()
    local _, targetRoot = characterParts(model)
    if not localRoot or not targetRoot then
        return math.huge
    end
    return (localRoot.Position - targetRoot.Position).Magnitude
end

local function getWorkspaceAttribute(name)
    if type(workspace) == "table" or type(workspace) == "userdata" then
        local ga = workspace.GetAttribute
        if type(ga) == "function" then
            local ok, val = pcall(function() return workspace:GetAttribute(name) end)
            if ok then return val end
        end
    end
    return nil
end

local function getGamemodeContext()
    local mode = "FFA"
    if getWorkspaceAttribute("Match") ~= nil then
        mode = "Match"
    elseif getWorkspaceAttribute("Roulette") ~= nil then
        mode = "Roulette"
    elseif getWorkspaceAttribute("FinalShowdown") ~= nil then
        mode = "FinalShowdown"
    elseif getWorkspaceAttribute("NightParade") ~= nil then
        mode = "NightParade"
    end
    local subMode = getWorkspaceAttribute("Gamemode")
    local timer = getWorkspaceAttribute("Timer")
    local teamName = "None"
    if LocalPlayer and LocalPlayer.Team then
        teamName = tostring(LocalPlayer.Team.Name or LocalPlayer.Team)
    end
    local inLobby = (teamName == "Lobby")
    controller.gamemode = mode
    controller.gamemodeSub = subMode
    controller.teamName = teamName
    controller.inLobby = inLobby
    return mode, subMode, teamName, inLobby, timer
end
controller.getGamemodeContext = getGamemodeContext

local function checkBeamQTE()
    if not LocalPlayer then return end
    local playerGui = (type(LocalPlayer.FindFirstChildOfClass) == "function" and LocalPlayer:FindFirstChildOfClass("PlayerGui"))
        or (type(LocalPlayer.FindFirstChild) == "function" and LocalPlayer:FindFirstChild("PlayerGui"))
        or LocalPlayer.PlayerGui
    if not playerGui then return end
    local qte = type(playerGui.FindFirstChild) == "function" and playerGui:FindFirstChild("BeamQTE")
    if qte and qte.Visible ~= false then
        local qtePC = type(qte.FindFirstChild) == "function" and qte:FindFirstChild("QTE_PC")
        if qtePC and qtePC.Text then
            local keyText = tostring(qtePC.Text)
            local keyCode = Enum and Enum.KeyCode and Enum.KeyCode[keyText]
            if keyCode and (not controller.lastBeamQTEAt or os.clock() - controller.lastBeamQTEAt > 0.04) then
                controller.lastBeamQTEAt = os.clock()
                if VirtualInputManager and type(VirtualInputManager.SendKeyEvent) == "function" then
                    pcall(function()
                        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
                        task.delay(0.015, function()
                            VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
                        end)
                    end)
                end
            end
        end
    end
end
controller.checkBeamQTE = checkBeamQTE

local function isCandidate(model)
    if typeof(model) ~= "Instance" or not model:IsA("Model") or model == LocalPlayer.Character then
        return false
    end
    if not model.Parent or model.Parent ~= workspace:FindFirstChild("Characters") then
        return false
    end

    -- Lobby state: If we are in Lobby, we must not acquire or engage targets
    if LocalPlayer and LocalPlayer.Team and LocalPlayer.Team.Name == "Lobby" then
        return false
    end

    -- Target player and team checks
    if Players and type(Players.GetPlayerFromCharacter) == "function" then
        local targetPlayer = Players:GetPlayerFromCharacter(model)
        if targetPlayer and targetPlayer.Team then
            -- Cannot target players who are in the Lobby
            if targetPlayer.Team.Name == "Lobby" then
                return false
            end
            -- Teammate protection in team modes (Duels Sorcerers/Curses, Roulette team games)
            if LocalPlayer and LocalPlayer.Team and LocalPlayer.Team == targetPlayer.Team then
                local teamName = LocalPlayer.Team.Name
                if teamName ~= "Round" and teamName ~= "FFA" and teamName ~= "None" then
                    return false
                end
            end
        end
    end

    return characterParts(model) ~= nil
end

local hasInfo

local function pushBounded(list, value, limit)
    table.insert(list, value)
    if #list > limit then
        table.remove(list, 1)
    end
end

local function knowledgeFor(model)
    local moveset = tostring(model and model:GetAttribute("Moveset") or "Unknown")
    local name = tostring(model and model.Name or "Unknown")
    local key = name .. "|" .. moveset
    local knowledge = controller.knowledge[key]
    if not knowledge then
        knowledge = {
            name = name,
            moveset = moveset,
            samples = 0,
            attacks = 0,
            m1 = 0,
            m2 = 0,
            skills = 0,
            blocks = 0,
            dashes = 0,
            successfulHits = 0,
            damage = 0,
            averageSpeed = 0,
            maxSpeed = 0,
            averageAttackDistance = 0,
            averageAttackHeight = 0,
            attackGeometrySamples = 0,
            attackApproaches = { front = 0, back = 0, left = 0, right = 0 },
            dashDirections = { toward = 0, away = 0, left = 0, right = 0 },
            reactions = { dashAfterOurMove = 0, blockAfterOurMove = 0, attackAfterOurMove = 0 },
            animations = {},
        }
        controller.knowledge[key] = knowledge
    end
    knowledge.dashDirections = knowledge.dashDirections or { toward = 0, away = 0, left = 0, right = 0 }
    knowledge.reactions = knowledge.reactions or { dashAfterOurMove = 0, blockAfterOurMove = 0, attackAfterOurMove = 0 }
    knowledge.attackApproaches = knowledge.attackApproaches or { front = 0, back = 0, left = 0, right = 0 }
    knowledge.averageAttackHeight = tonumber(knowledge.averageAttackHeight) or 0
    knowledge.attackGeometrySamples = tonumber(knowledge.attackGeometrySamples) or 0
    return knowledge
end

local function intelEvent(kind, model, data)
    pushBounded(controller.intelEvents, {
        t = now(),
        kind = kind,
        opponent = model and model.Name or nil,
        moveset = model and model:GetAttribute("Moveset") or nil,
        data = data,
    }, controller.config.maxIntelEvents)
end

local function saveIntel()
    if controller.pvp.SaveTiming then controller.pvp.SaveTiming() end
    if type(writefile) ~= "function" then
        return false
    end
    local ok = pcall(function()
        writefile(intelPath, HttpService:JSONEncode({
            version = controller.version,
            savedAt = os.time(),
            knowledge = controller.knowledge,
            matchups = controller.matchups,
            loadoutCoverage = controller.loadoutCoverage,
        }))
    end)
    return ok
end

local function bindOpponentAnimator(model)
    if controller.animationBound[model] then
        return
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        return
    end
    controller.animationBound[model] = true
    table.insert(controller.connections, animator.AnimationPlayed:Connect(function(track)
        if not controller.running or not isCandidate(model) or distanceTo(model) > controller.config.telemetryRadius then
            return
        end
        if track.Priority.Value < Enum.AnimationPriority.Action.Value then
            return
        end
        local id = ""
        pcall(function()
            id = track.Animation.AnimationId
        end)
        local key = model.Name .. "|" .. id
        if os.clock() - (controller.animationLastSeen[key] or 0) < 0.35 then
            return
        end
        controller.animationLastSeen[key] = os.clock()
        -- Wake the combat loop on the opponent's actual input instead of
        -- waiting for the next polling slice.
        controller.nextThink = 0
        local knowledge = knowledgeFor(model)
        knowledge.animations[id] = (knowledge.animations[id] or 0) + 1
        if controller.pvp.OnOpponentAnimation then controller.pvp.OnOpponentAnimation(model,track,id) end
        local _, root = characterParts(model)
        intelEvent("animation", model, {
            id = id,
            speed = track.Speed,
            x = root and root.Position.X or nil,
            y = root and root.Position.Y or nil,
            z = root and root.Position.Z or nil,
            distance = distanceTo(model),
        })
    end))
end

local function classifyDash(velocity, localRoot, opponentRoot)
    local horizontal = velocity * Vector3.new(1, 0, 1)
    local towardLocal = (localRoot.Position - opponentRoot.Position) * Vector3.new(1, 0, 1)
    if horizontal.Magnitude < 0.01 or towardLocal.Magnitude < 0.01 then
        return "away"
    end
    local forwardDot = horizontal.Unit:Dot(towardLocal.Unit)
    if forwardDot > 0.5 then
        return "toward"
    elseif forwardDot < -0.5 then
        return "away"
    end
    return horizontal.Unit:Dot(localRoot.CFrame.RightVector) >= 0 and "right" or "left"
end

local function recordAttackGeometry(knowledge, opponentRoot, localRoot)
    local localPosition = localRoot.CFrame:PointToObjectSpace(opponentRoot.Position)
    local approach
    if math.abs(localPosition.X) > math.abs(localPosition.Z) * 0.58 then
        approach = localPosition.X >= 0 and "right" or "left"
    else
        approach = localPosition.Z <= 0 and "front" or "back"
    end
    knowledge.attackApproaches[approach] = (knowledge.attackApproaches[approach] or 0) + 1
    knowledge.attackGeometrySamples += 1
    local height = opponentRoot.Position.Y - localRoot.Position.Y
    knowledge.averageAttackHeight += (height - knowledge.averageAttackHeight) / knowledge.attackGeometrySamples
end

local function sampleTelemetry()
    if os.clock() - controller.lastTelemetryAt < controller.config.telemetryInterval then
        return
    end
    controller.lastTelemetryAt = os.clock()

    local character, localHumanoid, localRoot = localParts()
    local folder = workspace:FindFirstChild("Characters")
    if not character or not localRoot or not folder then
        return
    end

    local candidates = {}
    for _, model in ipairs(folder:GetChildren()) do
        if isCandidate(model) then
            local distance = distanceTo(model)
            if distance <= controller.config.telemetryRadius then
                table.insert(candidates, { model = model, distance = distance })
            end
        end
    end
    table.sort(candidates, function(a, b)
        return a.distance < b.distance
    end)

    for index = 1, math.min(#candidates, controller.config.telemetryMaxCandidates) do
        local model = candidates[index].model
        local humanoid, root = characterParts(model)
        local state = controller.telemetryState[model] or {}
        local timestamp = now()
        local velocity = root.AssemblyLinearVelocity
        local horizontalSpeed = (velocity * Vector3.new(1, 0, 1)).Magnitude
        local lastM1 = tonumber(model:GetAttribute("LastM1")) or 0
        local lastM2 = tonumber(model:GetAttribute("LastM2")) or 0
        local blocking = hasInfo and hasInfo(model, "Block") or false
        local inSkill = hasInfo and hasInfo(model, "InSkill") or false
        local stunned = model:GetAttribute("Stun") == true or (hasInfo and hasInfo(model, "Stun")) or false
        local ragdoll = tonumber(model:GetAttribute("Ragdoll")) or 0
        local offset = (root.Position - localRoot.Position) * Vector3.new(1, 0, 1)
        local offsetUnit = offset.Magnitude > 0.01 and offset.Unit or Vector3.zero
        local knowledge = knowledgeFor(model)

        knowledge.samples += 1
        knowledge.averageSpeed += (horizontalSpeed - knowledge.averageSpeed) / knowledge.samples
        knowledge.maxSpeed = math.max(knowledge.maxSpeed, horizontalSpeed)
        bindOpponentAnimator(model)
        if controller.pvp.BindSignals then controller.pvp.BindSignals(model) end

        if state.lastM1 and lastM1 > state.lastM1 then
            knowledge.attacks += 1
            knowledge.m1 += 1
            knowledge.averageAttackDistance += (candidates[index].distance - knowledge.averageAttackDistance) / knowledge.attacks
            recordAttackGeometry(knowledge, root, localRoot)
            intelEvent("m1", model, { distance = candidates[index].distance, combo = model:GetAttribute("CurrentM1") })
            if controller.lastOurMove and controller.lastOurMove.target == model.Name and timestamp - controller.lastOurMove.t <= 0.9 then
                knowledge.reactions.attackAfterOurMove += 1
            end
        end
        if state.lastM2 and lastM2 > state.lastM2 then
            knowledge.attacks += 1
            knowledge.m2 += 1
            knowledge.averageAttackDistance += (candidates[index].distance - knowledge.averageAttackDistance) / knowledge.attacks
            recordAttackGeometry(knowledge, root, localRoot)
            intelEvent("m2", model, { distance = candidates[index].distance })
        end
        if inSkill and not state.inSkill then
            knowledge.skills += 1
            intelEvent("skill_start", model, { distance = candidates[index].distance })
        end
        if blocking and not state.blocking then
            knowledge.blocks += 1
            intelEvent("block_start", model, { distance = candidates[index].distance })
            if controller.lastOurMove and controller.lastOurMove.target == model.Name and timestamp - controller.lastOurMove.t <= 0.9 then
                knowledge.reactions.blockAfterOurMove += 1
            end
        end
        if horizontalSpeed >= 27 and (state.speed or 0) < 21 and ragdoll <= 0 then
            local direction = classifyDash(velocity, localRoot, root)
            knowledge.dashes += 1
            knowledge.dashDirections[direction] = (knowledge.dashDirections[direction] or 0) + 1
            intelEvent("dash", model, { direction = direction, speed = horizontalSpeed, distance = candidates[index].distance })
            if controller.lastOurMove and controller.lastOurMove.target == model.Name and timestamp - controller.lastOurMove.t <= 0.9 then
                knowledge.reactions.dashAfterOurMove += 1
            end
        end

        if model == controller.target or candidates[index].distance <= controller.config.threatDistance + 3 then
            pushBounded(controller.combatTrace, {
                t = timestamp,
                opponent = model.Name,
                moveset = model:GetAttribute("Moveset"),
                x = root.Position.X,
                y = root.Position.Y,
                z = root.Position.Z,
                vx = velocity.X,
                vy = velocity.Y,
                vz = velocity.Z,
                lx = root.CFrame.LookVector.X,
                ly = root.CFrame.LookVector.Y,
                lz = root.CFrame.LookVector.Z,
                distance = candidates[index].distance,
                forward = localRoot.CFrame.LookVector:Dot(offsetUnit),
                side = localRoot.CFrame.RightVector:Dot(offsetUnit),
                health = humanoid.Health,
                m1 = model:GetAttribute("CurrentM1"),
                block = blocking,
                skill = inSkill,
                stun = stunned,
                ragdoll = ragdoll,
                self = {
                    x = localRoot.Position.X, y = localRoot.Position.Y, z = localRoot.Position.Z,
                    health = localHumanoid.Health,
                    skill = hasInfo(character, "InSkill"), block = hasInfo(character, "Block"),
                    stun = hasInfo(character, "Stun") or character:GetAttribute("Stun") == true,
                    ragdoll = character:GetAttribute("Ragdoll"),
                    busy = controller.busy, pendingDash = controller.dashPending ~= nil,
                    lastM1 = character:GetAttribute("LastM1"), currentM1 = character:GetAttribute("CurrentM1"),
                },
            }, controller.config.maxTrace)
        end

        controller.telemetryState[model] = {
            lastM1 = lastM1,
            lastM2 = lastM2,
            blocking = blocking,
            inSkill = inSkill,
            skillStartedAt = inSkill and (state.inSkill and state.skillStartedAt or timestamp) or nil,
            speed = horizontalSpeed,
            health = humanoid.Health,
        }
    end

    if os.clock() - controller.lastIntelSaveAt >= 12 then
        controller.lastIntelSaveAt = os.clock()
        saveIntel()
    end
end

local function closestInCharacterFacing(maxDistance, anyDirection)
    local character, _, localRoot = localParts()
    local folder = workspace:FindFirstChild("Characters")
    if not character or not folder then
        return nil
    end

    local best, bestScore
    local forward = localRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
    if forward.Magnitude < 0.01 then
        return nil
    end
    forward = forward.Unit
    for _, model in ipairs(folder:GetChildren()) do
        if isCandidate(model) then
            local _, root = characterParts(model)
            local offset = (root.Position - localRoot.Position) * Vector3.new(1, 0, 1)
            local distance = offset.Magnitude
            if distance > 0.01 and distance <= maxDistance then
                local facing = forward:Dot(offset.Unit)
                if anyDirection or facing >= controller.config.facingAcquireDot then
                    local score = distance + (1 - facing) * 17
                    if not bestScore or score < bestScore then
                        best = model
                        bestScore = score
                    end
                end
            end
        end
    end
    return best
end

local function getControllers()
    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
    local root = scripts and scripts:FindFirstChild("Controllers")
    local characterFolder = root and root:FindFirstChild("Character")
    if not characterFolder then
        return nil
    end

    local toolModule = characterFolder:FindFirstChild("ToolController")
    local movementModule = characterFolder:FindFirstChild("MovementController")
    if not toolModule or not movementModule then
        return nil
    end

    local okTool, tool = pcall(require, toolModule)
    local okMovement, movement = pcall(require, movementModule)
    if not okTool or not okMovement then
        return nil
    end
    return tool, movement
end

local ToolController, MovementController = getControllers()
if not ToolController or not MovementController then
    warn("[JAC] Native controllers unavailable")
    controller.running = false
    return
end

local ControlModule
pcall(function()
    ControlModule = require(LocalPlayer.PlayerScripts.PlayerModule.ControlModule)
end)

-- ToolController owns the authoritative per-move input contract. Read it at runtime so
-- shuffled/custom inventories keep their real target, aim and movement-vector semantics.
local toolInputModes = {}
pcall(function()
    for index = 1, 20 do
        local ok, value = pcall(debug.getupvalue, ToolController.UseTool, index)
        if not ok then break end
        if type(value) == "table" then
            local numeric, total = 0, 0
            for _, mode in pairs(value) do
                total += 1
                if type(mode) == "number" and mode >= 1 and mode <= 5 then numeric += 1 end
            end
            -- The live controller may keep a small metadata entry beside the
            -- numeric contracts. Identify the table by density, not purity.
            if total >= 10 and numeric >= 10 and numeric / total >= 0.9 then
                toolInputModes = value
                break
            end
        end
    end
end)

local function moveInputMode(move)
    return move and tonumber(toolInputModes[move.Name]) or nil
end

local predictedPosition
local targetThreat
local pingSeconds
local startMicroStep
local BlockService
pcall(function()
    local Knit = require(game:GetService("ReplicatedStorage").Knit.Knit)
    BlockService = Knit.GetService("BlockService")
end)

local function releaseBlock(reason)
    controller.blockSerial += 1
    if controller.blockActive and BlockService and BlockService.Deactivated then
        pcall(BlockService.Deactivated.Fire, BlockService.Deactivated)
    end
    if controller.blockActive then
        log("block_release", reason)
        controller.completedBlockToken = controller.blockToken
        controller.blockReleasedAt = os.clock()
        if controller.pvp.Audit then
            controller.pvp.Audit("pvp_guard_release",{reason=reason,
                target=controller.target and controller.target.Name,
                distance=controller.target and distanceTo(controller.target),
                heldFor=os.clock()-(controller.blockStartedAt or os.clock())})
        end
        controller.blockRearmAt = os.clock() + controller.config.blockRearmGap
        -- Counter-punch: the moment the guard drops, the next M1 plan may start now.
        controller.nextComboAt = 0
        controller.counterPunchUntil = os.clock() + 0.6
    end
    controller.blockActive = false
end

-- A guard budget belongs to one observed attack, not to a global cooldown.
function controller.GuardAttackToken(target)
    if not target then return nil end
    local state = controller.telemetryState[target] or {}
    local observed = controller.pvp.attackObservations[target]
    local special = controller.specialThreats[target]
    return target.Name .. ":" .. tostring(target:GetAttribute("LastM1"))
        .. ":" .. tostring(target:GetAttribute("LastM2")) .. ":" .. tostring(state.skillStartedAt)
        .. ":" .. tostring(observed and observed.startedAt)
        .. ":" .. tostring(special and special.startedAt)
end

function controller.GuardAttackCapped(target)
    return controller.guardCapToken ~= nil
        and controller.guardCapToken == controller.GuardAttackToken(target)
        and os.clock() < (controller.guardCapUntil or 0)
end

local function quickBlock(target, reason)
    if not controller.running or not controller.enabled or not controller.armed
        or (controller.config.focusOnly and target ~= controller.target)
        or not isCandidate(target) or not BlockService or not BlockService.Activated
        or controller.pvp.dashDispatchPending
        or (controller.dashPending and os.clock()<controller.dashPending.deadline) then
        return false
    end
    if controller.config.focusOnly then
        local active, kind = targetThreat(target, distanceTo(target))
        if not active or kind == "learned_approach" or kind == "closing_approach"
            or kind == "movement" then return false end
    end
    if controller.pvp.DefenseDue and not controller.pvp.DefenseDue(target) then return false end
    local token = controller.GuardAttackToken(target)
    if controller.GuardAttackCapped(target) then return false end
    if controller.blockActive then
        if controller.blockToken ~= token then
            controller.blockStartedAt = os.clock()
            controller.blockSerial += 1
        end
        controller.blockLastThreatAt = os.clock()
        controller.blockToken = token
        return true
    end
    local inActiveSkill = hasInfo and hasInfo(target, "InSkill") or false
    local isNewAttack = token ~= controller.completedBlockToken
    -- Counter-punch window: right after dropping the guard, only a NEW attack may
    -- re-raise it; the same exhausted attack must not steal the punch.
    if not isNewAttack and os.clock() < (controller.counterPunchUntil or 0) then return false end
    local effectiveRearm = isNewAttack and 0 or controller.config.blockRearmGap
    if (os.clock() < (controller.blockReleasedAt or 0) + effectiveRearm and os.clock() < controller.blockRearmAt)
        or (not isNewAttack and not inActiveSkill) then
        return false
    end
    if controller.pvp.Cancel then controller.pvp.Cancel("defense_priority") end
    controller.blockSerial += 1
    controller.blockActive = true
    controller.blockToken = token
    controller.blockStartedAt = os.clock()
    controller.blockLastThreatAt = os.clock()
    controller.lastBlockAt = os.clock()
    local ok = pcall(BlockService.Activated.Fire, BlockService.Activated, target)
    if controller.pvp.RecordDefense then controller.pvp.RecordDefense(target,"block",ok,reason) end
    log("block", { target = target and target.Name or nil, reason = reason, ok = ok })
    if not ok then
        controller.blockActive = false
        return false
    end
    return true
end

local function maintainGuard(threat, kind, model)
    if not controller.blockActive then return end
    local isApproach = kind == "learned_approach" or kind == "closing_approach" or kind == "movement"
    local effectiveThreat = threat and not isApproach
    if effectiveThreat then
        quickBlock(model, "hold_threat")
    end
    local clock = os.clock()
    local enemyInSkill = model and isCandidate(model) and hasInfo and hasInfo(model, "InSkill")
    local quietGap = (enemyInSkill and (kind == "skill" or kind == "ranged_skill"))
        and math.max(controller.config.blockQuietTime, 0.38)
        or controller.config.blockQuietTime
    local punishTarget = model or controller.target
    local dist = punishTarget and isCandidate(punishTarget) and distanceTo(punishTarget) or 999
    local heldFor = clock - controller.blockStartedAt
    -- quickBlock has already renewed blockStartedAt if a NEW attack arrived.
    -- Only the exhausted attack token is capped; new attacks bypass this lease.
    -- Head-on clash: M1 strings are short, so release sooner (0.5 s) to punish;
    -- a real skill from the target keeps the longer 0.9 s guard.
    local closeCap = enemyInSkill and 0.9 or 0.5
    if heldFor >= (dist <= controller.config.m1Range + 2 and closeCap or 1.1) then
        controller.guardCapToken = controller.blockToken
        controller.guardCapUntil = clock + 0.6
        if controller.pvp.Audit then
            controller.pvp.Audit("pvp_guard_cap", {kind=kind,distance=dist,heldFor=heldFor,
                target=punishTarget and punishTarget.Name,token=controller.blockToken})
        end
        releaseBlock("guard_hard_cap")
        return
    end
    if not effectiveThreat and dist <= controller.config.m1Range and clock - controller.blockStartedAt >= 0.05 then
        releaseBlock("threat_ended_punish_now")
    elseif not effectiveThreat and clock - controller.blockStartedAt >= controller.config.blockMaxDuration then
        releaseBlock("guard_budget")
    elseif not effectiveThreat and clock - controller.blockLastThreatAt >= quietGap then
        releaseBlock("threat_ended")
    end
end

local function clearFullLockState()
    MovementController.LockOn = nil
    LocalPlayer:SetAttribute("LockOn", nil)
    local controls = LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("Controls")
    local marker = controls and controls:FindFirstChild("LockTarget")
    if marker then
        marker.Adornee = nil
        marker.Enabled = false
    end
end

function controller.HasManualInput()
    if UserInputService:GetFocusedTextBox() then return true end
    for _, key in ipairs({Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
        Enum.KeyCode.Space, Enum.KeyCode.Q, Enum.KeyCode.Up, Enum.KeyCode.Down,
        Enum.KeyCode.Left, Enum.KeyCode.Right}) do
        if UserInputService:IsKeyDown(key) then return true end
    end
    if controller.ReadManualMove then
        local ok, vector = pcall(controller.ReadManualMove)
        if ok and typeof(vector)=="Vector3" and vector.Magnitude > 0.08 then return true end
    end
    return false
end

local function releaseBodyFacing()
    if controller.bodyAlign then
        controller.bodyAlign:Destroy()
        controller.bodyAlign = nil
    end
    if controller.bodyAttachmentOwned and controller.bodyAttachment then
        controller.bodyAttachment:Destroy()
    end
    controller.bodyAttachment = nil
    controller.bodyAttachmentOwned = false

    local humanoid = controller.bodyHumanoid
    if humanoid and humanoid.Parent and controller.bodyOriginalAutoRotate ~= nil then
        -- Always return rotation to the engine default; a captured "false" (left by a
        -- previous load or a native lock) is what froze the character facing sideways.
        humanoid.AutoRotate = true
    end
    controller.bodyHumanoid = nil
    controller.bodyOriginalAutoRotate = nil
    controller.bodyLeaseUntil = 0
end

local function updateBodyFacing(character, humanoid, root, target, escapeDirection)
    local _, targetRoot = characterParts(target)
    if not controller.running or not controller.enabled or not controller.armed
        or not isCandidate(target) or not targetRoot
        or (targetRoot.Position-root.Position).Magnitude > controller.config.bodyTrackDistance
        or (tonumber(character:GetAttribute("Ragdoll")) or 0) > 0 then
        releaseBodyFacing()
        return
    end

    if root:FindFirstChildOfClass("BodyGyro") then
        releaseBodyFacing()
        return
    end

    if not controller.bodyAlign or controller.bodyAlign.Parent ~= root then
        releaseBodyFacing()
        local attachment = root:FindFirstChild("RootAttachment")
        if not attachment then
            attachment = Instance.new("Attachment")
            attachment.Name = "JACBodyAttachment"
            attachment.Parent = root
            controller.bodyAttachmentOwned = true
        end
        local align = Instance.new("AlignOrientation")
        align.Name = "JACBodyFacing"
        align.Mode = Enum.OrientationAlignmentMode.OneAttachment
        align.Attachment0 = attachment
        align.MaxTorque = math.huge
        align.MaxAngularVelocity = 120
        align.Responsiveness = 100
        align.RigidityEnabled = true
        align.Parent = root
        controller.bodyAttachment = attachment
        controller.bodyAlign = align
        controller.bodyHumanoid = humanoid
        controller.bodyOriginalAutoRotate = true
    end

    local aim = predictedPosition(target) or targetRoot.Position
    -- Native dash forces use body axes: preserve their short dispatch heading,
    -- then immediately return to the duel heading instead of walking/camera yaw.
    local dashHeading = os.clock() < (controller.nativeDashHeadingUntil or 0)
        and controller.escapeDirection
    local direction = (controller.config.focusOnly and dashHeading)
        or (not controller.config.focusOnly and escapeDirection)
        or Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
    if direction.Magnitude > 0.01 then
        controller.bodyLeaseUntil = os.clock() + 0.35
        humanoid.AutoRotate = false
        controller.bodyAlign.Enabled = true
        controller.bodyAlign.CFrame = CFrame.lookAt(Vector3.zero, direction.Unit)
        local curPos = root.Position
        root.CFrame = CFrame.lookAt(curPos, curPos + direction.Unit)
    end
end

local function faceForAction(target, overrideDuration)
    local character, humanoid, root = localParts()
    if not controller.running or not controller.enabled or not controller.armed
        or controller.target ~= target or not character or not isCandidate(target)
        or distanceTo(target) > controller.config.bodyTrackDistance
        or os.clock() < controller.escapeUntil then
        return
    end
    local duration = overrideDuration or controller.config.bodyFaceDuration
    controller.bodyFaceUntil = math.max(controller.bodyFaceUntil, os.clock() + duration)
    controller.bodyFaceSerial += 1
    local serial = controller.bodyFaceSerial
    updateBodyFacing(character, humanoid, root, target)
    task.delay(duration, function()
        if controller.bodyFaceSerial == serial and os.clock() >= controller.bodyFaceUntil
            and not (controller.config.focusOnly and controller.armed and isCandidate(controller.target))
            and not (character and hasInfo and hasInfo(character, "InSkill")) then
            releaseBodyFacing()
        end
    end)
end

local function shouldTrackHeading(character, target, distance)
    if not controller.running or not controller.enabled or not controller.armed
        or not character or not target or not isCandidate(target)
        or (tonumber(character:GetAttribute("Ragdoll")) or 0) > 0
        or (distance and distance > controller.config.bodyTrackDistance)
        or (not controller.config.focusOnly and os.clock() < controller.escapeUntil) then
        return false
    end
    -- Native camera lock may disappear; the selected duel target still owns heading.
    if controller.config.focusOnly then return true end
    -- In active skill or special execution (manual or automatic)
    if hasInfo and hasInfo(character, "InSkill") then return true end
    if os.clock() < controller.bodyFaceUntil then return true end
    if controller.busy or controller.comboBusy then return true end
    if controller.observedSkill ~= nil or controller.pendingMove ~= nil or controller.sustainedSpecialSteering ~= nil then
        return true
    end
    -- Close range combo requested
    if controller.comboRequested and distance and distance <= controller.config.m1Range then
        return true
    end
    -- Ranged special aiming/readiness
    local moveset = character:GetAttribute("Moveset")
    if rangedMovesets and rangedMovesets[moveset] == true then return true end
    local selected = controller.pvp and controller.pvp.selectedItem
    if selected and (selected.kind == "ranged" or (selected.range and selected.range.max and selected.range.max > 12)) then
        return true
    end
    -- Shift Lock active with candidate target: maintain target heading tracking
    if _G.Shift == true then return true end
    return false
end

local clearTargetEvents
local bindTargetEvents

local function clearTarget(reason)
    controller.armed = false
    controller.moveIntent = nil
    controller.sustainedSpecialSteering = nil
    releaseBodyFacing()
    if controller.pvp.Cancel then pcall(controller.pvp.Cancel, reason) end
    if controller.pvp.dynamic then pcall(controller.pvp.dynamic.reset, controller.pvp.dynamic) end
    if controller.pvp.movement then pcall(controller.pvp.movement.reset, controller.pvp.movement) end
    controller.pvp.opponentCache=nil
    controller.pvp.nextMovementPlanAt=0
    local old = controller.target
    controller.targetGeneration += 1
    controller.actionSerial += 1
    controller.bodyFaceSerial += 1
    controller.microStepSerial += 1
    controller.escapeUntil = 0
    controller.escapeDirection = nil
    controller.dashPending = nil
    controller.acquireUntil = 0
    controller.moveIntent = nil
    controller.pathTarget = nil
    controller.pathWaypoints = nil
    controller.pathIndex = 2
    controller.nextPathAt = 0
    controller.pathBusy = false
    controller.pathRequestSerial += 1
    controller.targetProgress = nil
    controller.downCharacter = nil
    controller.finisherCommitUntil = 0
    controller.steeringUntil = 0
    controller.recentEntry = nil
    controller.wasDown = false
    controller.getUpRequest = nil
    controller.bodyFaceUntil = 0
    controller.finisherTarget = nil
    controller.finisherUntil = 0
    controller.lastDownslamAt = 0
    controller.lastDownslamTarget = nil
    controller.recoveryRequest = nil
    controller.observedSkill = nil
    controller.pendingMove = nil
    controller.specialApproachPending = nil
    controller.specialFollowupUntil = 0
    controller.sustainedSpecialSteering = nil
    controller.armed = false
    controller.target = nil
    controller.guardCapToken = nil
    controller.guardCapUntil = 0
    controller.completedBlockToken = nil
    controller.busy = false
    controller.comboBusy = false
    controller.comboSerial += 1
    controller.comboRequested = false
    controller.pendingEvadeUntil = 0
    controller.pendingThreat = nil
    controller.pendingThreatKind = nil
    controller.manualDashBufferedUntil = 0
    controller.lostTargetAt = 0
    releaseBodyFacing()
    releaseBlock("target_clear")
    clearFullLockState()
    if clearTargetEvents then clearTargetEvents() end
    log("target_clear", reason)
end

local function hookToolControllerAiming()
    if not ToolController then return end
    if not controller.aimHooksInstalled then
        controller.aimHooksInstalled = true
        local origTarget = ToolController.GetTarget
        local origTargetOrProj = ToolController.GetTargetOrProjectile
        local origMouseTarget = ToolController.GetMouseTarget
        controller.origTarget = origTarget
        controller.origTargetOrProj = origTargetOrProj
        controller.origMouseTarget = origMouseTarget

        ToolController.GetTarget = function(self, ...)
            if controller.running and controller.enabled and controller.armed and controller.target and isCandidate(controller.target) then
                return controller.target
            end
            local orig = controller.origTarget
            if type(orig) == "function" then
                return orig(self, ...)
            end
            return nil
        end

        ToolController.GetTargetOrProjectile = function(self, ...)
            if controller.running and controller.enabled and controller.armed and controller.target and isCandidate(controller.target) then
                return controller.target
            end
            local orig = controller.origTargetOrProj
            if type(orig) == "function" then
                return orig(self, ...)
            end
            return nil
        end

        ToolController.GetMouseTarget = function(self, maxDist, ...)
            if controller.running and controller.enabled and controller.armed and controller.target and isCandidate(controller.target) then
                local aim = predictedPosition and predictedPosition(controller.target)
                if not aim then
                    local _, targetRoot = characterParts(controller.target)
                    aim = targetRoot and targetRoot.Position
                end
                if aim then
                    return aim
                end
            end
            local orig = controller.origMouseTarget
            if type(orig) == "function" then
                return orig(self, maxDist, ...)
            end
            return Vector3.zero
        end
    end
end

local function armTarget(target)
    if not isCandidate(target) or distanceTo(target) > controller.config.acquireDistance then
        return false
    end
    if controller.target ~= target then
        clearTarget("retarget")
    end
    controller.target = target
    controller.pvp.switchAfter=os.clock()+.9
    controller.armed = true
    hookToolControllerAiming()
    -- A re-arm is a new chase. Never inherit the no-progress deadline from a
    -- previous opponent or from an earlier engagement with this same target.
    controller.targetProgress = nil
    controller.comboRequested = true
    controller.comboStartLastM1 = tonumber(LocalPlayer.Character and LocalPlayer.Character:GetAttribute("LastM1")) or 0
    controller.nextComboAt = 0
    controller.lostTargetAt = 0
    clearFullLockState()
    log("target_arm", {
        name = target.Name,
        moveset = target:GetAttribute("Moveset"),
        distance = distanceTo(target),
    })
    print(string.format("[JAC v%s] Target: %s | %s", controller.version, target.Name, tostring(target:GetAttribute("Moveset") or "Unknown")))
    if bindTargetEvents then bindTargetEvents(target) end
    return true
end

-- Dynamic re-targeting: when the current rival dies, leaves or drifts out of range,
-- move to the best remaining rival instead of dropping the whole fight ("invalid").
local function pickReplacementTarget(exclude)
    local _, _, localRoot = localParts()
    local folder = workspace:FindFirstChild("Characters")
    if not localRoot or not folder then return nil end
    local maxDistance = controller.config.reacquireDistance or 90
    local best, bestScore
    for _, model in ipairs(folder:GetChildren()) do
        if model ~= exclude and isCandidate(model) then
            local _, root = characterParts(model)
            local distance = (root.Position - localRoot.Position).Magnitude
            if distance <= maxDistance and math.abs(root.Position.Y - localRoot.Position.Y) <= 40 then
                local score = distance
                if not Players:GetPlayerFromCharacter(model) then score += 25 end
                if (model:GetAttribute("Ragdoll") or 0) ~= 0 then score += 12 end
                if not bestScore or score < bestScore then
                    best, bestScore = model, score
                end
            end
        end
    end
    return best
end

local function tryReacquire(old, reason)
    if controller.config.autoReacquire == false then return false end
    local nextTarget = pickReplacementTarget(old)
    if not nextTarget then return false end
    log("target_reacquire", { from = old and old.Name, to = nextTarget.Name, reason = reason })
    return armTarget(nextTarget)
end

hasInfo = function(character, name)
    local info = character and character:FindFirstChild("Info")
    return info and info:FindFirstChild(name) ~= nil
end

local function canAct(character, allowInSkill)
    if not character or not character.Parent then
        return false
    end
    if (tonumber(character:GetAttribute("Ragdoll")) or 0) > 0 then
        return false
    end
    if character:GetAttribute("Stun") == true then
        return false
    end
    if hasInfo(character, "Stun") or hasInfo(character, "Block") then
        return false
    end
    if not allowInSkill and hasInfo(character, "InSkill") then
        return false
    end
    return true
end

local function m1UnavailableReason(character)
    if not character or not character.Parent then return "no_character" end
    if controller.blockActive or hasInfo(character,"Block") then return "guard_active" end
    if (tonumber(character:GetAttribute("Ragdoll")) or 0)>0 then return "ragdolled" end
    if character:GetAttribute("Stun")==true or hasInfo(character,"Stun") then return "stunned" end
    if controller.observedSkill then return "native_skill_active" end
end

local function canQueueM1(character)
    -- M1 itself sets InSkill. Buffer native input without changing its cooldown or animation.
    return m1UnavailableReason(character)==nil
end

-- Both native clicks and automatic requests share one bounded outstanding slot.
-- Clear by native token advance. Native retries expire after 0.18 s;
-- an engine dispatch keeps ownership through its bounded acknowledgement window.
local function m1RequestPending(character)
    if not character then return false end
    local p=controller.pvp
    local token=character:GetAttribute("LastM1")
    local native=p.nativeM1Pending
    if native and native.token==token and os.clock()-native.time<0.1 then return true end
    local pending=p.combo and p.combo.pending
    return pending and pending.kind=="m1" and pending.dispatchedAt~=nil
        and pending.token==token and os.clock()-pending.dispatchedAt<p.combo.profile.ackTimeout or false
end

local function setMoveIntent(direction, duration, allowInSkill, contactStopDistance)
    controller.moveIntent = {
        character = LocalPlayer.Character, generation = controller.targetGeneration,
        direction = direction, deadline = os.clock() + duration,
        allowInSkill = allowInSkill == true, contactStopDistance = contactStopDistance,
    }
end

local function purgeFacingOrphans()
    -- Remove facing constraints left by an older/crashed load (not owned by this controller).
    local character, humanoid, root = localParts()
    if not character or not root then return end
    for _, child in ipairs(root:GetChildren()) do
        if (child.Name == "JACBodyFacing" and child ~= controller.bodyAlign)
            or (child.Name == "JACBodyAttachment" and child ~= controller.bodyAttachment) then
            child:Destroy()
        end
    end
    if humanoid and not controller.bodyAlign then
        if humanoid.AutoRotate == false then
            local now = os.clock()
            controller.autoRotateOffSince = controller.autoRotateOffSince or now
            local native = (tonumber(character:GetAttribute("Ragdoll")) or 0) > 0 or humanoid.PlatformStand
                or humanoid.Sit or MovementController.LockOn ~= nil
            if now - controller.autoRotateOffSince > 0.4 and not native then
                humanoid.AutoRotate = true
                controller.autoRotateOffSince = nil
            end
        else
            controller.autoRotateOffSince = nil
        end
    end
end

local function maintainAutoMovement()
    pcall(purgeFacingOrphans)
    -- Independent of think(): every facing update expires, including early returns/errors.
    if controller.bodyAlign and (os.clock() >= (controller.bodyLeaseUntil or 0)
        or not controller.running or not controller.enabled or not controller.armed
        or not isCandidate(controller.target)) then
        releaseBodyFacing()
    end
    controller.manualOverride = false
    if controller.pvp.HoldJump then controller.pvp.HoldJump() end
    local intent = controller.moveIntent
    if not intent then return end
    local character, humanoid, root = localParts()
    if not controller.running or not controller.enabled or not controller.armed
        or intent.generation ~= controller.targetGeneration or character ~= intent.character
        or os.clock() >= intent.deadline or not canAct(character, intent.allowInSkill) then
        controller.moveIntent = nil
        return
    end
    if controller.target and root then
        local _, targetRoot = characterParts(controller.target)
        if targetRoot then
            local horiz = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
            if intent.contactStopDistance and horiz.Magnitude <= intent.contactStopDistance then
                controller.moveIntent = nil
                if not controller.HasManualInput() then humanoid:Move(Vector3.zero, false) end
                return
            end
            if horiz.Magnitude > 0.01 and horiz.Magnitude < 3.6 and intent.direction:Dot(horiz.Unit) > 0.3 then
                controller.moveIntent = nil
                humanoid:Move(Vector3.zero, false)
                return
            end
        end
    end
    local moveDir = intent.direction
    if controller.HasManualInput() and humanoid and humanoid.MoveDirection.Magnitude > 0.08 then
        moveDir = (humanoid.MoveDirection * 0.6 + intent.direction * 0.4).Unit
    end
    humanoid:Move(moveDir, false)
end

local function maintainHeadingTracking()
    if not controller.running or not controller.enabled or not controller.armed then return end
    local target = controller.target
    if not target or not isCandidate(target) then return end
    local character, humanoid, root = localParts()
    if not character or not humanoid or not root then return end
    local distance = distanceTo(target)
    if shouldTrackHeading(character, target, distance) then
        local isLateralDash = (controller.dashPending and (controller.dashPending.direction == "Left" or controller.dashPending.direction == "Right"))
            or (controller.pvp and controller.pvp.dashDispatchPending)
        local isAttacking = (hasInfo and hasInfo(character, "InSkill")) or controller.busy or controller.comboBusy
            or controller.observedSkill ~= nil or controller.pendingMove ~= nil or controller.sustainedSpecialSteering ~= nil
            or (controller.comboRequested and distance and distance <= controller.config.m1Range)
        local activeMoveDir = (humanoid.MoveDirection.Magnitude > 0.08 and humanoid.MoveDirection)
            or (controller.moveIntent and controller.moveIntent.direction.Magnitude > 0.08 and controller.moveIntent.direction)
        if not controller.config.focusOnly and not isAttacking and not isLateralDash and activeMoveDir then
            local moveFlat = Vector3.new(activeMoveDir.X, 0, activeMoveDir.Z)
            if moveFlat.Magnitude > 0.05 then
                local unit = moveFlat.Unit
                root.CFrame = CFrame.lookAt(root.Position, root.Position + unit)
                if controller.bodyAlign and controller.bodyAlign.Enabled then
                    controller.bodyAlign.CFrame = CFrame.lookAt(Vector3.zero, unit)
                end
                return
            end
        end
        updateBodyFacing(character, humanoid, root, target)
        if os.clock() < (controller.nativeDashHeadingUntil or 0) then return end
        local _, targetRoot = characterParts(target)
        if targetRoot then
            local aim = predictedPosition(target) or targetRoot.Position
            local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
            if flat.Magnitude > 0.05 then
                local unit = flat.Unit
                root.CFrame = CFrame.lookAt(root.Position, root.Position + unit)
                if controller.bodyAlign and controller.bodyAlign.Enabled then
                    controller.bodyAlign.CFrame = CFrame.lookAt(Vector3.zero, unit)
                end
            end
        end
    end
end

local function manualMovementActive()
    return controller.HasManualInput()
end

local function manualEscapeIsWorking(threatModel)
    local _, humanoid, root = localParts()
    local _, threatRoot = characterParts(threatModel)
    if not humanoid or not root or not threatRoot or humanoid.MoveDirection.Magnitude < 0.1 then
        return false
    end
    local away = (root.Position - threatRoot.Position) * Vector3.new(1, 0, 1)
    if away.Magnitude < 0.01 then
        return false
    end
    return humanoid.MoveDirection.Unit:Dot(away.Unit) > 0.22
end

local function targetDisabled(target)
    if not target then
        return true
    end
    if (tonumber(target:GetAttribute("Ragdoll")) or 0) > 0 then
        return true
    end
    if target:GetAttribute("Stun") == true or hasInfo(target, "Stun") then
        return true
    end
    return false
end

pingSeconds = function()
    local value = 0.05
    pcall(function()
        value = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    end)
    return math.clamp(value, 0.02, 0.18)
end

predictedPosition = function(target)
    local _, root = characterParts(target)
    if not root then
        return nil
    end
    local lead = math.clamp(0.07 + pingSeconds() * 0.55, 0.08, 0.17)
    local horizontalVelocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
    if horizontalVelocity.Magnitude > 55 then
        horizontalVelocity = horizontalVelocity.Unit * 55
    end
    local verticalVelocity = root.AssemblyLinearVelocity.Y or 0
    local verticalLead = math.clamp(verticalVelocity * lead, -6, 8)
    return root.Position + horizontalVelocity * lead + Vector3.new(0, verticalLead, 0)
end

local function moveReady(move)
    if not move or not move.Parent then
        return false
    end
    local readyAt = tonumber(move:GetAttribute("ReadyAt")) or 0
    return now() >= readyAt
end

local function moveForKey(key)
    local ok, move = pcall(ToolController.ReturnKey, ToolController, key)
    if ok then
        return move
    end
    return nil
end

local nativeControlMoveVector = previousController and previousController.nativeControlMoveVector or (ControlModule and ControlModule.GetMoveVector)
controller.nativeControlMoveVector = nativeControlMoveVector
controller.ReadManualMove = function()
    local active = ControlModule and ControlModule.activeController
    return active and active:GetMoveVector() or Vector3.zero
end

local function movementInputForTarget(character, target)
    local _, ownRoot = characterParts(character)
    local aim = predictedPosition(target)
    if not ownRoot or not aim then return nil, nil end
    local worldDirection = (aim - ownRoot.Position) * Vector3.new(1, 0, 1)
    if worldDirection.Magnitude <= 0.01 then return nil, nil end
    worldDirection = worldDirection.Unit
    local camera = workspace.CurrentCamera
    local frame = camera and camera.CFrame or ownRoot.CFrame
    local right = Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z)
    if right.Magnitude <= 0.01 then return nil, nil end
    right = right.Unit
    local forward = Vector3.new(right.Z, 0, -right.X)
    return Vector3.new(worldDirection:Dot(right), 0, -worldDirection:Dot(forward)), worldDirection
end

local function requestNativeAir(character, stillCurrent, timeout)
    local current, humanoid, root = localParts()
    if current ~= character or not humanoid or not root then return false end
    if humanoid.FloorMaterial == Enum.Material.Air then return true end
    local pressed = pcall(VirtualInputManager.SendKeyEvent, VirtualInputManager,
        true, Enum.KeyCode.Space, false, game)
    if ControlModule and ControlModule.activeController then
        ControlModule.activeController.jumpRequested = true
    end
    humanoid.Jump = true
    pcall(humanoid.ChangeState, humanoid, Enum.HumanoidStateType.Jumping)
    local deadline = os.clock() + (timeout or 0.46)
    repeat
        RunService.Heartbeat:Wait()
    until not stillCurrent() or humanoid.FloorMaterial == Enum.Material.Air or os.clock() >= deadline
    if pressed then
        pcall(VirtualInputManager.SendKeyEvent, VirtualInputManager,
            false, Enum.KeyCode.Space, false, game)
    end
    return stillCurrent() and humanoid.FloorMaterial == Enum.Material.Air
end

if ControlModule and nativeControlMoveVector then
    ControlModule.GetMoveVector = function(self, ...)
        local nativeVec = nativeControlMoveVector(self, ...)
        local steering = controller.sustainedSpecialSteering
        if steering then
            local invalid = not controller.running or not controller.enabled or not controller.armed
                or steering.character ~= LocalPlayer.Character
                or steering.generation ~= controller.targetGeneration
                or os.clock() >= steering.deadline or not isCandidate(steering.target)
                or (steering.carrier and not steering.carrier.Parent)
            if invalid then
                controller.sustainedSpecialSteering = nil
            else
                local input = movementInputForTarget(steering.character, steering.target)
                if input then
                    if nativeVec and nativeVec.Magnitude > 0.08 then
                        return (nativeVec * 0.55 + input * 0.45).Unit
                    end
                    return input
                end
            end
        end
        local intent = controller.moveIntent
        if intent and intent.direction and os.clock() < (intent.deadline or 0) then
            local cam = workspace.CurrentCamera
            if cam then
                local camRel = cam.CFrame:VectorToObjectSpace(intent.direction)
                camRel = Vector3.new(camRel.X, 0, camRel.Z)
                if camRel.Magnitude > 0.08 then
                    local autoUnit = camRel.Unit
                    if nativeVec and nativeVec.Magnitude > 0.08 then
                        return (nativeVec * 0.6 + autoUnit * 0.4).Unit
                    end
                    return autoUnit
                end
            end
        end
        return nativeVec
    end
end

local function serviceSupportsDeactivate(serviceName)
    if type(serviceName) ~= "string" or serviceName == "" then return false end
    local ok, supported = pcall(function()
        local services = game:GetService("ReplicatedStorage").Knit.Knit.Services
        local folder = services:FindFirstChild(serviceName)
        local remotes = folder and folder:FindFirstChild("RE")
        return remotes and remotes:FindFirstChild("Deactivated") ~= nil
    end)
    return ok and supported == true
end

local function captureLoadout(character)
    local snapshot = { character = character, moveset = character and character:GetAttribute("Moveset"), slots = {} }
    for key = 1, 4 do
        local move = moveForKey(key)
        if move then
            local serviceName = move:GetAttribute("Service")
            snapshot.slots[key] = { move = move, name = move.Name,
                service = serviceName, tip = move:GetAttribute("Tip"),
                inputMode = moveInputMode(move),
                supportsDeactivate = serviceSupportsDeactivate(serviceName) }
        end
    end
    return snapshot
end

local function sameLoadout(a, b)
    if not a or not b or a.character ~= b.character or a.moveset ~= b.moveset then return false end
    for key = 1, 4 do
        local left, right = a.slots[key], b.slots[key]
        if (left == nil) ~= (right == nil) then return false end
        -- Tool instances are recreated by some movesets without changing the
        -- loadout. Compare the stable contract so this cannot cancel combos.
        if left and (left.name ~= right.name
            or left.service ~= right.service or left.tip ~= right.tip
            or left.inputMode ~= right.inputMode
            or left.supportsDeactivate ~= right.supportsDeactivate) then return false end
    end
    return true
end

local function bindMoveObserver(slot)
    local serviceName = slot and slot.service
    if type(serviceName) ~= "string" or serviceName == ""
        or controller.moveObservers[serviceName] then return end
    local ok = pcall(function()
        local Knit = require(game:GetService("ReplicatedStorage").Knit.Knit)
        local service = Knit.GetService(serviceName)
        local connection = service.Effects:Connect(function(...)
            local args = { ... }
            local phase = tostring(args[1])
            local ownEffect = false
            for index = 1, math.min(#args, 6) do
                if args[index] == LocalPlayer.Character then ownEffect = true break end
            end
            local pending = controller.pendingMove
            local nearbyPerfect = false
            if not ownEffect and phase == "Crush2" and serviceName == "EarthquakeService"
                and pending and pending.service == serviceName then
                local _, root = localParts()
                if root then
                    local okNearby, isNearby = pcall(function()
                        return (args[2] - root.Position).Magnitude <= 16
                    end)
                    nearbyPerfect = okNearby and isNearby
                end
            end
            if (ownEffect or nearbyPerfect) and pending and pending.service == serviceName
                and pending.generation == controller.targetGeneration
                and os.clock() <= pending.deadline then
                pending.nativeAccepted = true
                pending.phase = phase
                if phase == "Crush2" then
                    pending.perfect = true
                    if pending.releaseCallback then
                        pcall(pending.releaseCallback)
                        pending.releaseCallback = nil
                    end
                end
                if serviceName == "BirdControlService" and phase == "Flight" and ownEffect then
                    controller.sustainedSpecialSteering = {
                        character = LocalPlayer.Character,
                        target = pending.target or controller.target,
                        generation = pending.generation,
                        carrier = args[3],
                        deadline = os.clock() + 8,
                    }
                    log("movement_special_steering", { name = pending.name, phase = phase })
                end
            end
        end)
        table.insert(controller.connections, connection)
    end)
    controller.moveObservers[serviceName] = ok and "connected" or "unavailable"
end

local function loadoutCurrent(snapshot)
    return sameLoadout(snapshot, captureLoadout(LocalPlayer.Character))
end

local function recordLoadoutCoverage(snapshot)
    local parts = { tostring(snapshot.moveset or "Unknown") }
    local slots = {}
    local slotCount = 0
    for key = 1, 4 do
        local slot = snapshot.slots[key]
        local label = slot and (slot.name .. "@" .. tostring(slot.service)) or "nil"
        table.insert(parts, label)
        if slot then
            slotCount += 1
            slots[key] = { name = slot.name, service = slot.service, inputMode = slot.inputMode,
                supportsDeactivate = slot.supportsDeactivate }
        end
    end
    if slotCount == 0 then return nil end
    local signature = table.concat(parts, "|")
    local entry = controller.loadoutCoverage[signature]
    if not entry then
        entry = { moveset = snapshot.moveset, slots = slots, firstSeen = now(), seen = 0 }
        controller.loadoutCoverage[signature] = entry
    end
    entry.lastSeen = now()
    entry.seen = (entry.seen or 0) + 1
    return signature
end

local function syncLoadout(character)
    local snapshot = captureLoadout(character)
    for key = 1, 4 do bindMoveObserver(snapshot.slots[key]) end
    local serviceName = tostring(snapshot.moveset or "") .. "Service"
    if not controller.chaseObservers[serviceName] then
        local ok = pcall(function()
            local Knit = require(game:GetService("ReplicatedStorage").Knit.Knit)
            local connection = Knit.GetService(serviceName).Effects:Connect(function(phase, model, ...)
                local pending = controller.dashPending
                if phase == "Chase" and model == LocalPlayer.Character and pending
                    and pending.character == model and pending.direction == "Front"
                    and pending.generation == controller.targetGeneration
                    and os.clock() <= pending.deadline then pending.nativeAccepted = true end
                local special = controller.specialApproachPending
                if special and special.service == serviceName and special.expectedPhases[phase]
                    and special.generation == controller.targetGeneration and os.clock() <= special.deadline then
                    local ownEffect = model == LocalPlayer.Character
                    if not ownEffect then
                        for _, value in ipairs({ ... }) do
                            if value == LocalPlayer.Character then ownEffect = true break end
                        end
                    end
                    if ownEffect then
                        special.accepted = true
                        controller.specialApproachPending = nil
                        controller.comboRequested = true
                        controller.nextComboAt = 0
                        log("special_approach_accepted", { name = special.name, phase = phase,
                            target = special.target and special.target.Name })
                    end
                end
            end)
            table.insert(controller.connections, connection)
        end)
        controller.chaseObservers[serviceName] = ok and "connected" or "unavailable"
    end
    if sameLoadout(controller.loadout, snapshot) then return end
    local signature = recordLoadoutCoverage(snapshot)
    local previous = controller.loadout
    controller.loadout = snapshot
    if not previous then return end
    controller.actionSerial += 1
    controller.comboSerial += 1
    controller.microStepSerial += 1
    controller.busy = false
    controller.comboBusy = false
    controller.comboRequested = false
    controller.recoveryRequest = nil
    controller.observedSkill = nil
    controller.pendingMove = nil
    controller.escapeUntil = 0
    controller.escapeDirection = nil
    releaseBlock("loadout_changed")
    releaseBodyFacing()
    log("loadout_changed", { moveset = snapshot.moveset, signature = signature })
end

local function matchupBucket(localMoveset, enemyMoveset, moveName)
    local matchupKey = tostring(localMoveset or "Unknown") .. "->" .. tostring(enemyMoveset or "Unknown")
    local matchup = controller.matchups[matchupKey]
    if not matchup then
        matchup = { uses = 0, hits = 0, damage = 0, moves = {} }
        controller.matchups[matchupKey] = matchup
    end
    local move = matchup.moves[moveName]
    if not move then
        move = { uses = 0, hits = 0, accepted = 0, acceptanceSamples = 0, damage = 0,
            maxAcceptedDistance = 0, maxHitDistance = 0, rejected = 0 }
        matchup.moves[moveName] = move
    end
    move.accepted = tonumber(move.accepted) or 0
    move.acceptanceSamples = tonumber(move.acceptanceSamples) or 0
    move.rejected = tonumber(move.rejected) or 0
    move.maxAcceptedDistance = tonumber(move.maxAcceptedDistance) or 0
    move.maxHitDistance = tonumber(move.maxHitDistance) or 0
    return matchup, move
end

local function learnedPressure(target)
    local knowledge = knowledgeFor(target)
    local hitPressure = math.clamp((knowledge.successfulHits or 0) / 24, 0, 1)
    local skillPressure = math.clamp((knowledge.skills or 0) / 45, 0, 1)
    return hitPressure * 0.72 + skillPressure * 0.28
end

local function adaptiveBlockGap(target)
    return controller.config.blockGap - learnedPressure(target) * 0.11
end

local function adaptiveSideDashGap(target)
    -- Standard lateral dashes have a native two-second cooldown.
    local character = LocalPlayer.Character
    if character and (character:GetAttribute("Moveset") == "Naoya" or hasInfo(character, "DomainClash")) then
        return 0.5
    end
    return 2.05
end

local function canRequestDash(character)
    local info = character and character:FindFirstChild("Info")
    if not info then return false end
    local forceEscape = info:FindFirstChild("ForceEsc")
    if info:FindFirstChild("Knockback")
        or (character:GetAttribute("Burst") and not info:GetAttribute("Burst"))
        or (forceEscape and forceEscape.Value) then
        return true, "native_escape"
    end
    if info:FindFirstChild("Block") or info:FindFirstChild("Stun") or info:FindFirstChild("NoDash")
        or (tonumber(character:GetAttribute("Ragdoll")) or 0) > 0 then return false end
    local skill = info:FindFirstChild("InSkill")
    if skill and skill.Value == false and not info:FindFirstChild("AllowDashInSkill") then return false end
    local slow = info:FindFirstChild("NoSprint")
    if slow and slow.Value == false and not slow:GetAttribute("AllowDash") then return false end
    return true, "normal"
end

local function observeBodyRepel(phase, model, object)
    if model == LocalPlayer.Character or not isCandidate(model) then return end
    if phase ~= "Start" and phase ~= "Clap" and phase ~= "Fire" then return end
    controller.specialThreats[model] = {
        phase = phase, object = object, deadline = os.clock() + (phase == "Fire" and 6 or 2),
    }
    controller.nextThink = 0
    log("special_observed", { name = "Body Repel", phase = phase, target = model.Name })
end

local function incomingBodyRepel(target, localRoot)
    local state = controller.specialThreats[target]
    if not state or state.kind then return false end
    if os.clock() > state.deadline or not state.object or not state.object.Parent then
        controller.specialThreats[target] = nil
        return false
    end
    if state.phase ~= "Fire" or not state.object:IsA("BasePart") then return false end
    local part = state.object
    local offset = localRoot.Position - part.Position
    local forward = part.CFrame.LookVector
    local along = offset:Dot(forward)
    local lateral = (offset - forward * along).Magnitude
    -- Native visual controller advances the projectile at 120 studs/second.
    return along >= -8 and along <= 8 + 120 * (0.3 + pingSeconds()) and lateral <= 10
end

controller.bodyRepelObserver = pcall(function()
    local Knit = require(game:GetService("ReplicatedStorage").Knit.Knit)
    table.insert(controller.connections, Knit.GetService("BodyRepelService").Effects:Connect(observeBodyRepel))
end)

local uroThreatRules = {
    BlindRageService = { kind = "uro_blind_rage", range = 38, duration = 1.45,
        phases = { Fly = true, Startup = true, Dash = true, Throw = true, Grab = true } },
    SkyDistortionService = { kind = "uro_sky_distortion", range = 65, duration = 1.35,
        phases = { Startup = true, Interp = true, Crunch = true } },
    ThinIceBreakerService = { kind = "uro_thin_ice", range = 24, duration = 1.2,
        phases = { Aerial = true, Startup = true, Crack = true } },
    ReversalRedMaxService = { kind = "gojo_red", range = 60, duration = 1.5 },
    LapseBlueService = { kind = "gojo_blue", range = 50, duration = 1.5 },
    ChosoService = { kind = "choso_piercing", range = 60, duration = 1.4 },
    DismantleService = { kind = "sukuna_dismantle", range = 45, duration = 1.2 },
    DismantleV2Service = { kind = "sukuna_dismantle_v2", range = 55, duration = 1.3 },
    UltraCannonService = { kind = "ryu_granite_blast", range = 65, duration = 1.6 },
    PlasmaWaveService = { kind = "ryu_plasma_wave", range = 40, duration = 1.3 },
    GreatSerpentService = { kind = "megumi_serpent", range = 38, duration = 1.4 },
    DivineDogService = { kind = "megumi_dog", range = 35, duration = 1.2 },
    CrushJawService = { kind = "yuki_crush_jaw", range = 30, duration = 1.2 },
    EarthquakeService = { kind = "earthquake", range = 35, duration = 1.4 },
    DroneStrikeService = { kind = "reggie_drone", range = 50, duration = 1.5 },
    BirdControlService = { kind = "meimei_bird_strike", range = 60, duration = 1.5 },
}

local nonThreatServices = {
    MovementService = true, ToolService = true, EmoteService = true,
    CharacterService = true, RagdollService = true, CameraService = true,
    SoundService = true, PingService = true, ChatService = true,
    StaminaService = true, SprintService = true, JumpService = true,
    HealthService = true, SpawnService = true, DialogueService = true,
    CutsceneService = true, TargetService = true, OverheadService = true,
}

local function observeUroThreat(serviceName, phase, ...)
    if nonThreatServices[serviceName] or type(phase)~="string" then return end
    local threatsMap = pvpModules.moveset_data and pvpModules.moveset_data.threats
    local rule = uroThreatRules[serviceName]
        or (threatsMap and threatsMap[serviceName])
    local knownRule = rule ~= nil
    if not rule then
        local base = serviceName:gsub("Service$", "")
        if base:find("Movement") or base:find("Emote") or base:find("Ragdoll") or base:find("Tool") then return end
        -- Unknown visual effects alone are not a 35-stud attack.
        rule = { kind = string.lower(base), range = 10.5, duration = .35 }
    end
    if phase == "Hit" or phase == "End" or phase == "Stop" or phase == "Destroy"
        or phase == "Cancel" then return end
    if select(1, ...) == LocalPlayer.Character then return end
    if not knownRule then
        local startup = phase == "Startup" or phase == "Start" or phase == "StartCharge"
            or phase == "Fire" or phase == "Launch" or phase == "Dash" or phase == "Throw"
            or phase == "Grab" or phase == "Cast" or phase == "Swing" or phase == "Swing2"
            or phase == "Chase" or phase == "ChaseHit" or phase == "AerialHit"
        if not startup then return end
    end
    if rule.kind == "movement" or rule.kind == "sprint" or rule.kind == "dash" then return end
    if rule.phases and not rule.phases[tostring(phase)] then return end
    -- Verified from the six live native controllers: Hit(victim,stage),
    -- Swing/Swing2/Chase(actor,...), ChaseHit/AerialHit(actor,victim).
    -- A hit receipt must not turn the victim of our punch into an attacker.
    local verifiedNative = serviceName == "GojoService" or serviceName == "ItadoriService"
        or serviceName == "MegumiService" or serviceName == "ChosoService"
        or serviceName == "HakariService" or serviceName == "TodoService"
    if verifiedNative and phase == "Hit" then
        -- Contact and health feedback remain connected through p.OnContact.
        controller.nextThink = 0
        return
    end
    local explicitNativeActor = verifiedNative and (phase == "Swing" or phase == "Swing2"
        or phase == "Chase" or phase == "ChaseHit" or phase == "AerialHit")
    if explicitNativeActor and select(1, ...) == LocalPlayer.Character then return end
    local model, object
    for _, value in ipairs({ ... }) do
        if isCandidate(value) then
            local humanoid, root = characterParts(value)
            if humanoid and root then model = value break end
        end
        local okPart, isPart = pcall(function() return value:IsA("BasePart") end)
        if okPart and isPart then object = value end
    end
    if explicitNativeActor then
        local actor=select(1, ...)
        if isCandidate(actor) then model=actor end
    end
    -- Never attribute a random nearby effect to our target just because it is in skill.
    if not model or model == LocalPlayer.Character then return end
    if controller.config.focusOnly and model ~= controller.target then return end
    if not knownRule and not explicitNativeActor and not hasInfo(model, "InSkill") then return end
    local nativeMeleePhase = phase == "Swing" or phase == "Swing2" or phase == "Hit"
        or phase == "AerialHit" or phase == "Chase" or phase == "ChaseHit"
    local baseMoveset=serviceName:match("^(.-)Service$")
    local nativeMelee = nativeMeleePhase and (controller.config.comboSequenceByMoveset[baseMoveset]
        or serviceName == tostring(model:GetAttribute("Moveset")) .. "Service")
    -- A native punch is still detected immediately. Its short contact window
    -- must not become the generic 1.2-second ranged-special guard/evade window.
    local duration = nativeMelee and ((phase == "Hit" or phase == "AerialHit" or phase == "ChaseHit")
        and .12 or .31 + pingSeconds()) or (rule.duration or 1.2)
    controller.specialThreats[model] = {
        kind = nativeMelee and "m1" or rule.kind or "special", phase = tostring(phase), object = object,
        range = nativeMelee and controller.config.threatDistance or rule.range or 35,
        startedAt = os.clock(), deadline = os.clock() + duration, nativeMelee = not not nativeMelee, service = serviceName,
    }
    controller.nextThink = 0
    log("special_observed", { name = serviceName, phase = tostring(phase), target = model.Name, kind = controller.specialThreats[model].kind })
end

controller.uroThreatObservers = {}
pcall(function()
    local Knit = require(game:GetService("ReplicatedStorage").Knit.Knit)
    local rs = game:GetService("ReplicatedStorage")
    local svcsFolder = rs:FindFirstChild("Knit") and rs.Knit:FindFirstChild("Knit") and rs.Knit.Knit:FindFirstChild("Services")
    local targets = {}
    for serviceName in pairs(uroThreatRules) do targets[serviceName] = true end
    local threatsMap = pvpModules.moveset_data and pvpModules.moveset_data.threats
    if threatsMap then
        for serviceName in pairs(threatsMap) do targets[serviceName] = true end
    end
    if svcsFolder then
        for _, child in ipairs(svcsFolder:GetChildren()) do
            if child.Name:find("Service$") and not targets[child.Name] and not nonThreatServices[child.Name] then
                targets[child.Name] = true
            end
        end
    end
    for serviceName in pairs(targets) do
        local connected = pcall(function()
            local svc = Knit.GetService(serviceName)
            if svc and svc.Effects then
                local connection = svc.Effects:Connect(function(phase, ...)
                    observeUroThreat(serviceName, phase, ...)
                end)
                table.insert(controller.connections, connection)
                return true
            end
            return false
        end)
        controller.uroThreatObservers[serviceName] = connected and "connected" or "unavailable"
    end
end)

targetThreat = function(target, distance)
    if not isCandidate(target) or (controller.config.focusOnly and target ~= controller.target)
        or targetDisabled(target) then return false, nil, 0 end
    local learned = knowledgeFor(target)
    -- Observation distance is not damage reach. Use actual recorded contact.
    local learnedDistance = math.clamp(tonumber(learned.maxContactDistance) or 10.5, 7, 16)
    local _, _, localRoot = localParts()
    if localRoot and incomingBodyRepel(target, localRoot) then return true, "body_repel", 12 end
    local observedSpecial = controller.specialThreats[target]
    if observedSpecial and observedSpecial.kind and observedSpecial.kind ~= "body_repel" then
        if os.clock() > observedSpecial.deadline then
            controller.specialThreats[target] = nil
        elseif distance <= observedSpecial.range then
            local _, enemyRoot = characterParts(target)
            local offset = enemyRoot and localRoot and localRoot.Position - enemyRoot.Position
            local directed = offset and (offset.Magnitude < 7
                or enemyRoot.CFrame.LookVector:Dot(offset.Unit) > .25)
            if not directed then return false, nil, 0 end
            return true, observedSpecial.kind,
                observedSpecial.kind == "uro_sky_distortion" and 10 or 9
        end
    end
    if targetDisabled(target) or distance > controller.config.rangedThreatDistance then
        return false, nil
    end
    local t = now()
    if controller.pvp.DefenseDue and not controller.pvp.DefenseDue(target) then return false,nil,0 end
    local lastM1 = tonumber(target:GetAttribute("LastM1")) or 0
    local lastM2 = tonumber(target:GetAttribute("LastM2")) or 0
    local _, targetRoot = characterParts(target)
    local facing = 0
    local closing = 0
    if targetRoot and localRoot then
        local towardLocal = (localRoot.Position - targetRoot.Position) * Vector3.new(1, 0, 1)
        if towardLocal.Magnitude > 0.01 then
            facing = (targetRoot.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit:Dot(towardLocal.Unit)
            closing = (targetRoot.AssemblyLinearVelocity * Vector3.new(1, 0, 1)):Dot(towardLocal.Unit)
        end
    end
    local observed=controller.pvp.attackObservations and controller.pvp.attackObservations[target]
    local measured=observed and controller.pvp.modules.moveset_data.timingFor(observed.id,observed.track.Speed)
    if measured and string.match(observed.name or "","^Melee[1-4]$") and not observed.contactSeen
        and os.clock()>=observed.startedAt and os.clock()<=observed.startedAt+measured.windup+.12
        and distance<=math.max(controller.config.m1Range,measured.maxContactDistance or 0)+2
        and facing>.15 then
        -- Animation startup can precede LastM1 replication. Use only repeated
        -- native contact observations at the same playback speed.
        return true,"m1",7+math.max(closing,0)/20
    end
    local learnedHitRate = (learned.attacks or 0) > 0
        and (learned.successfulHits or 0) / learned.attacks
        or 0
    if distance <= learnedDistance and t - lastM1 <= 0.31 + pingSeconds() and (facing > 0.15 or distance < 7) then
        return true, "m1", 4 + math.max(facing, 0) + math.max(closing, 0) / 20
    end
    if distance <= learnedDistance and t - lastM2 <= 0.39 + pingSeconds() and (facing > 0.05 or distance < 8) then
        return true, "m2", 5 + math.max(facing, 0)
    end
    if targetRoot and localRoot and math.abs(targetRoot.Position.Y - localRoot.Position.Y) <= 8
        and closing >= 35 and facing >= 0.8 and (distance - 5) / closing <= 0.3 + pingSeconds() then
        return true, "front_dash", 8 + closing / 50
    end
    -- InSkill is also used for recovery, buffs and idle holds. Require an
    -- actual playing attack animation; known service attacks are handled above.
    if observed and not observed.contactSeen and observed.track.IsPlaying
        and not string.match(observed.name or "", "^Melee[1-4]$")
        and os.clock() - observed.startedAt <= math.min(1.6,
            measured and measured.windup + .12 or .65)
        and hasInfo(target, "InSkill") and facing > .25 then
        return true, distance > learnedDistance and "ranged_skill" or "skill", 8
    end
    if controller.config.focusOnly then return false, nil, 0 end
    if target == controller.target and distance <= 9 and closing >= 14 and facing >= 0.65
        and targetRoot and localRoot and math.abs(targetRoot.Position.Y - localRoot.Position.Y) <= 6 then
        return true, "closing_approach", 3.5 + closing / 20
    end
    if target == controller.target and (learned.successfulHits or 0) >= 5
        and (learned.attacks or 0) >= 8 and learnedHitRate >= 0.28
        and closing >= 11 and facing >= 0.42 then
        return true, "learned_approach", 3.8 + closing / 18 + learnedHitRate
    end
    return false, nil, 0
end

local function findImmediateThreat(primaryTarget)
    if controller.config.focusOnly then
        local active, kind = targetThreat(primaryTarget, distanceTo(primaryTarget))
        if kind == "learned_approach" or kind == "closing_approach" or kind == "movement" then
            return false, nil, nil
        end
        return active, kind, active and primaryTarget or nil
    end
    local _, _, localRoot = localParts()
    local folder = workspace:FindFirstChild("Characters")
    if not localRoot or not folder then
        return false, nil, nil
    end
    local bestModel, bestKind, bestScore
    for _, model in ipairs(folder:GetChildren()) do
        if isCandidate(model) then
            local distance = distanceTo(model)
            if distance <= controller.config.rangedThreatDistance or controller.specialThreats[model] then
                local active, kind, severity = targetThreat(model, distance)
                if active then
                    local score = severity - distance * 0.08 + (model == primaryTarget and 0.4 or 0)
                    if not bestScore or score > bestScore then
                        bestModel, bestKind, bestScore = model, kind, score
                    end
                end
            end
        end
    end
    return bestModel ~= nil, bestKind, bestModel
end

local function discoverProfile(character)
    local profile = { order = {}, counterKeys = {}, ranges = {}, useTwice = {}, holdDurations = {},
        priorities = {}, inputModes = {}, perfectPhases = {},
        loadout = captureLoadout(character) }
    for key = 1, 4 do
        local slot = profile.loadout.slots[key]
        if slot then
            local lowerName = string.lower(slot.name)
            local rule = moveRules[lowerName]
            local inputMode = slot.inputMode
            profile.inputModes[key] = inputMode
            local inferredRange = controller.config.unknownAttackDistance
            if inputMode == 1 then inferredRange = controller.config.airVariantAttackDistance
            elseif inputMode == 2 then inferredRange = controller.config.targetedAttackDistance
            elseif inputMode == 3 then inferredRange = controller.config.aimedAttackDistance
            elseif inputMode == 4 then inferredRange = controller.config.movementAttackDistance
            elseif inputMode == 5 then inferredRange = controller.config.hybridAttackDistance end
            profile.ranges[key] = rule and rule.range or inferredRange
            profile.priorities[key] = rule and rule.priority or key + 4
            if counterNames[lowerName] then
                table.insert(profile.counterKeys, key)
            else
                table.insert(profile.order, key)
            end
            local tip = string.upper(tostring(slot.tip or ""))
            if rule and rule.useTwice then
                profile.useTwice[key] = rule.useTwice
            elseif string.find(tip, "USE TWICE", 1, true) then
                profile.useTwice[key] = 0.36
            end
            if rule and rule.holdDuration then
                profile.holdDurations[key] = rule.holdDuration
                profile.perfectPhases[key] = rule.perfectPhase
            elseif slot.supportsDeactivate or string.find(tip, "HOLD", 1, true) then
                profile.holdDurations[key] = controller.config.holdReleaseDelay
            end
        end
    end
    table.sort(profile.order, function(a, b)
        if profile.priorities[a] == profile.priorities[b] then return a < b end
        return profile.priorities[a] < profile.priorities[b]
    end)
    return profile
end

local function counterFitsThreat(character, target, threatKind, counterKey)
    if threatKind == "learned_approach" or threatKind == "closing_approach" then
        return false
    end
    if not counterKey then
        return false
    end
    if threatKind == "uro_sky_distortion" or threatKind == "body_repel"
        or threatKind == "ranged_skill" or threatKind == "ryu_granite_blast"
        or threatKind == "gojo_red" or threatKind == "gojo_blue"
        or threatKind == "choso_piercing" or threatKind == "meimei_bird_strike"
        or threatKind == "reggie_drone" then
        return false
    end
    local counterMove = moveForKey(counterKey)
    local counterLower = counterMove and string.lower(counterMove.Name)
    if counterLower == "eye catching" then
        -- Charles: reactive counter for the rival's specials, not for plain M1/M2.
        return threatKind ~= "m1" and threatKind ~= "m2"
    end
    if threatKind == "m1" or threatKind == "m2" then
        return true
    end

    local counter = counterMove
    if not counter then
        return false
    end
    local name = counterLower
    if name == "shut up!" then return true end
    if name == "parry" or name == "i had no idea.." then
        return true
    end
    if threatKind == "uro_blind_rage" or threatKind == "uro_thin_ice" then
        return name == "manji kick" or name == "door guard" or name == "head splitter"
            or name == "domain amplification" or name == "vengeance"
    end
    local opponentKnowledge = knowledgeFor(target)
    local counterHistory = opponentKnowledge.counterHistory and opponentKnowledge.counterHistory[threatKind]
    if counterHistory and counterHistory[name] then
        local data = counterHistory[name]
        if (data.uses or 0) >= 2 and (data.successes or 0) / data.uses < 0.25 then
            return false
        end
    end
    if name == "manji kick" or name == "door guard" or name == "head splitter" then
        return mostlyMeleeMovesets[tostring(target:GetAttribute("Moveset") or "")] == true
    end
    return mostlyMeleeMovesets[tostring(target:GetAttribute("Moveset") or "")] == true
end

local function targetCombatState(target)
    if not isCandidate(target) or (tonumber(target:GetAttribute("Ragdoll")) or 0) > 0 then
        return "down"
    end
    if target == controller.finisherTarget and os.clock() < controller.finisherUntil then
        return "settling"
    end
    local humanoid = target:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
        local _, root = characterParts(target)
        if root then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { target, LocalPlayer.Character }
            local height = math.max(3, humanoid.HipHeight + root.Size.Y * 0.5 + 1.5)
            local ground = workspace:Raycast(root.Position, Vector3.new(0, -height, 0), params)
            if not ground or math.abs(root.AssemblyLinearVelocity.Y) > 10 then return "airborne" end
        else
            return "airborne"
        end
    end
    return targetDisabled(target) and "stunned" or "standing"
end

local function targetStanding(target)
    local state = targetCombatState(target)
    return state == "standing" or state == "stunned"
end

local function targetM1Chainable(target, allowFinisherLift)
    if not isCandidate(target) or ((tonumber(target:GetAttribute("Ragdoll")) or 0) > 0 and not allowFinisherLift) then
        return false
    end
    local humanoid = target:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
        and not (target == controller.finisherTarget and os.clock() < controller.finisherUntil)
end

local function moveFitsTarget(move, target)
    -- Ground-hit support must be explicit; unknown specials are not assumed to hit ragdolls.
    return move ~= nil and targetStanding(target)
end

local function queueRecovery(target, reason)
    if not controller.running or not controller.armed or controller.target ~= target then return end
    controller.recoverySerial += 1
    controller.recoveryRequest = {
        target = target, reason = reason, id = controller.recoverySerial,
        generation = controller.targetGeneration,
        expiresAt = os.clock() + controller.config.recoveryWindow,
    }
    log("recovery_queued", { target = target.Name, reason = reason, id = controller.recoverySerial })
end

local function observeSkillRecovery(character)
    local action = controller.observedSkill
    if not action then return end
    if action.generation ~= controller.targetGeneration or controller.target ~= action.target
        or os.clock() - action.startedAt > 12 then
        controller.observedSkill = nil
        return
    end
    local active = hasInfo(character, "InSkill")
    if active then
        action.seenActive = true
    elseif action.seenActive then
        controller.observedSkill = nil
        -- A completed special is an offensive handoff, not a reason to retreat. The
        -- normal threat pass can still interrupt this follow-up for real defense.
        controller.comboRequested = true
        controller.nextComboAt = 0
        log("skill_followup", { target = action.target.Name, after = action.name })
    elseif os.clock() - action.startedAt > 1.2 then
        controller.observedSkill = nil
    end
end

local function effectiveMoveRange(profile, key, move, localMoveset, enemyMoveset)
    local range = profile.ranges[key] or controller.config.attackDistance
    local _, learned = matchupBucket(localMoveset, enemyMoveset, move and move.Name or "Unknown")
    local lowerName = move and string.lower(move.Name) or ""
    local rule = moveRules[lowerName]
    local isMelee = rule and rule.range and rule.range <= 9.5
    if not isMelee and learned.maxAcceptedDistance and learned.maxAcceptedDistance > 0 then
        range = math.max(range, math.min(controller.config.rangedThreatDistance,
            learned.maxAcceptedDistance + 2.5))
    end
    return range, learned
end

local aerialComboMoves = {
    ["rough energy"] = true,
    ["stockpile"] = true,
    ["execution"] = true,
    ["impetus updraft"] = true,
    ["circling"] = true,
}

local function variantScore(learned)
    local uses = learned and (learned.uses or 0) or 0
    if uses <= 0 then return 0.62 end
    local hitRate = (learned.hits or 0) / uses
    local acceptedRate = (learned.acceptanceSamples or 0) > 0
        and (learned.accepted or 0) / learned.acceptanceSamples or 0.5
    return hitRate + acceptedRate * 0.22
end

local function shouldUseAerialVariant(character, target, move, key, profile, distance)
    local inputMode = profile.inputModes[key]
    if (inputMode ~= 1 and inputMode ~= 5) or not targetStanding(target)
        or distance < 3.5 or distance > math.min(profile.ranges[key] or 18, 18)
        or UserInputService:IsKeyDown(Enum.KeyCode.Space) then return false end
    local humanoid, root = characterParts(character)
    local _, targetRoot = characterParts(target)
    if not humanoid or not root or not targetRoot or humanoid.FloorMaterial == Enum.Material.Air
        or math.abs(targetRoot.Position.Y - root.Position.Y) > 5
        or (targetRoot.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude > 19 then return false end

    local folder = workspace:FindFirstChild("Characters")
    if folder then
        for _, other in ipairs(folder:GetChildren()) do
            if other ~= character and other ~= target and isCandidate(other) and not targetDisabled(other) then
                local _, otherRoot = characterParts(other)
                if otherRoot and ((otherRoot.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude <= 15 then
                    return false
                end
            end
        end
    end

    local localMoveset = character:GetAttribute("Moveset")
    local enemyMoveset = target:GetAttribute("Moveset")
    local _, base = matchupBucket(localMoveset, enemyMoveset, move.Name)
    local _, air = matchupBucket(localMoveset, enemyMoveset, move.Name .. " [Air]")
    local _, ground = matchupBucket(localMoveset, enemyMoveset, move.Name .. " [Ground]")
    local airUses, groundUses = air.uses or 0, ground.uses or 0
    if airUses >= 2 and variantScore(air) + 0.06 < variantScore(ground) then return false end
    if aerialComboMoves[string.lower(move.Name)] and airUses < 2 then return true end
    if airUses < 2 then return (base.uses or 0) >= 2 and ((base.uses or 0) + key) % 4 == 0 end
    if variantScore(air) > variantScore(ground) + 0.04 then
        return (airUses + groundUses) % 3 ~= 2
    end
    return false
end

local function selectOffense(character, target, distance)
    local profile = discoverProfile(character)
    local targetBlocking = hasInfo(target, "Block") or target:GetAttribute("BlockTry") == true
    local targetVulnerable = targetDisabled(target)
    -- Preserve the reliable M1 chain at melee range instead of reciting every
    -- available skill as soon as its cooldown ends.
    if os.clock() < (controller.specialFollowupUntil or 0) and not targetBlocking then
        return nil, profile
    end
    if distance <= controller.config.m1Range and not targetBlocking
        and (controller.comboRequested or os.clock() >= controller.nextComboAt) then
        return nil, profile
    end
    local bestKey, bestScore
    local localMoveset = character:GetAttribute("Moveset")
    local enemyMoveset = target:GetAttribute("Moveset")
    local opponentKnowledge = knowledgeFor(target)
    local reactions = opponentKnowledge.reactions
    local reactionCount = (reactions.attackAfterOurMove or 0)
        + (reactions.blockAfterOurMove or 0)
        + (reactions.dashAfterOurMove or 0)
    local reactionPressure = math.clamp(reactionCount / 14, 0, 1)
    local _, enemyRoot = characterParts(target)
    local _, _, ownRoot = localParts()
    local separatingSpeed = 0
    if enemyRoot and ownRoot then
        local offset = enemyRoot.Position - ownRoot.Position
        if offset.Magnitude > 0.01 then
            separatingSpeed = (enemyRoot.AssemblyLinearVelocity - ownRoot.AssemblyLinearVelocity):Dot(offset.Unit)
        end
    end

    for index, key in ipairs(profile.order) do
        local move = moveForKey(key)
        local range, learned = effectiveMoveRange(profile, key, move, localMoveset, enemyMoveset)
        if move and moveReady(move) and distance <= range and moveFitsTarget(move, target)
            and os.clock() - (controller.moveRequestedAt[move] or -math.huge) >= controller.config.moveRequestGap then
            local hitRate = learned.uses > 0 and learned.hits / learned.uses or 0.5
            local acceptedRate = (learned.acceptanceSamples or 0) > 0
                and (learned.accepted or 0) / learned.acceptanceSamples or 0.5
            local moveName = string.lower(move.Name)
            local rule = moveRules[moveName]
            local comboPreferred = rule and rule.comboPreferred == true
            local inDownslamCombo = (os.clock() - (controller.lastDownslamAt or -math.huge) <= 1.2)
                and (controller.lastDownslamTarget == target or not controller.lastDownslamTarget)
            local antiBlock = targetBlocking and string.find(moveName, "divergent", 1, true) ~= nil
            local repeatedlyMissed = learned.uses >= controller.config.poorMoveMinUses
                and (learned.acceptanceSamples or 0) > 0
                and hitRate < controller.config.poorMoveHitRate
            local allowed = true
            local purposeRule = localMoveset == "Megumi" and megumiPurposeRules[moveName] or nil
            if purposeRule and (distance < purposeRule.min or distance > purposeRule.max) then
                allowed = false
            end
            if separatingSpeed > 12 and distance > range * 0.72 and not targetVulnerable then
                allowed = false
            end
            local inputMode = profile.inputModes[key]
            local score = 10 - index + hitRate * 3 + acceptedRate - reactionPressure * 2.75
            if not controller.moveRequestedAt[move] then score += 1.25 end
            local sinceRequest = os.clock() - (controller.moveRequestedAt[move] or -math.huge)
            if sinceRequest < 4 then score -= (4 - sinceRequest) * 1.5 end
            for recentIndex, recentName in ipairs(controller.recentOffenseMoves) do
                if recentName == move.Name then
                    score -= recentIndex == #controller.recentOffenseMoves and 5 or 1.75
                end
            end
            if controller.lastOffenseMove == move then score -= 2 end
            if repeatedlyMissed then
                local lastRequest = controller.moveRequestedAt[move] or -math.huge
                allowed = os.clock() - lastRequest >= 9
                score -= 5
            end
            if targetBlocking and not antiBlock then score -= 2.2 end
            if distance > controller.config.m1Range then
                if inputMode == 3 or inputMode == 5 then score += 3.5
                elseif inputMode == 4 then score += 2.5
                elseif inputMode == 2 then score += 1.5 end
            elseif inputMode == 4 and not targetVulnerable then
                score -= 1.2
            end
            if antiBlock then
                score += 5
            end
            if targetVulnerable then
                score += 2.2
            end
            if comboPreferred and (targetVulnerable or inDownslamCombo) then
                score += 3.5
            end
            if localMoveset and rangedMovesets[localMoveset] and distance > controller.config.m1Range then
                if inputMode == 2 or inputMode == 3 or inputMode == 5 or (rule and rule.range and rule.range > 20) then
                    score += 2.5
                end
            end
            if (tonumber(target:GetAttribute("Ragdoll")) or 0) > 0 and key == 3 then
                score -= 2
            end
            if allowed and (not bestScore or score > bestScore) then
                bestKey = key
                bestScore = score
            end
        end
    end
    return bestKey, profile
end

local function physicalAirVariant(character)
    local humanoid, root = characterParts(character)
    if not humanoid or not root or humanoid.FloorMaterial ~= Enum.Material.Air then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    local height = math.max(3.5, (humanoid.HipHeight or 2) + root.Size.Y * 0.5 + 1.5)
    return workspace:Raycast(root.Position, Vector3.new(0, -height, 0), params) == nil
end

local function nativeMovePayload(character, target, inputMode, specialInput)
    local airborne = physicalAirVariant(character)
    if inputMode == 1 then return airborne end
    if inputMode == 2 then return target end
    if inputMode == 3 then return predictedPosition(target) end
    if inputMode == 4 then return specialInput or Vector3.zero end
    if inputMode == 5 then
        return { airborne, target, predictedPosition(target), specialInput or Vector3.zero }
    end
    if inputMode == 6 then
        return { airborne, hasInfo(character, "InDash"), hasInfo(character, "InRoll") }
    end
    return false
end

local function fireNativeMove(character, move, eventName, target, inputMode, specialInput)
    local serviceName = move and move:GetAttribute("Service")
    local okService, service = pcall(ToolController.GetToolService, ToolController, serviceName)
    local event = okService and service and service[eventName]
    if not event or type(event.Fire) ~= "function" then
        return false, okService and ("missing native " .. tostring(eventName)) or tostring(service)
    end
    local payload = nativeMovePayload(character, target, inputMode, specialInput)
    return pcall(event.Fire, event, move, payload)
end

local function useNativeMove(key, reason, profile)
    local character = LocalPlayer.Character
    local target = controller.target
    local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
    local move = moveForKey(key)
    local localMoveset = character and character:GetAttribute("Moveset")
    local enemyMoveset = target and target:GetAttribute("Moveset")
    profile = profile or discoverProfile(character)
    if not controller.running or not controller.enabled or not controller.armed
        or not character or not targetHumanoid or not move or not moveReady(move)
        or not moveFitsTarget(move, target) or os.clock() < controller.escapeUntil
        or (string.sub(reason or "", 1, 7) ~= "counter" and string.sub(reason or "", 1, 5) ~= "chain"
            and os.clock() - (controller.lastSpecialDispatchAt or -math.huge) < controller.config.specialReserveGap)
        or os.clock() - (controller.moveRequestedAt[move] or -math.huge) < controller.config.moveRequestGap
        or not loadoutCurrent(profile.loadout) then
        return false
    end

    controller.recoveryRequest = nil
    controller.busy = true
    controller.actionSerial += 1
    pcall(hookToolControllerAiming)
    local serial = controller.actionSerial
    local beforeHealth = targetHumanoid.Health
    local beforeReadyAt = tonumber(move:GetAttribute("ReadyAt")) or 0
    local requestedDistance = distanceTo(target)
    local moveName = move.Name
    local serviceName = move:GetAttribute("Service")
    local localMoveset = character:GetAttribute("Moveset")
    local enemyMoveset = target:GetAttribute("Moveset")
    local inputMode = profile.inputModes[key]
    local matchup, learned = matchupBucket(localMoveset, enemyMoveset, moveName)

    local rule = uroThreatRules[serviceName]
    local isRangedSpecial = (inputMode == 1 or inputMode == 2 or inputMode == 3 or inputMode == 5)
        and (requestedDistance > controller.config.m1Range or (rule and rule.range and rule.range > 12) or rangedMovesets[localMoveset] == true)
    local specialDuration = (rule and rule.duration) or (isRangedSpecial and 1.35) or controller.config.bodyFaceDuration

    faceForAction(target, specialDuration)
    -- Counters are already selected from a confirmed incoming threat. Do not
    -- add an artificial 35 ms delay before their native dispatch.
    if string.sub(reason or "", 1, 7) ~= "counter" then
        task.wait(0.035)
    end
    local shadowCompatible = character:GetAttribute("Moveset") == "Megumi" and hasInfo(character, "InSkill")
        and (move.Name == "Rabbit Escape" or move.Name == "Divine Dog: Totality")
    if not controller.running or not controller.enabled or not controller.armed
        or controller.target ~= target or controller.actionSerial ~= serial
        or not isCandidate(target) or (not canAct(character, string.sub(reason or "", 1, 5) == "chain") and not shadowCompatible)
        or not moveFitsTarget(move, target)
        or not moveReady(move) or os.clock() < controller.escapeUntil
        or not loadoutCurrent(profile.loadout)
        or distanceTo(target) > effectiveMoveRange(profile, key, move, localMoveset, enemyMoveset) then
        if controller.actionSerial == serial then
            controller.busy = false
        end
        return false
    end

    local wantsAerial = shouldUseAerialVariant(character, target, move, key, profile, requestedDistance)
    local actualAerial = false
    if wantsAerial then
        local generation = controller.targetGeneration
        local function jumpStillCurrent()
            return controller.running and controller.enabled and controller.armed
                and controller.actionSerial == serial and controller.targetGeneration == generation
                and controller.target == target and isCandidate(target) and loadoutCurrent(profile.loadout)
        end
        actualAerial = requestNativeAir(character, jumpStillCurrent, 0.46)
        if not jumpStillCurrent() then
            if controller.actionSerial == serial then controller.busy = false end
            return false
        end
        if actualAerial then
            faceForAction(target, specialDuration)
            RunService.Heartbeat:Wait()
        else
            log("aerial_variant_failed", { name = moveName, target = target.Name })
        end
    end
    if not controller.running or controller.actionSerial ~= serial or controller.target ~= target
        or not isCandidate(target) or not moveReady(move) or not loadoutCurrent(profile.loadout)
        or distanceTo(target) > effectiveMoveRange(profile, key, move, localMoveset, enemyMoveset) then
        if controller.actionSerial == serial then controller.busy = false end
        return false
    end

    controller.moveRequestedAt[move] = os.clock()
    if string.sub(reason or "", 1, 7) ~= "counter" then
        controller.lastOffenseMove = move
        controller.lastSpecialDispatchAt = os.clock()
        table.insert(controller.recentOffenseMoves, move.Name)
        if #controller.recentOffenseMoves > 3 then table.remove(controller.recentOffenseMoves, 1) end
    end
    matchup.uses += 1
    learned.uses += 1
    local variantName = moveName .. (actualAerial and " [Air]" or " [Ground]")
    local _, variantLearned = matchupBucket(localMoveset, enemyMoveset, variantName)
    variantLearned.uses += 1

    local specialInput, specialWorldDirection
    if inputMode == 4 or inputMode == 5 then
        specialInput, specialWorldDirection = movementInputForTarget(character, target)
    end

    local attempt = {
        move = move, name = moveName, service = serviceName, target = target,
        generation = controller.targetGeneration, startedAt = os.clock(),
        deadline = os.clock() + controller.config.resultWindow,
        distance = requestedDistance, nativeAccepted = false,
        variant = actualAerial and "Air" or "Ground",
        perfectExpected = profile and profile.perfectPhases[key] or nil,
    }
    controller.pendingMove = attempt

    -- Calling ToolController.UseKey from an executor thread now fails inside its
    -- ControlModule require. Send the same native service event and payload directly.
    local ok, err = fireNativeMove(character, move, "Activated", target, inputMode, specialInput)

    controller.lastActionAt = os.clock()
    controller.lastOurMove = { t = now(), target = target.Name, name = moveName, key = key }
    log("move", {
        key = key,
        name = moveName,
        reason = reason,
        ok = ok,
        distance = distanceTo(target),
        targetRagdoll = target:GetAttribute("Ragdoll"),
        inputMode = inputMode,
        variant = attempt.variant,
        movementSpecial = specialWorldDirection ~= nil,
        error = not ok and tostring(err) or nil,
    })

    if not ok then
        warn("[JAC] " .. moveName .. ": " .. tostring(err))
        if controller.pendingMove == attempt then controller.pendingMove = nil end
        controller.busy = false
        return false
    end
    if specialWorldDirection then
        controller.sustainedSpecialSteering = {
            character = character, target = target, generation = controller.targetGeneration,
            deadline = os.clock() + 1.1, allowInSkill = true,
        }
    end
    if serviceName == "BirdControlService" then
        controller.sustainedSpecialSteering = {
            character = character, target = target, generation = controller.targetGeneration,
            deadline = os.clock() + 0.9,
        }
    end
    controller.observedSkill = {
        target = target, name = moveName, generation = controller.targetGeneration,
        startedAt = os.clock(), seenActive = hasInfo(character, "InSkill"),
    }

    local twiceDelay = profile and profile.useTwice[key]
    if twiceDelay then
        task.delay(twiceDelay + pingSeconds() * 0.25, function()
            if controller.running and controller.enabled and controller.armed and controller.target == target
                and serial == controller.actionSerial and os.clock() >= controller.escapeUntil
                and moveFitsTarget(move, target) and loadoutCurrent(profile.loadout) then
                fireNativeMove(character, move, "Activated", target, inputMode, specialInput)
                log("use_twice", { key = key, name = moveName })
            end
        end)
    end


    local holdDelay = profile and profile.holdDurations[key]
    if holdDelay then
        local releaseDelay = holdDelay
        if not (profile and profile.perfectPhases[key]) then
            releaseDelay += pingSeconds() * 0.2
        end
        local released = false
        local function doRelease()
            if released then return end
            released = true
            if controller.running and moveForKey(key) == move and loadoutCurrent(profile.loadout) then
                fireNativeMove(character, move, "Deactivated", target, inputMode, specialInput)
                log("move_release", { key = key, name = moveName, delay = releaseDelay,
                    perfectExpected = attempt.perfectExpected, reactive = attempt.perfect == true })
            end
        end
        attempt.releaseCallback = doRelease
        task.delay(releaseDelay, doRelease)
    end

    task.delay(controller.config.resultWindow, function()
        if not controller.running then
            return
        end
        local damage = math.max(0, beforeHealth - (targetHumanoid.Parent and targetHumanoid.Health or beforeHealth))
        local accepted = attempt.nativeAccepted
            or (tonumber(move:GetAttribute("ReadyAt")) or 0) > beforeReadyAt or damage > 0
        if accepted and string.sub(reason or "", 1, 7) ~= "counter" then
            local followupGap = math.clamp(controller.config.specialFollowupGap + pingSeconds() * 1.5, 1.15, 1.45)
            controller.specialFollowupUntil = os.clock() + followupGap
            controller.comboRequested = true
            controller.nextComboAt = 0
            log("special_handoff", { name = moveName, purpose = "confirmed_m1_entry", delay = followupGap })
        elseif not accepted and controller.observedSkill and controller.observedSkill.name == moveName then
            controller.observedSkill = nil
        end
        for _, record in ipairs({ learned, variantLearned }) do
            if accepted then
                record.acceptanceSamples = (record.acceptanceSamples or 0) + 1
                record.accepted = (record.accepted or 0) + 1
                record.maxAcceptedDistance = math.max(record.maxAcceptedDistance or 0, requestedDistance)
            else
                record.acceptanceSamples = (record.acceptanceSamples or 0) + 1
                record.rejected = (record.rejected or 0) + 1
            end
        end
        if damage > 0 then
            learned.hits += 1
            variantLearned.hits += 1
            matchup.hits += 1
            learned.damage += damage
            variantLearned.damage += damage
            matchup.damage += damage
            learned.maxHitDistance = math.max(learned.maxHitDistance or 0, requestedDistance)
            variantLearned.maxHitDistance = math.max(variantLearned.maxHitDistance or 0, requestedDistance)
        end
        if attempt.perfectExpected then
            learned.perfectAttempts = (learned.perfectAttempts or 0) + 1
            if attempt.perfect then learned.perfects = (learned.perfects or 0) + 1
            else learned.perfectMisses = (learned.perfectMisses or 0) + 1 end
        end
        if controller.pendingMove == attempt then controller.pendingMove = nil end
        log("result", { name = moveName, variant = attempt.variant, accepted = accepted, nativeAccepted = attempt.nativeAccepted,
            phase = attempt.phase, perfect = attempt.perfect, damage = damage, distance = requestedDistance })
    end)

    task.delay(0.08, function()
        if controller.actionSerial == serial then
            controller.busy = false
        end
    end)
    return true
end

clearTargetEvents = function()
    if controller.targetConnections then
        for _, conn in ipairs(controller.targetConnections) do
            if conn and typeof(conn) == "RBXScriptConnection" then
                pcall(conn.Disconnect, conn)
            end
        end
    end
    controller.targetConnections = {}
end

bindTargetEvents = function(target)
    clearTargetEvents()
    if not target or not target.Parent then return end

    local function onThreatSignal()
        if not controller.running or not controller.enabled or not controller.armed then return end
        if controller.target ~= target then return end

        local distance = distanceTo(target)
        -- targetThreat returns severity as its third value, NOT a Model.
        local active, threatKind = targetThreat(target, distance)
        if active and threatKind then
            controller.nextThink = 0

            local character = LocalPlayer.Character
            local profile = character and discoverProfile(character)
            local countered = false
            if profile and profile.counterKeys then
                for _, key in ipairs(profile.counterKeys) do
                    local counter = moveForKey(key)
                    if counter and moveReady(counter) and counterFitsThreat(character, target, threatKind, key) then
                        if useNativeMove(key, "counter:" .. tostring(threatKind), profile) then
                            countered = true
                            break
                        end
                    end
                end
            end
            if not countered then
                quickBlock(target, "event_threat:" .. tostring(threatKind))
            end
        end
    end

    table.insert(controller.targetConnections, target:GetAttributeChangedSignal("LastM1"):Connect(onThreatSignal))
    table.insert(controller.targetConnections, target:GetAttributeChangedSignal("LastM2"):Connect(onThreatSignal))

    local info = target:FindFirstChild("Info")
    if info then
        table.insert(controller.targetConnections, info.ChildAdded:Connect(function(child)
            if child.Name == "InSkill" then onThreatSignal() end
        end))
    end
end

local function beginEscapeFacing(direction, duration)
    if not controller.running or not controller.enabled or not controller.armed then return end
    controller.escapeUntil = os.clock() + duration
    controller.escapeDirection = direction
    controller.bodyFaceUntil = 0
    controller.actionSerial += 1
    controller.comboSerial += 1
    controller.busy = false
    controller.comboBusy = false
    controller.recoveryRequest = nil
    controller.observedSkill = nil
    controller.moveIntent = nil
    releaseBlock("escape")
    releaseBodyFacing()
    local character, humanoid, root = localParts()
    if character and direction then
        updateBodyFacing(character, humanoid, root, controller.target, direction)
    end
end

local function enterNativeDownslamWindow(character, humanoid, root, stillCurrent)
    -- Native ToolController selects Down ONLY with FloorMaterial == Air.
    -- Height/velocity alone must never authorize a ground fourth M1.
    return character ~= nil and humanoid ~= nil and root ~= nil
        and stillCurrent() and humanoid.FloorMaterial == Enum.Material.Air
        and (humanoid:GetState() == Enum.HumanoidStateType.Jumping
            or humanoid:GetState() == Enum.HumanoidStateType.Freefall)
end

local function dashFacing(direction, travel)
    if direction == "Left" or direction == "Right" then
        local target = controller.target
        local _, targetRoot = characterParts(target)
        local character, _, root = localParts()
        if targetRoot and root then
            local toTarget = Vector3.new(targetRoot.Position.X - root.Position.X, 0, targetRoot.Position.Z - root.Position.Z)
            if toTarget.Magnitude > 0.01 then
                return toTarget.Unit
            end
        end
    end
    return direction == "Back" and -travel or travel
end

local function dashInput(direction, root)
    local camera = workspace.CurrentCamera
    local frame = camera and camera.CFrame or root.CFrame
    local right = Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z)
    if right.Magnitude < 0.01 then return nil end
    right = right.Unit
    local forward = Vector3.new(right.Z, 0, -right.X)
    if direction == "Left" then return -right end
    if direction == "Right" then return right end
    return direction == "Back" and -forward or forward
end

local function dashForce(character)
    local torso = character and character:FindFirstChild("Torso")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return (torso and torso:FindFirstChild("MovementForce"))
        or (root and root:FindFirstChild("MovementForce"))
end

local function observeDash()
    local pending = controller.dashPending
    if not pending then return end
    if pending.character ~= LocalPlayer.Character or pending.generation ~= controller.targetGeneration
        or pending.serial ~= controller.actionSerial then
        controller.dashPending = nil
        return
    end
    local character = pending.character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local velMagnitude = root and (Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)).Magnitude or 0
    local hasInDash = hasInfo(character, "InDash") or hasInfo(character, "Dash") or hasInfo(character, "DashLinger")
    local velocitySurge = velMagnitude >= 30 and (pending.beforeVelocity == nil or velMagnitude > pending.beforeVelocity + 10)
    local force = dashForce(character)
    if (force and force ~= pending.beforeForce) or pending.nativeAccepted or hasInDash or velocitySurge then
        controller.dashPending = nil
        if controller.pvp.NotifyDash then controller.pvp.NotifyDash(pending,true) end
        if pending.direction == "Front" then controller.lastForwardDashAt = os.clock()
        else controller.lastDashAt = os.clock() end
        controller.escapeUntil = pending.startedAt + controller.config.escapeFacingDuration
        controller.dashFailures[pending.direction] = 0
        controller.dashBlockedUntil[pending.direction] = 0
        if pending.direction == "Front" and pending.reason == "chase" then
            controller.recentEntry = { target = controller.target, at = os.clock() }
            local knowledge = knowledgeFor(controller.target)
            knowledge.frontEntries = (knowledge.frontEntries or 0) + 1
        end
        log(pending.nativeAccepted and "dash_native_accepted" or "dash_motion_started",
            { direction = pending.direction, reason = pending.reason })
    elseif os.clock() >= pending.deadline then
        controller.dashPending = nil
        if controller.pvp.NotifyDash then controller.pvp.NotifyDash(pending,false) end
        controller.escapeUntil = 0
        controller.escapeDirection = nil
        releaseBodyFacing()
        local failures = (controller.dashFailures[pending.direction] or 0) + 1
        controller.dashFailures[pending.direction] = failures
        controller.dashBlockedUntil[pending.direction] = os.clock() + (pending.direction == "Front" and 0.4 or math.min(2.4, 0.75 + failures * 0.45))
        log("dash_unconfirmed", { direction = pending.direction, reason = pending.reason })
    end
end

local function nativeDash(direction, reason, worldDirection)
    local character, humanoid, root = localParts()
    local ready, mode = canRequestDash(character)
    if not controller.running or not controller.enabled or not controller.armed
        or not character or not ready or os.clock() < controller.dashRetryAt
        or os.clock() - controller.lastDashRequestAt < controller.config.dashRequestGap then
        return false
    end
    if os.clock() < (controller.dashBlockedUntil[direction] or 0) then return false end
    if mode=="normal" and direction~="Front"
        and os.clock()-controller.lastDashAt<adaptiveSideDashGap(controller.target) then return false end
    local generation = controller.targetGeneration
    local moveDirection = worldDirection
    if not direction then return false end
    -- Preserve an obstacle-checked world vector instead of rebuilding it from the camera.
    if not moveDirection then
        if direction == "Left" then
            moveDirection = -root.CFrame.RightVector
        elseif direction == "Right" then
            moveDirection = root.CFrame.RightVector
        elseif direction == "Back" then
            moveDirection = -root.CFrame.LookVector
        else
            local aim = predictedPosition(controller.target)
            moveDirection = aim and (aim - root.Position) or root.CFrame.LookVector
        end
    end
    moveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)
    if moveDirection.Magnitude < 0.01 then
        return false
    end

    local inputDirection = dashInput(direction, root)
    if not inputDirection then return false end
    local facingDirection = dashFacing(direction, moveDirection.Unit)
    -- Side dashes create their native local force synchronously. One short
    -- acknowledgement grace is enough; do not leave defense blocked for .35s.
    local confirmationWindow = direction == "Front" and math.clamp(pingSeconds()+.08,.12,.24) or .065
    controller.nativeDashHeadingUntil = os.clock() + confirmationWindow
    beginEscapeFacing(facingDirection, confirmationWindow)
    local actionSerial = controller.actionSerial
    -- The native selector reads camera-relative input; its force reads body-relative axes.
    humanoid:Move(inputDirection, false)
    RunService.Heartbeat:Wait()
    if not controller.running or not controller.enabled or not controller.armed
        or controller.targetGeneration ~= generation or LocalPlayer.Character ~= character
        or controller.actionSerial ~= actionSerial
        or not canRequestDash(character) then
        if controller.actionSerial == actionSerial and controller.targetGeneration == generation then
            controller.escapeUntil = 0
            controller.escapeDirection = nil
            releaseBodyFacing()
        end
        return false
    end
    humanoid:Move(inputDirection, false)
    local curVel = root and (Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)).Magnitude or 0
    controller.dashPending = {
        character = character, generation = generation, serial = actionSerial,
        direction = direction, reason = reason, beforeForce = dashForce(character),
        beforeVelocity = curVel,
        startedAt = os.clock(), deadline = os.clock() + confirmationWindow,
    }
    controller.lastDashRequestAt = os.clock()
    local ok, err = pcall(MovementController.DashRequest, MovementController)
    local defensive=reason and (string.find(reason,"evade",1,true) or string.find(reason,"recovery",1,true)
        or string.find(reason,"predicted_threat_exit",1,true))
    if defensive and controller.pvp.RecordDefense then
        controller.pvp.RecordDefense(controller.pvp.dispatchThreat or controller.pendingThreat or controller.target,
            "dash",ok,reason)
    end
    if ok then
        controller.dashRetryAt = os.clock() + 0.3
        observeDash()
        if direction == "Back" and defensive then
            -- Backdash + guard tech: instantly raise guard to stay intact against follow-up chases
            task.delay(0.18, function()
                if controller.running and controller.enabled and controller.armed and not controller.busy and not controller.comboBusy then
                    quickBlock(controller.target, "backdash_intact_guard")
                    task.delay(0.28, function()
                        if not controller.blockingManual then
                            releaseBlock("backdash_guard_end")
                        end
                    end)
                end
            end)
        end
    elseif controller.actionSerial == actionSerial then
        local rejected=controller.dashPending
        controller.dashPending = nil
        controller.escapeUntil = 0
        controller.escapeDirection = nil
        releaseBodyFacing()
        if rejected and controller.pvp.NotifyDash then controller.pvp.NotifyDash(rejected,false) end
    end
    log("dash_request", { direction = direction, reason = reason, ok = ok, mode = mode,
        error = not ok and tostring(err) or nil,
        facing = "escape", x = moveDirection.Unit.X, z = moveDirection.Unit.Z })
    return ok
end

local function pulseNativeM1(target, downslam)
    local character, humanoid, root = localParts()
    local generation = controller.targetGeneration
    local comboSerial = controller.comboSerial
    local loadout = captureLoadout(character)
    local function stillCurrent()
        return controller.running and controller.enabled and controller.armed
            and controller.targetGeneration == generation and controller.target == target
            and controller.comboSerial == comboSerial
            and LocalPlayer.Character == character and isCandidate(target)
            and loadoutCurrent(loadout)
            and os.clock() >= controller.escapeUntil
    end
    if not character or not humanoid or not stillCurrent() then
        return false
    end
    local actualDownslam = downslam and enterNativeDownslamWindow(character, humanoid, root, stillCurrent)

    if not stillCurrent() then return false, false end
    faceForAction(target)
    if not stillCurrent() or not canQueueM1(character) then return false, false end
    if m1RequestPending(character) then
        return false, false, "shared_native_pending"
    end
    if downslam and not actualDownslam then
        log("finisher_jump_failed", { target = target.Name, reason = "not_airborne_before_fourth" })
        return false, false
    end
    local variant = actualDownslam and "Down" or nil
    controller.lastOurMove = { t = now(), target = target.Name,
        name = actualDownslam and "M1 Downslam" or "M1", key = 0 }
    if actualDownslam then
        controller.pvp.slamReceipt={target=target,character=character,at=os.clock(),serial=controller.pvp.combo.serial,
            token=character:GetAttribute("LastM1"),downObserved=false,impactObserved=false}
        controller.pvp.Audit("pvp_slam_request",{target=target.Name,variant="Down",
            nativeStage=character:GetAttribute("CurrentM1"),airborne=true})
    end
    -- Scope ownership to the non-yielding dispatch, never the jump wait above.
    controller.pvp.ownM1Dispatch=true
    local ok = pcall(ToolController.UseSetService, ToolController, "Activated", variant, target)
    controller.pvp.ownM1Dispatch=false
    if ok then
        controller.pvp.lastNativeM1At=os.clock()
        controller.pvp.nativeM1Pending={token=character:GetAttribute("LastM1"),
            stage=character:GetAttribute("CurrentM1"),time=os.clock(),source="automatic"}
    end
    return ok, actualDownslam
end

local function chooseM1Finisher(character, target, fromStep3)
    local humanoid, root = characterParts(character)
    local targetHumanoid, targetRoot = characterParts(target)
    if not humanoid or not root or not targetHumanoid or not targetRoot then
        return false, "missing_parts"
    end
    if not fromStep3 and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
        return false, "manual_jump"
    end

    local distance = distanceTo(target)
    local targetPlanarVelocity = targetRoot.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
    local verticalGap = math.abs(targetRoot.Position.Y - root.Position.Y)
    local liftGrace = math.clamp(0.30 + pingSeconds() * 1.5, 0.35, 0.60)
    local recentThirdHit = fromStep3 or (controller.lastConsumedM1 > 0
        and now() - controller.lastConsumedM1 <= liftGrace)
    local maxDistance = recentThirdHit and math.max(controller.config.m1Range + 7.0, 14.0) or math.max(controller.config.m1Range + 1.5, 9.2)
    if distance > maxDistance then
        return false, "far"
    end
    if not recentThirdHit and targetPlanarVelocity.Magnitude > 18 then return false, "escaping" end
    local maxVerticalGap = recentThirdHit and 16.0 or 5.0
    if verticalGap > maxVerticalGap or (not recentThirdHit and targetCombatState(target) == "airborne") then
        return false, "target_airborne"
    end

    -- Once the native third hit is confirmed, the universal finisher is
    -- committed. Nearby opponents may influence defense before hit three, but
    -- never silently turn the fourth input back into a standing punch.
    if fromStep3 then
        return true, "universal_native_third"
    end

    local characters = workspace:FindFirstChild("Characters")
    if characters then
        for _, model in ipairs(characters:GetChildren()) do
            if model ~= character and model ~= target and isCandidate(model) and not targetDisabled(model) then
                local _, otherRoot = characterParts(model)
                local otherDistance = otherRoot
                    and ((otherRoot.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude or math.huge
                local towardLocal = otherRoot
                    and ((root.Position - otherRoot.Position) * Vector3.new(1, 0, 1)) or Vector3.zero
                local facing = towardLocal.Magnitude > 0.01
                    and (otherRoot.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit:Dot(towardLocal.Unit) or 0
                local lastAttack = math.max(tonumber(model:GetAttribute("LastM1")) or 0,
                    tonumber(model:GetAttribute("LastM2")) or 0)
                local threatening = otherDistance <= 15 and facing > 0.1
                    and (hasInfo(model, "InSkill") or (lastAttack > 0
                        and now() - lastAttack <= 0.42 + pingSeconds()))
                if not fromStep3 and threatening then
                    return false, "second_attacker"
                end
            end
        end
    end

    return true, targetDisabled(target) and "ground_stun" or "isolated"
end

local function characterMelee3Duration(character)
    local moveset = character and character.GetAttribute and character:GetAttribute("Moveset")
    local base = moveset and characterMelee3Durations[moveset]
    if base then
        return base
    end
    if character and type(character.FindFirstChildOfClass) == "function" then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and type(humanoid.FindFirstChildOfClass) == "function" and humanoid:FindFirstChildOfClass("Animator")
        if animator and type(animator.GetPlayingAnimationTracks) == "function" then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local name = track.Name or ""
                if string.find(name, "Melee3") or string.find(name, "Hit3") then
                    if track.Length > 0.2 and track.Length < 0.7 then
                        return track.Length
                    end
                end
            end
        end
    end
    return 0.35
end

local function prepareUniversalDownslam(character, target, thirdRequestedAt, comboSerial)
    if not controller.running or not controller.enabled or not controller.armed
        or controller.comboSerial ~= comboSerial or controller.target ~= target
        or LocalPlayer.Character ~= character then return false, "cancelled" end
    local allowed, reason = chooseM1Finisher(character, target, true)
    local humanoid, root = characterParts(character)
    if not allowed or not humanoid or not root then return false, reason end
    -- MovementController sets JumpPower=0 EVERY frame while Info.NoJump,
    -- Stun, Block or Movement is present. Wait for its real release instead
    -- of temporarily overwriting power and racing that controller.
    if not canQueueM1(character) or hasInfo(character, "NoJump")
        or character:GetAttribute("Movement")
        then return false, "native_jump_locked" end
    local impulse = humanoid.UseJumpPower and humanoid.JumpPower or humanoid.JumpHeight
    if impulse <= 0 or not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
        then return false, "native_jump_disabled" end
    -- Native NoJump/Movement and restored jump power establish recovery.
    -- A character-name timer must not delay this item/native-chain transition.
    return true, reason
end

local function runM1Chain()
    if controller.comboBusy or controller.busy then return false end
    return controller.pvp.Begin()
end

local function activeOpponent(target)
    if Players:GetPlayerFromCharacter(target) then return true end
    local lastAttack = math.max(tonumber(target:GetAttribute("LastM1")) or 0,
        tonumber(target:GetAttribute("LastM2")) or 0)
    return hasInfo(target, "InSkill") or (lastAttack > 0 and now() - lastAttack < 1.2)
end

local function spacingContext(character, root, target)
    local _, enemyRoot = characterParts(target)
    local toward = (enemyRoot.Position - root.Position) * Vector3.new(1, 0, 1)
    local look = enemyRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
    local front = toward.Magnitude > 0.01 and look.Magnitude > 0.01 and look.Unit:Dot(-toward.Unit) > 0.4
    local knowledge = knowledgeFor(target)
    local reactions = knowledge.reactions or {}
    local punishCount = reactions.damageAfterFrontEntry or 0
    local enemyMoveset = target:GetAttribute("Moveset")
    local rangedThreat = rangedMovesets[enemyMoveset] == true and toward.Magnitude > 12 and front and not targetDisabled(target)
    local enemyInSkill = hasInfo(target, "InSkill") and not targetDisabled(target)
    -- The opponent-facing local X/Z frame exposes the safer side/rear arcs.
    local flank = (front and not targetDisabled(target)
        and (hasInfo(target, "Block") or punishCount >= 2 or enemyInSkill)) or rangedThreat
    local others = {}
    local folder = workspace:FindFirstChild("Characters")
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model ~= character and model ~= target and isCandidate(model) and not targetDisabled(model) then
                local _, otherRoot = characterParts(model)
                if otherRoot then
                    local offset = (root.Position - otherRoot.Position) * Vector3.new(1, 0, 1)
                    local lastAttack = math.max(tonumber(model:GetAttribute("LastM1")) or 0,
                        tonumber(model:GetAttribute("LastM2")) or 0)
                    local isAttacking = hasInfo(model, "InSkill") or (lastAttack > 0 and now() - lastAttack < 1.4)
                    local isClosing = offset.Magnitude <= 16 and otherRoot.CFrame.LookVector:Dot(offset.Unit) > 0.25
                    if offset.Magnitude <= 18 and offset.Magnitude > 0.01
                        and otherRoot.CFrame.LookVector:Dot(offset.Unit) > 0.1
                        and (isAttacking or isClosing) then
                        table.insert(others, otherRoot.Position)
                    end
                end
            end
        end
    end
    local reason = "direct"
    if #others > 0 then
        reason = "second_attacker"
    elseif flank then
        if punishCount >= 2 then
            reason = "entry_damage_pattern"
        elseif hasInfo(target, "Block") then
            reason = "frontal_guard"
        elseif rangedThreat then
            reason = "ranged_threat"
        else
            reason = "frontal_angle"
        end
    end
    return { flank = flank, others = others, look = look, reason = reason }
end

local function spacingPenalty(position, enemyRoot, context)
    local penalty = 0
    local offset = (position - enemyRoot.Position) * Vector3.new(1, 0, 1)
    if context.flank and offset.Magnitude > 0.01 and context.look.Magnitude > 0.01 then
        penalty += math.max(0, context.look.Unit:Dot(offset.Unit)) * 10
    end
    for _, otherPosition in ipairs(context.others) do
        penalty += math.max(0, 13 - (position - otherPosition).Magnitude) * 2.5
    end
    return penalty
end

local function tacticalDirection(target, toward, distance)
    if controller.movementPatternTarget ~= target or os.clock() >= controller.movementPatternUntil then
        local previousStyle = controller.movementPatternStyle or 0
        local style = math.random(1, 4)
        if style == previousStyle then style = style % 4 + 1 end
        controller.movementPatternTarget = target
        controller.movementPatternStyle = style
        if math.random() < 0.68 then controller.movementPatternSign = -(controller.movementPatternSign or 1) end
        local latencyScale = math.clamp(0.85 + pingSeconds() * 2.2, 0.9, 1.25)
        controller.movementPatternUntil = os.clock() + latencyScale * (controller.config.tacticalPatternMin
            + math.random() * (controller.config.tacticalPatternMax - controller.config.tacticalPatternMin))
    end
    local side = Vector3.new(-toward.Z, 0, toward.X) * (controller.movementPatternSign or 1)
    local style = controller.movementPatternStyle
    local targetBlocking = hasInfo(target, "Block") or target:GetAttribute("BlockTry") == true
    local targetVulnerable = targetDisabled(target)
    local forwardWeight, sideWeight
    if targetVulnerable then
        if distance <= controller.config.engageDistance then
            forwardWeight, sideWeight = 0.20, 0.90
        else
            forwardWeight, sideWeight = 1.0, 0.0
        end
    elseif targetBlocking then
        forwardWeight, sideWeight = 0.40, 0.92
    elseif distance > 24 and not activeOpponent(target) then
        forwardWeight, sideWeight = 0.95, 0.31
    elseif distance > 25 then
        forwardWeight, sideWeight = 0.68, 0.73
    elseif style == 1 then
        forwardWeight, sideWeight = 0.26, 0.97 -- wide orbit
    elseif style == 2 then
        forwardWeight, sideWeight = 0.58, 0.81 -- diagonal cut
    elseif style == 3 then
        forwardWeight, sideWeight = -0.22, 0.97 -- baiting retreat
    else
        forwardWeight, sideWeight = 0.42, -0.91 -- cross behind the prior side
    end
    return (toward * forwardWeight + side * sideWeight).Unit
end

local function chooseApproachDirection(character, root, target)
    local humanoid, enemyRoot = characterParts(target)
    if not humanoid or not activeOpponent(target) or targetDisabled(target) then return nil end
    local toward = Vector3.new(enemyRoot.Position.X - root.Position.X, 0, enemyRoot.Position.Z - root.Position.Z)
    local distance = toward.Magnitude
    if distance < controller.config.lateralApproachMinDistance
        or distance > controller.config.lateralApproachMaxDistance then return nil end
    toward = toward.Unit
    local side = Vector3.new(-toward.Z, 0, toward.X)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character, target }
    local bestName, bestVector, bestScore
    local info = character:FindFirstChild("Info")
    local multiplierValue = info and info:FindFirstChild("DashMultiplier")
    local multiplier = multiplierValue and tonumber(multiplierValue.Value) or 1
    if not multiplier or multiplier <= 0 or multiplier > 3 then return nil end
    local travel = controller.config.lateralApproachTravel * multiplier
    local context = spacingContext(character, root, target)
    for _, sign in ipairs({ -1, 1 }) do
        local direction = (toward * 0.72 + side * (sign * 0.694)).Unit
        local finish = root.Position + direction * travel
        local remaining = (finish - enemyRoot.Position).Magnitude
        local clear = not workspace:Raycast(root.Position, direction * (travel + 2), params)
        local clearanceSide = Vector3.new(-direction.Z, 0, direction.X) * 1.5
        clear = clear and not workspace:Raycast(root.Position + clearanceSide, direction * (travel + 2), params)
            and not workspace:Raycast(root.Position - clearanceSide, direction * (travel + 2), params)
        local ground = clear and workspace:Raycast(finish + Vector3.new(0, 2, 0), Vector3.new(0, -10, 0), params)
        if remaining < distance - 2 and remaining >= 4 and ground and ground.Normal.Y >= 0.6 then
            local score = -math.abs(remaining - controller.config.m1Range * 0.8)
                + (sign == controller.side and 0.25 or 0)
                - spacingPenalty(finish, enemyRoot, context)
            if not bestScore or score > bestScore then
                bestName, bestVector, bestScore = sign < 0 and "Left" or "Right", direction, score
            end
        end
    end
    if bestName then controller.side = -controller.side end
    return bestName, bestVector
end

local function requestPathAsync(root, target, targetRoot)
    if not PathfindingService or controller.pathBusy
        or (controller.pathTarget == target and os.clock() < (controller.nextPathAt or 0)
            and controller.pathWaypoints) then return end
    controller.pathBusy = true
    controller.pathTarget = target
    controller.nextPathAt = os.clock() + math.clamp(0.7 + pingSeconds() * 2, 0.8, 1.1)
    controller.pathRequestSerial += 1
    local serial = controller.pathRequestSerial
    local generation = controller.targetGeneration
    local origin, destination = root.Position, targetRoot.Position
    task.spawn(function()
        local waypoints
        local ok, path = pcall(PathfindingService.CreatePath, PathfindingService, {
            AgentRadius = 2.2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 5,
        })
        if ok and path and pcall(path.ComputeAsync, path, origin, destination)
            and path.Status == Enum.PathStatus.Success then
            waypoints = path:GetWaypoints()
        end
        if controller.running and controller.pathRequestSerial == serial
            and controller.targetGeneration == generation and controller.target == target then
            controller.pathWaypoints = waypoints
            controller.pathComputedAt = os.clock()
            controller.pathIndex = 2
            controller.pathBusy = false
        end
    end)
end

local function advanceOnTarget(character, humanoid, root, target)
    local _, targetRoot = characterParts(target)
    if not targetRoot or not controller.armed or target ~= controller.target then return false end
    local toward = Vector3.new(targetRoot.Position.X - root.Position.X, 0, targetRoot.Position.Z - root.Position.Z)
    if toward.Magnitude > controller.config.retainDistance or toward.Magnitude < 0.01 then return false end

    -- Anti-Head-Climbing Protection:
    -- If vertically above the enemy while horizontally close, immediately step off to the floor!
    local verticalDiff = root.Position.Y - targetRoot.Position.Y
    if verticalDiff > 2.0 and toward.Magnitude < 3.2 then
        local stepOff = (toward.Magnitude > 0.2 and -toward.Unit or -root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
        setMoveIntent(stepOff, 0.18)
        humanoid:Move(stepOff, false)
        return true
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character, target }
    local direction = toward.Unit
    -- Use a real navigation path for long chases or when the direct lane is
    -- blocked. Refresh sparsely so combat decisions stay responsive.
    local directBlocked = workspace:Raycast(root.Position, direction * math.min(toward.Magnitude, 7), params) ~= nil
    if PathfindingService and (toward.Magnitude > 34 or directBlocked) then
        requestPathAsync(root, target, targetRoot)
        local waypoints = controller.pathWaypoints
        local waypoint = waypoints and waypoints[controller.pathIndex or 2]
        while waypoint and (waypoint.Position - root.Position).Magnitude <= 3.5 do
            controller.pathIndex += 1
            waypoint = waypoints[controller.pathIndex]
        end
        if waypoint then
            local pathVector = (waypoint.Position - root.Position) * Vector3.new(1, 0, 1)
            if pathVector.Magnitude > 0.01 then direction = pathVector.Unit end
            if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
        end
    else
        controller.pathTarget = nil
        controller.pathWaypoints = nil
    end
    local context = spacingContext(character, root, target)
    local reposition = toward.Magnitude <= controller.config.lateralApproachMaxDistance
        and not controller.comboBusy and os.clock() >= controller.finisherCommitUntil
        and not targetDisabled(target)
        and false -- no orbiting: M1 contact beats repositioning
    local minMeleeGap = controller.comboBusy and 4.6 or controller.config.engageDistance
    if toward.Magnitude <= minMeleeGap and not reposition then
        controller.moveIntent = nil
        if not controller.HasManualInput() then humanoid:Move(Vector3.zero, false) end
        return false
    end
    if reposition then
        local side = Vector3.new(-direction.Z, 0, direction.X)
        local desired = tacticalDirection(target, direction, toward.Magnitude)
        local candidates = { desired, (desired * 0.65 + side * 0.76).Unit,
            (desired * 0.65 - side * 0.76).Unit, side, -side, direction, -direction }
        local best, bestScore
        for _, candidate in ipairs(candidates) do
            local point = root.Position + candidate * 3
            local floor = workspace:Raycast(point + Vector3.new(0, 2, 0), Vector3.new(0, -11, 0), params)
            if floor and floor.Normal.Y >= 0.6 and not workspace:Raycast(root.Position, candidate * 4, params) then
                local range = (point - targetRoot.Position).Magnitude
                local score = -math.abs(range - controller.config.engageDistance) * 0.45
                    + candidate:Dot(desired) * 2.4 + math.abs(candidate:Dot(side)) * 0.8
                    - spacingPenalty(point, targetRoot, context)
                if not bestScore or score > bestScore then best, bestScore = candidate, score end
            end
        end
        if best then
            direction = best
            controller.steeringUntil = os.clock() + 0.18
            controller.bodyFaceUntil = 0
            if not controller.config.focusOnly then releaseBodyFacing() end
            if controller.lastSpacingReason ~= context.reason or os.clock() - (controller.lastSpacingLogAt or 0) > 1 then
                controller.lastSpacingReason, controller.lastSpacingLogAt = context.reason, os.clock()
                log("tactical_walk", { reason = context.reason, target = target.Name, otherAttackers = #context.others,
                    x = direction.X, z = direction.Z })
            end
        end
    end
    if workspace:Raycast(root.Position, direction * 3, params) then return false end
    local ground = workspace:Raycast(root.Position + direction * 3, Vector3.new(0, -9, 0), params)
    if not ground then return false end
    setMoveIntent(direction, reposition and controller.config.tacticalMoveDuration or 0.14, false,
        not reposition and minMeleeGap or nil)
    humanoid:Move(direction, false)
    return true
end

local function specialReady(character)
    local cooldown = tonumber(character:GetAttribute("M2_CD")) or 0
    local usedAt = tonumber(character:GetAttribute("LastM2")) or 0
    return cooldown <= 0 or usedAt <= 0 or now() - usedAt >= cooldown
end

local function characterOverheat(character)
    if not character then return 0 end
    local attrOverheat = character:GetAttribute("Overheat")
    if tonumber(attrOverheat) then return tonumber(attrOverheat) end
    local info = character:FindFirstChild("Info")
    if info then
        local overheatVal = info:FindFirstChild("Overheat")
        if overheatVal then
            if type(overheatVal) == "table" or typeof(overheatVal) == "Instance" then
                local val = overheatVal.Value
                if tonumber(val) then return tonumber(val) end
            elseif tonumber(overheatVal) then
                return tonumber(overheatVal)
            end
        end
        local heatVal = info:FindFirstChild("Heat")
        if heatVal then
            if type(heatVal) == "table" or typeof(heatVal) == "Instance" then
                local val = heatVal.Value
                if tonumber(val) then return tonumber(val) end
            elseif tonumber(heatVal) then
                return tonumber(heatVal)
            end
        end
    end
    return 0
end

local movementSpecialRules = {
    Gojo = { name = "Teleport", minDistance = 12, maxDistance = 42,
        expectedPhases = { Teleport = true }, role = "entry" },
    Todo = { name = "Boogie Woogie", minDistance = 4.5, maxDistance = 10.5,
        expectedPhases = { Swap = true, Swap2 = true, Perfect = true }, role = "mixup" },
    MeiMei = { name = "Bird Dash", minDistance = 12, maxDistance = 40,
        expectedPhases = { Dash = true, Activate = true }, role = "entry" },
    Naoya = { name = "Projection Entry", minDistance = 10, maxDistance = 38,
        expectedPhases = { Dash = true, Charge = true, Activate = true }, role = "entry" },
    Hanami = { name = "Root Approach", minDistance = 8, maxDistance = 35,
        expectedPhases = { Root = true, Dash = true, Activate = true }, role = "entry" },
}

local function specialDestinationCrowded(character, target)
    local _, targetRoot = characterParts(target)
    local folder = workspace:FindFirstChild("Characters")
    if not targetRoot or not folder then return false end
    for _, other in ipairs(folder:GetChildren()) do
        if other ~= character and other ~= target and isCandidate(other) and not targetDisabled(other) then
            local _, otherRoot = characterParts(other)
            if otherRoot and ((otherRoot.Position - targetRoot.Position) * Vector3.new(1, 0, 1)).Magnitude <= 13 then
                return true
            end
        end
    end
    return false
end

local function useMovementSpecial(character, humanoid, root, target, distance)
    local moveset = character and character:GetAttribute("Moveset")
    local rule = movementSpecialRules[moveset]
    if not rule or not specialReady(character) or not targetStanding(target)
        or distance < rule.minDistance or distance > rule.maxDistance
        or controller.busy or controller.comboBusy or controller.blockActive
        or controller.observedSkill or os.clock() - controller.lastSpecialAt < 1
        or specialDestinationCrowded(character, target) then return false end

    if rule.role == "mixup" then
        local context = spacingContext(character, root, target)
        if not context.flank then return false end
    end

    controller.busy = true
    controller.actionSerial += 1
    controller.comboSerial += 1
    local serial = controller.actionSerial
    local generation = controller.targetGeneration
    faceForAction(target)
    task.wait(0.035)
    if not controller.running or not controller.enabled or not controller.armed
        or controller.target ~= target or controller.actionSerial ~= serial
        or controller.targetGeneration ~= generation or not canAct(character)
        or not targetStanding(target) or specialDestinationCrowded(character, target) then
        if controller.actionSerial == serial then controller.busy = false end
        return false
    end

    local ok, err = pcall(ToolController.Special, ToolController)
    if not ok then
        if controller.actionSerial == serial then controller.busy = false end
        log("special_approach_error", { name = rule.name, error = tostring(err) })
        return false
    end

    controller.lastSpecialAt = os.clock()
    controller.lastActionAt = os.clock()
    controller.specialApproachPending = {
        name = rule.name, service = tostring(moveset) .. "Service", target = target,
        generation = generation, expectedPhases = rule.expectedPhases,
        deadline = os.clock() + 1.35, accepted = false,
    }
    log("special_approach", { name = rule.name, role = rule.role,
        target = target.Name, distance = distance })
    task.delay(0.08, function()
        if controller.running and controller.actionSerial == serial then
            pcall(ToolController.ReleaseSpecial, ToolController)
        end
    end)
    task.delay(0.16 + pingSeconds() * 0.25, function()
        if controller.running and controller.enabled and controller.armed
            and controller.target == target and controller.targetGeneration == generation
            and controller.actionSerial == serial then
            controller.busy = false
            controller.comboRequested = true
            controller.nextComboAt = 0
        end
    end)
    return true
end

local function useMegumiShadowApproach(character, humanoid, root, target, distance, profile)
    if character:GetAttribute("Moveset") ~= "Megumi" or not specialReady(character)
        or distance < controller.config.shadowApproachMinDistance
        or distance > controller.config.shadowApproachMaxDistance
        or os.clock() - controller.lastSpecialAt < 1 then return false end

    local dogKey, dog
    for key = 1, 4 do
        local move = moveForKey(key)
        if move and move.Name == "Divine Dog: Totality" and moveReady(move) then
            dogKey, dog = key, move
            break
        end
    end

    local _, targetRoot = characterParts(target)
    if not targetRoot then return false end
    local generation = controller.targetGeneration
    local loadout = profile.loadout
    local ok, err = pcall(ToolController.Special, ToolController)
    if not ok then
        log("special_error", { name = "Lurking Shadow", error = tostring(err) })
        return false
    end

    controller.lastSpecialAt = os.clock()
    controller.lastActionAt = os.clock()
    local direction = (targetRoot.Position - root.Position) * Vector3.new(1, 0, 1)
    if direction.Magnitude > 0.01 then
        direction = direction.Unit
        controller.sustainedSpecialSteering = {
            character = character, target = target, generation = generation,
            deadline = os.clock() + 1.55, allowInSkill = true,
        }
        setMoveIntent(direction, 1.55, true)
        humanoid:Move(direction, false)
    end
    log("special_move", { name = "Lurking Shadow", purpose = dogKey and "dog_approach" or "tactical_entry",
        target = target.Name, distance = distance })

    if dogKey then
        task.delay(0.16, function()
            if not controller.running or not controller.enabled or not controller.armed
                or controller.targetGeneration ~= generation or controller.target ~= target
                or moveForKey(dogKey) ~= dog or not loadoutCurrent(loadout) or not moveReady(dog) then
                return
            end
            local curDist = distanceTo(target)
            local targetBlocking = hasInfo(target, "Block") or target:GetAttribute("BlockTry") == true
            if targetBlocking then
                controller.comboRequested = true
                controller.nextComboAt = 0
                return
            end
            if curDist <= 32 then
                useNativeMove(dogKey, "lurking_shadow_dog", discoverProfile(character))
            else
                controller.comboRequested = true
                controller.nextComboAt = 0
            end
        end)
    else
        task.delay(0.16, function()
            if controller.running and controller.enabled and controller.armed
                and controller.targetGeneration == generation and controller.target == target then
                controller.comboRequested = true
                controller.nextComboAt = 0
            end
        end)
    end
    return true
end

local function useCombatSpecial(character, humanoid, root, target, distance)
    local moveset = character and character:GetAttribute("Moveset")
    if not moveset then
        return false
    end
    local overheat = characterOverheat(character)
    local maxDist = (moveset == "Ryu" or overheat > 0) and 60 or 38
    if not specialReady(character) or not targetStanding(target)
        or distance > maxDist
        or controller.busy or controller.comboBusy or controller.blockActive
        or controller.observedSkill or os.clock() - controller.lastSpecialAt < 1.0
        or os.clock() - controller.lastActionAt < controller.config.actionGap then
        return false
    end

    controller.busy = true
    controller.actionSerial += 1
    controller.comboSerial += 1
    local serial = controller.actionSerial
    local generation = controller.targetGeneration
    faceForAction(target)
    task.wait(0.035)
    if not controller.running or not controller.enabled or not controller.armed
        or controller.target ~= target or controller.actionSerial ~= serial
        or controller.targetGeneration ~= generation or not canAct(character)
        or not targetStanding(target) then
        if controller.actionSerial == serial then controller.busy = false end
        return false
    end

    local ok, err = pcall(ToolController.Special, ToolController)
    if not ok then
        if controller.actionSerial == serial then controller.busy = false end
        log("special_error", { moveset = tostring(moveset), error = tostring(err) })
        return false
    end

    controller.lastSpecialAt = os.clock()
    controller.lastActionAt = os.clock()
    log("special_combat", { moveset = tostring(moveset), target = target.Name, distance = distance, overheat = overheat })

    task.delay(0.12, function()
        if controller.running and controller.actionSerial == serial then
            pcall(ToolController.ReleaseSpecial, ToolController)
        end
    end)
    task.delay(0.24 + pingSeconds() * 0.25, function()
        if controller.running and controller.enabled and controller.armed
            and controller.target == target and controller.targetGeneration == generation
            and controller.actionSerial == serial then
            controller.busy = false
            controller.comboRequested = true
            controller.nextComboAt = 0
        end
    end)
    return true
end

local function chooseEscapeDirection(character, root, threatModel)
    local _, threatRoot = characterParts(threatModel)
    local special = controller.specialThreats[threatModel]
    if special and special.phase == "Fire" and special.object and special.object.Parent
        and special.object:IsA("BasePart") and os.clock() <= special.deadline then
        threatRoot = special.object
    end
    if not threatRoot then
        return "Back"
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character, threatModel }
    local knowledge = knowledgeFor(threatModel)
    local approaches = knowledge.attackApproaches
    local dashes = knowledge.dashDirections
    local leftBias = controller.side > 0 and 0.2 or 0
    local rightBias = controller.side < 0 and 0.2 or 0
    local backBias = 0.55
    local approachTotal = (approaches.left or 0) + (approaches.right or 0)
        + (approaches.front or 0) + (approaches.back or 0)
    if approachTotal > 0 then
        leftBias += math.max(0, (approaches.right or 0) - (approaches.left or 0)) / approachTotal * 1.4
        rightBias += math.max(0, (approaches.left or 0) - (approaches.right or 0)) / approachTotal * 1.4
        local frontalRatio = (approaches.front or 0) / approachTotal
        leftBias += frontalRatio * 0.42
        rightBias += frontalRatio * 0.42
        -- Frontal attacks are evaded backward out of hitbox reach to stay intact
        backBias += frontalRatio * 0.95
    end
    local dashTotal = (dashes.left or 0) + (dashes.right or 0) + (dashes.toward or 0) + (dashes.away or 0)
    if dashTotal > 0 then
        leftBias += math.max(0, (dashes.right or 0) - (dashes.left or 0)) / dashTotal * 1.1
        rightBias += math.max(0, (dashes.left or 0) - (dashes.right or 0)) / dashTotal * 1.1
        local towardRatio = (dashes.toward or 0) / dashTotal
        leftBias += towardRatio * 0.38
        rightBias += towardRatio * 0.38
        -- Inward dash threats are evaded backward to keep spacing intact
        backBias += towardRatio * 1.15
    end
    local candidates = {
        { name = "Left", vector = -root.CFrame.RightVector, bias = leftBias },
        { name = "Right", vector = root.CFrame.RightVector, bias = rightBias },
        { name = "Back", vector = -root.CFrame.LookVector, bias = backBias },
    }
    local folder = workspace:FindFirstChild("Characters")
    local bestName, bestScore, bestVector

    for _, candidate in ipairs(candidates) do
        local direction = candidate.vector * Vector3.new(1, 0, 1)
        if direction.Magnitude > 0.01 then
            direction = direction.Unit
            local obstacle = workspace:Raycast(root.Position, direction * 7.5, params)
            if not obstacle then
                local projected = root.Position + direction * 7
                local offset = projected - threatRoot.Position
                local attackForward = threatRoot.CFrame.LookVector * Vector3.new(1, 0, 1)
                local lateral = attackForward.Magnitude > 0.01
                    and (offset - attackForward.Unit * offset:Dot(attackForward.Unit)).Magnitude or 0
                local score = offset.Magnitude * 0.45 + lateral * 0.85 + candidate.bias
                local isSpecialThreat = special ~= nil or controller.pendingThreatKind == "ranged_skill" or controller.pendingThreatKind == "skill"
                if isSpecialThreat and (candidate.name == "Left" or candidate.name == "Right") then
                    score += 1.5
                elseif candidate.name == "Back" and offset.Magnitude < 14 then
                    -- Backdash disengage keeps character intact against close melee/dash pressure
                    score += 1.6
                end
                if folder then
                    local nearestOther = 30
                    for _, other in ipairs(folder:GetChildren()) do
                        if other ~= character and other ~= threatModel and isCandidate(other) then
                            local _, otherRoot = characterParts(other)
                            nearestOther = math.min(nearestOther, (projected - otherRoot.Position).Magnitude)
                        end
                    end
                    score += math.min(nearestOther, 18) * 0.22
                end
                if not bestScore or score > bestScore then
                    bestName, bestScore, bestVector = candidate.name, score, direction
                end
            end
        end
    end
    controller.side = -controller.side
    return bestName, bestVector
end

startMicroStep = function(threatModel)
    if os.clock() <= controller.manualDashPriorityUntil then
        return false
    end
    local character, humanoid, root = localParts()
    if not character or not humanoid or not canAct(character) or not isCandidate(threatModel) then
        return false
    end
    local directionName, direction = chooseEscapeDirection(character, root, threatModel)
    if not direction then return false end
    direction = direction * Vector3.new(1, 0, 1)
    if direction.Magnitude < 0.01 then
        return false
    end
    beginEscapeFacing(direction.Unit, controller.config.microStepDuration + 0.05)
    setMoveIntent(direction.Unit, controller.config.microStepDuration)

    controller.microStepSerial += 1
    local serial = controller.microStepSerial
    task.spawn(function()
        local deadline = os.clock() + controller.config.microStepDuration
        repeat
            if not controller.running or controller.microStepSerial ~= serial then
                break
            end
            humanoid:Move(direction.Unit, false)
            RunService.Heartbeat:Wait()
        until os.clock() >= deadline
    end)
    log("micro_step", { direction = directionName, threat = threatModel.Name })
    return true
end

local function runRecovery(character, humanoid, root)
    local request = controller.recoveryRequest
    if not request then return false end
    if request.reason == "combo_finish" then
        controller.recoveryRequest = nil
        return false
    end
    if request.generation ~= controller.targetGeneration or request.target ~= controller.target
        or not isCandidate(request.target) or os.clock() > request.expiresAt then
        controller.recoveryRequest = nil
        return false
    end
    if not activeOpponent(request.target) then
        controller.recoveryRequest = nil
        return false
    end
    if os.clock() < controller.escapeUntil or not canRequestDash(character)
        or humanoid.FloorMaterial == Enum.Material.Air then return false end
    if distanceTo(request.target) > controller.config.recoveryDistance
        or (not controller.config.combatMovementPriority and manualEscapeIsWorking(request.target)) then
        controller.recoveryRequest = nil
        return false
    end
    if request.reason ~= "combo_finish" and targetDisabled(request.target) then
        controller.recoveryRequest = nil
        return false
    end
    if os.clock() < controller.manualDashPriorityUntil then return false end
    local direction, vector = chooseEscapeDirection(character, root, request.target)
    if not vector then
        controller.recoveryRequest = nil
        log("recovery_skip", { id = request.id, reason = "no_clear_exit" })
        return false
    end
    local acted
    if os.clock() - controller.lastDashAt >= adaptiveSideDashGap(request.target) then
        acted = nativeDash(direction, "recovery:" .. request.reason, vector)
    else
        acted = startMicroStep(request.target)
    end
    if acted then
        controller.recoveryRequest = nil
        log("recovery_exit", { id = request.id, reason = request.reason, direction = direction })
    end
    return acted == true
end

local function observeGetUp(character)
    if character ~= LocalPlayer.Character or not controller.running or not controller.enabled or not controller.armed then return end
    local down = (tonumber(character:GetAttribute("Ragdoll")) or 0) > 0
    if controller.downCharacter ~= character then
        controller.downCharacter = character
        controller.wasDown = down
        return
    end
    if down then
        controller.getUpRequest = nil
    elseif controller.wasDown and isCandidate(controller.target) then
        controller.getUpRequest = {
            character = character, target = controller.target, generation = controller.targetGeneration,
            deadline = os.clock() + controller.config.getUpWindow,
        }
        log("getup_queued", { target = controller.target.Name })
    end
    controller.wasDown = down
end

local function runGetUpRecovery(character, humanoid, root, threatModel)
    local request = controller.getUpRequest
    if not request then return false end
    if request.character ~= character or request.generation ~= controller.targetGeneration
        or request.target ~= controller.target or not isCandidate(request.target)
        or os.clock() > request.deadline then
        controller.getUpRequest = nil
        return false
    end
    if os.clock() < controller.escapeUntil or os.clock() < controller.dashRetryAt
        or not canRequestDash(character) or humanoid.FloorMaterial == Enum.Material.Air then return false end
    local direction, vector
    if threatModel or distanceTo(request.target) <= controller.config.recoveryDistance then
        if os.clock() - controller.lastDashAt < adaptiveSideDashGap(request.target) then return false end
        direction, vector = chooseEscapeDirection(character, root, threatModel or request.target)
    else
        if os.clock() - controller.lastDashAt >= adaptiveSideDashGap(request.target) then
            direction, vector = chooseApproachDirection(character, root, request.target)
        end
        if not vector and distanceTo(request.target) <= controller.config.chaseMaxDistance
            and os.clock() - controller.lastForwardDashAt >= controller.config.forwardDashGap then
            local aim = predictedPosition(request.target)
            if aim then
                local travel = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = { character, request.target }
                local landing = workspace:Raycast(root.Position + travel + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), params)
                if travel.Magnitude > 0.01 and landing and landing.Normal.Y >= 0.55
                    and not workspace:Raycast(root.Position, travel, params) then
                    direction, vector = "Front", travel.Unit
                end
            end
        end
    end
    if not vector then return false end
    if nativeDash(direction, "getup_recovery", vector) then
        controller.getUpRequest = nil
        log("getup_dash_requested", { direction = direction, target = request.target.Name })
        return true
    end
    return false
end

-- Server ragdoll = Motor6D off + BallSocket on + Ragdoll attribute (~1 s). We own the
-- character physics, so stand up locally after config.ragdollRelease instead of waiting.
local function shortenRagdoll(character)
    if character ~= LocalPlayer.Character or not controller.running or not controller.enabled then return end
    if (tonumber(character:GetAttribute("Ragdoll")) or 0) <= 0 then return end
    controller.ragdollCutId = (controller.ragdollCutId or 0) + 1
    local id = controller.ragdollCutId
    task.delay(controller.config.ragdollRelease, function()
        if id ~= controller.ragdollCutId or not controller.running or not controller.enabled then return end
        if character.Parent == nil or character ~= LocalPlayer.Character then return end
        if (tonumber(character:GetAttribute("Ragdoll")) or 0) <= 0 then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then return end
        local released = 0
        for _, joint in ipairs(character:GetDescendants()) do
            if joint:IsA("BallSocketConstraint") and joint.Enabled then
                local a0, a1 = joint.Attachment0, joint.Attachment1
                local p0, p1 = a0 and a0.Parent, a1 and a1.Parent
                joint.Enabled = false
                for _, motor in ipairs(character:GetDescendants()) do
                    if motor:IsA("Motor6D") and not motor.Enabled
                        and ((motor.Part0 == p0 and motor.Part1 == p1) or (motor.Part0 == p1 and motor.Part1 == p0)) then
                        motor.Enabled = true
                        released += 1
                    end
                end
            end
        end
        character:SetAttribute("Ragdoll", 0)
        humanoid.PlatformStand = false
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        log("ragdoll_cut", { joints = released, after = controller.config.ragdollRelease })
    end)
end

local function closestDamageThreat()
    if controller.config.focusOnly then
        return isCandidate(controller.target) and controller.target or nil
    end
    local folder = workspace:FindFirstChild("Characters")
    local best, bestDistance
    if not folder then
        return nil
    end
    for _, model in ipairs(folder:GetChildren()) do
        if isCandidate(model) then
            local distance = distanceTo(model)
            if distance <= controller.config.threatDistance + 4 and (not bestDistance or distance < bestDistance) then
                best = model
                bestDistance = distance
            end
        end
    end
    return best
end

local function watchCharacter(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end
    local lastHealth = humanoid.Health
    table.insert(controller.connections, character:GetAttributeChangedSignal("Ragdoll"):Connect(function()
        observeGetUp(character)
        shortenRagdoll(character)
    end))
    table.insert(controller.connections, humanoid.HealthChanged:Connect(function(health)
        if health < lastHealth - 0.01 and controller.running and controller.enabled and controller.armed then
            local threat = closestDamageThreat() or (isCandidate(controller.target) and controller.target or nil)
            controller.lastDamageAt = os.clock()
            controller.nextThink = 0
            controller.comboSerial += 1
            controller.comboBusy = false
            controller.busy = false
            controller.finisherCommitUntil = 0
            local entry = controller.recentEntry
            if entry and entry.target == threat and os.clock() - entry.at <= 1.5 then
                local learned = knowledgeFor(entry.target)
                learned.reactions.damageAfterFrontEntry = (learned.reactions.damageAfterFrontEntry or 0) + 1
                log("entry_feedback", { target = entry.target.Name, result = "damage_after_front_entry" })
                controller.recentEntry = nil
            end
            local activeCounter = controller.activeCounter
            if activeCounter and os.clock() - activeCounter.at <= 0.85 then
                local k = knowledgeFor(activeCounter.target)
                k.counterHistory = k.counterHistory or {}
                local ch = k.counterHistory[activeCounter.threatKind] or {}
                k.counterHistory[activeCounter.threatKind] = ch
                local entry = ch[string.lower(activeCounter.name)] or { uses = 0, successes = 0 }
                entry.uses = (entry.uses or 0) + 1
                ch[string.lower(activeCounter.name)] = entry
                log("counter_punished", { counter = activeCounter.name, threat = activeCounter.threatKind })
                controller.activeCounter = nil
            end
            if threat then
                controller.pendingEvadeUntil = os.clock() + 1.05
                controller.pendingThreat = threat
                controller.pendingThreatKind = "damage"
                local knowledge = knowledgeFor(threat)
                knowledge.successfulHits += 1
                knowledge.damage += lastHealth - health
            end
            if controller.pvp.RecordDamage then controller.pvp.RecordDamage(lastHealth-health,threat) end
            log("damage_taken", { amount = lastHealth - health, health = health, threat = threat and threat.Name or nil })
        end
        lastHealth = health
    end))
end

-- Game adapter: Jujutsu 9391468976 only. Existing panel artwork is unchanged.
do
    local p = controller.pvp
    p.combo = p.modules.combos.new({placeId=game.PlaceId, maxStage=4,
        terminalStages={0,4,5}, m1Gap=controller.config.m1Gap,
        chainResetSeconds=0.95, finisherResetSeconds=0.85,
        ackTimeout=0.95, readyTimeout=controller.config.m1ReadyTimeout,
        jumpTimeout=0.55, slamAfterStage=3, thirdRecovery=0,
        sequenceTimeout=8})
    p.dynamic = p.modules.dynamic.new({placeId=game.PlaceId,
        attackRange=controller.config.attackDistance, threatRange=controller.config.threatDistance,
        maxEngageRange=controller.config.retainDistance, maxVerticalDistance=16, switchMargin=10,
        repeatDelays={approach=0.12,retreat=0.25,dodge=0.3,parry=0.12,attack=0.09,punish=0.09}})

    p.movement=p.modules.movement.new({placeId=game.PlaceId,attackRange=controller.config.m1Range,
        maxEngageRange=controller.config.retainDistance,walkSpeed=24,dashHorizon=.4,
        dashGap=controller.config.dashRequestGap,dashAckTimeout=.09})
    p.animationCatalog={}
    p.animationAliases={}
    local animations=game:GetService("ReplicatedStorage"):FindFirstChild("Animations")
    if animations then
        for _,animation in ipairs(animations:GetDescendants()) do
            if animation:IsA("Animation") then
                p.animationCatalog[animation.AnimationId]=animation.Name
                local aliases=p.animationAliases[animation.AnimationId] or {}
                aliases[animation.Name]=true
                p.animationAliases[animation.AnimationId]=aliases
            end
        end
    end
    p.attackObservations=setmetatable({}, {__mode="k"})
    p.skillObservations=setmetatable({}, {__mode="k"})
    p.signalBound=setmetatable({}, {__mode="k"})
    -- Client-observed onset -> actual native order. No server/network onset claim.
    p.audit={};p.auditCounts={};p.defenseStats={orders=0,hitsAfterDefense=0,damageAfterDefense=0,
        onsetToOrderTotal=0,dispatchDelay=.016,dashRejected=0}
    function p.Audit(kind,data)
        local entry={t=now(),clock=os.clock(),kind=kind,data=data}
        p.audit[#p.audit+1]=entry
        if #p.audit>768 then table.remove(p.audit,1) end
        p.auditCounts[kind]=(p.auditCounts[kind] or 0)+1
        log(kind,data)
    end
    function p.DefenseDue(model)
        local obs=p.attackObservations[model]
        if not obs or obs.contactSeen or not obs.track.IsPlaying
            or os.clock()-obs.startedAt>1.5 then return true end
        local timing=p.modules.moveset_data.timingFor(obs.id,obs.track.Speed)
        if timing then
            local contact=timing.windup-(timing.spread or 0)*.5
            obs.impactAt=obs.startedAt+contact
            -- Timing is telemetry only. Real threats are defended at onset;
            -- reducing idle guard must never delay an incoming attack.
        end
        return true
    end
    function p.RecordDefense(model,action,sent,reason)
        local obs=model and p.attackObservations[model]
        local clock=os.clock()
        local age=obs and clock-obs.startedAt
        local delay=obs and math.max(0,clock-math.max(obs.observedAt or obs.startedAt,obs.defendAt or obs.startedAt))
        local stats=p.defenseStats
        stats.orders+=1
        if age then stats.onsetToOrderTotal+=age;stats.onsetSamples=(stats.onsetSamples or 0)+1 end
        if delay then stats.dispatchDelay=stats.dispatchDelay*.8+math.min(.12,delay)*.2 end
        p.lastDefense={at=clock,model=model,action=action,sent=sent,obs=obs}
        p.Audit("pvp_defense_latency",{target=model and model.Name,action=action,sent=sent,reason=reason,
            animation=obs and obs.id,onsetToOrder=age,dispatchDelay=delay,
            measuredWindup=obs and obs.impactAt and obs.impactAt-obs.startedAt,
            earlyBy=obs and obs.impactAt and obs.impactAt-clock,source="client_animation_to_native_order"})
    end
    function p.RecordDamage(amount,threat)
        local defense=p.lastDefense
        local age=defense and os.clock()-defense.at
        local recent=age and age<=.85
        if recent then
            p.defenseStats.hitsAfterDefense+=1
            p.defenseStats.damageAfterDefense+=amount
        end
        p.Audit("pvp_damage_feedback",{amount=amount,nearbyThreat=threat and threat.Name,
            afterDefense=recent==true,defenseAge=recent and age or nil,
            defense=recent and defense.action or nil,attackerConfirmed=false})
    end
    function p.SaveAudit()
        if not controller.running or os.clock()<(p.nextAuditAt or 0) then return end
        p.nextAuditAt=os.clock()+10
        if #p.audit==0 then return end
        local ok,err=pcall(function()
            local path="pvp/combat_audit.json"
            if not p.auditBackedUp and isfile(path) then
                writefile(path..".bak-"..os.date("%Y%m%d-%H%M%S"),readfile(path))
            end
            p.auditBackedUp=true
            writefile(path,HttpService:JSONEncode({placeId=game.PlaceId,jobId=game.JobId,
                version=controller.version,counts=p.auditCounts,defense=p.defenseStats,events=p.audit}))
        end)
        if not ok then log("pvp_audit_error",tostring(err)) end
    end
    function p.NotifyDash(pending,observed)
        p.dashOutcome={startedAt=pending.startedAt,observed=observed,at=os.clock()}
        if string.sub(pending.reason or "",1,11)=="predictive:" and p.movement.pending then
            p.movement:confirmDash(p.movement.pending.id,observed,os.clock())
        end
        p.Audit("pvp_dash_outcome",{direction=pending.direction,reason=pending.reason,observed=observed,
            elapsed=os.clock()-pending.startedAt})
        if not observed then
            p.defenseStats.dashRejected+=1
            p.nextMovementPlanAt=0
            task.defer(function()
                if not controller.running or pending.character~=LocalPlayer.Character
                    or pending.generation~=controller.targetGeneration then return end
                local active,kind,model=findImmediateThreat(controller.target)
                if active then
                    local covered=quickBlock(model,"dash_rejected_fallback")
                    p.Audit("pvp_dash_fallback",{covered=covered,target=model and model.Name,threat=kind})
                end
            end)
        end
    end

    -- Actual native hotbar items, never the selected character's name.
    function p.Inventory(character,target)
        local items,catalog={},{}
        for key=1,4 do
            local move=moveForKey(key)
            if move then
                local name=string.lower(move.Name)
                local data=p.modules.moveset_data.moves[name] or {}
                local rule=moveRules[name]
                local attrRange=tonumber(move:GetAttribute("Range"))
                local empirical=data.observed and tonumber(data.observed.maxHitDistance)
                -- Acceptance distance is not a hit distance. Never expand a melee
                -- rule from an old maxAcceptedDistance or from its input mode.
                local range=attrRange or (rule and rule.range) or data.range
                    or (data.confirmed and empirical and empirical>0 and empirical)
                -- Twofold's native Swing1 is a physical kick, not a projectile.
                -- Its old maxHitDistance included later movement. Use a conservative
                -- M1 engagement policy, without claiming a measured kick hitbox.
                local meleePolicy=move:GetAttribute("Service")=="TwofoldKickService"
                if meleePolicy then range=controller.config.m1Range end
                local id=tostring(move:GetAttribute("Service") or move.Name)
                local usable=canAct(character,true) and moveFitsTarget(move,target or controller.target)
                items[#items+1]={id=id,name=move.Name,service=move:GetAttribute("Service"),key=key,
                    available=true,ready=moveReady(move),usable=usable}
                if range and range>0 then
                    local counter=counterNames[name]==true
                    catalog[id]={verified=true,revision="item-range-1",kind=counter and "counter"
                        or (range>12 and "ranged" or "melee"),
                        area={shape="band",minRange=tonumber(move:GetAttribute("MinRange")) or 0,
                            maxRange=range,height=16},requiresLOS=true,requiresHit=false,
                        -- Band is an engagement envelope, not a measured hitbox.
                        rangeSource=meleePolicy and "conservative_melee_policy" or attrRange and "native_attribute" or (rule and "code_rule"
                            or data.range and data.rangeSource or "historical_hit_envelope"),
                        score=counter and -100 or (12-(data.priority or rule and rule.priority or 6))
                            +(data.observed and data.observed.hitRate or .5)*3}
                else
                    catalog[id]={verified=false,revision="unknown-area-1",rangeSource="unknown"}
                end
            end
        end
        local rReady = specialReady(character)
        local rMoveset = character and character:GetAttribute("Moveset")
        local rServiceName = rMoveset and (rMoveset .. "Service") or "SpecialService"
        local rUsable = canAct(character, true) and targetStanding(target or controller.target)
        local rId = "Special_R"
        items[#items+1] = {
            id = rId, name = "Special", service = rServiceName, key = "R",
            available = true, ready = rReady, usable = rUsable, isSpecial = true,
        }
        catalog[rId] = {
            verified = true, revision = "special-r-1", kind = "ranged",
            area = { shape = "band", minRange = 0, maxRange = 38, height = 16 },
            requiresLOS = true, requiresHit = false,
            rangeSource = "native_special_r",
            score = rReady and 9 or -50,
        }
        -- Fast item chains: every ready, verified attack item can follow the
        -- opener, best score first (observed hit rate + priority). No slot order
        -- is assumed; the engine re-checks readiness and area before each link.
        -- Slot order (comboSequence, e.g. 2,1,3,4) decides the chain; slots outside
        -- the sequence go last by score. Each link is re-checked by the engine.
        local sequence=type(getgenv)=="function" and type(getgenv().JACComboSequence)=="table"
            and getgenv().JACComboSequence
            or controller.config.comboSequenceByMoveset[character and character:GetAttribute("Moveset")]
            or controller.config.comboSequence or {}
        local rank={}
        for index,slot in ipairs(sequence) do if rank[slot]==nil then rank[slot]=index end end
        if rank["R"] == nil and rank["r"] == nil and rank[5] == nil then
            rank["R"] = 5
        end
        local links={}
        for _,item in ipairs(items) do
            local def=catalog[item.id]
            if def and def.verified and def.kind~="counter" and def.kind~="evasive"
                and item.ready and item.usable then
                -- Phases: 1 = close melee, 2 = push / knockback, 3 = ranged, 4 = R finisher.
                -- Sequence rank only orders links inside the same phase, so the
                -- chain never walks away from the target and then back in.
                local roles=controller.config.comboRoleByMoveset[character and character:GetAttribute("Moveset")]
                local role=(item.key=="R" or item.isSpecial) and "finisher"
                    or (roles and roles[item.key]) or (def.kind=="ranged" and "ranged" or "close")
                local phase=role=="finisher" and 4 or role=="ranged" and 3 or role=="push" and 2 or 1
                def.role=role; item.role=role; item.area=def.area
                links[#links+1]={id=item.id,score=def.score or 0,area=def.area,phase=phase,
                    rank=rank[item.key] or (item.key == "R" and 5 or 100)}
            end
        end
        table.sort(links,function(a,b)
            if a.phase~=b.phase then return a.phase<b.phase end
            if a.rank~=b.rank then return a.rank<b.rank end
            if a.score~=b.score then return a.score>b.score end
            return a.id<b.id
        end)
        local m1Follow={}
        for position,link in ipairs(links) do
            if #m1Follow<5 then m1Follow[#m1Follow+1]=link.id end
            -- Followups continue the sequence after this link, then wrap to earlier slots.
            local follow={}
            for offset=1,#links-1 do
                local other=links[(position-1+offset)%#links+1]
                if #follow<5 then follow[#follow+1]=other.id end
            end
            catalog[link.id].followups=follow
            -- Opener preference follows the sequence (small, below the native M1 score).
            catalog[link.id].score=(catalog[link.id].score or 0)+math.max(0,(5-math.min(link.rank,5)))*0.8
        end
        return p.modules.combos.Inventory(items,catalog,{id="native_m1",revision="jac-native-1",
            verified=true,available=true,score=20,requiresLOS=true,followups=m1Follow,
            area={shape="band",minRange=0,maxRange=controller.config.m1Range},
            supportsSlam=true,slamArea={shape="band",minRange=0,maxRange=14}})
    end

    function p.AddInventory(s,root,tr)
        s.inventory=p.Inventory(s.character,s.target)
        s.skills={}
        for _,item in ipairs(s.inventory.items) do
            s.skills[item.id]={ready=item.ready,usable=item.usable,requiresHit=item.requiresHit}
        end
        s.slamAllowed=p.stage>=2
        s.distance=root and tr and (tr.Position-root.Position).Magnitude or math.huge
        if root and tr then
            local relative=root.CFrame:VectorToObjectSpace(tr.Position-root.Position)
            local velocity=root.CFrame:VectorToObjectSpace(tr.AssemblyLinearVelocity-root.AssemblyLinearVelocity)
            s.relative={x=relative.X,y=relative.Y,z=-relative.Z}
            s.relativeVelocity={x=velocity.X,y=velocity.Y,z=-velocity.Z}
            local params=RaycastParams.new()
            params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances={s.character,s.target}
            params.RespectCanCollide=true
            s.lineOfSight=workspace:Raycast(root.Position,tr.Position-root.Position,params)==nil
        end
        return s
    end

    function p.ObserveOpponents(character,root,clock)
        local cached=p.opponentCache
        if cached and cached.target==controller.target and cached.character==character and cached.root==root and clock-cached.time<.03 then
            return cached.observations
        end
        local observations={}
        local folder=workspace:FindFirstChild("Characters")
        if not folder or not root then return observations end
        for _,model in ipairs(folder:GetChildren()) do
            if isCandidate(model) and (not controller.config.focusOnly or model == controller.target) then
                local hum,tr=characterParts(model)
                local distance=tr and (tr.Position-root.Position).Magnitude or math.huge
                if hum and tr and distance<=controller.config.retainDistance then
                    local params=RaycastParams.new()
                    params.FilterType=Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances={character,model}
                    params.RespectCanCollide=true
                    local visible=workspace:Raycast(root.Position,tr.Position-root.Position,params)==nil
                    local active,kind=targetThreat(model,distance)
                    local animation=p.attackObservations[model]
                    local move,attackId,impactAt,timing
                    if animation and clock-animation.startedAt<1.5 then
                        attackId=animation.id..":"..tostring(animation.startedAt)
                        timing=p.modules.moveset_data.timingFor(animation.id,animation.track.Speed)
                        if timing then
                            impactAt=animation.startedAt+timing.windup
                            move={confirmed=true,windup=timing.windup,activeDuration=.12}
                        end
                    end
                    local learned = knowledgeFor(model)
                    local measuredContact=tonumber(timing and timing.maxContactDistance)
                        or tonumber(learned.maxContactDistance) or 10.5
                    if not measuredContact or measuredContact~=measuredContact or measuredContact<=0
                        or measuredContact==math.huge then measuredContact=10.5 end
                    local isRealAttack = active == true
                    local o={id=model,position=tr.Position,velocity=tr.AssemblyLinearVelocity,
                        facing=tr.CFrame.LookVector,health=hum.Health,maxHealth=hum.MaxHealth,
                        alive=hum.Health>0,hostile=true,sampledAt=clock,distance=distance,
                        verticalDistance=tr.Position.Y-root.Position.Y,visible=visible,
                        invulnerable=model:FindFirstChildOfClass("ForceField")~=nil,
                        blocking=hasInfo(model,"Block"),stunned=targetDisabled(model),
                        attacking=isRealAttack,move=move,attackId=attackId,impactAt=impactAt,
                        threatKind=kind,contactDistance=measuredContact,
                        isSpecial=controller.specialThreats[model]~=nil and not controller.specialThreats[model].nativeMelee,
                        specialThreat=controller.specialThreats[model]~=nil and not controller.specialThreats[model].nativeMelee}
                    local inventory=p.Inventory(character,model)
                    local reach=controller.config.m1Range
                    for _,item in ipairs(inventory.items) do
                        if item.verified and item.ready and item.usable and item.area
                            and item.kind~="counter" and item.kind~="evasive" then reach=math.max(reach,item.area.maxRange) end
                    end
                    o.attackRange=reach
                    local toward=root.Position-tr.Position
                    local facing=toward.Magnitude>.01 and tr.CFrame.LookVector:Dot(toward.Unit) or 0
                    o.targetsSelf=active and facing>.55 or false
                    -- Positional danger policy using measured contact distance
                    if isRealAttack and visible and not o.stunned then
                        o.riskEnvelope={active=true,shape="circle",range=math.max(measuredContact, controller.config.threatDistance),
                            impactAt=impactAt,expiresAt=impactAt and impactAt+.12 or clock+.12,source="measured_timing_spacing"}
                    end
                    -- No guessed cone, damage radius, or parry eligibility.
                    observations[#observations+1]=o
                end
            end
        end
        table.sort(observations,function(a,b) return a.distance<b.distance end)
        while #observations>24 do table.remove(observations) end
        p.opponentCache={target=controller.target,character=character,root=root,time=clock,observations=observations}
        return observations
    end

    function p.SwitchOffense(model)
        if model==controller.target then return true end
        if controller.config.focusOnly then return false end
        if not controller.armed or not isCandidate(model) or controller.comboBusy or controller.busy
            or not canAct(LocalPlayer.Character)
            or (controller.pendingMove and os.clock()<controller.pendingMove.deadline)
            or os.clock()<(p.switchAfter or 0) then return false end
        -- Never abandon a live rival for a far body or a dummy: the new rival must be
        -- close, and clearly closer than the current one unless the current one is
        -- gone/down or has been out of reach.
        local old=controller.target
        local newDistance=distanceTo(model)
        if newDistance>(controller.config.switchMaxDistance or 35) then return false end
        if isCandidate(old) then
            local oldDistance=distanceTo(old)
            local oldUsable=targetStanding(old) and oldDistance<=(controller.config.switchMaxDistance or 35)
            if oldUsable and (os.clock()<(p.holdTargetUntil or 0)
                or newDistance>oldDistance-(controller.config.switchMargin or 8)) then return false end
        end
        p.holdTargetUntil=os.clock()+(controller.config.switchHold or 3)
        p.Cancel("dynamic_target_switch")
        controller.target=model
        controller.targetGeneration+=1
        controller.actionSerial+=1
        controller.moveIntent=nil
        controller.pathWaypoints=nil
        controller.pathTarget=nil
        controller.targetProgress=nil
        controller.comboRequested=true
        controller.nextComboAt=0
        bindTargetEvents(model)
        p.switchAfter=os.clock()+.9
        p.Audit("pvp_target_switch",{from=old and old.Name,to=model.Name,
            distance=distanceTo(model),minimumHold=.9,reason="multi_opponent_opportunity"})
        return true
    end

    function p.MovementSnapshot(character,humanoid,root,target,opponents,range)
        local clock=os.clock()
        local selected
        for _,o in ipairs(opponents) do if o.id==target then selected=o;break end end
        local dashReady=canRequestDash(character)
        local s={now=clock,sampledAt=clock,placeId=game.PlaceId,jobId=game.JobId,
            characterId=character,enabled=controller.running and controller.enabled,
            armed=controller.armed,movementAllowed=true,
            manualOverride=UserInputService:GetFocusedTextBox()~=nil,
            self={position=root.Position,velocity=root.AssemblyLinearVelocity,health=humanoid.Health,
                stunned=character:GetAttribute("Stun")==true or hasInfo(character,"Stun"),
                ragdolled=(tonumber(character:GetAttribute("Ragdoll")) or 0)>0,
                busy=controller.busy,comboBusy=controller.comboBusy,defenseInterruptible=true},
            target=selected,opponents=opponents,range=range,
            contactRange=controller.config.engageDistance,
            can={move=canAct(character),dash=dashReady and not p.dashDispatchPending},
            cooldowns={dash=math.max(0,controller.dashRetryAt-clock,
                controller.lastDashRequestAt+controller.config.dashRequestGap-clock,
                controller.lastDashAt+adaptiveSideDashGap(target)-clock)},
            -- Conservative upper travel envelope from native 200->16 speed,
            -- Circular.Out easing over .4s: integral = 22.195 * multiplier.
            dashTravel=p.DashTravel(character),navigation={walk={},dash={}}}
        if not selected then return s end
        s.manualInput=controller.HasManualInput()
        -- Navigation route for long chases / blocked lanes (planner picks waypoints).
        local waypoints=controller.pathWaypoints
        if waypoints and controller.pathTarget==target and controller.pathComputedAt then
            local list={}
            for i,w in ipairs(waypoints) do
                list[i]={position=w.Position,jump=w.Action==Enum.PathWaypointAction.Jump}
            end
            s.path={targetId=target,computedAt=controller.pathComputedAt,busy=controller.pathBusy==true,waypoints=list}
        else
            s.path={targetId=target,busy=controller.pathBusy==true}
        end
        -- Approach specials the character can fire right now (Gojo teleport, etc.).
        local rule=movementSpecialRules[character:GetAttribute("Moveset")]
        if rule and specialReady(character) and targetStanding(target) and not controller.observedSkill
            and not controller.blockActive then
            s.specials={{name=rule.name,minDistance=rule.minDistance,maxDistance=rule.maxDistance,
                role=rule.role,ready=true,crowded=specialDestinationCrowded(character,target)}}
            s.flank=rule.role=="mixup" and spacingContext(character,root,target).flank or nil
        end
        -- Breathless-combo phases: the post-slam chain owns the first pass; after it
        -- ends (or never ran) the planner reuses any ready push/ranged slot.
        local chainOpen=not p.postChainBusy and p.stage==3
        s.combo={closeDone=chainOpen and (p.lastChainEndAt~=nil and clock-p.lastChainEndAt<3)}
        if chainOpen and s.combo.closeDone and not controller.observedSkill and not controller.blockActive
            and targetStanding(target) then
            if clock>=(p.comboInvAt or 0) then
                p.comboInvAt=clock+.12
                p.comboInv=p.Inventory(character,target)
            end
            s.specials=s.specials or {}
            for _,item in ipairs(p.comboInv and p.comboInv.items or {}) do
                if item.key~="R" and item.ready and item.usable and item.area and (item.role=="push" or item.role=="ranged") then
                    s.specials[#s.specials+1]={name="slot:"..tostring(item.key),role=item.role=="push" and "knockback" or "ranged",
                        minDistance=item.area.minRange or 0,maxDistance=item.area.maxRange,ready=true}
                end
            end
        end
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={workspace:FindFirstChild("Characters") or character,character,target}
        params.RespectCanCollide=true
        for _,candidate in ipairs(p.movement:candidates(s)) do
            for _,kind in ipairs({"walk","dash"}) do
                if (kind=="walk" and s.can.move) or (kind=="dash" and s.can.dash and s.cooldowns.dash<=0) then
                local travel=kind=="dash" and s.dashTravel or p.movement.config.walkSpeed*p.movement.config.walkHorizon
                local direction=candidate.direction*travel
                local hit=workspace:Blockcast(CFrame.new(root.Position),Vector3.new(4.4,3.5,4.4),direction,params)
                local ground=true
                for i=0,math.ceil(travel/3) do
                    local point=root.Position+direction*(i/math.max(1,math.ceil(travel/3)))
                    local floor=workspace:Raycast(point+Vector3.new(0,1,0),Vector3.new(0,-8,0),params)
                    if not floor or floor.Normal.Y<.6 or root.Position.Y-floor.Position.Y>5 then ground=false;break end
                end
                s.navigation[kind][candidate.route]={clear=hit==nil and not (kind=="dash" and candidate.native=="Front"),grounded=ground,distance=travel}
                end
            end
        end
        return s
    end

    function p.DashTravel(character)
        local info=character and character:FindFirstChild("Info")
        local mult=info and info:FindFirstChild("DashMultiplier")
        return 22.2*math.clamp(mult and tonumber(mult.Value) or 1,.1,3)
    end

    function p.Move(character,humanoid,root,target,opponents,range,defenseOnly)
        if os.clock()<(p.nextMovementPlanAt or 0) then return false end
        p.nextMovementPlanAt=os.clock()+.04
        local s=p.MovementSnapshot(character,humanoid,root,target,opponents,range)
        local d=p.movement:decide(s)
        p.lastMovementProposal=d
        if defenseOnly and not d.interruptCombo then return false end
        if d.action=="hold" then
            if d.reason=="m1_contact_ready" or d.reason=="item_range_reached" or d.reason=="action_owned" then
                controller.moveIntent=nil
                if not controller.HasManualInput() then humanoid:Move(Vector3.zero,false) end
            end
            return false
        end
        if d.action=="dash" then
            if p.dashDispatchPending or controller.dashPending then return false end
            p.dashDispatchPending=true
            local generation=controller.targetGeneration
            task.spawn(function()
                local ok,err=pcall(function()
                    if controller.running and controller.enabled and controller.armed
                        and controller.targetGeneration==generation and os.clock()<=d.expiresAt then
                        p.movement:step(s,{dash=function(proposal)
                            if proposal.interruptCombo then p.Cancel("predictive_evasion") end
                            p.dispatchThreat=proposal.interruptCombo and target or nil
                            local sent=nativeDash(proposal.nativeDirection,"predictive:"..proposal.reason,proposal.worldDirection)
                            p.dispatchThreat=nil
                            if sent then p.Audit("pvp_movement_dispatch",{action="dash",route=proposal.route,
                                target=target.Name,distance=distanceTo(target),preContact=distanceTo(target)>controller.config.m1Range,
                                opponents=proposal.opponentsObserved,risk=proposal.risk,currentRisk=proposal.currentRisk,
                                x=proposal.worldDirection.X,z=proposal.worldDirection.Z,reason=proposal.reason}) end
                            return sent
                        end})
                        local receipt=p.movement.pending
                        local outcome=p.dashOutcome
                        if receipt and outcome and outcome.startedAt>=s.now and outcome.at>=receipt.issuedAt then
                            p.movement:confirmDash(receipt.id,outcome.observed,os.clock())
                        end
                    end
                end)
                p.dashDispatchPending=false
                if not ok then log("pvp_movement_error",tostring(err)) end
            end)
            return true
        end
        local _,accepted=p.movement:step(s,{walk=function(proposal)
            if proposal.interruptCombo then p.Cancel("predictive_step") end
            if proposal.jump and not controller.comboBusy then humanoid.Jump=true end
            setMoveIntent(proposal.worldDirection,proposal.duration,false,
                proposal.reason=="contact_approach" and controller.config.engageDistance or nil)
            return true
        end,
        requestPath=function(proposal)
            local _,targetRoot=characterParts(target)
            if not targetRoot or controller.pathBusy then return false end
            requestPathAsync(root,target,targetRoot)
            p.Audit("pvp_movement_dispatch",{action="requestPath",target=target.Name,
                distance=distanceTo(target),reason=proposal.reason})
            return true
        end,
        special=function(proposal)
            local distance=distanceTo(target)
            if controller.busy or controller.comboBusy then return false end
            local slotKey=tonumber(string.match(tostring(proposal.name),"^slot:(%d)$"))
            if slotKey then
                if p.postChainBusy then return false end
                task.spawn(function()
                    faceForAction(target)
                    local sent=useNativeMove(slotKey,"combo_phase:"..tostring(proposal.role),discoverProfile(character))
                    if sent then p.Audit("pvp_movement_dispatch",{action="special",name=proposal.name,
                        target=target.Name,distance=distanceTo(target),reason=proposal.reason}) end
                end)
                return true
            end
            task.spawn(function()
                local ok,used=pcall(useMovementSpecial,character,humanoid,root,target,distance)
                if ok and used then
                    p.Audit("pvp_movement_dispatch",{action="special",name=proposal.name,
                        target=target.Name,distance=distance,reason=proposal.reason})
                end
            end)
            return true
        end})
        if accepted and os.clock()>=(p.nextWalkAuditAt or 0) then
            p.nextWalkAuditAt=os.clock()+.5
            p.Audit("pvp_movement_dispatch",{action="walk",route=d.route,target=target.Name,
                distance=distanceTo(target),opponents=d.opponentsObserved,reason=d.reason,
                x=d.worldDirection.X,z=d.worldDirection.Z})
        end
        return accepted
    end

    function p.OnOpponentAnimation(model,track,id)
        -- Record actual playback, correcting for a late AnimationPlayed callback.
        local clock=os.clock()
        local speed=math.abs(track.Speed)
        local started=clock-(speed>.001 and track.TimePosition/speed or 0)
        local aliases=p.animationAliases[id]
        local animationName=aliases and aliases[track.Name] and track.Name or p.animationCatalog[id] or track.Name
        local supported=string.match(animationName,"^Melee[1-4]$") or animationName=="LapseBlue"
            or animationName=="TwofoldKick" or animationName=="RapidPunches" or animationName=="ReversalRed"
        if supported then
            local observation={id=id,startedAt=started,observedAt=clock,track=track,name=animationName,speed=speed}
            p.attackObservations[model]=observation
            if not string.match(animationName,"^Melee[1-4]$") then
                local skills=p.skillObservations[model] or {}
                p.skillObservations[model]=skills
                skills[animationName]=observation
            end
            p.DefenseDue(model)
            if observation.defendAt and observation.defendAt>clock then
                task.delay(observation.defendAt-clock,function()
                    if controller.running and p.attackObservations[model]==observation and track.IsPlaying then p.React(model) end
                end)
            end
        end
        local markerSeen=false
        -- Do not allocate marker listeners for every unrelated Action animation.
        if not supported then
            p.React(model)
            return
        end
        local bindings={}
        local function disconnect()
            for _,connection in ipairs(bindings) do connection:Disconnect() end
            table.clear(bindings)
        end
        -- Only an actual authored marker can provide this measurement. Listening
        -- for these names does not assert they exist or that damage was dealt.
        for _,marker in ipairs({"Hit","Hitbox","Damage"}) do
            bindings[#bindings+1]=track:GetMarkerReachedSignal(marker):Connect(function()
                if not controller.running or markerSeen or math.abs(track.Speed-speed)>.05 then return end
                markerSeen=true
                local windup=os.clock()-started
                p.modules.moveset_data.recordTiming(id,windup,"animation_marker:"..marker,model.Name,speed)
                log("pvp_windup_marker",{id=id,windup=windup,marker=marker,damageConfirmed=false})
            end)
        end
        bindings[#bindings+1]=track.Stopped:Connect(disconnect)
        task.delay(4,disconnect)
        -- Every observed rival can wake defense, including a flank attacker.
        p.React(model)
    end

    function p.React(model)
        if controller.config.focusOnly and model ~= controller.target then return end
        if not controller.running or not controller.enabled or not controller.armed
            or UserInputService:GetFocusedTextBox() or not isCandidate(model) then return end
        controller.nextThink=0
        p.opponentCache=nil
        p.nextMovementPlanAt=0
        local active,kind=targetThreat(model,distanceTo(model))
        if active then
            local character,humanoid,root=localParts()
            if character and humanoid and root and not controller.blockActive and not p.dashDispatchPending then
                local observations=p.ObserveOpponents(character,root,os.clock())
                if p.Move(character,humanoid,root,model,observations,
                    {min=0,max=controller.config.m1Range},true) then return end
            end
            quickBlock(model,"nearby_attack_event")
        end
    end

    function p.OnContact(service,phase,...)
        local args={...}
        -- Verified current CharlesController: Hit(attacker,victim,stage).
        -- Other already supported controllers retain Hit(victim,stage).
        local explicitAttacker=service=="CharlesService" and phase=="Hit" and args[1] or nil
        local victim=explicitAttacker and args[2] or args[1]
        local hitStage=explicitAttacker and args[3] or args[2]
        if explicitAttacker==LocalPlayer.Character and typeof(victim)=="Instance" then
            local hum=victim:FindFirstChildOfClass("Humanoid")
            p.Audit("pvp_native_hit",{service=service,target=victim.Name,stage=hitStage,
                attacker=LocalPlayer.Name,explicitAttacker=true,health=hum and hum.Health})
            local request=p.combo.pending or p.combo.lastAttack
            if request and request.kind=="m1" and request.stage==hitStage
                and p.combo.context and p.combo.context.target==victim then
                local slam=p.slamReceipt
                local down=hitStage==4 and slam and slam.target==victim
                    and slam.character==explicitAttacker and os.clock()-slam.at<1.2 and slam.downObserved
                p.combo:Confirm(request.id,{hit=true,variant=down and "Down" or nil})
                if down then
                    slam.impactObserved=true
                    p.combo:ConfirmNativeFinisher(slam.serial,victim,{hit=true,variant="Down"})
                    p.Audit("pvp_slam_impact",{target=victim.Name,source="CharlesService.Hit",
                        downObserved=true,explicitAttacker=true,healthDeltaRequired=true})
                end
            end
        end
        for _,receipt in ipairs(p.damageReceipts or {}) do
            if phase=="Hit" and victim==receipt.target and os.clock()-receipt.clock<=.85
                and service==receipt.service
                and (not explicitAttacker or explicitAttacker==receipt.attacker) then
                receipt.contactObserved=true
                receipt.explicitAttacker=explicitAttacker==receipt.attacker
            end
        end
        local m1Receipt=p.m1Receipt
        if m1Receipt and os.clock()-m1Receipt.at<=.85 and phase=="Hit" and victim==m1Receipt.target
            and service==tostring(m1Receipt.character:GetAttribute("Moveset")).."Service"
            and (not explicitAttacker or explicitAttacker==m1Receipt.character) then
            m1Receipt.nativeContact=true
        end
        local receipt=p.slamReceipt
        if (service=="GojoService" or service=="CharlesService") and receipt and os.clock()-receipt.at<=1.2
            and receipt.character==LocalPlayer.Character then
            if phase=="Swing2" and args[1]==receipt.character and args[2]==4 and args[3]=="Down" then
                receipt.downObserved=true
                local hum=receipt.target:FindFirstChildOfClass("Humanoid")
                receipt.healthBefore=hum and hum.Health
                p.Audit("pvp_slam_variant",{variant="Down",native=true,target=receipt.target.Name})
            elseif service=="GojoService" and phase=="AerialHit" and args[1]==receipt.character and args[2]==receipt.target then
                receipt.impactObserved=true
                local hum=receipt.target:FindFirstChildOfClass("Humanoid")
                receipt.healthAtImpact=hum and hum.Health
                task.delay(.12,function()
                    if not controller.running or p.slamReceipt~=receipt then return end
                    local health=hum and hum.Parent and hum.Health
                    local loss=health and receipt.healthBefore and math.max(0,receipt.healthBefore-health) or 0
                    receipt.healthLoss=loss
                    if receipt.downObserved and receipt.impactObserved then
                        p.combo:ConfirmNativeFinisher(receipt.serial,receipt.target,{hit=true,variant="Down"})
                    end
                    p.Audit("pvp_slam_damage",{target=receipt.target.Name,healthLoss=loss,
                        damageConfirmed=loss>0,exclusiveAttribution=false,downObserved=receipt.downObserved})
                end)
                p.Audit("pvp_slam_impact",{target=receipt.target.Name,source="GojoService.AerialHit",
                    downObserved=receipt.downObserved,healthDeltaRequired=true})
                local request=p.combo.pending or p.combo.lastAttack
                if request and request.kind=="m1" and request.variant=="Down" and receipt.downObserved then
                    p.combo:Confirm(request.id,{hit=true,variant="Down"})
                end
            end
        end
        if (service=="TwofoldKickService" or service=="RapidPunchesService") and phase=="Hit" then
            local expected=service=="TwofoldKickService" and "TwofoldKick" or "RapidPunches"
            local moveName=service=="TwofoldKickService" and "twofold kick" or "rapid punches"
            local _,vr=characterParts(victim)
            local found
            for model,skills in pairs(p.skillObservations) do
                local obs=skills[expected]
                if obs and obs.name==expected and not obs.contactSeen and model~=victim
                    and os.clock()-obs.startedAt<=1 and math.abs(obs.track.Speed-obs.speed)<=.05 then
                    local _,ar=characterParts(model)
                    local delta=ar and vr and vr.Position-ar.Position
                    if delta and delta.Magnitude<=12 and delta.Magnitude>.01
                        and ar.CFrame.LookVector:Dot(delta.Unit)>.15 then
                        if found then return end
                        found={obs=obs,model=model,distance=delta.Magnitude}
                    end
                end
            end
            if found then
                found.obs.contactSeen=true
                p.modules.moveset_data.recordContact(moveName,found.obs.id,os.clock()-found.obs.startedAt,
                    found.distance,"unique_attacker_"..service..".Hit",found.model.Name,found.obs.speed)
                p.Audit("pvp_skill_contact",{service=service,id=found.obs.id,distance=found.distance,
                    windup=os.clock()-found.obs.startedAt,damageConfirmed=false})
            end
            return
        end
        if service=="LapseBlueService" then
            -- Native LapseBlueController.Grab(attacker,victim,object).
            if phase~="Grab" then return end
            local attacker=args[1]
            victim=args[2]
            local obs=p.skillObservations[attacker] and p.skillObservations[attacker].LapseBlue
            if not obs or os.clock()-obs.startedAt>3 or obs.contactSeen or obs.name~="LapseBlue" or math.abs(obs.track.Speed-obs.speed)>.05 then return end
            local _,ar=characterParts(attacker)
            local _,vr=characterParts(victim)
            if not ar or not vr then return end
            obs.contactSeen=true
            p.modules.moveset_data.recordContact("lapse blue",obs.id,os.clock()-obs.startedAt,
                (ar.Position-vr.Position).Magnitude,"native_LapseBlueService.Grab",attacker.Name,obs.speed)
            p.Audit("pvp_skill_contact",{service=service,id=obs.id,windup=os.clock()-obs.startedAt,
                source="explicit_attacker_grab",damageConfirmed=false})
            return
        end
        -- Read native Hit(victim,stage) contracts for these five services.
        local supported={ItadoriService="Itadori",GojoService="Gojo",MegumiService="Megumi",
            ChosoService="Choso",HakariService="Hakari",TodoService="Todo"}
        local enemySet=supported[service]
        if not enemySet or phase~="Hit" then return end
        local _,vr=characterParts(victim)
        if not vr then return end
        local matching={}
        for model,obs in pairs(p.attackObservations) do
            if model~=victim and model:GetAttribute("Moveset")==enemySet and not obs.contactSeen
                and math.abs(obs.track.Speed-obs.speed)<=.05
                and string.match(obs.name or "","^Melee[1-4]$")
                and (type(args[2])~="number" or obs.name=="Melee"..tostring(args[2])
                    or (p.animationAliases[obs.id] and p.animationAliases[obs.id]["Melee"..tostring(args[2])]))
                and os.clock()-obs.startedAt>=.01 and os.clock()-obs.startedAt<=.8 then
                local _,ar=characterParts(model)
                local delta=ar and vr.Position-ar.Position
                if ar and delta.Magnitude<=12 and delta.Magnitude>.01
                    and ar.CFrame.LookVector:Dot(delta.Unit)>.15 then
                    matching[#matching+1]={model=model,obs=obs,distance=delta.Magnitude}
                end
            end
        end
        -- Refuse multi-attacker ambiguity, rather than crediting the lock target.
        if #matching~=1 then return end
        local found=matching[1]
        found.obs.contactSeen=true
        local windup=os.clock()-found.obs.startedAt
        p.modules.moveset_data.recordContact("native melee",found.obs.id,windup,found.distance,
            "unique_attacker_"..service..".Hit",found.model.Name,found.obs.speed)
        log("pvp_contact_measured",{id=found.obs.id,windup=windup,distance=found.distance,
            source="unique_attacker_native_hit",damageConfirmed=false})
    end
    do
        local ok,Knit=pcall(require,game:GetService("ReplicatedStorage").Knit.Knit)
        if ok then
            for _,service in ipairs({"LapseBlueService","TwofoldKickService","RapidPunchesService","ItadoriService","GojoService","MegumiService","ChosoService","HakariService","TodoService"}) do
                local success,connection=pcall(function()
                    return Knit.GetService(service).Effects:Connect(function(phase,...)
                        if controller.running then p.OnContact(service,phase,...) end
                    end)
                end)
                if success then table.insert(controller.connections,connection) end
            end
        end
    end

    function p.SaveTiming()
        local data=p.modules.moveset_data
        local count=data.timingReport().samples
        if count==0 or count==p.lastSavedTimingCount then return end
        local path="pvp/measured_timings.json"
        local ok,err=pcall(function()
            if isfile(path) then
                writefile(path..".bak-"..os.date("%Y%m%d-%H%M%S"),readfile(path))
            end
            writefile(path,HttpService:JSONEncode({placeId=game.PlaceId,version=1,
                samples=data.animationTimings,recordedAt=now()}))
        end)
        if ok then p.lastSavedTimingCount=count else log("pvp_timing_save_error",tostring(err)) end
    end
    do
        local path="pvp/measured_timings.json"
        pcall(function()
            if not isfile(path) then return end
            local stored=HttpService:JSONDecode(readfile(path))
            if stored.placeId~=game.PlaceId or type(stored.samples)~="table" then return end
            for id,bucket in pairs(stored.samples) do
                if not p.modules.moveset_data.animationTimings[id] and type(id)=="string" and type(bucket)=="table" and type(bucket.samples)=="table"
                    and type(bucket.source)=="string" and type(bucket.speed)=="number" then
                    for i=1,math.min(#bucket.samples,12) do
                        if bucket.moveName and type(bucket.maxContactDistance)=="number" then
                            p.modules.moveset_data.recordContact(bucket.moveName,id,bucket.samples[i],
                                bucket.maxContactDistance,bucket.source,bucket.opponent,bucket.speed)
                        else
                            p.modules.moveset_data.recordTiming(id,bucket.samples[i],bucket.source,bucket.opponent,bucket.speed)
                        end
                    end
                end
            end
        end)
    end

    function p.BindSignals(model)
        if p.signalBound[model] then return end
        p.signalBound[model]=true
        local connections={}
        local function react() p.React(model) end
        local victimHumanoid = model:FindFirstChildOfClass("Humanoid")
        if victimHumanoid then
            connections[#connections+1]=victimHumanoid.HealthChanged:Connect(function(health)
                local receipt=p.m1Receipt
                if not receipt or receipt.target~=model or receipt.character~=LocalPlayer.Character
                    or receipt.confirmed or os.clock()-receipt.at>.85 then return end
                local nativeToken=tonumber(receipt.character:GetAttribute("LastM1")) or 0
                local loss=receipt.healthBefore-health
                if loss<=0 or nativeToken==receipt.nativeToken then return end
                receipt.confirmed=true
                receipt.data.damageConfirmed=true
                receipt.data.healthLoss=loss
                receipt.data.exclusiveAttribution=false
                p.Audit("pvp_m1_damage",{target=model.Name,request=receipt.request,
                    damageConfirmed=true,healthLoss=loss,nativeAccepted=true,
                    nativeContact=receipt.nativeContact==true,exclusiveAttribution=false,
                    sinceGuardRelease=receipt.data.sinceGuardRelease})
            end)
        end
        for _,attr in ipairs({"LastM1","LastM2"}) do
            connections[#connections+1]=model:GetAttributeChangedSignal(attr):Connect(react)
        end
        local info=model:FindFirstChild("Info")
        if info then connections[#connections+1]=info.ChildAdded:Connect(react) end
        connections[#connections+1]=model.AncestryChanged:Connect(function()
            if model:IsDescendantOf(workspace) then return end
            for _,connection in ipairs(connections) do connection:Disconnect() end
            p.signalBound[model]=nil;p.attackObservations[model]=nil
        end)
        for _,connection in ipairs(connections) do table.insert(controller.connections,connection) end
    end

    function p.ReleaseJump()
        if not p.jumpOwned then return end
        p.jumpOwned = false
        if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            local active = ControlModule and ControlModule.activeController
            if active and active == p.jumpController then
                active.isJumping = p.previousIsJumping
                active.jumpRequested = p.previousJumpRequest
            end
            if p.jumpHumanoid and p.jumpHumanoid.Parent then p.jumpHumanoid.Jump = false end
        end
        p.jumpController, p.jumpHumanoid = nil, nil
    end

    function p.HoldJump()
        if not p.jumpOwned then return end
        local character = LocalPlayer.Character
        if not controller.running or not controller.enabled or not controller.armed
            or not character or p.jumpHumanoid.Parent ~= character
            or not canQueueM1(character) then p.Cancel("jump_interrupted"); return end
        if hasInfo(character,"NoJump") or character:GetAttribute("Movement") then return end
        if p.jumpController then p.jumpController.isJumping = true end
        p.jumpHumanoid.Jump = true
    end

    function p.Cancel(reason)
        if p.combo:GetState().busy then
            p.combo:Cancel(reason)
            log("pvp_combo_cancel", {reason=reason,stage=p.combo:GetState().stage})
            controller.comboSerial += 1
            controller.comboBusy = false
            controller.busy = false
        end
        p.ReleaseJump()
        controller.nextComboAt = os.clock() + 0.14
    end

    function p.Snapshot(observedTarget)
        local character, humanoid, root = localParts()
        local target = observedTarget or controller.target
        local th, tr = characterParts(target)
        local last = character and tonumber(character:GetAttribute("LastM1")) or 0
        last = last or 0
        local age = last > 0 and math.max(0, now()-last) or 999
        local state = p.combo:GetState()
        local finisher = state.stage >= 3
        local physicalM1 = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        local jumpReady,jumpReason=false,"before_third"
        if finisher then jumpReady,jumpReason=prepareUniversalDownslam(character,target,os.clock()-age,controller.comboSerial) end
        local manual = UserInputService:GetFocusedTextBox() ~= nil
            or (not controller.config.combatMovementPriority and os.clock()<controller.manualDashPriorityUntil)
        local result = {now=os.clock(), placeId=game.PlaceId, jobId=game.JobId,
            character=character, target=target, loadout=character and character:GetAttribute("Moveset") or "",
            enabled=controller.running and controller.enabled, armed=controller.armed,
            localAlive=humanoid ~= nil and humanoid.Health>0, targetAlive=th ~= nil and th.Health>0,
            stunned=character and (character:GetAttribute("Stun")==true or hasInfo(character,"Stun")),
            ragdolled=character and (tonumber(character:GetAttribute("Ragdoll")) or 0)>0,
            defending=controller.blockActive, escaping=os.clock()<controller.escapeUntil,
            manualOverride=manual,
            physicalM1=physicalM1,
            manualM1=physicalM1 or os.clock()-(p.lastNativeM1At or -math.huge)<0.95,
            manualFinisherPending=p.nativeM1Pending and p.nativeM1Pending.stage==4
                and p.nativeM1Pending.token==last and os.clock()-p.nativeM1Pending.time<0.9,
            targetBlocking=hasInfo(target,"Block"),
            targetInvulnerable=target and target:FindFirstChildOfClass("ForceField")~=nil,
            inRange=root~=nil and tr~=nil and distanceTo(target)<=(finisher and 14 or controller.config.m1Range+1.5)
                and math.abs(tr.Position.Y-root.Position.Y)<=16 and targetM1Chainable(target,finisher),
            canM1=canQueueM1(character) and not m1RequestPending(character),
            canJump=jumpReady,jumpReason=jumpReason,
            airborne=humanoid~=nil and root~=nil and enterNativeDownslamWindow(character,humanoid,root,function() return true end),
            -- CurrentM1 is the NEXT native punch: 1=idle, 2=one
            -- accepted, 4=three accepted, 5=finisher sentinel. Observed live.
            stage=math.clamp((character and tonumber(character:GetAttribute("CurrentM1")) or 1)-1,0,4),
            m1Token=last, m1Age=age}
        result.opponents=p.ObserveOpponents(character,root,result.now)
        return p.AddInventory(result,root,tr)
    end

    function p.Begin()
        local s = p.Snapshot()
        if os.clock()<controller.nextComboAt or controller.busy or not targetStanding(s.target) then return false end
        local accepted, reason
        if p.stage==3 then
            accepted,reason=p.combo:BeginDynamic(s,{slam=true,resumeNative=true})
        else
            accepted,reason=p.combo:Begin(s,{slam=p.stage>=2,resumeNative=true})
        end
        if not accepted then p.lastBeginReason=reason; return false end
        p.lastBeginReason=nil
        controller.comboSerial += 1
        p.serial = controller.comboSerial
        p.loadout = captureLoadout(s.character)
        controller.comboBusy, controller.busy, controller.comboRequested = true,true,false
        p.Audit("pvp_combo_begin",{target=s.target.Name,nativeStage=s.stage,slam=p.stage>=2,
            distance=s.distance,blockActive=controller.blockActive,
            sinceGuardRelease=controller.blockReleasedAt and os.clock()-controller.blockReleasedAt,
            damageConfirmed=false})
        return true
    end

    function p.Step()
        if not p.combo:GetState().busy then return end
        if p.serial~=controller.comboSerial or not loadoutCurrent(p.loadout) then p.Cancel("generation_or_loadout"); return end
        local s = p.Snapshot()
        local before=p.combo:GetState()
        local actions = p.combo:Step(s)
        if (before.phase=="jump_ready" or before.phase=="await_air") and os.clock()>=(p.nextJumpAuditAt or 0) then
            p.nextJumpAuditAt=os.clock()+.12
            local hum=s.character and s.character:FindFirstChildOfClass("Humanoid")
            p.Audit("pvp_jump_state",{phase=before.phase,reason=s.jumpReason,airborne=s.airborne,
                noJump=hasInfo(s.character,"NoJump"),inSkill=hasInfo(s.character,"InSkill"),
                jumpPower=hum and hum.JumpPower,state=hum and hum:GetState().Name,nativeStage=s.stage})
        end
        if p.jumpOwned and not s.airborne then p.HoldJump() end
        for _, action in ipairs(actions) do
            if action.kind=="jump" then
                if action.down then
                    local humanoid = s.character and s.character:FindFirstChildOfClass("Humanoid")
                    p.jumpController = ControlModule and ControlModule.activeController
                    p.previousJumpRequest = p.jumpController and p.jumpController.jumpRequested
                    p.previousIsJumping = p.jumpController and p.jumpController.isJumping
                    p.jumpHumanoid = humanoid
                    p.jumpOwned = true
                    if not humanoid then p.Cancel("jump_humanoid_missing"); return end
                    p.HoldJump()
                    log("finisher_jump_planned",{target=s.target.Name,nativeStage=s.stage})
                else
                    p.ReleaseJump()
                    if s.airborne then log("finisher_jump_confirmed",{target=s.target.Name,nativeAir=true}) end
                end
            elseif action.kind=="skill" then
                local requestId,requestSerial=action.id,action.serial
                local slot=moveForKey(action.key)
                if not slot or slot:GetAttribute("Service")~=action.service
                    or action.target~=controller.target then
                    p.combo:Confirm(requestId,{accepted=false})
                else
                    local token=tonumber(slot:GetAttribute("ReadyAt")) or 0
                    local generation=controller.targetGeneration
                    task.spawn(function()
                        local ok,sent=pcall(function()
                            if not controller.running or not controller.enabled or not controller.armed
                                or controller.targetGeneration~=generation or p.combo.serial~=requestSerial then return false end
                            local fresh=p.Snapshot()
                            local item
                            for _,candidate in ipairs(fresh.inventory.items) do
                                if candidate.id==action.itemId then item=candidate;break end
                            end
                            if not item or not p.modules.combos.InDamageArea(item,fresh) then return false end
                            return useNativeMove(action.key,"item_combo",discoverProfile(s.character))
                        end)
                        if p.combo.serial~=requestSerial then return end
                        if not ok or not sent then
                            p.combo:Confirm(requestId,{accepted=false})
                            log("pvp_skill_request",{id=requestId,sent=false,error=not ok and tostring(sent) or nil})
                            return
                        end
                        -- Sending a remote is not acceptance: wait for THIS
                        -- item's native cooldown to advance, not another skill.
                        local deadline=os.clock()+.8
                        repeat
                            if not controller.running or p.combo.serial~=requestSerial
                                or controller.targetGeneration~=generation then return end
                            if (tonumber(slot:GetAttribute("ReadyAt")) or 0)>token then
                                p.combo:Confirm(requestId,{accepted=true})
                                log("pvp_skill_accepted",{id=requestId,item=action.itemId,key=action.key})
                                return
                            end
                            RunService.Heartbeat:Wait()
                        until os.clock()>=deadline
                        p.combo:Confirm(requestId,{accepted=false})
                    end)
                end
            elseif action.kind=="m1" then
                local victimHumanoid=s.target and s.target:FindFirstChildOfClass("Humanoid")
                local healthBefore=victimHumanoid and victimHumanoid.Health
                local nativeToken=tonumber(s.character:GetAttribute("LastM1")) or 0
                local sent, down, skipReason = pulseNativeM1(s.target,action.variant=="Down")
                if sent and p.combo.pending and p.combo.pending.id==action.id then
                    p.combo.pending.dispatchedAt=os.clock()
                end
                -- A native request racing the snapshot may acknowledge this stage.
                if not sent and skipReason~="shared_native_pending" then p.combo:Confirm(action.id,{accepted=false}) end
                local requestData={step=action.stage,downslam=down,sent=sent,request=action.id,
                    skipReason=skipReason or (not sent and (m1UnavailableReason(s.character) or "dispatch_context_changed") or nil),
                    target=s.target and s.target.Name,distance=s.distance,blockActive=controller.blockActive,
                    sinceGuardRelease=controller.blockReleasedAt and os.clock()-controller.blockReleasedAt,
                    damageConfirmed=false}
                if sent and healthBefore then
                    p.m1Receipt={target=s.target,character=s.character,request=action.id,
                        nativeToken=nativeToken,healthBefore=healthBefore,at=os.clock(),data=requestData}
                end
                p.Audit("pvp_m1_request",requestData)
            end
        end
        local after = p.combo:GetState()
        if after.stage~=p.lastStage then
            p.lastStage=after.stage
            controller.lastConsumedM1 = tonumber(s.character and s.character:GetAttribute("LastM1")) or 0
            p.Audit("pvp_native_stage",{stage=after.stage,nativeStage=s.stage,token=s.m1Token,
                target=s.target and s.target.Name,distance=s.distance,damageConfirmed=false})
        end
        if not after.busy then
            p.ReleaseJump()
            controller.comboBusy, controller.busy = false,false
            controller.nextComboAt = os.clock()+(after.phase=="complete" and controller.config.nextM1ChainGap or 0.14)
            if after.phase=="complete" then
                controller.finisherTarget,controller.finisherUntil = s.target,os.clock()+0.5
                controller.finisherCommitUntil=os.clock()+0.5
                if p.stage>=2 then controller.lastDownslamAt,controller.lastDownslamTarget=os.clock(),s.target end
            end
            log("pvp_combo_end",{phase=after.phase,reason=after.reason,stage=after.stage,
                nativeAccepted=after.phase=="complete",damageConfirmed=false,
                nativeStage=s.stage,token=s.m1Token,age=s.m1Age})
        end
    end

    -- Post-slam item chain for native held-M1 play (the engine never starts while
    -- the mouse is down). Order = m1.followups (comboSequence rank). Every step
    -- goes to its own audit file; unavailable links are skipped after 0.35 s.
    p.chainAudit={}
    local function chainStep(trigger,kind,data)
        data=data or {}
        data.kind,data.t=kind,math.floor((os.clock()-trigger.at)*1000)/1000
        p.chainAudit[#p.chainAudit+1]=data
        if #p.chainAudit>400 then table.remove(p.chainAudit,1) end
        log("pvp_chain_"..kind,data)
    end
    local function chainSave()
        pcall(function()
            local path="pvp/chain_audit.json"
            if not p.chainEvidenceBackedUp and isfile(path) then
                writefile(path..".bak-"..os.date("%Y%m%d-%H%M%S"),readfile(path))
            end
            p.chainEvidenceBackedUp=true
            writefile(path,HttpService:JSONEncode({version=controller.version,
                moveset=LocalPlayer.Character and LocalPlayer.Character:GetAttribute("Moveset"),
                sequenceSource=LocalPlayer.Character and controller.config.comboSequenceByMoveset[LocalPlayer.Character:GetAttribute("Moveset")] and "moveset_override" or "default",
                sequence=controller.config.comboSequenceByMoveset[LocalPlayer.Character
                    and LocalPlayer.Character:GetAttribute("Moveset")] or controller.config.comboSequence,
                events=p.chainAudit}))
        end)
    end
    function p.RunPostChain(trigger)
        if p.postChainBusy or not p.combo or p.combo:GetState().busy then return end
        p.postChainBusy=true
        task.spawn(function()
            local function alive()
                local character,humanoid=localParts()
                return controller.running and controller.enabled and controller.armed and not p.paused
                    and p.stage==3 and humanoid and humanoid.Health>0 and isCandidate(trigger.target)
                    and os.clock()<trigger.at+4 and not p.combo:GetState().busy
            end
            local ok,err=pcall(function()
                while os.clock()<trigger.at+.45 and not (trigger.receipt and trigger.receipt.impactObserved) do
                    if not alive() then chainStep(trigger,"abort",{reason="wait_impact"}) return end
                    RunService.Heartbeat:Wait()
                end
                local character=LocalPlayer.Character
                local fresh=p.Snapshot(trigger.target)
                local order={}
                -- Right after the slam the character can still be in recovery, so
                -- nothing is "usable" yet: retry for up to 1.2 s before giving up.
                local orderDeadline=os.clock()+1.2
                repeat
                    order={}
                    for _,id in ipairs(fresh.inventory.m1.followups or {}) do order[#order+1]=id end
                    if #order>0 or os.clock()>=orderDeadline then break end
                    if not alive() then chainStep(trigger,"abort",{reason="wait_order"}) return end
                    RunService.Heartbeat:Wait()
                    fresh=p.Snapshot(trigger.target)
                until false
                chainStep(trigger,"begin",{order=table.concat(order,">"),moveset=character and character:GetAttribute("Moveset"),
                    impact=trigger.receipt and trigger.receipt.impactObserved==true})
                local used=0
                for _,id in ipairs(order) do
                    local skipAt,done,why=os.clock()+.45,false,"unknown"
                    local lastDist,lastAreaWhy
                    local linkStartDist=fresh.distance
                    repeat
                        if not alive() then chainStep(trigger,"abort",{reason="guard",at_link=id}) return end
                        fresh=p.Snapshot(trigger.target)
                        local item
                        for _,candidate in ipairs(fresh.inventory.items) do
                            if candidate.id==id then item=candidate break end
                        end
                        if not item then why="not_in_inventory" break end
                        -- Not ready = real cooldown, skip. Not usable = still in the
                        -- previous skill/recovery: keep waiting instead of skipping.
                        if not item.ready then why="cooldown" break end
                        local inArea,areaWhy
                        if item.usable then inArea,areaWhy=p.modules.combos.InDamageArea(item,fresh) end
                        if not item.usable then
                            why="waiting_usable"
                        elseif not inArea then
                            why="out_of_area"
                            lastDist,lastAreaWhy=fresh.distance,areaWhy
                            local char, hum, myRoot = localParts()
                            local _, tRoot = characterParts(trigger.target)
                            local def=fresh.inventory.catalog and fresh.inventory.catalog[item.id]
                            local area=item.area or (def and def.area)
                            -- Only close the gap when too far; inside a ranged item's
                            -- minimum range, walking in would make it worse (skip it).
                            if area and fresh.distance<(area.minRange or 0) then
                                skipAt=0
                            elseif char and hum and myRoot and tRoot and fresh.distance>(area and area.maxRange or 0) then
                                hum:MoveTo(tRoot.Position)
                                skipAt=math.min(skipAt,os.clock()+.3)
                            end
                        else
                            local sent=false
                            if item.isSpecial or item.key=="R" or item.id=="Special_R" then
                                local char,hum,myRoot=localParts()
                                sent=useCombatSpecial(char,hum,myRoot,trigger.target,fresh.distance)
                            else
                                local slot=moveForKey(item.key)
                                local token=slot and tonumber(slot:GetAttribute("ReadyAt")) or 0
                                sent=useNativeMove(item.key,"chain_item",discoverProfile(character))
                                if sent then
                                    local deadline=os.clock()+.25
                                    repeat
                                        if slot and (tonumber(slot:GetAttribute("ReadyAt")) or 0)>token then break end
                                        RunService.Heartbeat:Wait()
                                    until os.clock()>=deadline
                                end
                            end
                            if sent then
                                chainStep(trigger,"accepted",{id=id,key=item.key,dist=fresh.distance,role=item.role})
                                used+=1
                                done=true
                                -- After a push the rival flies off-line: sidestep at once
                                -- so the ranged link lands without letting them recover.
                                if item.role=="push" then
                                    task.wait(.12)
                                    local after=p.Snapshot(trigger.target)
                                    if after and after.distance>controller.config.m1Range+1.5 then
                                        p.chainLateral=-(p.chainLateral or 1)
                                        local okDash,dashed=pcall(nativeDash,p.chainLateral>0 and "Right" or "Left","chain_lateral")
                                        chainStep(trigger,"lateral",{sent=okDash and dashed==true,dist=after.distance})
                                    end
                                end
                            else
                                why="send_refused"
                            end
                        end
                        if not done then RunService.Heartbeat:Wait() end
                    until done or os.clock()>=skipAt
                    if not done then chainStep(trigger,"skipped",{id=id,reason=why,dist=lastDist or fresh.distance,startDist=linkStartDist,
                        areaWhy=lastAreaWhy,inSkill=hasInfo(LocalPlayer.Character,"InSkill")}) end
                end
                -- Chain Special (R) as combo finisher if ready and unused
                if alive() and specialReady(character) and canAct(character,true) and not p.combo:GetState().busy then
                    local freshFin=p.Snapshot(trigger.target)
                    if freshFin and freshFin.distance<=38 then
                        local char,hum,myRoot=localParts()
                        local okSp,usedSp=pcall(useCombatSpecial,char,hum,myRoot,trigger.target,freshFin.distance)
                        if okSp and usedSp then
                            chainStep(trigger,"accepted",{id="Special_R",key="R",dist=freshFin.distance})
                            used+=1
                        end
                    end
                end
                chainStep(trigger,"end",{used=used,planned=#order})
            end)
            if not ok then chainStep(trigger,"error",{error=tostring(err)}) end
            p.postChainBusy=false
            p.lastChainEndAt=os.clock()
            chainSave()
        end)
    end

    function p.Decide(character,humanoid,root,target,physicalThreat,defenseOnly)
        local clock=os.clock()
        local opponents=p.ObserveOpponents(character,root,clock)
        local primary
        for _,o in ipairs(opponents) do if o.id==target then primary=o;break end end
        if not primary then return false end
        local comboSnapshot=p.Snapshot()
        local plan=p.stage==3 and p.combo:Decide(comboSnapshot,{slam=true,resumeNative=true}) or nil
        local range={min=0,max=controller.config.m1Range}
        local selectedItem
        if plan and plan.mode=="skills" then
            for _,item in ipairs(comboSnapshot.inventory.items) do
                if item.id==plan.skills[1] then selectedItem=item;break end
            end
        elseif not plan then
            -- Choose the nearest usable item envelope when no attack is in
            -- range. This keeps ranged items from chasing into M1 distance.
            local bestError=math.huge
            for _,item in ipairs(comboSnapshot.inventory.items) do
                if p.stage==3 and item.verified and item.ready and item.usable
                    and item.kind~="counter" and item.kind~="evasive" and item.area then
                    local error=math.max(0,primary.distance-item.area.maxRange,
                        (item.area.minRange or 0)-primary.distance)
                    if error<bestError then selectedItem=item;bestError=error end
                end
            end
        end
        if selectedItem then range={min=selectedItem.area.minRange or 0,max=selectedItem.area.maxRange} end
        -- Ready ranged skills may fire from here, but the feet still close for M1.
        -- Otherwise one available ranged item can keep us circling outside contact.
        local movementRange={min=0,max=controller.config.m1Range}
        p.selectedItem=selectedItem and {id=selectedItem.id,key=selectedItem.key,range=range,
            rangeSource=selectedItem.rangeSource} or {id="native_m1",range=range,rangeSource="code_rule"}
        local ready=not controller.busy and canAct(character)
            and clock-controller.lastActionAt>=controller.config.actionGap
        local canMove=true
        local dashReady, dashMode = canRequestDash(character)
        local canEvadeStun = (dashMode == "native_escape")
            or (character:GetAttribute("Evade") == 50)
            or (character.Info and character.Info:FindFirstChild("Knockback") ~= nil)
            or (character.Info and character.Info:FindFirstChild("ForceEsc") and character.Info.ForceEsc.Value == true)
            or (character:GetAttribute("Burst") and (not character.Info or not character.Info:GetAttribute("Burst")))
        local snapshot={now=clock,sampledAt=clock,placeId=game.PlaceId,jobId=game.JobId,
            enabled=controller.running and controller.enabled,armed=controller.armed,
            movementAllowed=canMove,inventory=comboSnapshot.inventory,range=range,
            lockTarget=controller.config.focusOnly or controller.comboBusy or controller.busy,latency=pingSeconds(),
            self={id=character,position=root.Position,velocity=root.AssemblyLinearVelocity,
                health=humanoid.Health,maxHealth=humanoid.MaxHealth,characterId=character,
                stunned=character:GetAttribute("Stun")==true or hasInfo(character,"Stun"),
                ragdolled=(tonumber(character:GetAttribute("Ragdoll")) or 0)>0,
                evasiveWhileStunned=canEvadeStun,
                busy=controller.busy,comboBusy=controller.comboBusy,defenseInterruptible=true},
            target=primary,opponents=opponents,
            can={approach=ready and canMove,retreat=ready and canMove,
                attack=ready,punish=ready,dodge=dashReady,
                block=not controller.GuardAttackCapped(target),
                parry=not controller.GuardAttackCapped(target) and not controller.busy and canAct(character),
                counter=not controller.busy and canAct(character),evasive=dashReady or canEvadeStun},
            cooldowns={approach=0,retreat=0,attack=0,punish=0,block=0,
                counter=0,parry=0,evasive=(dashMode == "native_escape") and 0 or math.max(0,controller.dashRetryAt-clock),
                dodge=math.max(0,controller.dashRetryAt-clock,
                    controller.lastDashRequestAt+controller.config.dashRequestGap-clock)}}
        p.lastTacticalSnapshot=snapshot
        if defenseOnly then
            -- Re-score every rival before legacy defense can return early.
            -- A committed native chain still owns its original target.
            local selection=p.dynamic:decide(snapshot)
            p.lastEarlyDecision=selection
            if selection.offenseTargetId and selection.offenseTargetId~=target
                and p.SwitchOffense(selection.offenseTargetId) then
                target=selection.offenseTargetId
            end
            return p.Move(character,humanoid,root,target,opponents,movementRange,true)
        end
        local function move(decision)
            local model=decision.targetId or target
            -- Defensive threats never change the offense target in mid-combo.
            if decision.action=="approach" and not p.SwitchOffense(model) then return false end
            return p.Move(character,humanoid,root,model,opponents,movementRange,false)
        end
        local function offense(decision)
            local model=decision.targetId
            if not model or not p.SwitchOffense(model) or not targetStanding(model)
                or UserInputService:GetFocusedTextBox() then return false end
            -- Snapshot/combos adopts native held-M1 stages without duplicate Down.
            -- Keep the jump/slam assistant alive while the user clicks.
            return p.Begin()
        end
        local decision,accepted=p.dynamic:step(snapshot,{
            attack=offense,punish=offense,approach=move,retreat=move,
            dodge=function(d)
                local cTarget = d.targetId or target
                local dir, vec = chooseEscapeDirection(character, root, cTarget)
                if dir and nativeDash(dir, "dodge:" .. tostring(d.reason), vec) then
                    return true
                end
                return move(d)
            end,
            block=function(d) return quickBlock(d.targetId,"dynamic_nearby_threat") end,
            parry=function(d)
                local sent = quickBlock(d.targetId, "dynamic_parry")
                local guardSerial = controller.blockSerial
                task.delay(0.22, function()
                    if sent and controller.blockSerial == guardSerial and not controller.blockingManual then
                        releaseBlock("parry_window_end")
                    end
                end)
                return sent
            end,
            counter=function(d)
                local cTarget = d.targetId or target
                local threatKind = d.reason or "incoming_hit"
                local counterKey, profile = findBestCounter(cTarget, threatKind)
                if counterKey then
                    controller.activeCounter = {
                        key = counterKey,
                        name = profile and profile.Name or tostring(counterKey),
                        threatKind = threatKind,
                        target = cTarget,
                        at = os.clock(),
                    }
                    return useNativeMove(counterKey, "counter:" .. tostring(threatKind), profile)
                end
                return false
            end,
            evasive=function(d)
                local cTarget = d.targetId or target
                local dir, vec = chooseEscapeDirection(character, root, cTarget)
                if dir and nativeDash(dir, "evasive:" .. tostring(d.reason), vec) then
                    return true
                end
                return false
            end})
        -- Positional risk can exist before an attack flag. Let the movement
        -- planner avoid crossing bodies while preserving a native combo.
        if not accepted and decision.action=="hold"
            and decision.reason~="avoid_low_health_chase"
            and humanoid.Health/humanoid.MaxHealth>p.dynamic.config.lowHealthRatio
            and not controller.busy
            and not controller.comboBusy and ready and canMove then
            if p.Move(character,humanoid,root,target,opponents,movementRange,false) then return true end
        end
        -- Native approach fallback (restored from 1.14.x): when the movement
        -- planner holds or the dynamic step rejects an approach, still close
        -- the gap by special, lateral path or pathfinding instead of standing.
        if not accepted and not controller.busy and not controller.comboBusy and ready and canMove
            and (decision.action=="approach" or decision.action=="hold" or decision.action=="attack"
                or decision.action=="punish")
            and primary.distance>controller.config.m1Range+0.5
            and humanoid.Health/humanoid.MaxHealth>p.dynamic.config.lowHealthRatio
            and clock>=(p.nextLegacyApproachAt or 0) then
            p.nextLegacyApproachAt=clock+.06
            if p.stage==3 and not p.approachPending and canAct(character) then
                p.approachPending=true
                task.spawn(function()
                    local ok,used=pcall(useMovementSpecial,character,humanoid,root,target,primary.distance)
                    p.approachPending=false
                    if ok and used then
                        p.Audit("pvp_movement_dispatch",{action="special_fallback",target=target.Name,
                            distance=primary.distance,reason="legacy_approach"})
                    end
                end)
            end
            -- Combat special (R key) poke & zoning to keep enemy at bay
            if not controller.busy and not controller.comboBusy and canAct(character)
                and specialReady(character) and primary.distance <= 38 and targetStanding(target)
                and clock >= (controller.lastSpecialAt + 1.2)
                and humanoid.Health/humanoid.MaxHealth > p.dynamic.config.lowHealthRatio then
                task.spawn(function()
                    local okSp, usedSp = pcall(useCombatSpecial, character, humanoid, root, target, primary.distance)
                    if okSp and usedSp then
                        p.Audit("pvp_combat_special", { action = "combat_special_r", target = target.Name,
                            distance = primary.distance, moveset = character:GetAttribute("Moveset") })
                    end
                end)
            end
            if advanceOnTarget(character,humanoid,root,target) then
                if clock>=(p.nextWalkAuditAt or 0) then
                    p.nextWalkAuditAt=clock+.5
                    p.Audit("pvp_movement_dispatch",{action="advance_fallback",target=target.Name,
                        distance=primary.distance,reason=decision.reason or "legacy_approach"})
                end
                return true
            end
        end
        return accepted
    end


    function controller.SetPaused(paused)
        p.paused=paused==true
        if p.ui then p.ui:SetPaused(p.paused,true) end
        controller.SetEnabled(p.requestedEnabled)
        return p.paused
    end

    function controller.SetStage(index)
        if index~=1 and index~=2 and index~=3 then return false end
        if p.stage~=index then p.Cancel("stage_changed") end
        p.stage=index
        if p.ui then p.ui:SetStage(index,true) end
        return true
    end

    function p.RecordHeldM1(physical,target,hum)
        local stats=p.nativeM1Stats
        if not stats then return end
        if physical then
            if not p.heldM1Session then
                p.heldM1Session={at=os.time(),clock=os.clock(),target=target,
                    healthBefore=hum and hum.Health,minHealth=hum and hum.Health,
                    requests=stats.requests,forwarded=stats.forwarded,accepted=stats.accepted,
                    minDistance=target and distanceTo(target),maxDistance=target and distanceTo(target)}
            end
            local session=p.heldM1Session
            if target==session.target and hum then
                session.minHealth=math.min(session.minHealth or hum.Health,hum.Health)
                local distance=distanceTo(target)
                session.minDistance=math.min(session.minDistance or distance,distance)
                session.maxDistance=math.max(session.maxDistance or distance,distance)
            else session.targetChanged=true end
            return
        end
        local session=p.heldM1Session
        if not session then return end
        p.heldM1Session=nil
        local data={at=session.at,seconds=os.clock()-session.clock,target=session.target and session.target.Name,
            targetChanged=session.targetChanged==true,healthBefore=session.healthBefore,minHealth=session.minHealth,
            healthAfter=target==session.target and hum and hum.Health,minDistance=session.minDistance,maxDistance=session.maxDistance,
            requests=stats.requests-session.requests,forwarded=stats.forwarded-session.forwarded,
            accepted=stats.accepted-session.accepted,exclusiveAttribution=false}
        p.Audit("pvp_m1_held_session",data)
        p.heldM1Evidence=p.heldM1Evidence or {}
        table.insert(p.heldM1Evidence,data)
        if #p.heldM1Evidence>60 then table.remove(p.heldM1Evidence,1) end
        pcall(function()
            local path="pvp/no-punch-held.json"
            if not p.heldEvidenceBackedUp and isfile(path) then
                writefile(path..".bak-"..os.date("%Y%m%d-%H%M%S"),readfile(path))
            end
            p.heldEvidenceBackedUp=true
            writefile(path,HttpService:JSONEncode({placeId=game.PlaceId,version=controller.version,
                sampledInterval=.15,passive=true,sessions=p.heldM1Evidence}))
        end)
    end

    function p.AuditM1Gate()
        local character=LocalPlayer.Character
        local target=controller.target
        local hum=target and target:FindFirstChildOfClass("Humanoid")
        local physical=UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        p.RecordHeldM1(physical,target,hum)
        local age=character and math.max(0,now()-(tonumber(character:GetAttribute("LastM1")) or 0)) or 999
        local raw=character and tonumber(character:GetAttribute("CurrentM1")) or 1
        local reason
        if not controller.enabled then reason="disabled"
        elseif not controller.armed or not target then reason="no_target"
        elseif not hum or hum.Health<=0 then reason="target_dead" end
        reason=reason or m1UnavailableReason(character)
            or (UserInputService:GetFocusedTextBox() and "text_input")
            or (os.clock()<controller.escapeUntil and "escaping")
            or (distanceTo(target)>controller.config.m1Range and "out_of_m1_range")
            or (m1RequestPending(character) and "shared_native_pending")
            or (raw>=5 and age<p.combo.profile.finisherResetSeconds and "native_finisher_cooldown")
            or (os.clock()-(p.lastNativeM1At or -math.huge)<=.25 and "recent_native_request")
            or (p.combo.pending and "awaiting_native_ack")
            or (controller.busy and "combo_or_skill_busy")
            or p.lastBeginReason or "ready"
        if reason==p.lastM1SkipReason and os.clock()<(p.nextM1GateAt or 0) then return end
        p.lastM1SkipReason=reason;p.nextM1GateAt=os.clock()+.75
        p.Audit("pvp_m1_gate",{reason=reason,target=target and target.Name,
            distance=target and distanceTo(target),physical=physical,nativeStage=raw,m1Age=age,
            phase=p.combo:GetState().phase,pendingId=p.combo.pending and p.combo.pending.id})
    end

    function p.RecordM1Damage(character)
        local target=controller.target
        local hum=target and target:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health<=0 then return end
        p.damageReceipts=p.damageReceipts or {}
        local receipt={target=target,clock=os.clock(),at=os.time(),healthBefore=hum.Health,
            minHealth=hum.Health,distance=distanceTo(target),token=character:GetAttribute("LastM1"),
            stage=character:GetAttribute("CurrentM1"),attacker=character,
            service=tostring(character:GetAttribute("Moveset")).."Service",
            physical=UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)}
        table.insert(p.damageReceipts,receipt)
        if #p.damageReceipts>20 then table.remove(p.damageReceipts,1) end
        local connection=hum.HealthChanged:Connect(function(health) receipt.minHealth=math.min(receipt.minHealth,health) end)
        task.delay(.75,function()
            connection:Disconnect()
            if not controller.running or target.Name~="Dummy" then return end
            local loss=math.max(0,receipt.healthBefore-receipt.minHealth)
            local data={at=receipt.at,clock=receipt.clock,target=target.Name,distance=receipt.distance,
                healthBefore=receipt.healthBefore,healthAfter=hum.Parent and hum.Health,
                minHealth=receipt.minHealth,healthLoss=loss,damageConfirmed=loss>0,
                contactObserved=receipt.contactObserved==true,explicitAttackerContact=receipt.explicitAttacker==true,
                exclusiveAttribution=false,
                physical=receipt.physical,token=receipt.token,nativeStage=receipt.stage}
            p.Audit("pvp_m1_damage_observed",data)
            p.damageEvidence=p.damageEvidence or {}
            table.insert(p.damageEvidence,data)
            if #p.damageEvidence>200 then table.remove(p.damageEvidence,1) end
            pcall(function()
                local path="pvp/no-punch-damage.json"
                if not p.damageEvidenceBackedUp and isfile(path) then
                    writefile(path..".bak-"..os.date("%Y%m%d-%H%M%S"),readfile(path))
                end
                p.damageEvidenceBackedUp=true
                writefile(path,HttpService:JSONEncode({placeId=game.PlaceId,version=controller.version,
                    passive=true,exclusiveAttribution=false,events=p.damageEvidence}))
            end)
        end)
    end

    function p.Mount()
        p.nativeM1Stats={requests=0,forwarded=0,held=0,accepted=0}
        -- A slam reservation belongs only to a live jump plan. It must never
        -- swallow the player's fourth punch while the assistant is idle,
        -- defending, out of range, or unable to jump.
        function p.HoldNativeFinisher(character,humanoid,rawStage,token)
            if p.stage<2 or rawStage~=4 or not humanoid
                or humanoid.FloorMaterial==Enum.Material.Air
                or not canQueueM1(character)
                or not isCandidate(controller.target)
                or distanceTo(controller.target)>controller.config.m1Range+1.5 then return false end
            local state=p.combo:GetState()
            -- The slam plan may not have started yet when the fourth click
            -- arrives; start it here so the click is never spent on the ground.
            if not state.busy then
                if not p.Begin() then return false end
                state=p.combo:GetState()
            end
            if not state.busy or not p.combo.slam
                or (state.phase~="jump_ready" and state.phase~="await_air") then return false end
            if p.finisherHoldToken~=token or not p.finisherHoldAt then
                p.finisherHoldToken=token
                p.finisherHoldAt=os.clock()
            end
            -- NoJump after hit three lasts ~0.4 s (jump_state audit); hold the
            -- fourth click across it so it leaves as the Down slam.
            return os.clock()-p.finisherHoldAt<0.6
        end
        local function bindNativeM1(mountedCharacter)
            if p.nativeM1Connection then p.nativeM1Connection:Disconnect() end
            if not mountedCharacter then return end
            local previousToken=tonumber(mountedCharacter:GetAttribute("LastM1")) or 0
            p.nativeM1Connection=mountedCharacter:GetAttributeChangedSignal("LastM1"):Connect(function()
                local token=tonumber(mountedCharacter:GetAttribute("LastM1")) or 0
                local advancing=token>previousToken
                previousToken=token
                if not advancing then return end
                local stats=p.nativeM1Stats
                stats.accepted+=1
                stats.lastAcceptedAt=os.clock()
                stats.lastToken=mountedCharacter:GetAttribute("LastM1")
                p.Audit("pvp_m1_native_accepted",{stage=mountedCharacter:GetAttribute("CurrentM1"),
                    token=stats.lastToken,physical=UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1),
                    damageConfirmed=false})
                p.RecordM1Damage(mountedCharacter)
            end)
            table.insert(controller.connections,p.nativeM1Connection)
        end
        bindNativeM1(LocalPlayer.Character)
        table.insert(controller.connections,LocalPlayer.CharacterAdded:Connect(bindNativeM1))
        p.originalDash=MovementController.Dash
        p.dashWrapper=function(self,player,character,direction,...)
            local result=table.pack(p.originalDash(self,player,character,direction,...))
            if controller.running and player==LocalPlayer and character==LocalPlayer.Character
                and (dashForce(character) or hasInfo(character,"InDash")) then
                controller.lastDashAt=os.clock()
                local pending=controller.dashPending
                if pending and pending.character==character then pending.nativeAccepted=true end
                p.Audit("pvp_native_dash",{direction=direction,automated=pending~=nil})
            end
            return table.unpack(result,1,result.n)
        end
        MovementController.Dash=p.dashWrapper
        p.originalUseSetService = ToolController.UseSetService
        p.meleeWrapper = function(self, event, variant, target, ...)
            if event=="Activated" and not p.ownM1Dispatch and controller.running
                and controller.enabled and controller.armed then
                local character, humanoid = localParts()
                local rawStage=character and tonumber(character:GetAttribute("CurrentM1")) or 1
                local token=character and character:GetAttribute("LastM1")
                p.nativeM1Stats.requests+=1
                if p.HoldNativeFinisher(character,humanoid,rawStage,token) then
                    p.nativeM1Stats.held+=1
                    return
                end
                if m1RequestPending(character) then
                    p.nativeM1Stats.deduplicated=(p.nativeM1Stats.deduplicated or 0)+1
                    return
                end
                p.nativeM1Stats.forwarded+=1
                p.nativeM1Stats.lastForwardedAt=os.clock()
                p.lastNativeM1At=os.clock()
                p.nativeM1Pending={token=token,stage=rawStage,time=p.lastNativeM1At}
                if p.stage>=2 and rawStage==4 and humanoid and humanoid.FloorMaterial==Enum.Material.Air then
                    -- Charles: Shut Up! (slot 2) pressed in the air is the special slam.
                    local airKey,airMove
                    for k=1,4 do
                        local mv=moveForKey(k)
                        if mv and string.lower(mv.Name)=="shut up!" then airKey,airMove=k,mv break end
                    end
                    local airVictim=target or controller.target
                    if airKey and moveReady(airMove) and isCandidate(airVictim) and distanceTo(airVictim)<=9
                        and os.clock()-(p.lastAirShutUpAt or -math.huge)>0.6 then
                        p.lastAirShutUpAt=os.clock()
                        local selfRef,ev,var,tgt,rest=self,event,variant,target,table.pack(...)
                        task.spawn(function()
                            local sent=useNativeMove(airKey,"chain_air_shutup",discoverProfile(character))
                            p.Audit("pvp_air_shutup",{sent=sent==true,target=airVictim.Name})
                            if not sent then
                                p.originalUseSetService(selfRef,ev,var,tgt,table.unpack(rest,1,rest.n))
                            end
                        end)
                        return
                    end
                    variant="Down"
                    local victim=target or controller.target
                    if isCandidate(victim) then
                        local receipt=p.slamReceipt
                        -- Repeated native input shares its receipt. Deduplicate
                        -- bookkeeping, never the player's actual punch request.
                        if not receipt or receipt.character~=character or receipt.target~=victim
                            or receipt.token~=token or os.clock()-receipt.at>1 then
                            p.slamReceipt={target=victim,character=character,at=os.clock(),serial=p.combo.serial,
                                token=token,downObserved=false,impactObserved=false}
                            p.Audit("pvp_slam_request",{target=victim.Name,variant="Down",nativeStage=4,
                                airborne=true,source="held_native_input"})
                            if p.stage==3 then p.RunPostChain({at=os.clock(),target=victim,receipt=p.slamReceipt}) end
                        end
                    end
                end
            end
            return p.originalUseSetService(self,event,variant,target,...)
        end
        ToolController.UseSetService=p.meleeWrapper
        p.ui=p.modules.panel.new({enabled=p.requestedEnabled,stage=p.stage,
            stages={"M1: 4 golpes","M1 + salto slam","Dinamico + habilidades"},pauseKey=Enum.KeyCode.F8})
        p.ui:OnToggle(controller.SetEnabled)
        p.ui:OnPause(controller.SetPaused)
        p.ui:OnStage(controller.SetStage)
        table.insert(controller.connections,RunService.Heartbeat:Connect(function()
            if os.clock()<(p.nextUiAt or 0) then return end
            p.nextUiAt=os.clock()+0.15
            p.AuditM1Gate()
            local state=p.combo:GetState()
            local text=p.paused and "Pausa F8" or not controller.enabled and "Apagado"
                or not controller.armed and "Clic: rival | Ctrl: soltar"
                or ("M1 "..state.stage.."/4 | "..state.phase)
            p.ui:SetStatus(text)
        end))
    end
end

local function think()
    if not controller.running or not controller.enabled then
        return
    end
    _G.Settings = _G.Settings or {}
    _G.Settings.AutoRun = true
    sampleTelemetry()

    if controller.getGamemodeContext then
        controller.getGamemodeContext()
    end
    if controller.checkBeamQTE then
        controller.checkBeamQTE()
    end

    -- When in Lobby, stand down gracefully and do not acquire or pursue targets
    if LocalPlayer and LocalPlayer.Team and LocalPlayer.Team.Name == "Lobby" then
        if controller.armed then
            clearTarget("lobby_wait")
        end
        return
    end

    local character, humanoid, root = localParts()
    if character then syncLoadout(character) end

    if not controller.armed then
        if os.clock() < controller.acquireUntil then
            local target = closestInCharacterFacing(controller.config.acquireDistance)
                or closestInCharacterFacing(120, true)
            if target then armTarget(target) end
        end
        -- Sin clic previo: si alguien cercano te estÃ¡ atacando, fÃ­jalo solo
        -- para que la defensa, los M1 y el combo no se queden en no_target.
        if not controller.armed and character and os.clock() >= (controller.nextDefensiveArmAt or 0) then
            controller.nextDefensiveArmAt = os.clock() + 0.1
            local folder = workspace:FindFirstChild("Characters")
            local t = now()
            local bestModel, bestDistance
            for _, model in ipairs(folder and folder:GetChildren() or {}) do
                if model ~= character and isCandidate(model) and not targetDisabled(model) then
                    local distance = distanceTo(model)
                    if distance <= 16 and (not bestDistance or distance < bestDistance) then
                        local observed = controller.pvp.attackObservations[model]
                        local attacking = t - (tonumber(model:GetAttribute("LastM1")) or 0) <= 0.45
                            or t - (tonumber(model:GetAttribute("LastM2")) or 0) <= 0.5
                            or (observed and observed.track.IsPlaying and not observed.contactSeen
                                and os.clock() - observed.startedAt <= 0.9 and hasInfo(model, "InSkill"))
                        if attacking then bestModel, bestDistance = model, distance end
                    end
                end
            end
            if bestModel and armTarget(bestModel) then
                log("target_defensive_arm", { name = bestModel.Name, distance = bestDistance })
            end
        end
        if not controller.armed then return end
    end
    local target = controller.target
    if not character then
        clearTarget("invalid")
        return
    end
    if not isCandidate(target) then
        if not tryReacquire(target, "invalid") then clearTarget("invalid") end
        return
    end

    if distanceTo(target) > controller.config.retainDistance then
        releaseBodyFacing()
        controller.moveIntent = nil
        controller.sustainedSpecialSteering = nil
        if controller.lostTargetAt == 0 then controller.lostTargetAt = os.clock()
        elseif os.clock()-controller.lostTargetAt > 1.25 then
            if not tryReacquire(target, "range") then clearTarget("range") end
        end
        return
    end
    controller.lostTargetAt = 0

    -- Positional escape is evaluated before the combo step or any
    -- yielding skill/counter. It never arms or acquires a fight by itself.
    local predictiveEscape=controller.pvp.Decide(character,humanoid,root,target,false,true)
    target=controller.target
    if predictiveEscape then return end
    controller.pvp.Step()
    local distance = distanceTo(target)
    if distance > controller.config.retainDistance then
        releaseBodyFacing()
        if controller.lostTargetAt == 0 then
            controller.lostTargetAt = os.clock()
        elseif os.clock() - controller.lostTargetAt > 1.25 then
            clearTarget("range")
        end
        return
    end
    controller.lostTargetAt = 0

    if distance > 35 then
        local progress = controller.targetProgress
        if not progress or progress.target ~= target then
            controller.targetProgress = {
                target = target,
                minDistance = distance,
                lastProgressAt = os.clock(),
            }
        else
            if distance < progress.minDistance - 3.5 then
                progress.minDistance = distance
                progress.lastProgressAt = os.clock()
            elseif os.clock() - progress.lastProgressAt > 4.5 then
                if not tryReacquire(target, "lack_of_progress") then
                    clearTarget("lack_of_progress")
                    controller.targetProgress = nil
                end
                return
            end
        end
    else
        controller.targetProgress = nil
    end

    local activeCounter = controller.activeCounter
    if activeCounter and os.clock() - activeCounter.at > 0.85 then
        if isCandidate(activeCounter.target) then
            local k = knowledgeFor(activeCounter.target)
            k.counterHistory = k.counterHistory or {}
            local ch = k.counterHistory[activeCounter.threatKind] or {}
            k.counterHistory[activeCounter.threatKind] = ch
            local entry = ch[string.lower(activeCounter.name)] or { uses = 0, successes = 0 }
            ch[string.lower(activeCounter.name)] = entry
            entry.uses = (entry.uses or 0) + 1
            entry.successes = (entry.successes or 0) + 1
            log("counter_success", { counter = activeCounter.name, threat = activeCounter.threatKind })
        end
        log("counter_window_ended",{counter=activeCounter.name,threat=activeCounter.threatKind,
            successConfirmed=true})
        controller.activeCounter = nil
    end

    observeDash()
    observeGetUp(character)
    observeSkillRecovery(character)
    local threat, threatKind, threatModel = findImmediateThreat(target)
    local physicalThreat = threat and threatKind ~= "learned_approach" and threatKind ~= "closing_approach" and threatKind ~= "movement"
    if runGetUpRecovery(character, humanoid, root, physicalThreat and threatModel or nil) then return end
    maintainGuard(threat, threatKind, threatModel)
    if os.clock() < controller.escapeUntil then
        if physicalThreat and threatKind ~= "body_repel" and controller.dashPending then
            quickBlock(threatModel, "pending_dash_threat")
        end
        if controller.escapeDirection then
            updateBodyFacing(character, humanoid, root, target, controller.escapeDirection)
        else
            releaseBodyFacing()
        end
        return
    end
    controller.escapeDirection = nil
    local needsFacing = physicalThreat or shouldTrackHeading(character, target, distance)
    if needsFacing and distance <= controller.config.bodyTrackDistance
        and (controller.config.focusOnly or physicalThreat or controller.comboBusy or os.clock() >= controller.steeringUntil) then
        updateBodyFacing(character, humanoid, root, controller.config.focusOnly and target or (physicalThreat and threatModel or target))
    else
        releaseBodyFacing()
    end
    if threat then
        controller.pendingEvadeUntil = os.clock() + controller.config.evadeBuffer
        controller.pendingThreat = threatModel
        controller.pendingThreatKind = threatKind
    elseif controller.pendingThreatKind ~= "damage" and controller.pendingThreatKind ~= "manual_dash" then
        controller.pendingEvadeUntil = 0
        controller.pendingThreat = nil
        controller.pendingThreatKind = nil
    end
    local bufferedThreat = controller.pendingThreat
    local buffered = bufferedThreat and isCandidate(bufferedThreat) and os.clock() <= controller.pendingEvadeUntil
    local manualDashBuffered = os.clock() <= controller.manualDashBufferedUntil
    local forcedRecovery = controller.pendingThreatKind == "damage" or manualDashBuffered
    local manualDashPriority = not controller.config.combatMovementPriority
        and os.clock() <= controller.manualDashPriorityUntil and not forcedRecovery
    local manualEscape = buffered and manualEscapeIsWorking(bufferedThreat)
        and not controller.config.combatMovementPriority
    local wantsDash = buffered and not manualDashPriority and (forcedRecovery or not manualEscape)
        and os.clock() - controller.lastDashAt >= adaptiveSideDashGap(bufferedThreat)
    if controller.pendingThreatKind == "closing_approach" or controller.pendingThreatKind == "learned_approach" then
        wantsDash = false
    end
    local dashAllowed, dashMode = canRequestDash(character)
    if buffered and dashAllowed and dashMode == "native_escape" and not manualDashPriority then
        wantsDash = os.clock() - controller.lastDashAt >= 0.3
    end
    wantsDash = wantsDash and os.clock() >= controller.dashRetryAt
    if controller.blockActive then
        if controller.pendingThreatKind == "body_repel" then
            releaseBlock("projectile_escape")
            dashAllowed, dashMode = canRequestDash(character)
        elseif wantsDash and dashAllowed and os.clock() - controller.blockStartedAt >= 0.18 then
            releaseBlock("prepare_escape")
        elseif not physicalThreat and distance <= controller.config.m1Range and os.clock() - controller.blockStartedAt >= 0.10 then
            releaseBlock("in_range_punish_opportunity")
        else
            return
        end
    end
    if not canAct(character) then
        if buffered and wantsDash and dashAllowed then
            local direction, vector = chooseEscapeDirection(character, root, bufferedThreat)
            if vector and nativeDash(direction, "recovery_window:" .. tostring(controller.pendingThreatKind), vector) then return end
        end
        if physicalThreat and threatKind ~= "body_repel" then quickBlock(threatModel, "defense_during_action") end
        return
    end

    local profile = discoverProfile(character)
    local generation = controller.targetGeneration
    -- Multi-rival: counter the attacker itself, not only the locked target.
    if physicalThreat and isCandidate(threatModel) and threatKind ~= "body_repel" then
        local threatDistance = distanceTo(threatModel)
        for _, counterKey in ipairs(profile.counterKeys) do
            local counter = moveForKey(counterKey)
            local counterRange = profile.ranges[counterKey] or controller.config.threatDistance
            if counter and moveReady(counter) and threatDistance <= counterRange
                and (not controller.busy or controller.comboBusy)
                and counterFitsThreat(character, threatModel, threatKind, counterKey) then
                if controller.comboBusy then
                    controller.pvp.Cancel("native_counter")
                    controller.comboSerial += 1
                    controller.comboBusy = false
                    controller.busy = false
                end
                controller.activeCounter = {
                    key = counterKey,
                    name = counter.Name,
                    threatKind = threatKind,
                    target = target,
                    at = os.clock(),
                }
                if useNativeMove(counterKey, "counter:" .. tostring(threatKind), profile) then return end
            end
        end
    end

    if controller.targetGeneration ~= generation or not controller.armed then return end
    if wantsDash then
        local kind = controller.pendingThreatKind
        local direction, vector = chooseEscapeDirection(character, root, bufferedThreat)
        if direction and nativeDash(direction, "evade:" .. tostring(kind), vector) then
            controller.pendingEvadeUntil = 0
            controller.pendingThreat = nil
            controller.pendingThreatKind = nil
            controller.manualDashBufferedUntil = 0
            return
        end
    end
    if controller.targetGeneration ~= generation or not controller.armed then return end
    if buffered then
        if threatKind == "body_repel" then
            startMicroStep(threatModel)
        elseif physicalThreat then
            if not quickBlock(threatModel, "attack_window:" .. tostring(threatKind)) then
                startMicroStep(threatModel)
            end
        elseif forcedRecovery then
            startMicroStep(bufferedThreat)
        end
        if forcedRecovery then return end
    end

    if controller.pvp.stage == 3 and runRecovery(character, humanoid, root) then return end
    if os.clock() < controller.finisherCommitUntil then return end
    controller.pvp.Decide(character, humanoid, root, target, physicalThreat)

end

table.insert(controller.connections, UserInputService.InputBegan:Connect(function(input, processed)
    if not controller.running then
        return
    end
    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        clearTarget("left_control_killswitch")
        print("[JAC] Target released | attack again to re-arm")
        return
    end
    if not controller.enabled then return end
    if input.KeyCode == Enum.KeyCode.One
        or input.KeyCode == Enum.KeyCode.Two
        or input.KeyCode == Enum.KeyCode.Three
        or input.KeyCode == Enum.KeyCode.Four then
        if controller.armed and controller.target and isCandidate(controller.target) then
            faceForAction(controller.target, 1.35)
        end
    end
    if input.KeyCode == Enum.KeyCode.Q then
        if controller.config.combatMovementPriority then return end
        controller.recoveryRequest = nil
        controller.manualDashPriorityUntil = os.clock() + 0.16
        local character = LocalPlayer.Character
        if controller.armed and character and not canAct(character) then
            local threat = closestDamageThreat() or (isCandidate(controller.target) and controller.target or nil)
            if threat then
                controller.manualDashBufferedUntil = os.clock() + 0.85
                controller.pendingEvadeUntil = os.clock() + 0.85
                controller.pendingThreat = threat
                controller.pendingThreatKind = "manual_dash"
            end
        elseif controller.armed then
            beginEscapeFacing(nil, controller.config.escapeFacingDuration)
        end
        controller.microStepSerial += 1
        if os.clock() - controller.lastManualLogAt > 0.4 then
            controller.lastManualLogAt = os.clock()
            log("manual_priority", "dash")
        end
    elseif input.KeyCode == Enum.KeyCode.W
        or input.KeyCode == Enum.KeyCode.A
        or input.KeyCode == Enum.KeyCode.S
        or input.KeyCode == Enum.KeyCode.D
        or input.KeyCode == Enum.KeyCode.Space then
        if not controller.armed or not controller.config.combatMovementPriority then
            controller.microStepSerial += 1
        end
    end
    if processed and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end
    -- UI clicks belong to the panel, never to target acquisition.
    local ui = controller.pvp.ui
    if ui and ui.gui.Enabled and ui.root.Visible then
        local point, origin, size = input.Position, ui.root.AbsolutePosition, ui.root.AbsoluteSize
        if point.X >= origin.X and point.X <= origin.X + size.X
            and point.Y >= origin.Y and point.Y <= origin.Y + size.Y then return end
    end
    if UserInputService:GetFocusedTextBox() then return end
    if controller.armed and isCandidate(controller.target) then
        controller.comboRequested = true
        return
    end
    local target
    pcall(function()
        local mouseTarget = LocalPlayer:GetMouse().Target
        local model = mouseTarget and mouseTarget:FindFirstAncestorOfClass("Model")
        if isCandidate(model) and distanceTo(model) <= controller.config.acquireDistance then
            target = model
        end
    end)
    target = target or closestInCharacterFacing(controller.config.acquireDistance)
        or closestInCharacterFacing(120, true)
    if target and (not controller.armed or controller.target ~= target) then
        armTarget(target)
    elseif not target then
        controller.acquireUntil = os.clock() + controller.config.acquireGrace
        if os.clock() - controller.lastMissLogAt > 0.5 then
            controller.lastMissLogAt = os.clock()
            log("target_miss", { processed = processed, reason = "no_facing_target" })
        end
    end
end))

table.insert(controller.connections, LocalPlayer.CharacterAdded:Connect(function()
    clearTarget("respawn")
    controller.lastConsumedM1 = 0
    task.wait(1)
    ToolController, MovementController = getControllers()
    watchCharacter(LocalPlayer.Character)
    _G.Settings = _G.Settings or {}
    _G.Settings.AutoRun = true
end))

watchCharacter(LocalPlayer.Character)

RunService:BindToRenderStep("JACAutoMovement", Enum.RenderPriority.Input.Value + 1, maintainAutoMovement)
pcall(RunService.UnbindFromRenderStep, RunService, "JACHeadingTrack")
RunService:BindToRenderStep("JACHeadingTrack", Enum.RenderPriority.Character.Value + 1, maintainHeadingTracking)

table.insert(controller.connections, RunService.Heartbeat:Connect(function()
    observeDash()
    if controller.pvp.SaveAudit and os.clock()>=(controller.pvp.nextAuditAt or 0) then
        task.defer(controller.pvp.SaveAudit)
    end
    -- Fast-path reactive guard check on every frame (60Hz / 16.6ms)
    if controller.running and controller.enabled and controller.armed and not controller.thinkBusy then
        local target = controller.target
        local character = LocalPlayer.Character
        if character then
            local ready, mode = canRequestDash(character)
            local _, escapeRoot = characterParts(character)
            if mode == "native_escape" and escapeRoot then
                local cTarget = target or closestDamageThreat()
                local root = escapeRoot
                local dir, vec = chooseEscapeDirection(character, root, cTarget)
                if dir and nativeDash(dir, "reactive_native_escape", vec) then
                    log("reactive_native_evasive", { direction = dir, target = cTarget and cTarget.Name })
                end
            end
        end
        if target and isCandidate(target) then
            local active, kind, model = findImmediateThreat(target)
            if active then
                local threatModel = model or target
                local special = controller.specialThreats[threatModel]
                if special and not special.nativeMelee and special.kind ~= "movement" then
                    local ready = canRequestDash(character)
                    if ready and os.clock() >= controller.dashRetryAt
                        and os.clock() - controller.lastDashRequestAt >= controller.config.dashRequestGap then
                        local _, root = characterParts(character)
                        local dir, vec = chooseEscapeDirection(character, root, threatModel)
                        if dir and nativeDash(dir, "evade_special:" .. tostring(special.kind or kind), vec) then
                            log("reactive_special_evade", { direction = dir, special = tostring(special.kind or kind) })
                        end
                    else
                        quickBlock(threatModel, "reactive_special_block")
                    end
                elseif kind == "m1" or kind == "m2" or kind == "skill" then
                    quickBlock(threatModel, "reactive_heartbeat")
                end
            else
                if controller.blockActive and distanceTo(target) <= controller.config.m1Range and os.clock() - controller.blockStartedAt >= 0.05 then
                    releaseBlock("heartbeat_in_range_punish")
                end
            end
        end
    end

    if controller.thinkBusy or os.clock() < controller.nextThink then
        return
    end
    controller.nextThink = os.clock() + controller.config.decisionInterval
    controller.thinkBusy = true
    local ok, err = pcall(think)
    controller.thinkBusy = false
    if not ok then
        clearTarget("decision_error")
        log("error", tostring(err))
        warn("[JAC] " .. tostring(err))
    end
end))

function controller.SetEnabled(value)
    controller.pvp.requestedEnabled = value == true
    controller.enabled = controller.pvp.requestedEnabled and not controller.pvp.paused
    if controller.pvp.ui then controller.pvp.ui:SetEnabled(controller.pvp.requestedEnabled, true) end
    if not controller.enabled then
        clearTarget("disabled")
    end
    return controller.enabled
end

function controller.SetTarget(model)
    return armTarget(model)
end

function controller.ClearTarget()
    clearTarget("manual")
end

function controller.GetStatus()
    local character = LocalPlayer.Character
    return {
        version = controller.version,
        pvpStage = controller.pvp.stage,
        paused = controller.pvp.paused,
        sequence = controller.pvp.combo and controller.pvp.combo:GetState(),
        decision = controller.pvp.dynamic and controller.pvp.dynamic.lastDecision,
        panel = controller.pvp.ui ~= nil,
        movementVersion = controller.pvp.modules.movement.version,
        comboVersion = controller.pvp.modules.combos.version,
        movement = controller.pvp.movement.lastDecision,
        selectedItem = controller.pvp.selectedItem,
        observedOpponents = controller.pvp.lastTacticalSnapshot and #controller.pvp.lastTacticalSnapshot.opponents or 0,
        timing = controller.pvp.modules.moveset_data.timingReport(),
        defense = controller.pvp.defenseStats,
        slam = controller.pvp.slamReceipt and {downObserved=controller.pvp.slamReceipt.downObserved,
            impactObserved=controller.pvp.slamReceipt.impactObserved,healthLoss=controller.pvp.slamReceipt.healthLoss,
            target=controller.pvp.slamReceipt.target.Name},
        auditCounts = controller.pvp.auditCounts,
        enabled = controller.enabled,
        armed = controller.armed,
        target = controller.target and controller.target.Name or nil,
        moveset = character and character:GetAttribute("Moveset") or nil,
        autoRun = _G.Settings and _G.Settings.AutoRun == true,
        historyCount = #controller.history,
        comboBusy = controller.comboBusy,
        comboRequested = controller.comboRequested,
        pingMs = math.floor(pingSeconds() * 1000 + 0.5),
        specialFollowupRemaining = math.max(0, (controller.specialFollowupUntil or 0) - os.clock()),
        bodyRepelObserver = controller.bodyRepelObserver,
        uroThreatObserverCount = (function()
            local count = 0
            for _, state in pairs(controller.uroThreatObservers or {}) do
                if state == "connected" then count += 1 end
            end
            return count
        end)(),
        inputContractCount = (function()
            local count = 0
            for _, mode in pairs(toolInputModes) do
                mode = tonumber(mode)
                if mode and mode >= 1 and mode <= 5 then count += 1 end
            end
            return count
        end)(),
        moveObserverCount = (function()
            local count = 0
            for _, state in pairs(controller.moveObservers) do
                if state == "connected" then count += 1 end
            end
            return count
        end)(),
        loadoutCoverageCount = (function()
            local count = 0
            for _ in pairs(controller.loadoutCoverage) do count += 1 end
            return count
        end)(),
        matchupCount = (function()
            local count = 0
            for _ in pairs(controller.matchups) do
                count += 1
            end
            return count
        end)(),
    }
end

function controller.GetLoadoutReport()
    local character = LocalPlayer.Character
    local profile = character and discoverProfile(character)
    local slots = {}
    if profile then
        for key = 1, 4 do
            local slot = profile.loadout.slots[key]
            if slot then
                slots[key] = {
                    name = slot.name,
                    service = slot.service,
                    inputMode = profile.inputModes[key],
                    range = profile.ranges[key],
                    holdDuration = profile.holdDurations[key],
                    perfectPhase = profile.perfectPhases[key],
                    useTwice = profile.useTwice[key],
                    supportsDeactivate = slot.supportsDeactivate,
                    observer = controller.moveObservers[slot.service],
                }
            end
        end
    end
    return { moveset = character and character:GetAttribute("Moveset") or nil, slots = slots }
end

function controller.GetOpponentReport(name)
    local reports = {}
    for key, knowledge in pairs(controller.knowledge) do
        if not name or string.find(string.lower(key), string.lower(tostring(name)), 1, true) then
            reports[key] = knowledge
        end
    end
    return {
        reports = reports,
        intelEvents = controller.intelEvents,
        trace = controller.combatTrace,
    }
end

function controller.Stop()
    if not controller.running then
        return
    end
    controller.running = false
    controller.enabled = false
    controller.armed = false
    controller.moveIntent = nil
    controller.sustainedSpecialSteering = nil
    releaseBodyFacing()
    RunService:UnbindFromRenderStep("JACAutoMovement")
    pcall(RunService.UnbindFromRenderStep, RunService, "JACHeadingTrack")
    controller.pvp.Cancel("stopped")
    controller.pvp.dynamic:stop()
    controller.pvp.movement:stop()
    if MovementController.Dash==controller.pvp.dashWrapper then MovementController.Dash=controller.pvp.originalDash end
    if ToolController.UseSetService==controller.pvp.meleeWrapper then
        ToolController.UseSetService=controller.pvp.originalUseSetService
    end
    if controller.pvp.ui then controller.pvp.ui:Destroy() end
    controller.sustainedSpecialSteering = nil
    if ControlModule and nativeControlMoveVector then
        ControlModule.GetMoveVector = nativeControlMoveVector
    end
    if controller.aimHooksInstalled and ToolController then
        if type(controller.origTarget) == "function" then ToolController.GetTarget = controller.origTarget end
        if type(controller.origTargetOrProj) == "function" then ToolController.GetTargetOrProjectile = controller.origTargetOrProj end
        if type(controller.origMouseTarget) == "function" then ToolController.GetMouseTarget = controller.origMouseTarget end
        controller.aimHooksInstalled = false
    end
    RunService:UnbindFromRenderStep("JACAutoMovement")
    pcall(RunService.UnbindFromRenderStep, RunService, "JACHeadingTrack")
    saveIntel()
    clearTarget("stopped")
    disconnectAll()
    print("[JAC] Stopped")
end

controller.pvp.Mount()

_G.Settings = _G.Settings or {}
_G.Settings.AutoRun = true
clearFullLockState()
pcall(purgeFacingOrphans)

print(string.format("[JujutsuAdaptiveCombat v%s] Ready | first click arms target | native AutoRun + dash", controller.version))


