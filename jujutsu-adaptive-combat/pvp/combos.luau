-- Mesa PvP combos 1.3.0. Pure sequencer: no remotes, movement, UI or auto-start.
-- Integration: loadstring(readfile("pvp/combos.luau"))(); module.new(profile).
-- profile MUST come from the confirmed place's native combat implementation.
-- Required: placeId, maxStage, m1Gap, chainResetSeconds, finisherResetSeconds.
-- Optional slam: slamAfterStage (=maxStage-1), thirdRecovery (native duration).
-- terminalStages optionally includes native end sentinels, e.g. {0,4,5}.
-- All times below are monotonic seconds (os.clock), NOT LastM1's wall clock.
-- Adapter converts LastM1 to an opaque m1Token and computes m1Age separately.
-- Jujutsu: CurrentM1 is the NEXT punch. Adapter passes CurrentM1-1 as stage.
-- Snapshot fields: now, placeId, jobId, character, target, loadout (stable IDs),
-- enabled, armed, localAlive, targetAlive, stunned, ragdolled, defending,
-- escaping, manualOverride, targetBlocking, targetInvulnerable, inRange,
-- canM1, canJump, airborne, stage, m1Token, m1Age; skillToken, skills[name].
-- Begin(snapshot, {slam=true, skills={"name1","name2"}}) then Step(snapshot).
-- Execute returned actions IN ORDER, exactly once. Stop/respawn/unload MUST
-- execute Cancel()'s returned actions so an owned jump key is released.
-- Actions: m1{id,stage,variant,target}, jump{down}, skill{id,name,target}.
-- The adapter owns native input; m1 Down maps to native Activated,"Down" only
-- when that API has been verified for this place. Never force JumpPower/CFrame.
-- Native attributes confirm acceptance, NOT damage. For hit-gated skills call
-- Confirm(id,{hit=true,variant="Down"}) from a real hit/variant observation.
-- Snapshot skill entry: ready, usable, inRange (all true); defaults fail closed.
-- Every planned skill requires the preceding attack's confirmed hit, unless
-- its entry explicitly sets requiresHit=false. No guessed slot ordering.

local Combos = { version = "1.3.3" }
local Engine = {}
Engine.__index = Engine

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function positive(n, name, allowZero)
    assert(finite(n) and (allowZero and n >= 0 or n > 0), "Invalid " .. name)
    return n
end

local function stageValid(stage, maxStage)
    return finite(stage) and stage >= 0 and stage <= maxStage and stage % 1 == 0
end

-- Inventory API (no character/moveset lookup):
-- Inventory(items, catalog, m1) accepts actual backpack OR native hotbar slots.
-- Each item: id/name/service/key, available, ready, usable. Catalog is keyed by
-- service/id/name and contains verified=true, area, kind, startup, score,
-- requiresHit, followups (stable item IDs), supportsSlam. Never infer damage
-- from slot number, input mode, character name, or a cosmetic Handle's size.
-- area: shape="band" (distance only), "sphere", "box", "cone", "capsule";
-- min/maxRange; box width/height, sphere/capsule radius, cone halfAngle (radians).
-- origin is {x,y,z} in the attack frame: x=lateral, y=up, z=forward.
-- Snapshot: inventory, distance, relative={x,y,z}, relativeVelocity={x,y,z},
-- lineOfSight, skills[id], canM1, slamAllowed. Positive z is FORWARD; convert
-- Roblox object-space -Z before passing it here. M1 has id/revision, verified,
-- available, area, supportsSlam, slamArea, optional followups (item IDs).
-- Catalog definitions are immutable; bump revision if damage rules change.
-- Decide returns a plan or nil,reason. BeginDynamic returns Begin's result.
-- Adapter executes actions; this module NEVER attacks, moves or equips items.
local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

