-- Pure decisions. No input injection, remotes, connections or auto-start.
-- API unchanged: new(config), decide(snapshot), step(snapshot, handlers), reset/stop.
-- Optional opponents (or targets) array; target remains the legacy fallback.
-- Decisions include target/targetId, offenseTargetId, impactAt and threatCount.
-- Multi-target adapters MUST use decision.target, not a captured snapshot.target.
-- Optional block/counter/evasive require explicit can[action], cooldowns[action]
-- and non-yielding handlers returning true ONLY on accepted requests.
-- Accepted requests do not prove successful defense. Every action remains opt-in.
-- Optional target.move (or moveset) = CONFIRMED game-specific move properties:
-- range,minRange,height,shape,radius,width,angle (radians),windup,activeDuration,
-- blockable,parryable,counterable. confirmed=false ignores unverified properties.
-- target.area may override geometry. Shapes: sphere/radial, cone, line/box.
-- Geometry vectors: Vector3 or {x,y,z}; self.position/velocity and
-- target.position/velocity/facing. Without geometry use measured radial distance.
-- Timing: target.impactAt OR attackStartedAt/startedAt + move.windup;
-- activeUntil, attackId, hitIndex, counterWindowUntil, recoveryUntil, whiffedUntil.
-- All times share snapshot.now's monotonic clock; latency is one-way seconds.
-- threatensSelf=false excludes unrelated attacks; affectsThroughCover=true allows
-- observed attacks through cover. Unknown timing never invents a parry window.
-- self.evasiveWhileStunned permits native escape only via can.evasive.
-- snapshot.attackRange/minAttackRange are ranges of the currently selected item.
-- Shared planner aliases: range={min,max}, target.attack={active,impactAt,
-- expiresAt,shape,range,width,halfAngle,direction}; position-only opponents work.
-- Counter startup: self.counterWindup (legacy cooldowns.counterWindup accepted).
-- Adapter integration must supply observations and handlers; this module does
-- not inspect Instances or guess which move an animation represents.

local Dynamic = {version = "2.0.2"}
local Controller = {}
Controller.__index = Controller
local baseActions = {"approach", "retreat", "dodge", "parry", "attack", "punish"}
local optionalDelays = {block=0.06, counter=0.12, evasive=0.12}
local function finite(v)
    return type(v)=="number" and v==v and v > -math.huge and v < math.huge
end
local function positive(v, name)
    assert(finite(v) and v>0, "dynamic: invalid "..name)
    return v
end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function future(v,now) return finite(v) and v>now end
local function vec(v)
    if typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) then return v.X,v.Y,v.Z end
    if type(v)=="table" then
        local x,y,z=v.x or v.X,v.y or v.Y,v.z or v.Z
        if finite(x) and finite(y) and finite(z) then return x,y,z end
    end
end
local function properties(t)
    local move=type(t.move)=="table" and t.move or type(t.moveset)=="table" and t.moveset
        or type(t.attack)=="table" and t.attack or {}
    if move.confirmed==false or move.verified==false then move={} end
    local area=type(t.area)=="table" and t.area or move
    if area.confirmed==false or area.verified==false then area=move end
    -- Geometry overrides inherit unspecified fields from the confirmed move.
    if area~=move then
        local override=area
        area=setmetatable({}, {__index=function(_,key)
            if override[key]~=nil then return override[key] end
            return move[key]
        end})
    end
    return move,area
end
local function value(t,m,key)
    if t[key]~=nil then return t[key] end
    return m[key]
end
local function recovering(t,now)
    return t.stunned==true or t.guardBroken==true or future(t.recoveryUntil,now) or future(t.whiffedUntil,now)
end

