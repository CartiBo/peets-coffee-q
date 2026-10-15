-- Predictive movement planner 1.0.0. No auto-start, connections, inputs or remotes.
-- Adapter: local m=loadstring(readfile('pvp/movement.luau'))().new(config)
-- config: placeId, attackRange; optional parameters below. Units: studs/seconds.
-- decide(snapshot) is a proposal; step(snapshot,handlers) dispatches one proposal.
-- Snapshot: now, sampledAt (os.clock), placeId, jobId, characterId, enabled=true,
-- armed=true, movementAllowed=true, manualOverride=false,
-- self={position=Vector3,velocity=Vector3,health,stunned,ragdolled,busy,comboBusy,
--       defenseInterruptible}, target={id,position,velocity,health,sampledAt},
-- opponents={same observations, hostile=true}; target need not occur in opponents.
-- Per opponent: alive=false/hostile=false/invulnerable excludes it as a target.
-- attack={active=true,shape='circle'|'cone'|'line',range,width,halfAngle [radians],
--         direction=Vector3,impactAt,expiresAt}; only use observed game geometry.
-- riskEnvelope is an optional conservative spacing policy, not a measured hitbox.
-- can={move=true,dash=true}, cooldowns={dash=0}, dashTravel=<native distance>.
-- range={min,max}: usable range of the SELECTED INVENTORY ITEM/attack, not moveset.
-- navigation[kind][route]={clear=true,grounded=true,distance=<checked travel>}.
-- kinds: walk/dash; routes: approachLeft,approachRight,left,right,back,forward.
-- Adapter must verify the entire swept capsule AND floor along each path, using
-- the direction from candidates(snapshot); never copy clearance to another ray.
-- handlers.walk/dash(decision,snapshot): true only if native request accepted.
-- handlers.hold optional: release this module's movement intent (not manual keys).
-- Dash decision.nativeDirection is native Left/Right/Back/Front; worldDirection
-- must reach nativeDash unchanged. Do NOT use camera-relative humanoid:Move.
-- confirmDash(id, observed, now) needs native MovementForce/actual dash evidence.
-- stop/reset on unload/respawn and release owned movement via adapter.
-- 1.2.0: approach routing (action 'walk' route='path' / 'requestPath' via s.path),
-- approach specials (action 'special' via s.specials), s.manualInput => hold.
-- 1.3.0: in-range strafe (reason 'strafe', left/right, stays inside item range);
-- disable with config.strafe=false or snapshot.strafe=false.
-- Extra handlers (optional): requestPath(decision,snapshot), special(decision,snapshot).
-- 1.3.2: optional contactRange prioritizes M1 contact over idle orbit/facing risk.
-- 1.3.3: with contactRange, never strafe/flank (even vs a blocker): straight approach, then hold.
-- 1.4.0: breathless combo phases (close -> knockback -> lateral dash -> ranged special -> reentry).
-- Snapshot: s.combo={closeDone=bool} (M1 chain finished); s.specials roles 'knockback'|'ranged'|'approach'.
-- Phases only run when not imminent; contactRange hold/no-strafe is unchanged, target is s.target only.
local Movement = { version = '1.4.1' }
local Planner = {}
Planner.__index = Planner
local ZERO = Vector3.zero
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function vector(v)
    return typeof(v)=='Vector3' and finite(v.X) and finite(v.Y) and finite(v.Z)
end
local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function capped(v, limit)
    v = vector(v) and flat(v) or ZERO
    return v.Magnitude>limit and v.Unit*limit or v
end
local function unit(v) return v.Magnitude>0.001 and v.Unit or ZERO end
local function positive(v, name)
    assert(finite(v) and v>0, 'movement: invalid '..name)
    return v
