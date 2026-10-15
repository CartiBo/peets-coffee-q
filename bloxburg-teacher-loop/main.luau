
if game.PlaceId ~= 185655149 then return end
local env = getgenv()
if env.MesaTeacherLoop then env.MesaTeacherLoop:Stop('replaced') end
local player = game:GetService('Players').LocalPlayer
local input = game:GetService('UserInputService')
local handler = require(player.PlayerScripts.Modules.JobHandler)
local teacher = require(player.PlayerScripts.Modules.JobHandler.HighSchoolTeacher)
local interaction = handler.Modules.InteractionHandler
local line = require(player.PlayerScripts.Modules._UI.MinigameHandler.LineFollow)
local state = {version='1.6.0', alive=true, enabled=true, stage='starting',
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
    if tostring(event):find('mood') then
        state.moodHistory=state.moodHistory or {}
        table.insert(state.moodHistory, {time=os.clock(), event=event, data=data})
        if #state.moodHistory > 200 then table.remove(state.moodHistory, 1) end
    end
    if #state.history > 400 then table.remove(state.history, 1) end
end
local function releaseMouse()
    state.mouseHeld=false
end
local pathfinding=game:GetService('PathfindingService')
local navigation
local WALK_SPEED=28
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
local function detachMoodNative()
    local identity=getthreadidentity and getthreadidentity()
    local char=player.Character
    local root=char and char:FindFirstChild('HumanoidRootPart')
    local hum=char and char:FindFirstChildOfClass('Humanoid')
    local attached=false
    pcall(function() attached=handler.Shared.AttachService:GetAttachWeld(char)~=nil end)
    if attached or (root and root:FindFirstChild('AttachWeld')) or (hum and hum.Sit) then
        -- Native stand-up: destroys the local weld and tells the server (Type='Detach'), so the sit pose really ends.
        state.detachedAt=os.clock()
        task.spawn(function()
            pcall(function() handler.Modules.CharacterHandler:Detach() end)
            if hum and hum.Parent then hum.Sit=false end
        end)
    end
    pcall(function() handler.Shared.AttachService:DetachPlayer(player) end)
    if identity and setthreadidentity then setthreadidentity(identity) end
end
function state:Stop(reason)
    self.alive=false self.enabled=false self.stage='stopped'
    if self.mood then
        self.mood.token+=1 self.mood.busy=false self.mood.phase='idle'
        detachMoodNative()
    end
    stopWalking()
    releaseMouse()
    if self.gui then self.gui:Destroy() self.gui=nil end
    if line.LaunchGameShapes==launchWrapper then line.LaunchGameShapes=originalLaunchShapes end
    log('stopped',reason)
end
-- Stage hub (replaces the F7/F8/F9 keybinds): one Docente button toggling all stages jointly, plus mood and pause/stop.
state.stageOn={pass=true,scold=true,board=true}
local STAGE_OF={I_Take='pass',I_Give='pass',I_Scold='scold',activate_lecture='board',B_Interact='board'}
do
    local parent=(gethui and gethui()) or game:GetService('CoreGui')
    local gui=Instance.new('ScreenGui')
    gui.Name='MesaTeacherHub' gui.ResetOnSpawn=false gui.DisplayOrder=50
    local frame=Instance.new('Frame')
    frame.Size=UDim2.fromOffset(176,0) frame.AutomaticSize=Enum.AutomaticSize.Y
    frame.AnchorPoint=Vector2.new(0,0.5)
    frame.Position=UDim2.new(0,16,0.5,0)
    frame.BackgroundColor3=Color3.fromRGB(14,18,22) frame.BackgroundTransparency=0.12
    frame.BorderSizePixel=0 frame.Parent=gui
    Instance.new('UICorner',frame).CornerRadius=UDim.new(0,10)
    local stroke=Instance.new('UIStroke',frame) stroke.Color=Color3.fromRGB(45,212,191) stroke.Transparency=0.55
    local pad=Instance.new('UIPadding',frame)
    pad.PaddingTop=UDim.new(0,8) pad.PaddingBottom=UDim.new(0,8) pad.PaddingLeft=UDim.new(0,8) pad.PaddingRight=UDim.new(0,8)
    local list=Instance.new('UIListLayout',frame) list.Padding=UDim.new(0,4) list.SortOrder=Enum.SortOrder.LayoutOrder
    local function label(text,order,size,color)
        local l=Instance.new('TextLabel')
        l.Size=UDim2.new(1,0,0,size) l.BackgroundTransparency=1 l.Text=text l.LayoutOrder=order
        l.Font=Enum.Font.GothamBold l.TextSize=size>16 and 14 or 11 l.TextColor3=color
        l.TextXAlignment=Enum.TextXAlignment.Left l.Parent=frame
        return l
    end
    label('DOCENTE',0,18,Color3.fromRGB(45,212,191))
    local status=label('',1,22,Color3.fromRGB(150,160,170))
    status.Font=Enum.Font.Gotham status.TextSize=10 status.TextWrapped=true
    local function button(order,name,get,click)
        local b=Instance.new('TextButton')
        b.Size=UDim2.new(1,0,0,26) b.LayoutOrder=order b.AutoButtonColor=false b.BorderSizePixel=0
        b.Font=Enum.Font.GothamMedium b.TextSize=12 b.Parent=frame
        Instance.new('UICorner',b).CornerRadius=UDim.new(0,6)
        local function paint()
            local on,text=get()
            b.Text=text or ((on and '● ' or '○ ')..name)
            b.BackgroundColor3=on and Color3.fromRGB(20,110,100) or Color3.fromRGB(34,40,46)
            b.TextColor3=on and Color3.fromRGB(230,255,250) or Color3.fromRGB(140,150,160)
        end
        b.MouseButton1Click:Connect(function() click() paint() end)
        b.MouseEnter:Connect(function() b.BackgroundTransparency=0.15 end)
        b.MouseLeave:Connect(function() b.BackgroundTransparency=0 end)
        paint()
        return paint
    end
    local paints={}
    local function teacherOn() local s=state.stageOn return s.pass and s.scold and s.board end
    paints[#paints+1]=button(2,'Docente',teacherOn,function()
        local on=not teacherOn()
        state.stageOn.pass=on state.stageOn.scold=on state.stageOn.board=on
        if not on then releaseMouse() stopWalking() end
        log('stage_teacher',on)
    end)
    label('ÁNIMO',5,14,Color3.fromRGB(45,212,191))
    paints[#paints+1]=button(6,'Auto-ánimo',function() return state.mood and state.mood.enabled end,function()
        if not state.mood then return end
        state.mood.enabled=not state.mood.enabled
        -- Off means off: abort any trip in flight; no further warps or shift starts.
        if not state.mood.enabled and state.moodCancel then state.moodCancel('hub') end
        log('mood_enabled',state.mood.enabled)
    end)
    label('CONTROL',7,12,Color3.fromRGB(150,160,170))
    paints[#paints+1]=button(8,'Pausa',function() return not state.enabled,(state.enabled and '⏸ Pausar' or '▶ Reanudar') end,function()
        state.enabled=not state.enabled
        if not state.enabled then releaseMouse() stopWalking() end
        log('enabled',state.enabled)
    end)
    local stop=Instance.new('TextButton')
    stop.Size=UDim2.new(1,0,0,26) stop.LayoutOrder=9 stop.AutoButtonColor=false stop.BorderSizePixel=0
    stop.Font=Enum.Font.GothamMedium stop.TextSize=12 stop.Text='■ Detener'
    stop.BackgroundColor3=Color3.fromRGB(120,36,44) stop.TextColor3=Color3.fromRGB(255,225,225) stop.Parent=frame
    Instance.new('UICorner',stop).CornerRadius=UDim.new(0,6)
    stop.MouseButton1Click:Connect(function() state:Stop('hub') end)
    gui.Parent=parent
    state.gui=gui
    task.spawn(function()
        while state.alive and gui.Parent do
            local st=tostring(state.stage):gsub('_',' ')
            if not state.enabled then st='EN PAUSA - pulsa Reanudar' end
            status.Text=st..' · '..state.completed..' hechas'
            for _,p in ipairs(paints) do p() end
            task.wait(0.5)
        end
    end)
end
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
local function findAction(object,wanted)
    local entry=registry[object]
    if entry and type(entry[1])=='table' then
        for _, provider in pairs(entry[1]) do
            if type(provider)=='function' then
                local ok,label,_,callback=pcall(provider)
                if ok and label==wanted and type(callback)=='function' then
                    return {callback=callback,isCustom=true,label=label,object=object}
                end
            end
        end
    end
    local id=interaction.Shared and interaction.Shared.InteractionData
    if id and typeof(object)=='Instance' then
        local ok,data=pcall(function() return id:GetData(object,player) end)
        if ok and type(data)=='table' then
            for i, fn in ipairs(data) do
                if type(fn)=='function' then
                    local sok,label,_,callback,opts=pcall(fn,object)
                    if sok and label==wanted and type(callback)=='function' then
                        return {callback=callback,isCustom=false,label=label,path=tostring(i),options=opts or {},object=object}
                    end
                end
            end
        end
    end
    return nil
end
local function action(object,wanted)
    local act=findAction(object,wanted)
    return act and act.callback or nil
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
        if humanoid.WalkSpeed<WALK_SPEED then humanoid.WalkSpeed=WALK_SPEED end
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
                    if (root.Position-pos).Magnitude<50 then
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
-- Auto-mood: each 6,000 of native shift earnings ends the shift after the pending action, warps home with the
-- native HouseHandler:ToPlot (same call as the phone's "Go to plot" button), refills needs with
-- native house interactions, then warps back through the native job warp and restarts the shift.
local jobKey=tostring(teacher.Script)
local NEEDS={
    {name='Hunger',labels={'I_TakeQuickMeal','I_Eat'}},
    {name='Energy',labels={'I_Sleep'}},
    {name='Hygiene',labels={'I_Use','I_UseShower','I_UseBathtub','I_WashFace','I_BrushTeeth'}},
    {name='Fun',labels={'I_Watch','I_TurnOn','I_PlayAlone'}},
}
-- Quick meals in preference order (cheap and filling-sounding; real gain is measured and logged).
local FOOD_PRIORITY={'Apple','Banana','Yogurt','Cereal','Toast','Grilled Cheese','PB&J','Oatmeal',"Mac 'n' Cheese"}
-- Normal decay (98, 95, 92...) never triggers anything. A trip starts at each 6,000 of shift earnings only if some need is
-- below minReturn (70), or at any time a need is critical (<startBelow, 25). At home needs below minReturn are served up to
-- fillTarget (98); the player goes back as soon as every need is >=minReturn.
local mood={enabled=true,phase='idle',values={},earningsTarget=6000,nextEarnings=6000,target=90,startBelow=25,minReturn=70,fillTarget=98,homeMax=900,actionMax=240,cooldown=180,
    cooldownUntil=0,trips=0,busy=false,token=0,foodGain={},failed=setmetatable({},{__mode='k'})}
state.mood=mood
task.spawn(function()
    local last=os.clock()
    while state.alive do
        task.wait(0.1)
        local now=os.clock()
        if state.enabled and not input:GetFocusedTextBox() then mood.clock=(mood.clock or 0)+(now-last) end
        last=now
    end
end)
-- Cancellation: bumping the token makes every in-flight trip thread stop at its next gate.
local function moodCancel(reason)
    mood.token+=1 mood.phase='idle' mood.busy=false mood.action=nil
    detachMoodNative()
    log('mood_cancel',reason)
end
state.moodCancel=moodCancel
-- True while the trip owned by tok may continue; holds (F8 pause) until resumed, or holds during typing.
local function gate(tok)
    while state.alive and mood.enabled and mood.token==tok and not state.enabled do task.wait(0.2) end
    while state.alive and mood.enabled and mood.token==tok and input:GetFocusedTextBox() do task.wait(0.2) end
    return state.alive and mood.enabled and mood.token==tok and state.enabled
end
local function pause(tok,seconds)
    task.wait(seconds)
    return gate(tok)
end
local function readMood()
    local ok,folder=pcall(function() return game:GetService('ReplicatedStorage').Stats[player.Name].MoodData end)
    if not ok or not folder then return false end
    local values,lowName,lowValue={},nil,math.huge
    for _,need in ipairs(NEEDS) do
        local object=folder:FindFirstChild(need.name)
        if object then
            values[need.name]=object.Value
            if object.Value<lowValue then lowValue=object.Value lowName=need.name end
        end
    end
    local total=0 for _,need in ipairs(NEEDS) do total+=values[need.name] or 0 end
    mood.overall=total/#NEEDS
    mood.values=values mood.lowest=lowName mood.lowestValue=lowValue mood.status=folder.Value
    return lowName~=nil
end
-- Reads replicated job data only; never parses currency text or touches the player's balance.
function state:MoodEarnings()
    local ok,amount=pcall(function()
        local job=handler.Modules.ClientStats:GetStat('Job')
        local value=job and job:FindFirstChild('ShiftEarnings')
        return value and tonumber(value.Value)
    end)
    if not ok or not amount or amount<0 or amount~=amount then
        mood.earningsAvailable=false
        return nil
    end
    if mood.shiftEarnings and amount<mood.shiftEarnings then
        mood.nextEarnings=mood.earningsTarget
    end
    mood.shiftEarnings=amount mood.earningsAvailable=true
    return amount
end
-- The fridge refuses quick meals once Hunger is high (observed ~75). A need the game will not fill further
-- counts as satisfied while it stays >=60, so the visit can end instead of waiting for an unreachable 98.
local CAPPED_MIN=75
local function needCapped(name)
    return mood.capped and mood.capped[name] and (mood.values[name] or 0)>=CAPPED_MIN
end
local function moodReadyForWork()
    if not mood.overall then return false end
    for _,need in ipairs(NEEDS) do
        local v=mood.values[need.name] or 0
        if v<mood.minReturn and not needCapped(need.name) then return false end
    end
    return true
end
local function isAtHome(root)
    local plot=workspace.Plots:FindFirstChild('Plot_'..player.Name)
    if not plot or not root then return false end
    local house=plot:FindFirstChild('House')
    if house then
        local hp=house:GetPivot().Position
        if (root.Position-hp).Magnitude<200 then return true end
    end
    local ground=plot:FindFirstChild('Ground')
    if ground and ground:IsA('BasePart') then
        if (root.Position-ground.Position).Magnitude<200 then return true end
    end
    return false
end
local function findMoodTarget(need,root)
    local plot=workspace.Plots:FindFirstChild('Plot_'..player.Name)
    if not plot then return nil end
    local candidates={}
    for _, d in ipairs(plot:GetDescendants()) do
        if d:IsA('BasePart') and (mood.failed[d] or 0)<os.clock() and (blockedUntil[d] or 0)<os.clock() then
            local n=d.Name:lower()
            local matched=false
            local prio=10
            if need.name=='Hunger' then
                if n:find('fridge') and not n:find('cabinet') then matched=true prio=1 end
            elseif need.name=='Energy' then
                if n:find('bed') and not n:find('lamp') and not n:find('table') and not n:find('sheet') then matched=true prio=1 end
            elseif need.name=='Hygiene' then
                -- Toilet only adds a slow status (about 2 per use), so showers/baths go first when they have room.
                if n:find('shower') or n:find('bathtub') then matched=true prio=1
                elseif n:find('toilet') then matched=true prio=2
                elseif n:find('sink') or n:find('vanity') then matched=true prio=3 end
            elseif need.name=='Fun' then
                if n:find('tv') or n:find('television') then matched=true prio=1 end
            end
            if matched then
                local dDist=distance(d,root)
                -- Search the whole current plot, including large/rebuilt houses.
                if dDist<math.huge then
                    table.insert(candidates,{object=d,prio=prio,dist=dDist})
                end
            end
        end
    end
    table.sort(candidates,function(a,b)
        if a.prio~=b.prio then return a.prio<b.prio end
        return a.dist<b.dist
    end)
    for _, c in ipairs(candidates) do
        local obj=c.object
        for _, label in ipairs(need.labels) do
            local act=findAction(obj,label)
            if act then
                return {object=obj,label=label,path=act.path,options=act.options,callback=act.callback,isCustom=act.isCustom,taskID=0,d=c.dist}
            end
        end
    end
    return nil
end
-- Mood navigation is deliberately independent of the teacher pathfinding.
local function moodDetach()
    detachMoodNative()
    local hum=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
    if hum then hum.Sit=false end
end
local function moodDispatch(c)
    local fresh=findAction(c.object,c.label)
    if not fresh then error('Interaction unavailable: '..c.label) end
    local _,extra=fresh.callback()
    if not fresh.isCustom then
        local opts=fresh.options or {}
        if not opts.NoSend then
            local packet={Type='Interact',Target=c.object,Path=fresh.path or '1'}
            for k,v in pairs(opts.SendData or {}) do packet[k]=v end
            if type(extra)=='table' then for k,v in pairs(extra) do packet[k]=v end end
            if not packet.NoSend then handler.net:FireServer(packet) end
        end
    end
end
local function moodWaypoint(c,root)
    stopWalking()
    local pos=origin(c.object)
    if not pos then return false end
    local char=player.Character
    local ray=RaycastParams.new()
    ray.FilterType=Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances={char,c.object}
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Exclude
    overlap.FilterDescendantsInstances={char,c.object}
    local radius=c.object:GetAttribute('OverrideInteractRadius') or interaction.Shared.InteractionData.INTERACTION_DISTANCE
    local nativeAttach=c.object:FindFirstChild('AttachPos',true)
    local preferred
    if nativeAttach and nativeAttach:IsA('Attachment') then preferred=nativeAttach.WorldPosition
    elseif nativeAttach and nativeAttach:IsA('BasePart') then preferred=nativeAttach.Position end
    local best,bestD
    for _,r in ipairs({math.min(4,radius-3),math.min(6,radius-3),2.5}) do
        if r>0 then for i=0,15 do
            local a=i*math.pi/8
            local point=pos+Vector3.new(math.cos(a)*r,3,math.sin(a)*r)
            local hit=workspace:Raycast(point,Vector3.new(0,-9,0),ray)
            if hit and hit.Normal.Y>0.7 and math.abs(hit.Position.Y-pos.Y)<2 then
                local dest=hit.Position+Vector3.new(0,root.Size.Y/2+2,0)
                local clear=true
                for _,part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(dest),Vector3.new(2,4,2),overlap)) do
                    if part.CanCollide then clear=false break end
                end
                local d=preferred and (dest-preferred).Magnitude*10 or (dest-root.Position).Magnitude
                if clear and (dest-pos).Magnitude<radius-1 and (not bestD or d<bestD) then best=dest bestD=d end
            end
        end end
    end
    if not best then log('mood_waypoint_blocked',c.object.Name) return false end
    moodDetach()
    char:PivotTo(CFrame.lookAt(best,Vector3.new(pos.X,best.Y,pos.Z)))
    root.AssemblyLinearVelocity=Vector3.zero
    root.AssemblyAngularVelocity=Vector3.zero
    log('mood_waypoint',c.object.Name..' distance='..math.round((best-pos).Magnitude*10)/10)
    return true