function Dynamic.new(config)
    assert(type(config)=="table", "dynamic: game adapter config required")
    local s={
        placeId=positive(config.placeId,"placeId"),
        attackRange=positive(config.attackRange,"attackRange"),
        threatRange=positive(config.threatRange,"threatRange"),
        maxEngageRange=positive(config.maxEngageRange,"maxEngageRange"),
        maxVerticalDistance=positive(config.maxVerticalDistance,"maxVerticalDistance"),
        maxSnapshotAge=positive(config.maxSnapshotAge or 0.25,"maxSnapshotAge"),
        lowHealthRatio=config.lowHealthRatio or 0.3,
        approachMargin=positive(config.approachMargin or 0.5,"approachMargin"),
        parryLead=positive(config.parryLead or 0.14,"parryLead"),
        dodgeLead=positive(config.dodgeLead or 0.28,"dodgeLead"),
        maxPrediction=positive(config.maxPrediction or 0.7,"maxPrediction"),
        defenseRetry=positive(config.defenseRetry or 0.05,"defenseRetry"),
        switchMargin=config.switchMargin or 6,repeatDelays={}}
    assert(s.maxEngageRange>=s.attackRange,"dynamic: engagement range too small")
    assert(finite(s.lowHealthRatio) and s.lowHealthRatio>0 and s.lowHealthRatio<1,"dynamic: invalid lowHealthRatio")
    assert(finite(s.switchMargin) and s.switchMargin>=0,"dynamic: invalid switchMargin")
    assert(type(config.repeatDelays)=="table","dynamic: repeatDelays required")
    for _,a in ipairs(baseActions) do s.repeatDelays[a]=positive(config.repeatDelays[a],a.." repeat delay") end
    for a,d in pairs(optionalDelays) do s.repeatDelays[a]=positive(config.repeatDelays[a] or d,a.." repeat delay") end
    local c=setmetatable({config=s,dispatching=false,stopped=false},Controller)
    c:reset()
    return c
end
function Controller:reset()
    self.readyAt,self.rejectedUntil,self.handled={},{},{}
    self.adapterRetryAt,self.targetId,self.characterId=nil,nil,nil
    self.lastNow,self.lastSampleAt,self.lastThreatAt=nil,nil,nil
    self.pressure=0
    self.lastDecision,self.lastError=nil,nil
end
function Controller:stop() self.stopped=true end
local function decision(s,action,reason,target,interrupt)
    target=target or (type(s.target)=="table" and s.target or nil)
    return {action=action,reason=reason,targetId=target and target.id,target=target,
        issuedAt=s.now,attackId=target and target.attackId,hitIndex=target and target.hitIndex,
        interruptCombo=interrupt==true}
end

local function intersects(s,t,area,eta,c)
    if t.threatensSelf==false then return false end
    local distance,height=t.distance,math.abs(t.verticalDistance)
    local untilImpact=eta and math.max(0,eta) or 0
    local ownHorizon=clamp(untilImpact+s.now-s.sampledAt,0,c.maxPrediction)
    local targetSample=finite(t.sampledAt) and t.sampledAt or s.sampledAt
    local horizon=clamp(untilImpact+s.now-targetSample,0,c.maxPrediction)
    if finite(t.radialVelocity) then distance=math.max(0,distance+t.radialVelocity*horizon) end
    local px,py,pz=vec(s.self.position)
    local tx,ty,tz=vec(area.origin or t.position)
    local rx,rz
    if px and tx then
        local pvx,pvy,pvz=vec(s.self.velocity)
        local tvx,tvy,tvz=vec(area.velocity or (not area.origin and t.velocity or nil))
        rx=px-tx+(pvx or 0)*ownHorizon-(tvx or 0)*horizon
        rz=pz-tz+(pvz or 0)*ownHorizon-(tvz or 0)*horizon
        height=math.abs(py-ty+(pvy or 0)*ownHorizon-(tvy or 0)*horizon)
        distance=math.sqrt(rx*rx+rz*rz)
    end
    if height>(finite(area.height) and math.max(0,area.height) or c.maxVerticalDistance) then return false end
    local range=finite(area.range) and math.max(0,area.range)
        or finite(area.maxRange) and math.max(0,area.maxRange) or c.threatRange
    if (area.shape=="sphere" or area.shape=="radial" or area.shape=="circle")
        and finite(area.radius) then range=math.max(0,area.radius) end
    local radial=area.shape=="sphere" and math.sqrt(distance*distance+height*height) or distance
    local fx,_,fz=vec(area.direction or t.facing)
    local directed=(area.shape=="line" or area.shape=="box") and finite(area.width) and rx and fx
        and fx*fx+fz*fz>0.000001
    if not directed and (radial>range or (finite(area.minRange) and radial<area.minRange)) then return false end
    if rx and fx then
        local mag=math.sqrt(fx*fx+fz*fz)
        if mag>0.001 then
            fx,fz=fx/mag,fz/mag
            local forward,lateral=rx*fx+rz*fz,math.abs(rx*fz-rz*fx)
            local angle=finite(area.angle) and area.angle or finite(area.halfAngle) and area.halfAngle*2 or nil
            if area.shape=="cone" and angle and distance>0.001 then
                return forward/distance>=math.cos(clamp(angle,0,math.pi*2)/2),distance
            elseif (area.shape=="line" or area.shape=="box") and finite(area.width) then
                local minimum=finite(area.minRange) and math.max(0,area.minRange) or 0
                return forward>=minimum and forward<=range and lateral<=math.max(0,area.width)/2,distance
            end
        end
    end
    return true,distance