function Combos.Inventory(items, catalog, m1)
    local inventory = { items = {}, m1 = m1 and copy(m1) or nil }
    local signature, seen = {}, {}
    for _, item in pairs(items or {}) do
        local id = item.id or item.service or item.name
        if type(id) == "string" and id ~= "" and not seen[id] and item.available ~= false then
            seen[id] = true
            local definition = catalog and (catalog[id] or catalog[item.name])
            local entry = copy(definition)
            entry.id, entry.name, entry.key = id, item.name or id, item.key
            entry.service = item.service
            entry.available = item.available == true
            entry.ready, entry.usable = item.ready == true, item.usable == true
            inventory.items[#inventory.items + 1] = entry
            -- Readiness/equipped state changes do not invalidate the inventory.
            -- Length prefixes prevent collisions with punctuation in tool names.
            local slot = tostring(item.key or "")
            local revision = tostring(entry.revision or "")
            signature[#signature + 1] = #id .. ":" .. id .. ":" .. #slot .. ":" .. slot
                .. ":" .. #revision .. ":" .. revision
        end
    end
    table.sort(signature)
    if m1 then
        local id, revision = tostring(m1.id or "native_m1"), tostring(m1.revision or "")
        signature[#signature + 1] = "m1:" .. #id .. ":" .. id .. ":" .. #revision .. ":" .. revision
    end
    table.sort(inventory.items, function(a, b) return a.id < b.id end)
    inventory.signature = table.concat(signature, "|")
    return inventory
end

local function xyz(v)
    if type(v) ~= "table" or not finite(v.x) or not finite(v.y) or not finite(v.z) then return end
    return v.x, v.y, v.z
end

function Combos.InDamageArea(move, s)
    if type(move) ~= "table" or move.verified ~= true or type(move.area) ~= "table" then
        return false, "unknown_damage_area"
    end
    local a = move.area
    local low, high = a.minRange or 0, a.maxRange
    if not finite(low) or low < 0 or not finite(high) or high <= 0 or high < low then
        return false, "invalid_damage_area"
    end
    if move.requiresLOS ~= false and s.lineOfSight ~= true then return false, "line_of_sight_unknown_or_blocked" end
    local x, y, z = xyz(s.relative)
    local d = s.distance
    if x then
        local vx, vy, vz = xyz(s.relativeVelocity)
        if vx then
            local delay = finite(move.startup) and math.max(0, move.startup) or 0
            if finite(move.projectileSpeed) and move.projectileSpeed > 0 then
                delay = delay + math.sqrt(x*x+y*y+z*z) / move.projectileSpeed
            end
            delay = math.min(delay, 0.75)
            x, y, z = x + vx*delay, y + vy*delay, z + vz*delay
        end
        local ox, oy, oz = 0, 0, 0
        if a.origin then
            ox, oy, oz = xyz(a.origin)
            if not ox then return false, "invalid_area_origin" end
        end
        x, y, z = x-ox, y-oy, z-oz
        d = math.sqrt(x*x+y*y+z*z)
    elseif a.shape ~= "band" then
        return false, "missing_attack_coordinates"
    end
    if not finite(d) or d < 0 then return false, "missing_distance" end
    if d < low or d > high then return false, "outside_damage_range" end
    if a.shape == "band" then return true end
    if a.shape == "sphere" then
        return finite(a.radius) and a.radius > 0 and d <= a.radius, "outside_sphere"
    elseif a.shape == "box" then
        return finite(a.width) and a.width > 0 and finite(a.height) and a.height > 0
            and z >= 0 and z <= high and math.abs(x) <= a.width/2 and math.abs(y) <= a.height/2, "outside_box"
    elseif a.shape == "cone" then
        if not finite(a.halfAngle) or a.halfAngle <= 0 or a.halfAngle > math.pi/2 then return false, "invalid_cone" end
        return z >= 0 and (d == 0 or z/d >= math.cos(a.halfAngle)), "outside_cone"
    elseif a.shape == "capsule" then
        if not finite(a.radius) or a.radius <= 0 then return false, "invalid_capsule" end
        local dz = z - math.clamp(z, 0, high)
        return x*x+y*y+dz*dz <= a.radius*a.radius, "outside_capsule"
    end
    return false, "unknown_area_shape"
end

local function itemById(inventory, id)
    for _, item in ipairs(inventory.items or {}) do if item.id == id then return item end end
end

local function itemState(s, item)
    return s.skills and s.skills[item.id] or item
end

local function usableItem(s, item, requireHit)
    local state = itemState(s, item)
    return item.available == true and state.ready == true and state.usable == true
        and (not requireHit or item.requiresHit == false)
        and Combos.InDamageArea(item, s)
end

local function m1InArea(s, slam)
    if not s.inventory then return s.inRange == true end
    local m1 = s.inventory.m1
    if not m1 or m1.available ~= true then return false end
    if not slam then return Combos.InDamageArea(m1, s) end
    if s.slamAllowed ~= true or m1.supportsSlam ~= true or type(m1.slamArea) ~= "table" then return false end
    return Combos.InDamageArea({verified=m1.verified,area=m1.slamArea,requiresLOS=m1.requiresLOS}, s)
end

function Engine:Decide(s, options)
    options = options or {}
    if type(s) ~= "table" or s.placeId ~= self.profile.placeId then return nil, "wrong_place" end
    if s.enabled ~= true or s.armed ~= true or s.localAlive ~= true or s.targetAlive ~= true
        or s.stunned or s.ragdolled or s.defending or s.escaping or s.manualOverride
        or s.targetInvulnerable then return nil, "offense_unavailable" end
    local inv = s.inventory
    if type(inv) ~= "table" or type(inv.items) ~= "table" or type(inv.signature) ~= "string" then
        return nil, "missing_item_inventory"
    end
    local best, score
    for _, item in ipairs(inv.items) do
        -- Counters/evasives belong to defense, never spend them as a combo opener.
        if item.kind ~= "counter" and item.kind ~= "evasive" and usableItem(s, item, true) then
            local value = finite(item.score) and item.score or 0
            if item.kind == "ranged" and s.inRange ~= true then value = value + 1 end
            if not score or value > score then best, score = item, value end
        end
    end
    local m1 = inv.m1
    -- Held native input owns the punch requests; the engine may still resume
    -- its observed chain to schedule the third-hit jump and fourth-hit Down.
    local nativeChain=s.manualM1==true and s.stage and s.stage>0 and s.stage<self.profile.maxStage
        and finite(s.m1Age) and s.m1Age<self.profile.chainResetSeconds
    local finishing=s.stage==self.profile.slamAfterStage and options.slam~=false and s.slamAllowed==true
    local meleeArea=finishing and m1InArea(s,true) or (m1 and Combos.InDamageArea(m1,s))
    local heldMelee = s.physicalM1 == true
    local melee = m1 and m1.available == true and (s.canM1 == true or nativeChain or heldMelee) and meleeArea
    -- A live chain is resumed only inside the M1 area. Never splice in a ranged
    -- skill just because it has a higher score while native punches are pending.
    local chain = s.stage and s.stage > 0 and s.stage < self.profile.maxStage
        and finite(s.m1Age) and s.m1Age < self.profile.chainResetSeconds
    if melee and (heldMelee or chain or not best or (finite(m1.score) and m1.score or 0) >= score or s.targetBlocking == true) then
        local skills, seen = {}, {}
        for _, id in ipairs(m1.followups or {}) do
            local follow = itemById(inv, id)
            if follow and follow.verified == true and not seen[id]
                and follow.kind ~= "counter" and follow.kind ~= "evasive" then
                skills[#skills+1], seen[id] = id, true
                if #skills >= 4 then break end
            end
        end
        return { mode = "m1", slam = options.slam ~= false and s.slamAllowed == true
            and m1.supportsSlam == true and type(m1.slamArea) == "table"
            and self.profile.slamAfterStage ~= nil,
            resumeNative = options.resumeNative == true, skills = skills,
            inventorySignature = inv.signature, decision = "item_melee_chain" }
    end
    if chain then return nil, "native_chain_active" end
    -- A held click owns the opener and the restart after the fourth punch.
    -- Do not replace either with a skill while its native cooldown is running.
    if heldMelee then return nil, "held_m1_out_of_area" end
    if best then
        local skills = { best.id }
        -- Only explicitly compatible links; no arbitrary slot order. Re-evaluate
        -- each link's hit confirmation/readiness/area immediately before sending.
        local seen = { [best.id] = true }
        for _, id in ipairs(best.followups or {}) do
            local follow = itemById(inv, id)
            if follow and follow.verified == true and not seen[id]
                and follow.kind ~= "counter" and follow.kind ~= "evasive" then
                skills[#skills+1], seen[id] = id, true
                if #skills >= 4 then break end
            end
        end
        return { mode = "skills", skills = skills, slam = false,
            inventorySignature = inv.signature, decision = "item_skill_chain" }
    end
    return nil, "no_ready_item_in_damage_area"
end

function Engine:BeginDynamic(s, options)
    local plan, reason = self:Decide(s, options)
    if not plan then return false, reason end
    return self:Begin(s, plan)
end

function Combos.new(profile)
    assert(type(profile) == "table", "A verified place profile is required")
    local p = {}
    p.placeId = positive(profile.placeId, "placeId")
    p.maxStage = positive(profile.maxStage, "maxStage")
    assert(p.maxStage % 1 == 0 and p.maxStage >= 2, "Invalid maxStage")
    p.terminalStages = { [p.maxStage] = true, [0] = true }
    p.nativeMaxStage = p.maxStage
    for _, stage in ipairs(profile.terminalStages or {}) do
        assert(finite(stage) and stage % 1 == 0 and (stage == 0 or stage >= p.maxStage), "Invalid terminal stage")
        p.terminalStages[stage] = true
        p.nativeMaxStage = math.max(p.nativeMaxStage, stage)
    end
    p.m1Gap = positive(profile.m1Gap, "m1Gap", true)
    p.chainResetSeconds = positive(profile.chainResetSeconds, "chainResetSeconds")
    p.finisherResetSeconds = positive(profile.finisherResetSeconds, "finisherResetSeconds")
    -- Deadlines are safety limits, never claims about native attack durations.
    p.ackTimeout = positive(profile.ackTimeout or 0.9, "ackTimeout")
    p.readyTimeout = positive(profile.readyTimeout or 1.35, "readyTimeout")
    p.jumpTimeout = positive(profile.jumpTimeout or 0.4, "jumpTimeout")
    p.skillTimeout = positive(profile.skillTimeout or 1.5, "skillTimeout")
    p.sequenceTimeout = positive(profile.sequenceTimeout or 12, "sequenceTimeout")
    if profile.slamAfterStage ~= nil then
        assert(profile.slamAfterStage == p.maxStage - 1, "Slam must be the final M1")
        p.slamAfterStage = profile.slamAfterStage
        p.thirdRecovery = positive(profile.thirdRecovery, "thirdRecovery", true)
    end
    return setmetatable({ profile = p, phase = "idle", serial = 0,
        nextId = 0, jumpOwned = false, events = {}, lastNow = -math.huge }, Engine)
end

function Engine:_event(name, detail)
    self.events[#self.events + 1] = { name = name, detail = detail,
        time = self.lastNow, serial = self.serial }
    if #self.events > 64 then table.remove(self.events, 1) end
end

function Engine:_release(actions)
    if self.jumpOwned then
        actions[#actions + 1] = { kind = "jump", down = false }
        self.jumpOwned = false
    end
end

function Engine:Cancel(reason)
    local actions = {}
    self:_release(actions)
    self.pending = nil
    self.lastAttack = nil
    self.phase = "cancelled"
    self.reason = reason or "cancelled"
    self.serial = self.serial + 1
    self:_event("cancelled", self.reason)
    return actions
end

function Engine:_finish(actions)
    self:_release(actions)
    self.pending = nil
    self.phase = "complete"
    self.reason = nil
    self:_event("complete", self.slamConfirmed and "slam_confirmed" or "sequence_accepted")
    return actions
end

function Engine:_guard(s)
    if type(s) ~= "table" or not finite(s.now) then return "invalid_snapshot" end
    if s.now < self.lastNow then return "clock_reversed" end
    if s.placeId ~= self.profile.placeId then return "wrong_place" end
    if s.enabled ~= true or s.armed ~= true then return "disabled" end
    if s.localAlive ~= true or s.targetAlive ~= true then return "dead_or_missing" end
    if s.inventory ~= nil and (type(s.inventory) ~= "table" or type(s.inventory.items) ~= "table"
        or type(s.inventory.signature) ~= "string") then return "invalid_item_inventory" end
    if not s.character or not s.target or not s.jobId or (s.loadout == nil and not s.inventory) then return "missing_identity" end
    if s.stunned or s.ragdolled then return "interrupted" end
    if s.defending or s.escaping then return "defense_priority" end
    if s.manualOverride then return "manual_override" end
    if s.targetBlocking or s.targetInvulnerable then return "target_protected" end
    if not stageValid(s.stage, self.profile.nativeMaxStage) then return "unknown_native_stage" end
    if s.m1Token == nil or not finite(s.m1Age) or s.m1Age < 0 then return "missing_native_clock" end
    if self.context then
        for _, key in ipairs({ "jobId", "character", "target" }) do
            if s[key] ~= self.context[key] then return key .. "_changed" end
        end
        if self.context.inventorySignature then
            if not s.inventory or s.inventory.signature ~= self.context.inventorySignature then return "inventory_changed" end
        elseif s.loadout ~= self.context.loadout then return "loadout_changed" end
    end
    return nil
end

function Engine:Begin(s, plan)
    if self.phase ~= "idle" and self.phase ~= "complete" and self.phase ~= "cancelled" then
        return false, "busy"
    end
    if plan == nil and type(s) == "table" and s.inventory then
        local reason
        plan, reason = self:Decide(s)
        if not plan then return false, reason end
    end
    self.context = nil
    local reason = self:_guard(s)
    if reason then return false, reason end
    plan = plan or {}
    if type(plan) ~= "table" then return false, "invalid_combo_plan" end
    if plan.mode ~= nil and plan.mode ~= "m1" and plan.mode ~= "skills" then return false, "invalid_combo_mode" end
    if plan.inventorySignature and (not s.inventory or s.inventory.signature ~= plan.inventorySignature) then
        return false, "inventory_changed"
    end
    if plan.mode ~= "skills" then
        if not m1InArea(s) then return false, "out_of_range" end
    end
    if plan.slam and not self.profile.slamAfterStage then return false, "slam_profile_missing" end
    -- Do not steal an already running native/manual chain or guess its history.
    local resume = plan.resumeNative == true and s.stage >= 1
        and s.stage < self.profile.maxStage and s.m1Age < self.profile.chainResetSeconds
    if s.stage > 0 and not resume then
        local reset = self.profile.terminalStages[s.stage]
            and self.profile.finisherResetSeconds or self.profile.chainResetSeconds
        if s.m1Age < reset then return false, "native_chain_active" end
    end
    local skills = {}
    for i, name in ipairs(plan.skills or {}) do
        if type(name) ~= "string" or name == "" then return false, "invalid_skill_plan" end
        if s.inventory and not itemById(s.inventory, name) then return false, "skill_not_in_inventory:" .. name end
        skills[i] = name
    end
    if plan.mode == "skills" and #skills == 0 then return false, "empty_skill_plan" end
    self.context = { jobId = s.jobId, character = s.character, target = s.target, loadout = s.loadout,
        inventorySignature = s.inventory and s.inventory.signature }
    self.serial = self.serial + 1
    self.lastNow = s.now
    self.startedAt = s.now
    self.stage = resume and s.stage or 0
    self.nativeStage = s.stage
    self.nativeToken = s.m1Token
    self.slam = plan.slam == true
    self.mode, self.decision = plan.mode or "m1", plan.decision
    self.skills = skills
    self.skillIndex = 1
    self.lastHit = false
    self.slamConfirmed = false
    self.lastAcceptedAt = resume and (s.now - s.m1Age) or nil
    self.phase = self.mode == "skills" and "skills" or (resume and self.slam
        and self.stage == self.profile.slamAfterStage and "jump_ready" or "ready")
    self.phaseAt = s.now
    self.pending = nil
    self.lastAttack = nil
    self.reason = nil
    self.externalChangedAt = nil
    self:_event("begin")
    return true
end

-- Only the active request ID may be acknowledged. No delayed task can advance
-- a later generation, and an input call returning successfully is not an ack.
function Engine:Confirm(id, observation)
    local p = self.pending
    if not p or p.id ~= id then p = self.lastAttack end
    if not p or p.id ~= id or p.serial ~= self.serial then return false end
    if type(observation) ~= "table" then return false end
    if observation.accepted == false then
        p.rejected = true
        return true
    end
    if observation.hit == true then
        p.hit = true
        if p == self.lastAttack then self.lastHit = true end
    end
    if observation.variant == "Down" then
        p.downConfirmed = true
        if p == self.lastAttack and p.variant == "Down" then self.slamConfirmed = true end
    end
    if observation.accepted == true then p.accepted = true end
    return true
end

-- Native held-input finishers may complete without an engine-issued request.
-- The adapter supplies BOTH native Down and native contact evidence, scoped
-- to the original chain serial and victim; a sent input never confirms this.
function Engine:ConfirmNativeFinisher(serial,target,evidence)
    if serial~=self.serial or not self.context or self.context.target~=target
        or not self.slam or (self.stage or 0)<self.profile.slamAfterStage
        or type(evidence)~="table" or evidence.variant~="Down" or evidence.hit~=true then return false end
    self.slamConfirmed=true
    self.lastHit=true
    return true
end

function Engine:_request(kind, s, actions, name, variant)
    self.nextId = self.nextId + 1
    self.pending = { id = self.nextId, serial = self.serial, kind = kind,
        stage = self.stage + 1, nativeStage = s.stage, token = s.m1Token,
        skillToken = s.skillToken, sentAt = s.now, hit = false, variant = variant }
    actions[#actions + 1] = { kind = kind, id = self.nextId, serial = self.serial,
        stage = kind == "m1" and self.stage + 1 or nil,
        name = name, variant = variant, target = self.context.target }
    if kind == "skill" and s.inventory then
        local item = itemById(s.inventory, name)
        actions[#actions].itemId, actions[#actions].key = item.id, item.key
        actions[#actions].service = item.service
    end
    self.phase = "await_ack"
    self.phaseAt = s.now
    self:_event("request", kind == "m1" and self.stage + 1 or name)
end

function Engine:Step(s)
    if self.phase == "idle" or self.phase == "complete" or self.phase == "cancelled" then return {} end
    local reason = self:_guard(s)
    if reason then return self:Cancel(reason) end
    self.lastNow = s.now
    if s.now - self.startedAt >= self.profile.sequenceTimeout then return self:Cancel("sequence_timeout") end
    local actions = {}
    if self.phase == "await_ack" then
        local p = self.pending
        if p.rejected then return self:Cancel("native_rejected") end
        local accepted = p.accepted == true
        if p.kind == "m1" then
            accepted = false -- M1 stages always require fresh native attributes.
            -- Stage changes without a fresh native attack token are insufficient.
            if s.m1Token ~= p.token then
                local terminalReset = p.stage == self.profile.maxStage and self.profile.terminalStages[s.stage]
                if s.stage == p.stage or terminalReset then
                    accepted = true
                else
                    -- Attributes replicate separately. Wait for the stage paired
                    -- with this fresh token before diagnosing a desync.
                    p.tokenChangedAt = p.tokenChangedAt or s.now
                    if s.now - p.tokenChangedAt >= 0.25 then return self:Cancel("stage_desync") end
                end
            end
        elseif s.skillToken ~= nil and s.skillToken ~= p.skillToken then
            -- Adapter must scope skillToken to THIS requested skill, not any skill.
            accepted = true
        end
        if not accepted then
            if s.now - p.sentAt >= self.profile.ackTimeout then return self:Cancel("ack_timeout") end
            return actions -- Never blindly resend: a delayed ack could duplicate an attack.
        end
        self.lastHit = p.hit == true
        self.lastAcceptedAt = p.sentAt
        self.nativeStage, self.nativeToken = s.stage, s.m1Token
        self.lastAttack = p -- Damage often arrives AFTER native input acceptance.
        self.pending = nil
        if p.kind == "skill" then
            self.skillIndex = self.skillIndex + 1
            self.phase = "skills"
        else
            self.stage = p.stage
            if p.variant == "Down" then self.slamConfirmed = p.downConfirmed == true end
            if self.stage == self.profile.maxStage then
                self.phase = "skills"
            elseif self.slam and self.stage == self.profile.slamAfterStage then
                self.phase = "jump_ready"
            else
                self.phase = "ready"
            end
        end
        self.phaseAt = s.now
        self:_event("accepted", p.kind == "m1" and self.stage or "skill")
        return actions -- One transition per snapshot; never consume the same ack twice.
    end

    if self.phase == "skills" and s.m1Token ~= self.nativeToken then
        return self:Cancel("external_attack_during_followup")
    end
    if self.phase ~= "skills" then
        if s.manualM1 == true and s.m1Token ~= self.nativeToken then
            -- The game owns physical held-M1 input. Observe its next accepted
            -- stage instead of cancelling, resending, or inventing an ack.
            if s.stage == self.stage + 1 then
                self.stage = s.stage
                self.nativeStage, self.nativeToken = s.stage, s.m1Token
                self.lastAcceptedAt = s.now - s.m1Age
                self.lastHit = false
                self.lastAttack = nil
                if self.stage == self.profile.maxStage then
                    self:_release(actions)
                    self.phase = "skills"
                elseif self.slam and self.stage == self.profile.slamAfterStage then
                    self.phase = "jump_ready"
                else self.phase = "ready" end
                self.phaseAt = s.now
                self:_event("native_manual_stage", self.stage)
                return actions
            end
            self.externalChangedAt = self.externalChangedAt or s.now
            if s.now - self.externalChangedAt < 0.25 then return actions end
            return self:Cancel("external_stage_desync")
        end
        self.externalChangedAt = nil
        if s.m1Token ~= self.nativeToken or s.stage ~= self.nativeStage then
            -- A native reset can precede the fresh token; keep the engine
            -- conservative for states not explicitly adopted above.
            return self:Cancel("external_attack_or_reset")
        end
        if self.stage > 0 and s.m1Age >= self.profile.chainResetSeconds then
            return self:Cancel("native_chain_expired")
        end
    end

    if self.phase == "ready" then
        if not m1InArea(s) then return self:Cancel("out_of_m1_area") end
        if s.canM1 == true and s.m1Age >= self.profile.m1Gap then
            self:_request("m1", s, actions)
        elseif s.now - self.phaseAt >= self.profile.readyTimeout then
            return self:Cancel("m1_not_ready")
        end
    elseif self.phase == "jump_ready" then
        if not m1InArea(s, true) then return self:Cancel("slam_area_unavailable") end
        if s.now - self.lastAcceptedAt >= self.profile.thirdRecovery and (s.airborne == true or s.canJump == true) then
            if s.airborne == true then
                self.phase = "airborne"
            else
                self.jumpOwned = true
                actions[#actions + 1] = { kind = "jump", down = true }
                self.phase = "await_air"
            end
            self.phaseAt = s.now
        elseif s.now - self.phaseAt >= self.profile.readyTimeout then
            return self:Cancel("jump_not_ready")
        end
    elseif self.phase == "await_air" then
        if s.airborne == true then
            self:_release(actions)
            self.phase = "airborne"
            self.phaseAt = s.now
        elseif s.now - self.phaseAt >= self.profile.jumpTimeout then
            return self:Cancel("no_liftoff")
        end
    elseif self.phase == "airborne" then
        if s.airborne ~= true then
            -- A physical native fourth request may already be in flight when
            -- the slam lands. Await its real attribute acknowledgement.
            if s.manualFinisherPending == true then return actions end
            return self:Cancel("landed_before_slam")
        end
        if not m1InArea(s, true) then return self:Cancel("slam_area_unavailable") end
        if s.canM1 == true and s.m1Age >= self.profile.m1Gap then
            self:_release(actions)
            self:_request("m1", s, actions, nil, "Down")
        elseif s.manualM1 == true then
            -- Held physical M1: the game fires the native Down itself. Keep
            -- waiting (stage adoption / landing decide the outcome) instead of
            -- cancelling the slam at jumpTimeout.
            if s.now - self.phaseAt >= self.profile.jumpTimeout * 4 then return self:Cancel("slam_window_expired") end
        elseif s.now - self.phaseAt >= self.profile.jumpTimeout then
            return self:Cancel("slam_window_expired")
        end
    elseif self.phase == "skills" then
        local name = self.skills[self.skillIndex]
        if not name then return self:_finish(actions) end
        local item = s.inventory and itemById(s.inventory, name)
        local skill = item and itemState(s, item) or s.skills and s.skills[name]
        if not skill then return self:Cancel("unknown_skill:" .. name) end
        local requiresHit = skill.requiresHit ~= false
        if item then requiresHit = item.requiresHit ~= false end
        -- A confirmed slam (Down + contact) is itself the hit proof for follow-ups.
        if requiresHit and not (self.lastHit or self.slamConfirmed) then
            if s.now - self.phaseAt >= self.profile.skillTimeout then return self:Cancel("followup_hit_unconfirmed") end
            return actions
        end
        local inArea = item and item.available == true and Combos.InDamageArea(item, s)
        if skill.ready == true and skill.usable == true
            and (s.inventory and inArea or not s.inventory and skill.inRange == true) then
            self:_request("skill", s, actions, name)
        elseif s.now - self.phaseAt >= (self.profile.skillSkipSeconds or 0.35) then
            -- Fast chain: a link that is cooling down or out of area is skipped
            -- instead of stalling the whole sequence.
            self.skillIndex = self.skillIndex + 1
            self.phaseAt = s.now
            self:_event("skill_skipped", name)
        end
    end
    return actions
end

function Engine:GetState()
    return { version = Combos.version, phase = self.phase, stage = self.stage or 0,
        serial = self.serial, reason = self.reason, busy = self.phase ~= "idle"
            and self.phase ~= "complete" and self.phase ~= "cancelled",
        pendingId = self.pending and self.pending.id, jumpOwned = self.jumpOwned,
        slamConfirmed = self.slamConfirmed == true, lastHit = self.lastHit == true,
        mode = self.mode, decision = self.decision,
        inventorySignature = self.context and self.context.inventorySignature }
end

return Combos