end
function Movement.new(config)
    assert(type(config)=='table', 'movement: game adapter config required')
    local c = {}
    for key,value in pairs({placeId=config.placeId,attackRange=config.attackRange}) do
        c[key]=positive(value,key)
    end
    assert(c.placeId and c.attackRange, 'movement: placeId and attackRange required')
    for key,value in pairs({maxSnapshotAge=.22,maxPrediction=.45,maxLead=10,
        maxSpeed=120,maxAcceleration=120,maxVerticalDistance=8,maxEngageRange=100,
        maxOpponents=24,bodyRadius=2.2,walkSpeed=24,walkHorizon=.16,
        dashHorizon=.18,dashGap=.72,dashAckTimeout=.3,rejectDelay=.2,
        sideHold=.4,reactionLead=.28,maxDashTravel=70,pathDistance=34,
        pathRefresh=.9,pathReach=3.5,pathMaxAge=3,specialGap=1,comboGap=.12,
        comboPhaseWindow=1.4,comboLateralWindow=.9}) do
        c[key]=positive(config[key] or value,key)
    end
    assert(c.maxOpponents>=1 and c.maxOpponents<=64 and c.maxOpponents%1==0,
        'movement: maxOpponents must be an integer from 1 to 64')
    if config.strafe ~= nil then c.strafe = config.strafe == true end
    return setmetatable({config=c,history={},side=1,sideUntil=0,serial=0,
        nextDashAt=0,nextWalkAt=0,nextPathAt=0,nextSpecialAt=0,pathIndex=2,
        nextStrafeAt=0,strafeUntil=0,strafeSide=1,
        rejectedUntil={},lastNow=-math.huge},Planner)
end
function Planner:reset()
    self.generation=(self.generation or 0)+1
    self.history={}; self.side=1; self.sideUntil=0; self.targetId=nil
    self.pending=nil; self.nextDashAt=0; self.nextWalkAt=0
    self.nextPathAt=0; self.nextSpecialAt=0; self.pathIndex=2; self.pathStamp=nil
    self.nextStrafeAt=0; self.strafeUntil=0; self.strafeSide=1
    self.rejectedUntil={}; self.lastNow=-math.huge; self.lastDecision=nil
    self.phase='close'; self.phaseAt=0; self.lateralSide=1
end
local function readySpecial(s,role,distance)
    for _,sp in ipairs(type(s.specials)=='table' and s.specials or {}) do
        if type(sp)=='table' and sp.ready==true and sp.crowded~=true and sp.role==role
            and finite(sp.minDistance) and finite(sp.maxDistance)
            and distance>=sp.minDistance and distance<=sp.maxDistance then return sp end
    end
end
-- Chains phases with minimal gaps. Returns a decision or nil (fall through to
-- the normal contact/approach logic). Never strafes while in contact.
function Planner:_combo(s,distance,actualDistance,desired,range,aim)
    local c=self.config
    local phase=self.phase or 'close'
    local age=s.now-(self.phaseAt or 0)
    local inContact=actualDistance<=desired+.4
    if inContact and phase~='knockback' then phase='close'; self.phase='close' end
    local function special(sp,reason,newPhase)
        self.phase=newPhase; self.phaseAt=s.now
        return {action='special',reason=reason,name=sp.name,role=sp.role,combo=true,
            targetId=s.target.id,issuedAt=s.now,expiresAt=s.now+c.maxSnapshotAge,
            worldDirection=unit(flat(aim-s.self.position)),predictedPosition=aim,
            remainingDistance=distance,side=0,phase=newPhase}
    end
    if s.now<self.nextSpecialAt then
        -- Gap between combo actions is comboGap; lateral dash below may still fire.
        if phase~='knockback' and phase~='lateral' then return nil end
    end
    if phase=='close' and inContact and type(s.combo)=='table' and s.combo.closeDone==true then
        local sp=readySpecial(s,'knockback',actualDistance)
        if sp and s.now>=self.nextSpecialAt then return special(sp,'combo_knockback','knockback') end
        return nil
    end
    if (phase=='knockback' or phase=='lateral') and age>c.comboPhaseWindow then
        self.phase='close'; return nil
    end
    if phase=='knockback' and actualDistance>desired+1.5 then
        -- Knocked away: sidestep immediately so the ranged special lands off-line.
        local can=type(s.can)=='table' and s.can or {}
        local cooldown=type(s.cooldowns)=='table' and s.cooldowns.dash
        local nativeTravel=s.dashTravel
        if can.dash==true and finite(cooldown) and cooldown<=0 and finite(nativeTravel)
            and nativeTravel>0 and nativeTravel<=c.maxDashTravel and s.now>=self.nextDashAt then
            local choices=self:candidates(s)
            local dashNav=type(s.navigation)=='table' and s.navigation.dash
            for pass=1,2 do
                local sign=pass==1 and (self.lateralSide or 1) or -(self.lateralSide or 1)
                for _,cand in ipairs(choices) do
                    local nav=type(dashNav)=='table' and dashNav[cand.route]
                    if (cand.route=='left' or cand.route=='right') and cand.sign==sign
                        and s.now>=(self.rejectedUntil[cand.route] or 0)
                        and type(nav)=='table' and nav.clear==true and nav.grounded==true
                        and finite(nav.distance) and nav.distance>=nativeTravel then
                        self.phase='lateral'; self.phaseAt=s.now; self.lateralSide=-sign
                        return {action='dash',reason='combo_lateral',combo=true,phase='lateral',
                            targetId=s.target.id,issuedAt=s.now,expiresAt=s.now+c.maxSnapshotAge,
                            worldDirection=cand.direction,nativeDirection=cand.native,
                            route=cand.route,side=cand.sign,travel=nativeTravel,
                            duration=c.dashHorizon,predictedPosition=aim,
                            remainingDistance=distance,risk=0,currentRisk=0,
                            opponentsObserved=1}
                    end
                end
            end
        end
        phase='lateral'; self.phase='lateral'  -- no safe dash: go straight to ranged
    end
    if phase=='lateral' or phase=='knockback' then
        local sp=readySpecial(s,'ranged',actualDistance)
        if sp and s.now>=self.nextSpecialAt then return special(sp,'combo_ranged','reentry') end
    end
    if self.phase=='reentry' and distance>range.max and s.now>=self.nextSpecialAt then
        local ap=readySpecial(s,'approach',distance)
        if ap then return special(ap,'combo_reentry','reentry') end
    end
    return nil