end
local function moodSeat(tv,root,tok)
    local plot=workspace.Plots:FindFirstChild('Plot_'..player.Name)
    local seat,seatDistance
    for _,o in ipairs(plot:GetDescendants()) do
        if o:IsA('BasePart') then
            local n=o.Name:lower()
            if n:find('sofa') or n:find('couch') or n:find('armchair') then
                local d=(o.Position-tv.object.Position).Magnitude
                if d<20 and (not seatDistance or d<seatDistance) then
                    local a=findAction(o,'I_Sit')
                    if a then seat={object=o,label='I_Sit'} seatDistance=d end
                end
            end
        end
    end
    if seat and gate(tok) then
        -- Seat first, then watch: television uses a proximity attachment with Multiple=true.
        if moodWaypoint(seat,root) then
            if not pause(tok,0.9) then return end
            moodDispatch(seat)
            if not pause(tok,0.5) then return end
            if inRange(tv.object,root) then moodDispatch(tv) end
        end
    end
end
local function dismissPopups()
    pcall(function()
        local gui=player.PlayerGui
        local msgBox=gui:FindFirstChild('_MessageBox')
        if msgBox then
            msgBox.Enabled=false
            for _, b in ipairs(msgBox:GetDescendants()) do
                if b:IsA('GuiButton') and b.Name=='ButtonTemplate' then
                    for _, c in ipairs(getconnections(b.Activated)) do c:Fire() end
                    for _, c in ipairs(getconnections(b.MouseButton1Click)) do c:Fire() end
                end
            end
        end
        local mg=gui:FindFirstChild('MainGUI')
        if mg then
            for _, f in ipairs(mg:GetChildren()) do
                if (f.Name=='PaycheckFrame' or f.Name=='PaycheckFrameOriginal') and f:IsA('GuiObject') then
                    f.Position=UDim2.new(10,0,10,0) f.Visible=false
                end
            end
        end
    end)