end

function Controller:decide(s)
    s=type(s)=="table" and s or {}
    local function hold(reason) return decision(s,"hold",reason) end
    if self.stopped then return hold("stopped") end
    if s.enabled~=true or s.armed~=true then return hold("not_armed") end
    if s.placeId~=self.config.placeId then return hold("wrong_place") end
    local now,c=s.now,self.config
    if not finite(now) or not finite(s.sampledAt) or s.sampledAt>now or now-s.sampledAt>c.maxSnapshotAge then
        return hold("stale_snapshot")
    end
    if self.lastNow and now<self.lastNow then return hold("clock_regressed") end
    local own=s.self
    if type(own)~="table" or not finite(own.health) or not finite(own.maxHealth)
        or own.maxHealth<=0 or own.health<=0 then return hold("self_unavailable") end
    if self.characterId~=own.characterId then self:reset(); self.characterId=own.characterId end
    self.lastNow=now
    for id,r in pairs(self.handled) do if r.untilAt<=now then self.handled[id]=nil end end
    local can=type(s.can)=="table" and s.can or {}
    local cooldowns=type(s.cooldowns)=="table" and s.cooldowns or {}
    local function ready(a)
        return can[a]==true and finite(cooldowns[a]) and cooldowns[a]<=0
            and now>=(self.readyAt[a] or -math.huge) and now>=(self.rejectedUntil[a] or -math.huge)
    end
    local disabled=own.stunned or own.ragdolled or own.disabled
    if disabled and not (own.evasiveWhileStunned==true and ready("evasive")) then return hold("self_disabled") end
    local canMove=s.movementAllowed==true
    local comboBusy=own.comboBusy==true
    local busy=own.busy==true or comboBusy
    local defenseAllowed=not busy or own.defenseInterruptible==true or disabled
    local lowHealth=own.health/own.maxHealth<=c.lowHealthRatio
    local lead=(finite(s.latency) and clamp(s.latency,0,0.25) or 0)
        +(finite(own.reactionDelay) and clamp(own.reactionDelay,0,0.25) or 0)
    local candidates,seen={},{}
    local function add(t)
        if type(t)~="table" or t.id==nil or seen[t.id] or t.hostile==false or t.alive==false then return end
        if not finite(t.distance) or not finite(t.verticalDistance) then
            local px,py,pz=vec(own.position)
            local tx,ty,tz=vec(t.position)
            if px and tx then
                local copy={}
                for k,v in pairs(t) do copy[k]=v end
                copy.distance=math.sqrt((px-tx)^2+(pz-tz)^2)
                copy.verticalDistance=ty-py
                t=copy
            end
        end
        if not finite(t.health) or t.health<=0
            or not finite(t.distance) or t.distance<0 or not finite(t.verticalDistance) then return end
        if t.sampledAt~=nil and (not finite(t.sampledAt) or t.sampledAt>now
            or now-t.sampledAt>c.maxSnapshotAge) then return end
        seen[t.id]=true
        candidates[#candidates+1]=t
    end
    local supplied=s.opponents or s.targets
    if type(supplied)=="table" then for _,t in ipairs(supplied) do add(t) end end
    add(s.target)
    local best,bestScore,current,currentScore
    local threats={}
    for _,t in ipairs(candidates) do
        local move,area=properties(t)
        local impactAt=value(t,move,"impactAt")
        local started=t.attackStartedAt or t.startedAt or move.startedAt
        if not finite(impactAt) and finite(started) and finite(move.windup) and move.windup>=0 then
            impactAt=started+move.windup
        end
        local eta=finite(impactAt) and impactAt-now or nil
        local activeUntil=t.activeUntil or move.activeUntil or move.expiresAt
        if not finite(activeUntil) and finite(impactAt) and finite(move.activeDuration) and move.activeDuration>=0 then
            activeUntil=impactAt+move.activeDuration
        end
        local active=t.attacking==true or move.active==true or future(activeUntil,now)
        local expired=(finite(activeUntil) and activeUntil<now)
            or (not finite(activeUntil) and eta and eta < -0.04)
        local inArea,predictedDistance=intersects(s,t,area,eta,c)
        local isThreat=active and not expired and not recovering(t,now) and inArea
            and (t.visible==true or t.affectsThroughCover==true)
        if isThreat then
            local urgency=eta and 110-clamp(eta,0,c.maxPrediction)*100 or 50
            local aimed=t.targetsSelf==true or (own.id~=nil and t.attackTargetId==own.id)
            local damage=finite(t.damage) and clamp(t.damage/own.maxHealth,0,1)*30 or 0
            local imminent=(eta and eta<=c.dodgeLead+lead)
                or (future(activeUntil,now) and (not eta or eta<=0))
            local isSpecial=t.isSpecial==true or move.isSpecial==true or t.specialThreat==true
            threats[#threats+1]={target=t,move=move,eta=eta,impactAt=impactAt,activeUntil=activeUntil,
                imminent=imminent==true,predictedDistance=predictedDistance,
                isSpecial=isSpecial==true,
                score=urgency+(aimed and 18 or 0)+damage+(isSpecial and 25 or 0)}
        end
        if not t.invulnerable and t.visible==true and t.distance<=c.maxEngageRange
            and math.abs(t.verticalDistance)<=c.maxVerticalDistance then
            local ratio=finite(t.maxHealth) and t.maxHealth>0 and clamp(t.health/t.maxHealth,0,1) or 1
            local score=30*(1-clamp(t.distance/c.maxEngageRange,0,1))+(1-ratio)*18
                +(isThreat and 42 or 0)+(recovering(t,now) and 12 or 0)
                +(t.blocking==true and -8 or 0)+(t.targetsSelf==true and 10 or 0)
            -- Readiness and distance belong to held items, independently for
            -- each rival. Penalize chasing into a cluster's combined pressure.
            local reach=finite(t.attackRange) and t.attackRange or c.attackRange
            score+=t.distance<=reach and 12 or -math.min(18,(t.distance-reach)*.35)
            local crowd=0
            local tx,_,tz=vec(t.position)
            if tx then for _,other in ipairs(candidates) do
                if other.id~=t.id and not other.stunned then
                    local ox,_,oz=vec(other.position)
                    if ox and (tx-ox)^2+(tz-oz)^2<18^2 then crowd+=1 end
                end
            end end
            score-=math.min(16,crowd*4)
            if not best or score>bestScore then best,bestScore=t,score end
            if t.id==self.targetId then current,currentScore=t,score end
        end
    end
    if current and best and currentScore+c.switchMargin>=bestScore then best=current end
    if s.lockTarget==true and type(s.target)=="table" then
        for _,t in ipairs(candidates) do
            if t.id==s.target.id and not t.invulnerable and t.visible==true and t.distance<=c.maxEngageRange
                and math.abs(t.verticalDistance)<=c.maxVerticalDistance then best=t; break end
        end
    end
    self.targetId=best and best.id or nil
    table.sort(threats,function(a,b)
        if a.imminent~=b.imminent then return a.imminent end
        if a.score==b.score then return a.target.distance<b.target.distance end
        return a.score>b.score
    end)
    if not self.lastSampleAt or s.sampledAt>self.lastSampleAt then
        local elapsed=self.lastSampleAt and s.sampledAt-self.lastSampleAt or 0
        local weight=1-math.exp(-math.min(elapsed,1)*3)
        self.pressure=self.pressure+((#threats>0 and 1 or 0)-self.pressure)*weight
        self.lastSampleAt=s.sampledAt
    end
    if #threats>0 then self.lastThreatAt=now end
    local function emit(action,reason,threat)
        local d=decision(s,action,reason,threat and threat.target or best,comboBusy and action~="hold")
        d.offenseTargetId,d.threatCount=self.targetId,#threats
        if threat then d.impactAt,d.timeToImpact,d.predictedDistance=threat.impactAt,threat.eta,threat.predictedDistance end
        return d
    end
    if #threats>0 then
        if not defenseAllowed then return emit("hold","defense_not_interruptible",threats[1]) end
        for _,th in ipairs(threats) do
            local t,m,eta=th.target,th.move,th.eta
            local record=self.handled[t.id]
            local handled=t.attackId~=nil and record and record.attackId==t.attackId
                and record.hitIndex==t.hitIndex and record.untilAt>now
            if not handled then
                local imminent=th.imminent
                local unparryable=value(t,m,"unparryable")==true or value(t,m,"parryable")==false
                local unblockable=value(t,m,"unblockable")==true or value(t,m,"blockable")==false
                local parryable=value(t,m,"unparryable")==false or value(t,m,"parryable")==true
                if disabled then
                    if (canMove or own.evasiveWhileStunned == true) and ready("evasive") then return emit("evasive","native_stun_escape",th) end
                else
                    local isSpecial = th.isSpecial == true or value(t,m,"special") == true
                    if imminent and (unblockable or unparryable or lowHealth or #threats>1 or isSpecial) then
                        if ready("evasive") then return emit("evasive",isSpecial and "evade_incoming_special" or "evade_incoming_area",th) end
                        if canMove and ready("dodge") then return emit("dodge",isSpecial and "evade_incoming_special" or "evade_incoming_area",th) end
                    end
                    local windup=own.counterWindup or cooldowns.counterWindup
                    local counterFits=eta and eta>=lead and finite(windup) and windup>=0 and windup+lead<=eta
                    if imminent and #threats==1 and value(t,m,"counterable")==true and future(t.counterWindowUntil,now)
                        and counterFits and ready("counter") then return emit("counter","confirmed_counter_window",th) end
                    if eta and eta>=lead-0.04 and eta<=c.parryLead+lead and parryable
                        and not unparryable and not isSpecial and #threats==1 and ready("parry") then
                        return emit("parry","timed_incoming_hit",th)
                    end
                    if imminent and ready("evasive") then return emit("evasive","native_evasion_fallback",th) end
                    if imminent and canMove and ready("dodge") then return emit("dodge","parry_unavailable",th) end
                    if not unblockable and not isSpecial and ready("block") then return emit("block","cover_incoming_attack",th) end
                    if canMove and ready("retreat") then return emit("retreat","space_incoming_attack",th) end
                end
            end
        end
        return emit("hold","wait_defense_window",threats[1])
    end
    if disabled then return hold("self_disabled") end
    if busy then return emit("hold",comboBusy and "preserve_combo_stage" or "action_in_progress") end
    if not best then return hold("target_unavailable") end
    if self.adapterRetryAt and now<self.adapterRetryAt then return emit("hold","adapter_backoff") end
    local recovery=recovering(best,now)
    if lowHealth and not recovery and best.distance<=c.threatRange and canMove and ready("retreat") then
        return emit("retreat","recover_spacing_low_health")
    end
    local itemRange=type(s.range)=="table" and s.range or {}
    local range=finite(s.attackRange) and math.max(0,s.attackRange)
        or finite(itemRange.max) and math.max(0,itemRange.max) or c.attackRange
    local minRange=finite(s.minAttackRange) and math.max(0,s.minAttackRange)
        or finite(itemRange.min) and math.max(0,itemRange.min) or 0
    if best.distance<minRange then
        if canMove and ready("retreat") then return emit("retreat","inside_item_min_range") end
        return emit("hold","inside_item_min_range")
    end
    if best.distance<=range then
        if recovery then
            if ready("punish") then return emit("punish","confirmed_opponent_recovery") end
            return emit("hold","punish_unavailable")
        end
        if best.blocking==true then
            if ready("attack") then return emit("attack","guard_break_pressure") end
            return emit("hold","opponent_guarding")
        end
        if ready("attack") then return emit("attack","in_range_clear") end
        if self.lastThreatAt and now-self.lastThreatAt<self.pressure*c.parryLead then return emit("hold","wait_safe_gap") end
        return emit("hold","attack_cooldown")
    end
    if lowHealth and not recovery then return emit("hold","avoid_low_health_chase") end
    if best.distance>range+c.approachMargin and canMove and ready("approach") then
        return emit("approach",recovery and "close_for_punish" or "close_to_attack_range")
    end
    return emit("hold","maintain_spacing")
end

function Controller:step(s,handlers)
    if self.dispatching then return decision(type(s)=="table" and s or {},"hold","dispatch_in_progress"),false end
    local selected=self:decide(s)
    self.lastDecision=selected
    if selected.action=="hold" then return selected,false end
    local callback=type(handlers)=="table" and handlers[selected.action] or nil
    if type(callback)~="function" then
        selected.reason,selected.action="missing_handler:"..selected.action,"hold"
        return selected,false
    end
    local action,issuedAt=selected.action,selected.issuedAt
    self.dispatching=true
    local ok,accepted=pcall(callback,selected,s)
    self.dispatching=false
    local defensive=action=="block" or action=="counter" or action=="evasive" or action=="dodge" or action=="parry"
    if ok and accepted==true then
        self.readyAt[action]=issuedAt+self.config.repeatDelays[action]
        -- Only debounce duplicate dispatches briefly, never an entire multi-hit attack.
        if defensive and action~="block" and selected.targetId~=nil and selected.attackId~=nil then
            self.handled[selected.targetId]={attackId=selected.attackId,hitIndex=selected.hitIndex,
                untilAt=issuedAt+self.config.defenseRetry}
        end
        self.lastError=nil
        return selected,true
    end
    self.rejectedUntil[action]=issuedAt+(defensive and self.config.defenseRetry or self.config.repeatDelays[action])
    if not defensive then self.adapterRetryAt=self.rejectedUntil[action] end
    self.lastError=ok and "handler_rejected" or tostring(accepted)
    selected.reason=self.lastError
    return selected,false
end
return Dynamic