end
function Planner:stop() self.stopped=true; self:reset() end
function Planner:_context(s)
    if self.jobId~=s.jobId or self.characterId~=s.characterId then
        self:reset(); self.jobId=s.jobId; self.characterId=s.characterId
    end
end
local function hold(s,reason)
    return {action='hold',reason=reason,issuedAt=s.now,worldDirection=ZERO,
        targetId=type(s.target)=='table' and s.target.id or nil}
end
function Planner:_valid(s)
    if self.stopped then return 'stopped' end
    if s.enabled~=true or s.armed~=true then return 'not_armed' end
    if s.placeId~=self.config.placeId then return 'wrong_place' end
    if not finite(s.now) or not finite(s.sampledAt) or s.sampledAt>s.now
        or s.now-s.sampledAt>self.config.maxSnapshotAge then return 'stale_snapshot' end
    if s.now<self.lastNow then return 'clock_regressed' end
    local own=s.self
    if type(own)~='table' or not vector(own.position) or not finite(own.health)
        or own.health<=0 then return 'self_unavailable' end
    if own.stunned or own.ragdolled or own.disabled then return 'self_disabled' end
    if s.manualOverride or s.movementAllowed~=true then return 'manual_or_movement_disabled' end
    local t=s.target
    if type(t)~='table' or t.id==nil or not vector(t.position) or t.alive==false
        or not finite(t.health) or t.health<=0 or t.hostile==false or t.invulnerable
        then return 'target_unavailable' end
    local stamp=t.sampledAt or s.sampledAt
    if not finite(stamp) or stamp>s.now or s.now-stamp>self.config.maxSnapshotAge
        then return 'stale_target' end
    if math.abs(t.position.Y-own.position.Y)>self.config.maxVerticalDistance
        then return 'vertical_separation' end
    if flat(t.position-own.position).Magnitude>self.config.maxEngageRange
        then return 'outside_engagement' end
end
function Planner:_predict(o,s,dt)
    local stamp=o.sampledAt or s.sampledAt
    local age=math.max(0,s.now-stamp)
    local velocity=capped(o.velocity,self.config.maxSpeed)
    local previous=self.history[o.id]
    local acceleration=ZERO
    -- Repeated reads of one observation never manufacture acceleration.
    if previous and stamp>previous.time and stamp-previous.time<=.25 then
        acceleration=capped((velocity-previous.velocity)/(stamp-previous.time),
            self.config.maxAcceleration)
    end
    local time=math.min(age+dt,self.config.maxPrediction)
    return o.position+capped(velocity*time+acceleration*(.5*time*time),self.config.maxLead)