end
local function pickQuickFood(list)
    for _,wanted in ipairs(FOOD_PRIORITY) do
        for _,entry in ipairs(list) do
            if entry._itemName==wanted and entry.Price and entry.Price>0 then return entry end
        end
    end
    local cheapest
    for _,entry in ipairs(list) do
        if entry.Price and entry.Price>0 and (not cheapest or entry.Price<cheapest.Price) then cheapest=entry end
    end
    return cheapest
end
-- Fridge sequence (native): I_TakeQuickMeal -> list "T_QuickMeals" -> server TakeQuickFood -> EatEquipped.
local function takeAndEat(c,tok,act)
    dismissPopups()
    log('mood_meal_start','sit='..tostring(player.Character and player.Character:FindFirstChildOfClass('Humanoid').Sit))
    detachMoodNative()
    local lfh=handler.Modules.ListFrameHandler
    local original=lfh.ShowList
    lfh.ShowList=function(self,info,list,...)
        if type(info)=='table' and info.Title=='T_QuickMeals' and type(list)=='table' then
            local pick=pickQuickFood(list)
            if pick then act.food=pick._itemName return pick end
        end
        return original(self,info,list,...)
    end
    local ok,err=pcall(function()
        local equipment=handler.Shared.EquipmentService
        local function held()
            local item=equipment:GetEquipped(player)
            return typeof(item)=='Instance' and item or nil
        end
        local before=held()
        if not pause(tok,0.5) then return end

        local opts=c.options or {}
        if not opts.NoSend then
            local packet={Type='Interact',Target=c.object,Path=c.path or '1'}
            if opts.SendData then
                for k,v in pairs(opts.SendData) do packet[k]=v end
            end
            handler.net:FireServer(packet)
        end

        task.spawn(function()
            pcall(c.callback)
        end)

        task.spawn(function()
            task.wait(0.6)
            if not act.food then
                local fallbackFood=FOOD_PRIORITY[1]
                act.food=fallbackFood
                handler.net:FireServer({Type='TakeQuickFood',Name=fallbackFood})
            end
        end)

        local t=os.clock()
        -- No resend of TakeQuickFood: each accepted request is a purchase. The native callback attaches the player to the
        -- fridge first and aborts if already attached (e.g. still seated), hence the detach at the start.
        while (not held() or held()==before) and os.clock()-t<12 do
            if not pause(tok,0.25) then return end
        end
        local item=held()
        if not item or item==before then
            log('mood_meal_fail','food='..tostring(act.food)..' sit='..tostring(player.Character:FindFirstChildOfClass('Humanoid').Sit))
            error('no_meal_equipped')
        end
        if not gate(tok) then return end

        local h0=mood.values.Hunger or 0
        local eatStart=os.clock()
        while held() and os.clock()-eatStart<15 do
            handler.net:FireServer({Type='EatEquipped',IsQuick=true})
            pcall(function()
                local eb=player.PlayerGui.HUDGui.Hotbar.LayoutContainer:FindFirstChild('EquippedButton',true)
                if eb then for _,conn in ipairs(getconnections(eb.Activated) or {}) do conn:Fire() end end
            end)
            if not pause(tok,1) then return end
            readMood()
            if (mood.values.Hunger or 0)>=mood.target then break end
        end
        readMood()
        act.gained=(mood.values.Hunger or 0)-h0
    end)
    lfh.ShowList=original
    if not ok then error(err,0) end
