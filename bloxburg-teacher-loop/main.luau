
if game.PlaceId ~= 185655149 then return end
local env = getgenv()
if env.MesaTeacherLoop then env.MesaTeacherLoop:Stop('replaced') end
local player = game:GetService('Players').LocalPlayer
local input = game:GetService('UserInputService')
local handler = require(player.PlayerScripts.Modules.JobHandler)
local teacher = require(player.PlayerScripts.Modules.JobHandler.HighSchoolTeacher)
local interaction = handler.Modules.InteractionHandler
local line = require(player.PlayerScripts.Modules._UI.MinigameHandler.LineFollow)
local state = {version='1.3.0', alive=true, enabled=true, stage='starting',
    completed=0, attempts=0, errors=0, history={}, pending=nil, mouseHeld=false, confirmedByAction={}}
env.MesaTeacherLoop = state
local registry
for _, value in pairs(getupvalues(interaction.AddInteraction)) do
    if type(value) == 'table' and value ~= interaction then
        for object in pairs(value) do
            if typeof(object) == 'Instance' then registry=value break end
        end
    end
end
assert(registry, 'Native interaction registry unavailable')
local cooldown = setmetatable({}, {__mode='k'})
local observedTasks = setmetatable({}, {__mode='k'})
local function log(event, data)
    table.insert(state.history, {time=os.clock(), event=event, data=data})
    if #state.history > 400 then table.remove(state.history, 1) end
end
local function releaseMouse()
    state.mouseHeld=false
end
local pathfinding=game:GetService('PathfindingService')
local navigation
local WALK_SPEED=24
local LECTURE_RANGE=7
local cur,lectureLogged,boardLogged
local function track(object,label)
    if not cur or cur.object~=object or cur.label~=label then cur={object=object,label=label,t0=os.clock(),repaths=0} end
end
local blockedUntil=setmetatable({}, {__mode='k'})
local function stopWalking()
    local old=navigation
    navigation=nil
    state.navigationStatus=nil
    if old and old.humanoid and old.humanoid.Parent then
        local root=old.humanoid.RootPart
        if root then old.humanoid:MoveTo(root.Position) end
        old.humanoid:Move(Vector3.zero)
        if old.origSpeed then old.humanoid.WalkSpeed=old.origSpeed end
    end
end
local originalLaunchShapes=line.LaunchGameShapes
local launchWrapper
launchWrapper=function(self,callback,...)
    if state.alive and state.pending and state.pending.label=='B_Interact' then
        state.boardCallback=callback
        state.boardSession=true
    end
    return originalLaunchShapes(self,callback,...)