end
function Planner:_observations(s)
    local result={s.target}; local seen={[s.target.id]=true}
    for _,o in ipairs(type(s.opponents)=='table' and s.opponents or {}) do
        local stamp=type(o)=='table' and (o.sampledAt or s.sampledAt)
        if type(o)=='table' and o.id~=nil and not seen[o.id] and vector(o.position)
            and o.hostile~=false and o.alive~=false and finite(o.health) and o.health>0
            and finite(stamp) and stamp<=s.now and s.now-stamp<=self.config.maxSnapshotAge
            and math.abs(o.position.Y-s.self.position.Y)<=self.config.maxVerticalDistance
            and flat(o.position-s.self.position).Magnitude<=self.config.maxEngageRange then
            result[#result+1]=o; seen[o.id]=true
        end
    end
    -- Keep nearest threats, never an arbitrary iteration-order subset.
    table.sort(result,function(a,b)
        if a.id==s.target.id then return b.id~=s.target.id end
        if b.id==s.target.id then return false end
        local da=(a.position-s.self.position).Magnitude
        local db=(b.position-s.self.position).Magnitude
        if da==db then return tostring(a.id)<tostring(b.id) end
        return da<db
    end)
    while #result>self.config.maxOpponents do table.remove(result) end
    return result
end
local function footprint(attack,origin,position,padding)
    if type(attack)~='table' or attack.active~=true or not finite(attack.range)
        or attack.range<=0 then return false end
    local delta=flat(position-origin); local range=attack.range+padding
    if attack.shape=='circle' then return delta.Magnitude<=range end
    if not vector(attack.direction) then return false end
    local dir=unit(flat(attack.direction))
    if dir==ZERO then return false end
    if attack.shape=='line' and finite(attack.width) and attack.width>0 then
        local along=delta:Dot(dir)
        return along>=-padding and along<=range
            and (delta-dir*along).Magnitude<=attack.width*.5+padding
    elseif attack.shape=='cone' and finite(attack.halfAngle)
        and attack.halfAngle>0 and attack.halfAngle<=math.pi then
        if delta.Magnitude<=padding then return true end
        local extra=math.asin(math.min(1,padding/delta.Magnitude))
        return delta.Magnitude<=range and unit(delta):Dot(dir)>=
            math.cos(math.min(math.pi,attack.halfAngle+extra))
    end
    return false
end
function Planner:_risk(s,observations,direction,travel,horizon)
    local risk=0; local imminent=false
    local ownVelocity=direction.Magnitude<.001 and capped(s.self.velocity,self.config.maxSpeed)
        or direction*(travel/math.max(.01,horizon))
    for _,o in ipairs(observations) do
        local origin=self:_predict(o,s,0)
        local relative=flat(origin-s.self.position)
        local velocity=capped(o.velocity,self.config.maxSpeed)-ownVelocity
        local time=velocity:Dot(velocity)>.001 and
            math.clamp(-relative:Dot(velocity)/velocity:Dot(velocity),0,horizon) or 0
        local clearance=(relative+velocity*time).Magnitude
        local radius=math.max(self.config.bodyRadius*2,(o.contactDistance or 0)*.85)
        local attack=o.attack or o.riskEnvelope
        local actualAttack=type(attack)=='table' and attack.active==true
        local contactTarget=finite(s.contactRange) and o.id==s.target.id
        -- Walking ourselves into M1 range is not an incoming enemy dash.
        local enemyVelocity=capped(o.velocity,self.config.maxSpeed)
        local incoming=enemyVelocity.Magnitude>18 and relative:Dot(enemyVelocity)<0
        -- Focus mode (contact range set): only real attacks count; a walking/dashing body is not damage.
        local focus=finite(s.contactRange)
        local bodyThreat=not focus or actualAttack
        if bodyThreat then risk+=math.max(0,radius-clearance)*2 end
        -- Incoming body/dash crossing is already a movement threat even when
        -- an attack's damage shape has not yet been observed.
        if bodyThreat and clearance<radius and time>0 and relative:Dot(velocity)<0
            and not o.stunned and not o.ragdolled then imminent=true end
        -- Coordinate/facing policy: discourage approaching an unoccupied
        -- target through another rival's front even before an attack starts.
        -- This is positional risk, never an assertion of a damage hitbox.
        if vector(o.facing) and not o.stunned and (not contactTarget or actualAttack or o.blocking) then
            local point=s.self.position+ownVelocity*horizon
            local delta=flat(point-self:_predict(o,s,horizon))
            local facing=unit(flat(o.facing))
            if delta.Magnitude>.01 and delta.Magnitude<18 and facing:Dot(delta.Unit)>.55 then
                risk+=(18-delta.Magnitude)*.16
            end
        end
        if type(attack)=='table' and attack.active==true then
            local expiry=attack.expiresAt
            -- Missing impact timing: avoid the observed footprint throughout
            -- this short horizon, rather than inventing a startup window.
            local start=finite(attack.impactAt) and math.max(0,attack.impactAt-s.now) or 0
            local finish=finite(expiry) and math.min(horizon,expiry-s.now) or horizon
            if start<=finish then
                for _,dt in ipairs({start,(start+finish)*.5,finish}) do
                    local point=s.self.position+ownVelocity*dt
                    if footprint(attack,self:_predict(o,s,dt),point,self.config.bodyRadius) then
                        -- Third-party attacks only add soft risk in focus mode; the marked target drives evasion.
                        if focus and not contactTarget then risk+=4 else risk+=12; imminent=true end
                        break
                    end
                end
            end
        end
    end
    return risk,imminent
end
-- Candidate directions are public so the adapter can probe the EXACT swept
-- corridor. Both calls must use the same snapshot; no hidden random directions.
function Planner:candidates(s)
    if type(s)~='table' then return {} end
    self:_context(s)
    if self:_valid(s) then return {} end
    local distance=flat(s.target.position-s.self.position).Magnitude
    local lead=math.min(self.config.maxPrediction,distance/self.config.walkSpeed*.25)
    local aim=self:_predict(s.target,s,lead)
    local forward=unit(flat(aim-s.self.position))
    if forward==ZERO then forward=Vector3.new(0,0,-1) end
    local side=Vector3.new(-forward.Z,0,forward.X)
    return {
        {route='approachLeft',direction=unit(forward*.78-side*.63),sign=-1,native='Left'},
        {route='approachRight',direction=unit(forward*.78+side*.63),sign=1,native='Right'},
        {route='left',direction=-side,sign=-1,native='Left'},
        {route='right',direction=side,sign=1,native='Right'},
        {route='back',direction=-forward,sign=0,native='Back'},
        {route='forward',direction=forward,sign=0,native='Front'},
    },aim
end
-- Approach special (teleport/dash entry). Adapter lists only specials it can
-- fire right now: s.specials={{name,minDistance,maxDistance,role,ready,crowded}}.
function Planner:_special(s,distance,range,aim)
    if s.now<self.nextSpecialAt or distance<=range.max then return nil end
    for _,sp in ipairs(type(s.specials)=='table' and s.specials or {}) do
        if type(sp)=='table' and sp.ready==true and sp.crowded~=true
            and finite(sp.minDistance) and finite(sp.maxDistance)
            and distance>=sp.minDistance and distance<=sp.maxDistance
            and (sp.role~='mixup' or s.flank==true) then
            return {action='special',reason='approach_special',name=sp.name,role=sp.role,
                targetId=s.target.id,issuedAt=s.now,expiresAt=s.now+self.config.maxSnapshotAge,
                worldDirection=unit(flat(aim-s.self.position)),predictedPosition=aim,
                remainingDistance=distance,side=0}
        end
    end
end
-- Route following for long chases or blocked direct lanes. Adapter supplies
-- s.path={targetId,computedAt,busy,waypoints={{position=Vector3,jump=bool}}}
-- from PathfindingService; planner picks the next waypoint, never raw keys.
function Planner:_path(s,distance,aim)
    local c=self.config
    local walk=type(s.navigation)=='table' and s.navigation.walk
    local lane=type(walk)=='table' and walk.forward
    local blocked=type(lane)=='table' and lane.clear==false
    if distance<=c.pathDistance and not blocked then return nil end
    local path=type(s.path)=='table' and s.path or {}
    local list=path.waypoints
    if path.targetId==s.target.id and type(list)=='table' and finite(path.computedAt)
        and s.now-path.computedAt<=c.pathMaxAge then
        if self.pathStamp~=path.computedAt then self.pathStamp=path.computedAt; self.pathIndex=2 end
        local i=self.pathIndex
        while list[i] and vector(list[i].position)
            and flat(list[i].position-s.self.position).Magnitude<=c.pathReach do i+=1 end
        self.pathIndex=i
        local w=list[i]
        if w and vector(w.position) then
            local dir=unit(flat(w.position-s.self.position))
            if dir~=ZERO then
                return {action='walk',reason='path_follow',route='path',targetId=s.target.id,
                    issuedAt=s.now,expiresAt=s.now+c.maxSnapshotAge,worldDirection=dir,
                    side=0,travel=c.walkSpeed*c.walkHorizon,duration=c.walkHorizon,
                    predictedPosition=aim,waypointIndex=i,jump=w.jump==true}
            end
        end
    end
    if path.busy~=true and s.now>=self.nextPathAt then
        return {action='requestPath',reason=blocked and 'direct_lane_blocked' or 'long_chase',
            targetId=s.target.id,issuedAt=s.now,expiresAt=s.now+c.maxSnapshotAge,
            worldDirection=ZERO,predictedPosition=aim,side=0}
    end
end
function Planner:decide(s)
    s=type(s)=='table' and s or {}
    self:_context(s)
    local invalid=self:_valid(s)
    if invalid then return hold(s,invalid) end
    self.lastNow=s.now
    if self.pending and s.now>=self.pending.deadline then
        self.rejectedUntil[self.pending.route]=s.now+self.config.rejectDelay
        self.lastDashOutcome='unconfirmed'; self.pending=nil
    end
    if self.targetId~=s.target.id then
        self.targetId=s.target.id; self.sideUntil=0
    end
    local observations=self:_observations(s)
    local choices,aim=self:candidates(s)
    local currentRisk,imminent=self:_risk(s,observations,ZERO,0,self.config.reactionLead)
    if (s.self.busy or s.self.comboBusy) and
        not (imminent and s.self.defenseInterruptible==true) then return hold(s,'action_owned') end
    if self.pending then
        -- The lateral dash is already moving us: fire the ranged special without waiting for the ack.
        local sp=self.phase=='lateral' and not imminent and readySpecial(s,'ranged',
            flat(s.target.position-s.self.position).Magnitude)
        if not (sp and s.now>=self.nextSpecialAt) then return hold(s,'dash_pending_confirmation') end
        self.phase='reentry'; self.phaseAt=s.now
        return {action='special',reason='combo_ranged',name=sp.name,role=sp.role,combo=true,
            targetId=s.target.id,issuedAt=s.now,expiresAt=s.now+self.config.maxSnapshotAge,
            worldDirection=unit(flat(aim-s.self.position)),predictedPosition=aim,
            remainingDistance=flat(aim-s.self.position).Magnitude,side=0,phase='reentry'}
    end
    local range=s.range or {min=self.config.attackRange*.65,max=self.config.attackRange}
    if type(range)~='table' or not finite(range.min) or not finite(range.max) or range.min<0 or range.max<=range.min
        then return hold(s,'invalid_item_range') end
    local distance=flat(aim-s.self.position).Magnitude
    local contact=finite(s.contactRange) and s.contactRange>0
    local desired=contact and math.clamp(s.contactRange,range.min,range.max) or (range.min+range.max)*.5
    local actualDistance=flat(s.target.position-s.self.position).Magnitude
    if not imminent and currentRisk<1 then
        local combo=self:_combo(s,distance,actualDistance,desired,range,aim)
        if combo then return combo end
    end
    -- Leave margin inside damage range, then stop the automatic feet. Manual
    -- movement and real reactive evasion continue to be handled by the adapter.
    if contact and not imminent
        and actualDistance<=desired+.4 and distance<=range.max then
        return hold(s,'m1_contact_ready')
    end
    local closingContact=contact and not imminent
    local strafeOnly=false
    if not imminent and not closingContact and not contact and currentRisk<1
        and distance>=range.min and distance<=range.max then
        -- In item range: keep moving laterally (never a standing target) unless disabled.
        if self.config.strafe==false or s.strafe==false or s.now<self.nextStrafeAt then
            return hold(s,'item_range_reached')
        end
        strafeOnly=true
        if s.now>=self.strafeUntil then
            self.strafeSide=-self.strafeSide
            self.strafeUntil=s.now+.9+(self.serial%3)*.3
        end
    end
    if not imminent and not strafeOnly and currentRisk<1 then
        local special=self:_special(s,distance,range,aim)
        if special then return special end
    end
    local best=nil; local bestScore=-math.huge
    local can=type(s.can)=='table' and s.can or {}
    local cooldown=type(s.cooldowns)=='table' and s.cooldowns.dash
    local nativeTravel=s.dashTravel
    local dashReady=can.dash==true and finite(cooldown) and cooldown<=0
        and finite(nativeTravel) and nativeTravel>0 and nativeTravel<=self.config.maxDashTravel
        and s.now>=self.nextDashAt
    for _,kind in ipairs(strafeOnly and {'walk'} or {'walk','dash'}) do
        local ready=kind=='walk' and can.move==true and s.now>=self.nextWalkAt
            or kind=='dash' and dashReady
        local horizon=kind=='dash' and self.config.dashHorizon or self.config.walkHorizon
        local travel=kind=='dash' and nativeTravel or self.config.walkSpeed*horizon
        if kind=='walk' and closingContact then
            -- A full walking horizon would overshoot and be rejected just outside
            -- contact. Probe less travel, with the same checked navigation lane.
            travel=math.min(travel,math.max(.1,actualDistance-desired))
            horizon=math.min(horizon,travel/self.config.walkSpeed)
        end
        if ready then for _,candidate in ipairs(choices) do
            local routes=type(s.navigation)=='table' and s.navigation[kind]
            local nav=type(routes)=='table' and routes[candidate.route]
            local safe=type(nav)=='table' and nav.clear==true and nav.grounded==true
                and finite(nav.distance) and nav.distance>=travel
            if strafeOnly and candidate.route~='left' and candidate.route~='right' then safe=false end
            if safe and s.now>=(self.rejectedUntil[candidate.route] or 0) then
                local finish=s.self.position+candidate.direction*travel
                local futureTarget=self:_predict(s.target,s,horizon)
                local remaining=flat(futureTarget-finish).Magnitude
                local risk,entersAttack=self:_risk(s,observations,candidate.direction,travel,horizon)
                local error=math.max(0,range.min-remaining,remaining-range.max)
                local progress=math.abs(distance-desired)-math.abs(remaining-desired)
                local score=progress-error*.7-risk*3
                if candidate.sign~=0 then score+=.35 end
                if candidate.sign==self.side and s.now<self.sideUntil then score+=.65 end
                -- Straight entry is a fallback. Pre-evasive diagonals win when
                -- equally safe; no timer-driven left/right flip every frame.
                if candidate.route=='forward' then score+=closingContact and 8 or -2 end
                if candidate.route=='back' then
                    -- Neutral spacing & backward evasion to keep enemy at bay
                    if distance<range.min then score+=2.5 end
                    if imminent and risk<currentRisk then score+=3.0 end
                end
                if kind=='dash' then
                    score-=1.5
                    if imminent and risk<currentRisk then score+=5 end
                end
                local reactive=imminent and risk<currentRisk-1
                local approach=not imminent and progress>.15 and not entersAttack
                    and risk<=currentRisk+.25 and remaining>=range.min*.7
                -- Do not dash through/over the preferred item range merely
                -- because it shortens a long chase. Native travel is not shortened.
                if kind=='dash' and not reactive then
                    approach=approach and remaining>=range.min and remaining<=distance
                        and candidate.route~='forward'
                end
                local spacing=not imminent and distance<range.min and candidate.route=='back'
                    and not entersAttack and risk<=currentRisk+.25 and remaining<=range.max
                local strafe=strafeOnly and remaining>=range.min and remaining<=range.max
                    and risk<=currentRisk+.25
                if strafe then
                    score=risk*-3+(candidate.sign==self.strafeSide and 1 or 0)
                end
                if (reactive or approach or strafe or spacing) and score>bestScore then
                    bestScore=score
                    best={action=kind,reason=reactive and 'predicted_threat_exit' or
                        (closingContact and 'contact_approach' or strafe and 'strafe' or spacing and 'spacing_disengage' or distance<range.min and 'item_spacing' or 'predictive_flank'),
                        targetId=s.target.id,issuedAt=s.now,expiresAt=s.now+self.config.maxSnapshotAge,
                        worldDirection=candidate.direction,nativeDirection=candidate.native,
                        route=candidate.route,side=candidate.sign,travel=travel,duration=horizon,
                        predictedPosition=aim,remainingDistance=remaining,risk=risk,
                        currentRisk=currentRisk,opponentsObserved=#observations,
                        interruptCombo=reactive and s.self.defenseInterruptible==true}
                end
            end
        end end
    end
    -- Bounded history, replaced every observation; no retained character Instances.
    local history={}
    for _,o in ipairs(observations) do history[o.id]={time=o.sampledAt or s.sampledAt,
        velocity=capped(o.velocity,self.config.maxSpeed)} end
    self.history=history
    -- Path fallback: only for walking approach, never over a reactive evade/dash.
    if strafeOnly and not best then self.nextStrafeAt=s.now+.25 end
    if not imminent and distance>range.max and can.move==true and s.now>=self.nextWalkAt
        and (not best or (best.action=='walk' and best.reason~='predicted_threat_exit')) then
        local routed=self:_path(s,distance,aim)
        if routed then return routed end
    end
    return best or hold(s,imminent and 'no_safe_escape' or 'no_safe_route')
end
function Planner:step(s,handlers)
    if self.dispatching then return hold(type(s)=='table' and s or {},'dispatch_busy'),false end
    local d=self:decide(s); self.lastDecision=d
    local handler=type(handlers)=='table' and handlers[d.action]
    if type(handler)~='function' then return d,false end
    self.serial+=1; d.id=self.serial
    local generation=self.generation
    self.dispatching=true
    local ok,accepted=pcall(handler,d,s)
    self.dispatching=false
    if not ok then self.lastError=tostring(accepted) end
    -- A native adapter may yield for one Heartbeat while requesting a dash.
    -- An unload/respawn during that yield must not resurrect its old intent.
    if self.stopped or self.generation~=generation then return d,false end
    if ok and accepted==true and d.action~='hold' then
        if d.side and d.side~=0 then self.side=d.side; self.sideUntil=s.now+self.config.sideHold end
        if d.action=='requestPath' then self.nextPathAt=s.now+self.config.pathRefresh
        elseif d.action=='special' then
            self.nextSpecialAt=s.now+(d.combo and self.config.comboGap or self.config.specialGap)
        elseif d.action=='dash' then
            self.nextDashAt=s.now+self.config.dashGap
            if d.combo then self.nextSpecialAt=s.now+self.config.comboGap end
            self.pending={id=d.id,route=d.route,issuedAt=s.now,
                deadline=s.now+self.config.dashAckTimeout}
            self.lastDashOutcome='requested'
        else self.nextWalkAt=s.now+.05 end
        return d,true
    end
    if d.combo then self.phase='close' end
    if d.route then self.rejectedUntil[d.route]=s.now+self.config.rejectDelay end
    return d,false
end
function Planner:confirmDash(id,observed,now)
    local p=self.pending
    if not p or p.id~=id or not finite(now) or now<p.issuedAt then return false end
    self.lastDashOutcome=observed==true and 'confirmed' or 'rejected'
    if observed~=true then self.rejectedUntil[p.route]=now+self.config.rejectDelay end
    self.pending=nil
    return observed==true
end
return Movement