end
local function anyTeacherStageEnabled()
    return state.stageOn.pass or state.stageOn.scold or state.stageOn.board
end
local function moodFinish(reason,ok)
    mood.cooldownUntil=os.clock()+mood.cooldown
    mood.phase='idle' mood.busy=false mood.action=nil
    if ok==false then mood.enabled=false end
    log('mood_done',reason..' enabled='..tostring(mood.enabled))
end
local function moodStep()
    local now=mood.clock or 0
    local phase=mood.phase
    local earnings=state:MoodEarnings()
    if phase=='idle' then
        if not mood.enabled or os.clock()<mood.cooldownUntil or state.pending then return false end
        if not readMood() then return false end
        local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
        if not root then return false end
        local atHome=isAtHome(root)
        if line:IsRunning() then return false end
        if atHome then
            -- A manual home fill runs once. Natural decay cannot start another home loop.
            if mood.homePrepared then return false end
            if (mood.lowestValue or 100)>=mood.startBelow then return false end
            mood.returnSatisfied=false
            mood.capped={}
            mood.phase='home' mood.startLowest=mood.lowestValue mood.trips+=1 mood.busy=false
            mood.homeStart=now
            stopWalking()
            log('mood_home_start',mood.lowest..'='..math.round(mood.lowestValue)..' status='..tostring(mood.status))
            return true
        else
            if not handler:IsWorking(teacher.Script) or not anyTeacherStageEnabled() then return false end
            local critical=(mood.lowestValue or 100)<mood.startBelow
            local milestone=earnings and earnings>=mood.nextEarnings
            if not critical and not milestone then return false end
            if milestone then
                -- Consume the milestone before leaving; a delayed/resetting payout cannot retrigger it.
                mood.nextEarnings=(math.floor(earnings/mood.earningsTarget)+1)*mood.earningsTarget
                if not critical and moodReadyForWork() then log('mood_skip','milestone, needs ok min='..math.round(mood.lowestValue)) return false end
            end
            mood.triggerEarnings=earnings
            mood.homePrepared=false
            mood.returnSatisfied=false
            mood.capped={}
            mood.phase='leaving' mood.startLowest=mood.lowestValue mood.trips+=1 mood.busy=false
            stopWalking()
            log('mood_leave','earnings='..tostring(earnings)..' next='..tostring(mood.nextEarnings)..' min='..math.round(mood.lowestValue))
            return true
        end
    elseif phase=='leaving' then
        state.stage='mood_leaving'
        if mood.busy then return true end
        mood.busy=true
        local tok=mood.token
        task.spawn(function()
            local ok,err=pcall(function()
                if not gate(tok) then return end
                dismissPopups()
                local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
                local from=root and root.Position
                if handler:IsWorking(teacher.Script) then handler:StopWorking() end
                local t=os.clock()
                while handler:IsWorking(teacher.Script) and os.clock()-t<5 do
                    if not pause(tok,0.2) then return end
                end
                if not pause(tok,0.5) then return end
                handler.Modules.HouseHandler:ToPlot()
                if not pause(tok,1) then return end
                root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
                mood.moved=root and from and (root.Position-from).Magnitude or 0
            end)
            if not state.alive or mood.token~=tok then return end
            if not ok then log('mood_error',tostring(err)) mood.moved=0 end
            mood.phase=(mood.moved or 0)>20 and 'home' or 'return'
            mood.homeStart=mood.clock or 0 mood.busy=false
            log('mood_home','moved='..math.round(mood.moved or 0))
        end)
        return true
    elseif phase=='home' then
        dismissPopups()
        local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
        local humanoid=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
        if not root or not humanoid or humanoid.Health<=0 then return true end
        if not readMood() then
            moodDetach() moodFinish('mood_stats_unavailable',false)
            return true
        end
        -- Accept healthy decay during the visit instead of cycling through already filled needs.
        if moodReadyForWork() and not mood.busy and (not mood.action or mood.action.returned) then
            mood.returnSatisfied=true mood.homePrepared=true
            mood.lastFull={time=now,values=table.clone(mood.values),overall=mood.overall}
            mood.action=nil mood.retryAt=nil mood.waitingFor=nil
            moodDetach()
            log('mood_ready',string.format('overall=%.2f min=%.2f',mood.overall,mood.lowestValue))
            if anyTeacherStageEnabled() then mood.phase='return' else moodFinish('healthy_needs',true) end
            return true
        end
        local act=mood.action
        if act then
            local plot=workspace.Plots:FindFirstChild('Plot_'..player.Name)
            if not plot or not act.object:IsDescendantOf(plot) then
                moodDetach()
                mood.action=nil
                mood.retryAt=nil
                log('mood_target_removed',act.label)
                return true
            end
            local value=mood.values[act.need.name] or 0
            local gained=value-act.startValue
            state.stage='mood_'..act.need.name:lower()..'_'..math.round(value)
            if act.label=='I_TurnOn' and act.returned then
                -- Give the server time to flag the TV as on; re-dispatching would toggle it off again.
                mood.action=nil mood.retryAt=now+2
                return true
            end
            if act.label=='I_TakeQuickMeal' then
                if act.returned then
                    log('mood_meal_done','gained='..(math.round(gained*10)/10)..' now='..math.round(value)..(act.food and (' food='..act.food) or ''))
                    mood.action=nil
                elseif now-act.started>20 then
                    log('mood_meal_timeout',act.label)
                    mood.failed[act.object]=os.clock()+30
                    mood.action=nil
                end
                return true
            end
            if value>=mood.fillTarget then
                log('mood_need_ok',act.need.name..'='..math.round(value))
                mood.action=nil
                moodDetach()
            elseif now-act.started>mood.actionMax or (act.returned and gained<1 and now-act.started>20) then
                log('mood_action_failed',act.label..' gained='..(math.round(gained*10)/10))
                mood.failed[act.object]=os.clock()+60
                mood.action=nil
                moodDetach()
            end
            return true
        end
        if now-mood.homeStart>mood.homeMax then
            moodDetach() moodFinish('home_timeout_below_healthy',false)
            log('mood_home_timeout')
            return true
        end
        if mood.retryAt and now<mood.retryAt then return true end
        mood.retryAt=nil
        local pick
        local missing={}
        for _,need in ipairs(NEEDS) do
            local value=mood.values[need.name] or 0
            if value<mood.minReturn and not needCapped(need.name) then
                local target=findMoodTarget(need,root)
                if target then
                    if not pick or value<pick.value then pick={need=need,target=target,value=value} end
                else
                    table.insert(missing,need.name)
                end
            end
        end
        if not pick then
            if mood.waitingFor~=table.concat(missing,',') then log('mood_wait_targets',table.concat(missing,',')) end
            mood.waitingFor=table.concat(missing,',')
            mood.retryAt=now+1
            state.stage='mood_wait_'..mood.waitingFor
            return true
        end
        mood.waitingFor=nil
        state.stage='mood_to_'..pick.need.name:lower()
        local c=pick.target
        if inInner(c.object,root) then
            stopWalking()
            local act={need=pick.need,label=c.label,object=c.object,started=now,startValue=pick.value}
            mood.action=act
            log('mood_use',c.label..' '..pick.need.name..'='..math.round(pick.value)..' '..c.object.Name)
            local tok=mood.token
            task.spawn(function()
                local ok,err=pcall(function()
                    if c.label=='I_TakeQuickMeal' then
                        takeAndEat(c,tok,act)
                    else
                        if not gate(tok) then return end
                        -- Native Attach (toilet, bed, sofa) aborts while the previous seat is still attached server-side.
                        detachMoodNative()
                        local wait=(state.detachedAt or 0)+0.8-os.clock()
                        if wait>0 and not pause(tok,wait) then return end
                        moodDispatch(c)
                        if c.label=='I_Watch' then moodSeat(c,root,tok) end
                    end
                end)
                if mood.token~=tok then return end
                if not ok then
                    state.errors+=1
                    log('mood_callback_error',tostring(err))
                    if c.label=='I_TakeQuickMeal' and tostring(err):find('no_meal_equipped') and (mood.values.Hunger or 0)>=CAPPED_MIN then
                        mood.capped=mood.capped or {}
                        mood.capped.Hunger=true
                        log('mood_capped','Hunger='..math.round(mood.values.Hunger or 0))
                    end
                    mood.failed[c.object]=os.clock()+(c.label=='I_TakeQuickMeal' and 12 or 60)
                    mood.action=nil
                elseif mood.action==act then
                    act.returned=true
                end
            end)
        else
            if not moodWaypoint(c,root) then mood.failed[c.object]=os.clock()+30 end
        end
        return true
    elseif phase=='return' then
        state.stage='mood_returning'
        if mood.busy then return true end
        mood.busy=true
        local tok=mood.token
        task.spawn(function()
            local ok,err=pcall(function()
                if not gate(tok) then return end
                stopWalking()
                dismissPopups()
                local humanoid=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
                moodDetach()
                if not pause(tok,0.5) then return end
                local t=os.clock()
                while not handler:IsWorking(teacher.Script) and os.clock()-t<30 do
                    if not gate(tok) then return end
                    dismissPopups()
                    if handler:HasOngoingJob() and not handler:IsWorking(teacher.Script) then
                        handler:StopWorking()
                        if not pause(tok,1) then return end
                    elseif not handler:GoToWork(jobKey) then
                        if not pause(tok,2) then return end
                    else
                        local w=os.clock()
                        while not handler:IsWorking(teacher.Script) and os.clock()-w<4 do
                            if not pause(tok,0.3) then return end
                        end
                        if not gate(tok) then return end
                        if not handler:IsWorking(teacher.Script) then
                            handler:StartWorking(jobKey)
                            if not pause(tok,2) then return end
                        end
                    end
                end
            end)
            if not state.alive or mood.token~=tok then return end
            readMood()
            local back=handler:IsWorking(teacher.Script)
            if not ok then log('mood_error',tostring(err)) end
            local gained=(mood.lowestValue or 0)-(mood.startLowest or 0)
            moodFinish('back='..tostring(back)..' gained='..math.round(gained),back and (mood.returnSatisfied==true))
        end)
        return true
    end
    return false