end
line.LaunchGameShapes=launchWrapper
function state:Report(n)
    local out={}
    for i=math.max(1,#self.history-(n or 40)+1),#self.history do
        local h=self.history[i] out[#out+1]=string.format('%.1f %s %s',h.time,h.event,tostring(h.data or ''))
    end
    return table.concat(out,'\n')
end
function state:Stop(reason)
    self.alive=false self.enabled=false self.stage='stopped'
    stopWalking()
    releaseMouse()
    if self.connection then self.connection:Disconnect() end
    if line.LaunchGameShapes==launchWrapper then line.LaunchGameShapes=originalLaunchShapes end
    log('stopped',reason)
end
state.connection=input.InputBegan:Connect(function(key, _processed)
    -- F9 is also processed by Roblox's core UI; emergency stop must still run.
    if input:GetFocusedTextBox() then return end
    if key.KeyCode == Enum.KeyCode.F8 then
        state.enabled=not state.enabled
        if not state.enabled then releaseMouse() stopWalking() end
        log('enabled',state.enabled)
    elseif key.KeyCode == Enum.KeyCode.F9 then state:Stop('F9') end
end)
local function origin(object)
    local part=interaction.Shared.InteractionData:GetOrigin(object,6)
    if typeof(part)=='Instance' then
        if part:IsA('Attachment') then return part.WorldPosition end
        if part:IsA('BasePart') then return part.Position end
    end
    return nil
end
local function distance(object,root)
    local pos=origin(object)
    return pos and (root.Position-pos).Magnitude or math.huge
end
local function inRange(object,root)
    return distance(object,root) < (object:GetAttribute('OverrideInteractRadius')
        or interaction.Shared.InteractionData.INTERACTION_DISTANCE)
end
-- Interior margin: dispatch only once clearly inside the native sphere. After
-- the approach has dragged on (blocked path) the nominal radius is accepted.
local INNER_MARGIN=2
local function inInner(object,root)
    local radius=object:GetAttribute('OverrideInteractRadius') or interaction.Shared.InteractionData.INTERACTION_DISTANCE
    local d=distance(object,root)
    if d<radius-INNER_MARGIN then return true end
    return navigation~=nil and navigation.object==object and os.clock()-navigation.started>5 and d<radius
end
-- Where the walk ends: well inside the dispatch band (radius-2) but not on top of
-- the target. Capped so a smaller override radius still keeps the margin.
local STOP_RANGE=6.5
local function stopRange(object)
    local radius=object:GetAttribute('OverrideInteractRadius') or interaction.Shared.InteractionData.INTERACTION_DISTANCE
    return math.min(STOP_RANGE,radius-INNER_MARGIN-1)
end
local function action(object,wanted)
    local entry=registry[object]
    if not entry or type(entry[1])~='table' then return end
    for _, provider in pairs(entry[1]) do
        if type(provider)=='function' then
            local ok,label,_,callback=pcall(provider)
            if ok and label==wanted and type(callback)=='function' then return callback end
        end
    end
end
local function equippedPass()
    local item=handler.Shared.EquipmentService:GetEquipped(player)
    return item and item.Name=='Hall Pass'
end
local function canTry(object,label,taskID)
    if (blockedUntil[object] or 0)>os.clock() then return false end
    local c=cooldown[object]
    return not c or c.taskID~=taskID or c.label~=label or (c.count<3 and os.clock()>=c.next)
end
local function approach(candidate,root)
    local humanoid=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
    if not humanoid or humanoid.Health<=0 or humanoid.Sit then
        stopWalking() state.stage='waiting_for_walking_character' return
    end
    local object=candidate.object
    local pos=origin(object)
    if not pos then stopWalking() return end
    state.targetDesk=candidate.desk and candidate.desk:GetAttribute('ID')
    state.targetTask=candidate.taskID
    state.targetDistance=math.round((root.Position-pos).Magnitude*10)/10
    state.stage='walking_'..candidate.label
    if navigation and (navigation.object~=object or navigation.label~=candidate.label or navigation.humanoid~=humanoid) then stopWalking() end
    if not navigation then
        local nav={object=object,label=candidate.label,humanoid=humanoid,planning=true,
            origSpeed=humanoid.WalkSpeed,started=os.clock(),lastProgress=os.clock(),lastPosition=root.Position,index=1}
        navigation=nav
        state.navigationStatus='planning'
        log('approach',candidate.label..' desk='..tostring(state.targetDesk))
        task.spawn(function()
            local ok,err=pcall(function()
                -- Reach a free spot inside the native interaction sphere rather
                -- than walking into a desk, student, board or wall.
                local radius=object:GetAttribute('OverrideInteractRadius') or interaction.Shared.InteractionData.INTERACTION_DISTANCE
                local vertical=root.Position.Y-pos.Y
                -- Stop at a comfortable distance inside the dispatch band, not on the target.
                local stop=stopRange(object)
                local ring=math.clamp(math.sqrt(math.max(0,stop^2-vertical^2)),1.5,16)
                if candidate.label=='activate_lecture' then ring=math.min(ring,LECTURE_RANGE-2) end
                local delta=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
                local direction=delta.Magnitude>0.1 and delta.Unit or Vector3.xAxis
                local offsets={0,math.pi/4,-math.pi/4,math.pi/2,-math.pi/2,math.pi,3*math.pi/4,-3*math.pi/4}
                -- Goals stay inside the dispatch band so the walk ends where the prompt fires.
                local maxRing=math.max(ring,math.sqrt(math.max(0,(radius-INNER_MARGIN-0.5)^2-vertical^2)))
                if candidate.label=='activate_lecture' then maxRing=math.max(ring,LECTURE_RANGE-0.8) end
                -- Fast path: a clear straight line to the stop point needs no path computation.
                do
                    local goal=Vector3.new(pos.X+direction.X*ring,root.Position.Y,pos.Z+direction.Z*ring)
                    if (root.Position-goal).Magnitude<24 then
                        local params=RaycastParams.new()
                        params.FilterType=Enum.RaycastFilterType.Exclude
                        params.FilterDescendantsInstances={player.Character}
                        local rp=root.Position-Vector3.new(0,1.5,0)
                        local hit=workspace:Raycast(rp,Vector3.new(goal.X-rp.X,0,goal.Z-rp.Z),params)
                        local side=workspace:Raycast(root.Position+root.CFrame.RightVector*1.4,Vector3.new(goal.X-rp.X,0,goal.Z-rp.Z),params)
                        local side2=workspace:Raycast(root.Position-root.CFrame.RightVector*1.4,Vector3.new(goal.X-rp.X,0,goal.Z-rp.Z),params)
                        if not hit and not side and not side2 then
                            nav.waypoints={{Position=goal}} nav.planning=false nav.lastProgress=os.clock()
                            state.navigationStatus='walking_fast'
                            return
                        end
                    end
                end
                local tries={}
                for _,k in ipairs({0,0.6,1.2}) do
                    local rr=math.min(ring+k,maxRing)
                    if rr>=ring and not table.find(tries,rr) then table.insert(tries,rr) end
                end
                for _,agentR in ipairs({1.5,0.9}) do for _,rr in ipairs(tries) do for _,angle in ipairs(offsets) do
                    if navigation~=nav or not state.alive or not state.enabled then return end
                    local offset=CFrame.Angles(0,angle,0):VectorToWorldSpace(direction)*rr
                    local goal=Vector3.new(pos.X+offset.X,root.Position.Y,pos.Z+offset.Z)
                    local path=pathfinding:CreatePath({AgentRadius=agentR,AgentHeight=5,AgentCanJump=false,WaypointSpacing=8})
                    path:ComputeAsync(root.Position,goal)
                    if navigation~=nav then return end
                    if path.Status==Enum.PathStatus.Success then
                        nav.waypoints=path:GetWaypoints()
                        nav.planning=false
                        nav.lastProgress=os.clock()
                        state.navigationStatus='walking'
                        return
                    end
                end end end
                if navigation==nav then
                    -- Last resort: walk straight to the closest interior point; the stuck
                    -- detector repaths if something is in the way.
                    local flat=Vector3.new(pos.X+direction.X*ring,root.Position.Y,pos.Z+direction.Z*ring)
                    if (root.Position-pos).Magnitude<30 then
                        nav.waypoints={{Position=flat}} nav.planning=false nav.lastProgress=os.clock()
                        state.navigationStatus='walking_direct'
                        log('path_direct',candidate.label)
                    else
                        blockedUntil[object]=os.clock()+6
                        log('path_unavailable',candidate.label)
                        stopWalking()
                    end
                end
            end)
            if not ok and navigation==nav then
                log('path_error',tostring(err)) blockedUntil[object]=os.clock()+6 stopWalking()
            end
        end)
        return
    end
    local nav=navigation
    if os.clock()-nav.started>25 then
        blockedUntil[object]=os.clock()+6 log('approach_timeout',candidate.label) stopWalking() return
    end
    if nav.planning then return end
    if (root.Position-nav.lastPosition).Magnitude>0.6 then
        nav.lastPosition=root.Position nav.lastProgress=os.clock()
    elseif os.clock()-nav.lastProgress>1.5 then
        log('repath',candidate.label) if cur then cur.repaths+=1 if cur.repaths%3==0 then blockedUntil[object]=os.clock()+3 end end stopWalking() return
    end
    local waypoint=nav.waypoints[nav.index]
    while waypoint do
        local last=nav.index>=#nav.waypoints
        local hd=(Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(waypoint.Position.X,0,waypoint.Position.Z)).Magnitude
        if hd>=(last and 1.5 or 4) then break end
        if last then nav.arrived=true waypoint=nil else nav.index+=1 waypoint=nav.waypoints[nav.index] end
    end
    if nav.arrived then waypoint=nil end
    if humanoid.WalkSpeed<WALK_SPEED then humanoid.WalkSpeed=WALK_SPEED end
    if waypoint then humanoid:MoveTo(waypoint.Position)
    else
        -- Path finished but still outside the stop band: close in along the
        -- current bearing to the stop distance, never onto the target itself.
        local out=Vector3.new(root.Position.X-pos.X,0,root.Position.Z-pos.Z)
        if out.Magnitude>0.1 then
            local stop=out.Unit*stopRange(object)
            humanoid:MoveTo(Vector3.new(pos.X+stop.X,root.Position.Y,pos.Z+stop.Z))
        end
    end
end
local function dispatch(object,label,desk,taskID)
    local c=cooldown[object]
    track(object,label)
    local walked=navigation and navigation.object==object and math.round((os.clock()-navigation.started)*10)/10 or 0
    local dist=math.round(distance(object,player.Character.HumanoidRootPart)*10)/10
    if not c or c.taskID~=taskID or c.label~=label then c={taskID=taskID,label=label,count=0,next=0} cooldown[object]=c end
    if os.clock()<c.next or c.count>=3 then return false end
    local callback=action(object,label)
    if not callback then return false end
    stopWalking()
    c.count+=1 c.next=os.clock()+8
    state.attempts+=1
    state.pending={object=object,desk=desk,taskID=taskID,label=label,started=os.clock()}
    log('dispatch',label..' desk='..tostring(desk and desk:GetAttribute('ID'))..' dist='..dist..' walked='..walked..'s')
    -- One native callback at a time; never duplicate an outstanding server request.
    task.spawn(function()
        local ok,err=pcall(callback)
        if not ok then state.errors+=1 log('callback_error',tostring(err)) end
        if state.pending and state.pending.object==object then state.pending.returned=true end
    end)
    return true
end
local function traceBoard()
    -- Advance every ordered node using the native minigame API. The callback
    -- is captured only when the native board interaction launches this game.
    local up=getupvalues(line.Increment)
    local nodes,index=up[2],up[3]
    if type(nodes)~='table' or type(index)~='number' then error('LineFollow layout changed') end
    local node=nodes[index]
    if not node or not node.Obj or not node.Obj.Parent then return end
    if not state.boardSession or type(state.boardCallback)~='function' then return end
    local finished=line:Increment()
    state.nodesSeen=(state.nodesSeen or 0)+1
    if finished then
        local callback=state.boardCallback
        state.boardCallback=nil state.boardSession=false
        -- Cleanup before the next render frame can read beyond the final node.
        line:Cleanup()
        log('board_nodes_complete',index)
        callback()
    end
end
local function tickLoop()
    if not state.enabled then stopWalking() state.stage='paused' return end
    if input:GetFocusedTextBox() then releaseMouse() stopWalking() state.stage='typing' return end
    if not handler:IsWorking(teacher.Script) then
        releaseMouse() stopWalking() state.pending=nil state.stage='waiting_for_teacher_shift' return
    end
    local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    if not root then releaseMouse() stopWalking() state.stage='waiting_for_character' return end
    local up=getupvalues(teacher.StartShift)
    local gameplay=up[3]
    if typeof(gameplay)~='Instance' or not gameplay.Parent then stopWalking() state.stage='waiting_for_classroom' return end
    local desks=gameplay:FindFirstChild('Desks')
    local stations=gameplay:FindFirstChild('Hall Pass Stations')
    local board=gameplay:FindFirstChild('Board')
    if not (desks and stations and board) then stopWalking() state.stage='waiting_for_classroom' return end
    if line:IsRunning() then
        stopWalking()
        -- Only control a board game this loop started, never another minigame.
        if state.pending and state.pending.label=='B_Interact' then
            state.stage='tracing_board' traceBoard()
        else state.stage='waiting_for_manual_minigame' end
        return
    end
    releaseMouse()
    local pending=state.pending
    if pending then
        local confirmed=false
        if pending.label=='I_Take' then confirmed=equippedPass()
        elseif pending.desk and pending.desk.Parent then confirmed=pending.desk:GetAttribute('TaskID')==-1 end
        if confirmed then
            if pending.label~='I_Take' then state.completed+=1 end
            log('stage_time',pending.label..' full='..(cur and cur.label==pending.label and math.round((os.clock()-cur.t0)*10)/10 or '?')..'s repaths='..(cur and cur.repaths or 0)..' callback='..(math.round((os.clock()-pending.started)*10)/10)..'s total_done='..state.completed) cur=nil
            state.confirmedByAction[pending.label]=(state.confirmedByAction[pending.label] or 0)+1
            cooldown[pending.object]=nil
            log('confirmed',pending.label..' desk='..tostring(pending.desk and pending.desk:GetAttribute('ID')))
            state.pending=nil
        elseif not pending.returned then
            state.stage='waiting_for_native_callback' return
        elseif os.clock()-pending.started < (pending.label=='B_Interact' and 90 or 8) then
            state.stage='waiting_for_confirmation' return
        else
            log('unconfirmed',pending.label) state.pending=nil
        end
    end
    local candidates={}
    local routes={}
    local hasPass=equippedPass()
    local lectureDesk
    local nearestDistance=math.huge
    state.targetDesk=nil state.targetTask=nil
    for _,desk in ipairs(desks:GetChildren()) do
        local taskID=desk:GetAttribute('TaskID')
        if observedTasks[desk]~=taskID then
            observedTasks[desk]=taskID
            cooldown[desk]=nil
        end
        if taskID and taskID>0 then
            local d=distance(desk,root)
            if d<nearestDistance then nearestDistance=d state.targetDesk=desk:GetAttribute('ID') state.targetTask=taskID end
            if taskID==3 then lectureDesk=desk end
            local label=taskID==1 and 'I_Scold' or (taskID==2 and hasPass and 'I_Give')
            if label and canTry(desk,label,taskID) and action(desk,label) then
                local c={object=desk,label=label,desk=desk,taskID=taskID,d=d}
                table.insert(routes,c)
                if inInner(desk,root) then table.insert(candidates,c) end
            end
        end
    end
    local boardAction=action(board,'B_Interact')
    if lectureDesk and boardAction then
        -- Use the desk captured by the real board callback, not an arbitrary
        -- lecture task if more than one student is waiting.
        for _,v in pairs(getupvalues(boardAction)) do
            if typeof(v)=='Instance' and v.Parent==desks and v:GetAttribute('TaskID')==3 then lectureDesk=v break end
        end
        if boardLogged~=lectureDesk then boardLogged=lectureDesk log('board_available','after_lecture='..(cur and cur.label=='activate_lecture' and math.round((os.clock()-cur.t0)*10)/10 or '?')..'s dist_board='..(math.round(distance(board,root)*10)/10)) cur=nil end
        if canTry(board,'B_Interact',3) then
            local c={object=board,label='B_Interact',desk=lectureDesk,taskID=3,d=distance(board,root)}
            table.insert(routes,c)
            if inInner(board,root) then table.insert(candidates,c) end
        end
    elseif lectureDesk then
        -- Native lecture activation watches student proximity (sqrt(90)).
        -- Visit the student first; only then does the board callback exist.
        table.insert(routes,{object=lectureDesk,label='activate_lecture',desk=lectureDesk,taskID=3,d=distance(lectureDesk,root)})
    end
    if not hasPass then
        local needsPass=false
        for _,desk in ipairs(desks:GetChildren()) do if desk:GetAttribute('TaskID')==2 then needsPass=true break end end
        if needsPass then
            for _,station in ipairs(stations:GetChildren()) do
                if canTry(station,'I_Take',2) and action(station,'I_Take') then
                    local c={object=station,label='I_Take',taskID=2,d=distance(station,root)}
                    table.insert(routes,c)
                    if inInner(station,root) then table.insert(candidates,c) end
                end
            end
        end
    end
    if hasPass then
        -- Scolding/board animations can unequip a pass. Complete the delivery
        -- stage before starting another action, including during its walk.
        local deliveries={}
        local nearbyDeliveries={}
        for _,c in ipairs(routes) do if c.label=='I_Give' then table.insert(deliveries,c) end end
        if #deliveries>0 then
            for _,c in ipairs(candidates) do if c.label=='I_Give' then table.insert(nearbyDeliveries,c) end end
            routes=deliveries candidates=nearbyDeliveries
        end
    end
    table.sort(candidates,function(a,b) return a.d<b.d end)
    table.sort(routes,function(a,b) return a.d<b.d end)
    -- Sticky focus: finish the chosen request before any other, even if a
    -- newer one is closer. Focus changes only when it is done or unavailable.
    local selected
    local order=state.order
    if order and not (order.desk.Parent and order.desk:GetAttribute('TaskID')==order.taskID) then order=nil state.order=nil end
    if order then
        for _,c in ipairs(routes) do
            if c.desk==order.desk or (c.label=='I_Take' and order.taskID==2) then selected=c break end
        end
    end
    local focus=state.focus
    if focus and not selected then
        for _,c in ipairs(routes) do
            if c.object==focus.object and c.label==focus.label then selected=c break end
        end
        if not selected and focus.label=='activate_lecture' then
            for _,c in ipairs(routes) do if c.label=='B_Interact' then selected=c break end end
        end
    end
    if not selected then selected=routes[1] end
    if selected and (not state.focus or state.focus.object~=selected.object or state.focus.label~=selected.label) then
        log('focus',selected.label..' desk='..tostring(selected.desk and selected.desk:GetAttribute('ID'))..' open_routes='..#routes)
    end
    state.focus=selected and {object=selected.object,label=selected.label} or nil
    if selected and not state.order then
        local od=selected.desk
        if selected.label=='I_Take' then
            local best=math.huge
            for _,desk in ipairs(desks:GetChildren()) do
                if desk:GetAttribute('TaskID')==2 then
                    local d=distance(desk,root)
                    if d<best then best=d od=desk end
                end
            end
        end
        if od then state.order={desk=od,taskID=od:GetAttribute('TaskID')} end
    end
    if selected then
        for _,c in ipairs(candidates) do
            if c.object==selected.object and c.label==selected.label then
                if dispatch(c.object,c.label,c.desk,c.taskID) then state.stage=c.label return end
            end
        end
    end
    if selected then
        if selected.label=='activate_lecture' and distance(selected.object,root)<LECTURE_RANGE then
            stopWalking() state.stage='waiting_for_lecture_activation'
            track(selected.object,'activate_lecture')
            if lectureLogged~=selected.object then lectureLogged=selected.object log('lecture_stop','dist='..(math.round(distance(selected.object,root)*10)/10)..' full='..(math.round((os.clock()-cur.t0)*10)/10)..'s repaths='..cur.repaths) end
        else track(selected.object,selected.label) approach(selected,root) end
        return
    end
    stopWalking()
    state.targetDistance=nearestDistance<math.huge and math.round(nearestDistance*10)/10 or nil
    state.stage=nearestDistance<math.huge and 'waiting_for_native_action' or 'waiting_for_task'
end
log('started',state.version..' F8 pause / F9 stop')
task.spawn(function()
    while state.alive and env.MesaTeacherLoop==state do
        local ok,err=xpcall(tickLoop,debug.traceback)
        if not ok then
            releaseMouse() stopWalking() state.errors+=1 state.enabled=false state.stage='error_paused'
            log('error',tostring(err))
        end
        task.wait(0.1)
    end
    releaseMouse() stopWalking()
end)