end
function state:MoodStatus()
    readMood()
    local out={}
    for _,need in ipairs(NEEDS) do out[#out+1]=need.name..'='..math.round(mood.values[need.name] or -1) end
    local earnings=self:MoodEarnings()
    return string.format('%s phase=%s enabled=%s trips=%d earnings=%s next=%s ready=%s %s',tostring(mood.status),mood.phase,tostring(mood.enabled),mood.trips,tostring(earnings),tostring(mood.nextEarnings),tostring(moodReadyForWork()),table.concat(out,' '))
end
-- Read-only discovery for checking a rebuilt house without starting a trip.
function state:MoodTargets()
    local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    local out={}
    if not root then return out end
    for _,need in ipairs(NEEDS) do
        local c=findMoodTarget(need,root)
        out[need.name]=c and {name=c.object.Name,label=c.label,distance=math.round(c.d),path=c.path} or false
    end
    return out
end
local function tickLoop()
    if not state.enabled then stopWalking() state.stage='paused' return end
    if input:GetFocusedTextBox() then releaseMouse() stopWalking() state.stage='typing' return end
    if mood.phase~='idle' or mood.enabled then
        local ok,owned=pcall(moodStep)
        if not ok then
            log('mood_error',tostring(owned)) mood.enabled=false moodCancel('error')
        elseif owned then return end
    end
    if not handler:IsWorking(teacher.Script) then
        releaseMouse() stopWalking() state.pending=nil
        local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
        if root and isAtHome(root) then
            state.stage=mood.enabled and 'mood_idle_at_home' or 'at_home_waiting'
        else
            state.stage='waiting_for_teacher_shift'
        end
        return
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
        if state.pending and state.pending.label=='B_Interact' and state.stageOn.board then
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
    -- Hub filter: drop stages switched off, before the delivery priority below.
    for _,list in ipairs({routes,candidates}) do
        for i=#list,1,-1 do
            if not state.stageOn[STAGE_OF[list[i].label]] then table.remove(list,i) end
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
log('started',state.version..' hub')
task.spawn(function()
    while state.alive and env.MesaTeacherLoop==state do
        local ok,err=xpcall(tickLoop,debug.traceback)
        if not ok then
            releaseMouse() stopWalking() state.errors+=1 state.enabled=false state.stage='error_paused'
            log('error',tostring(err))
        end
        task.wait(0.05)
    end
    releaseMouse() stopWalking()
end)

