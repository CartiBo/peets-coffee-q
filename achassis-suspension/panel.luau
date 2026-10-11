-- Mojave Valley / Potassium. Vehicle presets are locked locally per car instance.
-- Baselines are captured from physical parts, not guessed from the Tune module.
local PLACE = 94539932414164
if game.PlaceId ~= PLACE then return 'Este panel corresponde a Mojave Valley.' end
local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local Tween = game:GetService('TweenService')
local player = Players.LocalPlayer
local env = getgenv()
local migrated={}
local previousSettings,previousPower
if env.MojaveSuspensionPanel then
    local previous=env.MojaveSuspensionPanel
    local active=previous.car and previous.records[previous.car]
    previousSettings=previous.general or (active and active.settings)
    previousPower=previous.power
    for car,r in pairs(env.MojaveSuspensionPanel.records) do
        if r.settings then migrated[car]={F=table.clone(r.settings.F),R=table.clone(r.settings.R)} end
    end
    env.MojaveSuspensionPanel:Destroy()
end
env.MojaveSuspensionRecords=env.MojaveSuspensionRecords or {}
local controller = {alive=true, connections={}, records=env.MojaveSuspensionRecords, car=nil, axle='F', dragging=nil}
local Http=game:GetService('HttpService')
local transport=request or http_request or (syn and syn.request)
local presets={}
local storageError
local function storage(method,body)
    if not transport then return nil,'Potassium no ofrece request HTTP.' end
    local ok,response=pcall(transport,{Url='http://127.0.0.1:16385/presets',Method=method,
        Headers={['Content-Type']='application/json'},Body=body and Http:JSONEncode(body) or nil})
    if not ok or not response or tonumber(response.StatusCode)~=200 then return nil,'No se pudo guardar/leer el preset local.' end
    local decoded,data=pcall(Http.JSONDecode,Http,response.Body)
    if not decoded then return nil,'Respuesta de presets invalida.' end
    return data
end
presets,storageError=storage('GET')
presets=presets or {}
-- One general preset per account and game, independent of car name/springs.
local generalKey='general:'..PLACE..':'..player.UserId
local function copySettings(settings)
    return {F=table.clone(settings.F),R=table.clone(settings.R)}
end
controller.general=presets[generalKey] or previousSettings
if not controller.general then
    -- Recover this account's old preset, never another driver's settings.
    local marker='|'..player.Name.."'s Car|"
    for key,settings in pairs(presets) do
        if string.find(key,marker,1,true) then
            controller.general=copySettings(settings)
            break
        end
    end
end
local function queueGeneral(settings)
    controller.general=copySettings(settings)
    presets[generalKey]=copySettings(settings)
    controller.pending=copySettings(settings)
    controller.revision=(controller.revision or 0)+1
    controller.saveAfter=os.clock()+0.6
end
if controller.general then queueGeneral(controller.general) end
-- Engine stage and drivetrain: their own preset, applied through the car attributes
-- (HorsepowerMultiplier / DrivetrainType / AWDBias) that Drive (1.4) reads when it starts.
local powerKey='power:'..PLACE..':'..player.UserId
local DRIVES={ORIG=true,FWD=true,RWD=true,AWD=true}
local STAGE_STEP=0.1 -- the garage sells Stage 1/2/3 as +10/+20/+30% horsepower
local function cleanPower(p)
    if type(p)~='table' then return nil end
    local stage,bias=tonumber(p.stage),tonumber(p.bias)
    return {stage=(stage and stage>=0 and stage<=3) and math.floor(stage) or 0,
        drive=DRIVES[p.drive] and p.drive or 'ORIG',
        bias=(bias and bias>=-1 and bias<=1) and bias or nil}
end
controller.power=cleanPower(presets[powerKey]) or cleanPower(previousPower) or cleanPower({})
controller.loaded=setmetatable({},{__mode='k'})
controller.sigLog=setmetatable({},{__mode='k'})
env.MojavePowerBase=env.MojavePowerBase or setmetatable({},{__mode='k'})
local powerBase=env.MojavePowerBase
local function queuePower()
    controller.powerPending=cleanPower(controller.power)
    controller.powerRevision=(controller.powerRevision or 0)+1
    controller.powerSaveAfter=os.clock()+0.6
end
env.MojaveSuspensionPanel = controller
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(controller.connections, c)
    return c
end
local COMPACT=0.72
local function pxOffset(x,y) return UDim2.fromOffset(math.round(x*COMPACT),math.round(y*COMPACT)) end
local function pxUDim(xs,xo,ys,yo) return UDim2.new(xs,math.round(xo*COMPACT),ys,math.round(yo*COMPACT)) end
local function create(class, props, parent)
    -- Text keeps a readable floor: sizes below ~11px render soft on Roblox.
    if props.TextSize then props.TextSize=math.max(11,math.round(props.TextSize*0.9)) end
    if class=='TextLabel' or class=='TextButton' or class=='TextBox' then
        props.TextScaled=false
        props.TextStrokeTransparency=1
    end
    local obj=Instance.new(class)
    for k,v in pairs(props) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local function corner(obj, radius) create('UICorner',{CornerRadius=UDim.new(0,math.round((radius or 8)*COMPACT))},obj) end
local gui=create('ScreenGui',{Name='MojaveSuspensionPanel',ResetOnSpawn=false,DisplayOrder=120, ZIndexBehavior=Enum.ZIndexBehavior.Sibling},player:WaitForChild('PlayerGui'))
controller.gui=gui
local TEAL,MINT=Color3.fromRGB(134,171,170),Color3.fromRGB(181,204,201)
-- Native compact pixels preserve text clarity; no offscreen CanvasGroup resampling.
local PANEL_H=632
local panel=create('Frame',{Name='SuspensionHub',Size=pxOffset(380,PANEL_H),Position=pxUDim(0,24,0.5,-PANEL_H/2),BackgroundColor3=Color3.fromRGB(7,8,10),BackgroundTransparency=0,BorderSizePixel=0,ClipsDescendants=true},gui)
corner(panel,22)
local panelStroke=create('UIStroke',{Color=Color3.fromRGB(27,30,35),Transparency=0.9,Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},panel)
create('UIGradient',{Color=ColorSequence.new(Color3.fromRGB(13,137,124),Color3.fromRGB(60,78,96),Color3.fromRGB(34,44,58)),Rotation=120},panelStroke)
create('UIGradient',{Color=ColorSequence.new(Color3.fromRGB(7,8,10),Color3.fromRGB(15,17,20)),Rotation=110},panel)
local scale=create('UIScale',{Scale=1},panel)
local home=pxOffset(16,40)
local function fitPanel()
    local camera=workspace.CurrentCamera
    if camera then
        local panelH=PANEL_H*COMPACT
        scale.Scale=math.min(1,math.max(0.5,math.min((camera.ViewportSize.X-32)/274,(camera.ViewportSize.Y-32)/panelH)))
        home=UDim2.fromOffset(16,math.round(math.max(16,(camera.ViewportSize.Y-panelH*scale.Scale)/2)))
        if controller.shown then panel.Position=home end
    end
end
fitPanel()
if workspace.CurrentCamera then connect(workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'),fitPanel) end
-- Decorative effects stay behind controls and never capture input.
local effects=create('Frame',{Name='WaterAndSweep',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,ClipsDescendants=true,Active=false,ZIndex=0},panel)
corner(effects,22)
local sweep=create('Frame',{Name='SoftNeonSweep',Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(70,230,210),BorderSizePixel=0,Active=false,ZIndex=0},effects)
local sweepGradient=create('UIGradient',{Rotation=25,Offset=Vector2.new(-1.4,0),Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.35,1),NumberSequenceKeypoint.new(0.5,0.84),NumberSequenceKeypoint.new(0.65,1),NumberSequenceKeypoint.new(1,1)})},sweep)
local sweepTween=Tween:Create(sweepGradient,TweenInfo.new(5,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,false,1.5),{Offset=Vector2.new(1.4,0)})
sweepTween:Play()
controller.effectTweens={sweepTween}
-- Feathered line: translucent halos around a barely visible one-pixel center.
for _,layer in ipairs({{7,0.985},{4,0.975},{1,0.93}}) do
    local line=create('Frame',{Name='FeatheredLine',Size=pxUDim(1,-40,0,layer[1]),Position=pxOffset(20,73-layer[1]/2),BackgroundColor3=Color3.fromRGB(167,195,193),BackgroundTransparency=layer[2],BorderSizePixel=0,Active=false,ZIndex=0},effects)
    corner(line,4)
    create('UIGradient',{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.25,0.4),NumberSequenceKeypoint.new(0.5,0),NumberSequenceKeypoint.new(0.75,0.4),NumberSequenceKeypoint.new(1,1)})},line)
end
local lastDrop=0
local function waterDrop(point)
    if os.clock()-lastDrop<0.18 then return end
    lastDrop=os.clock()
    local localPoint=(Vector2.new(point.X,point.Y)-panel.AbsolutePosition)/scale.Scale
    for _,layer in ipairs({{1,0.89},{3,0.975},{6,0.99}}) do
        local ring=create('Frame',{Name='WaterDrop',AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(4,4),Position=UDim2.fromOffset(math.round(localPoint.X),math.round(localPoint.Y)),BackgroundTransparency=1,BorderSizePixel=0,Active=false,ZIndex=0},effects)
        create('UICorner',{CornerRadius=UDim.new(1,0)},ring)
        local stroke=create('UIStroke',{Color=Color3.fromRGB(178,201,204),Thickness=layer[1],Transparency=layer[2]},ring)
        local expand=Tween:Create(ring,TweenInfo.new(0.85,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(106,106)})
        Tween:Create(stroke,TweenInfo.new(0.85),{Transparency=1}):Play()
        expand:Play()
        expand.Completed:Connect(function() ring:Destroy() end)
    end
end
connect(UIS.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        local point=input.Position
        local origin,size=panel.AbsolutePosition,panel.AbsoluteSize
        if point.X>=origin.X and point.X<=origin.X+size.X and point.Y>=origin.Y and point.Y<=origin.Y+size.Y then waterDrop(point) end
    end
end)
local dot=create('Frame',{Size=pxOffset(10,10),Position=pxOffset(22,22),BackgroundColor3=Color3.fromRGB(110,124,140),BorderSizePixel=0},panel)
corner(dot,5)
create('TextLabel',{Size=pxOffset(250,14),Position=pxOffset(40,20),Text='MOJAVE  ·  GARAGE',TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,TextSize=10,TextColor3=TEAL,BackgroundTransparency=1},panel)
local header=create('TextButton',{Size=pxUDim(1,-84,0,30),Position=pxOffset(40,36),Text='A-Chassis Suspension',TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,TextSize=18,TextColor3=Color3.fromRGB(235,240,243),BackgroundTransparency=1,AutoButtonColor=false},panel)
local toggle=create('TextButton',{Size=pxOffset(34,34),Position=pxUDim(1,-54,0,21),Text='−',Font=Enum.Font.GothamBold,TextSize=20,TextColor3=Color3.fromRGB(214,229,226),BackgroundColor3=Color3.fromRGB(28,31,36),BorderSizePixel=0,AutoButtonColor=false},panel)
corner(toggle,17)
create('UIStroke',{Color=TEAL,Transparency=0.6,Thickness=1},toggle)
-- Keep input controls in a regular Frame: nested CanvasGroups can swallow input.
local body=create('Frame',{Name='Controls',Size=pxUDim(1,0,1,-76),Position=pxOffset(0,76),BackgroundTransparency=1,Active=true,ZIndex=2},panel)
local status=create('TextLabel',{Name='VehicleStatus',Size=pxUDim(1,-40,0,46),Position=pxOffset(20,0),Text='Buscando tu carro...',TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=Color3.fromRGB(181,190,200),BackgroundColor3=Color3.fromRGB(20,23,28),BorderSizePixel=0},body)
corner(status,12)
create('UIStroke',{Color=Color3.fromRGB(80,110,128),Transparency=0.6,Thickness=1},status)
create('UIPadding',{PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,12)},status)
local function hover(button)
    local press=create('UIScale',{Scale=1},button)
    local fast=TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
    connect(button.MouseEnter,function() Tween:Create(button,TweenInfo.new(0.15),{BackgroundTransparency=0.2}):Play() end)
    connect(button.MouseLeave,function()
        Tween:Create(button,TweenInfo.new(0.15),{BackgroundTransparency=0}):Play()
        Tween:Create(press,fast,{Scale=1}):Play()
    end)
    connect(button.MouseButton1Down,function() Tween:Create(press,fast,{Scale=0.95}):Play() end)
    connect(button.MouseButton1Up,function() Tween:Create(press,TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end)
end
hover(toggle)
local tabs={}
local tabIndicator
local refreshPower
local rows={}
local specs={
    {key='offset',label='Offset lateral',unit='stud',min=-0.6,max=0.6,step=0.02,default=0},
    {key='height',label='Altura de suspensión',unit='stud',min=-0.5,max=0.5,step=0.02,default=0},
    {key='damping',label='Amortiguación',unit='',min=0,max=2000,step=25,default=200},
    {key='stiffness',label='Rigidez',unit='',min=500,max=15000,step=100,default=5000},
    {key='camber',label='Camber',unit='°',min=-12,max=12,step=0.5,default=0},
}
local function seatedCar()
    local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
    local seat=h and h.SeatPart
    if not seat or not seat:IsA('VehicleSeat') or seat.Occupant~=h then return nil end
    local c=seat.Parent
    if c and c:FindFirstChild('A-Chassis Tune') and c:FindFirstChild('Wheels') then return c,seat end
end
local function restore(record)
    for _,b in ipairs(record.wheels) do
        if b.spring.Parent then
            b.spring.FreeLength=b.free
            b.spring.MinLength=b.min
            b.spring.MaxLength=b.max
            b.spring.Damping=b.damping
            b.spring.Stiffness=b.stiffness
        end
        if b.joint and b.joint.Parent then b.joint.C1=b.c1 end
    end
    record.settings=nil
end
local function capture(car, seat)
    local r={car=car,seat=seat,wheels={},settings={F={},R={}}}
    for _,w in ipairs(car.Wheels:GetChildren()) do
        local spring=w:FindFirstChild('Spring')
        if spring and spring:IsA('SpringConstraint') and (w.Name=='FL' or w.Name=='FR' or w.Name=='RL' or w.Name=='RR') then
            local axle=w:FindFirstChild('Axle')
            local hub=w:FindFirstChild('AxleP')
            local joint=hub and hub:FindFirstChild('Weld')
            if not (joint and joint:IsA('Weld') and joint.Part0==hub and joint.Part1==axle) then joint=nil end
            local group=string.sub(w.Name,1,1)
            table.insert(r.wheels,{spring=spring,free=spring.FreeLength,min=spring.MinLength,max=spring.MaxLength,damping=spring.Damping,stiffness=spring.Stiffness,joint=joint,c1=joint and joint.C1,axle=axle,group=group,side=string.sub(w.Name,2,2)=='L' and -1 or 1})
            r.settings[group]={offset=0,height=0,damping=spring.Damping,stiffness=spring.Stiffness,camber=0}
        end
    end
    if #r.wheels~=4 then return nil,'No se reconocen los cuatro resortes de este chasis.' end
    local fingerprint={car.Name}
    for _,b in ipairs(r.wheels) do
        table.insert(fingerprint,string.format('%s:%s:%.4f:%.4f:%.4f:%.4f:%.4f',b.group,b.side,b.free,b.min,b.max,b.damping,b.stiffness))
    end
    table.sort(fingerprint)
    r.key=table.concat(fingerprint,'|')
    r.saved=migrated[car] or controller.general
    controller.records[car]=r
    return r
end
local function saveRecord(r)
    -- This vehicle keeps its own snapshot when its occupant changes. The general
    -- preset is only a default for vehicles that have never been adjusted here.
    r.lockedSettings=copySettings(r.settings)
    queueGeneral(r.settings)
end
local function apply(group,key,value,recovering)
    local car,seat=seatedCar()
    if not car or not seat or car~=controller.car then status.Text='Sientate en tu carro para ajustar.' return false end
    if not recovering and seat.AssemblyLinearVelocity.Magnitude>5 then status.Text='Deten el carro para ajustar la suspension.' return false end
    local r=controller.records[car]
    if not r or not r.settings then return false end
    if key=='offset' or key=='camber' then
        for _,b in ipairs(r.wheels) do if b.group==group and not b.joint then status.Text='Este cubo no permite offset/camber.' return false end end
    end
    r.settings[group][key]=value
    local s=r.settings[group]
    for _,b in ipairs(r.wheels) do if b.group==group then
        -- Translate the original spring length and travel together: no accumulation.
        b.spring.MinLength=math.max(0,b.min+s.height)
        b.spring.MaxLength=math.max(b.spring.MinLength+0.05,b.max+s.height)
        b.spring.FreeLength=math.max(0.05,b.free+s.height)
        b.spring.Damping=s.damping
        b.spring.Stiffness=s.stiffness
        if b.joint then
            -- Move the physical AxleP hub: motor and brake hinges stay native.
            local outward=b.axle.CFrame:VectorToObjectSpace(seat.CFrame.RightVector*b.side)
            local rollAxis=b.axle.CFrame:VectorToObjectSpace(seat.CFrame.LookVector)
            local rotation=CFrame.fromAxisAngle(rollAxis,math.rad(s.camber*b.side))
            b.joint.C1=CFrame.new(b.c1.Position+outward*s.offset)*rotation*b.c1.Rotation
            b.appliedC1=b.joint.C1
        end
    end end
    status.Text='Aplicado al eje '..(group=='F' and 'delantero' or 'trasero')..' · local'
    if not recovering then saveRecord(r) end
    return true
end
local function refresh()
    local r=controller.car and controller.records[controller.car]
    for group,button in pairs(tabs) do
        Tween:Create(button,TweenInfo.new(0.2),{TextColor3=group==controller.axle and Color3.fromRGB(12,17,18) or Color3.fromRGB(181,190,200)}):Play()
    end
    if tabIndicator then
        Tween:Create(tabIndicator,TweenInfo.new(0.28,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=pxOffset(controller.axle=='F' and 4 or 170,4)}):Play()
    end
    dot.BackgroundColor3=controller.car and TEAL or Color3.fromRGB(110,124,140)
    for _,spec in ipairs(specs) do
        local row=rows[spec.key]
        local val=r and r.settings and r.settings[controller.axle][spec.key] or spec.default
        row.box.Text=string.format(spec.step<1 and '%.2f' or '%.0f',val)
        local fraction=math.clamp((val-spec.min)/(spec.max-spec.min),0,1)
        Tween:Create(row.fill,TweenInfo.new(0.12),{Size=UDim2.fromScale(fraction,1)}):Play()
        Tween:Create(row.knob,TweenInfo.new(0.12),{Position=UDim2.fromScale(fraction,0.5)}):Play()
    end
    if refreshPower then refreshPower() end
end
-- Three sections: suspension, engine stages, drivetrain. Each page is a plain Frame.
local SECTIONS={'susp','engine','drive'}
local SECTION_LABELS={susp='SUSPENSIÓN',engine='MOTOR',drive='TRANSMISIÓN'}
local sectionBase=pxOffset(0,102)
local sectionBar=create('Frame',{Name='Sections',Size=pxOffset(340,40),Position=pxOffset(20,54),BackgroundColor3=Color3.fromRGB(20,23,28),BorderSizePixel=0},body)
corner(sectionBar,14)
create('UIStroke',{Color=Color3.fromRGB(80,110,128),Transparency=0.65,Thickness=1},sectionBar)
local sectionIndicator=create('Frame',{Size=pxOffset(110,32),Position=pxOffset(4,4),BackgroundColor3=TEAL,BorderSizePixel=0},sectionBar)
corner(sectionIndicator,11)
create('UIGradient',{Color=ColorSequence.new(MINT,TEAL),Rotation=90},sectionIndicator)
local sectionButtons,pages={}, {}
for i,key in ipairs(SECTIONS) do
    sectionButtons[key]=create('TextButton',{Size=pxOffset(110,32),Position=pxOffset(4+(i-1)*111,4),Text=SECTION_LABELS[key],Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.fromRGB(181,190,200),BackgroundTransparency=1,BorderSizePixel=0,AutoButtonColor=false,ZIndex=2},sectionBar)
    pages[key]=create('Frame',{Name='Page_'..key,Size=pxUDim(1,0,0,360),Position=sectionBase,BackgroundTransparency=1,BorderSizePixel=0,Visible=key=='susp'},body)
end
local pageS,pageE,pageD=pages.susp,pages.engine,pages.drive
local resetButton,legend
local function setSection(name)
    controller.section=name
    for i,key in ipairs(SECTIONS) do
        local on=key==name
        Tween:Create(sectionButtons[key],TweenInfo.new(0.2),{TextColor3=on and Color3.fromRGB(12,17,18) or Color3.fromRGB(181,190,200)}):Play()
        local page=pages[key]
        if on then
            Tween:Create(sectionIndicator,TweenInfo.new(0.28,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=pxOffset(4+(i-1)*111,4)}):Play()
            if not page.Visible then
                page.Position=sectionBase+pxOffset(14,0)
                page.Visible=true
                Tween:Create(page,TweenInfo.new(0.3,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=sectionBase}):Play()
            end
        else page.Visible=false end
    end
    if legend then legend.Visible=name=='susp' end
    if resetButton then resetButton.Text=name=='susp' and 'Restaurar suspensión' or (name=='engine' and 'Restaurar motor' or 'Restaurar tracción') end
end
for _,key in ipairs(SECTIONS) do connect(sectionButtons[key].Activated,function() setSection(key) end) end
local tabBar=create('Frame',{Size=pxOffset(340,40),Position=pxOffset(20,0),BackgroundColor3=Color3.fromRGB(20,23,28),BorderSizePixel=0},pageS)
corner(tabBar,14)
create('UIStroke',{Color=Color3.fromRGB(80,110,128),Transparency=0.65,Thickness=1},tabBar)
tabIndicator=create('Frame',{Size=pxOffset(166,32),Position=pxOffset(4,4),BackgroundColor3=TEAL,BorderSizePixel=0},tabBar)
corner(tabIndicator,11)
create('UIGradient',{Color=ColorSequence.new(MINT,TEAL),Rotation=90},tabIndicator)
for i,group in ipairs({'F','R'}) do
    local button=create('TextButton',{Size=pxOffset(166,32),Position=pxOffset(4+(i-1)*166,4),Text=group=='F' and 'EJE DELANTERO' or 'EJE TRASERO',Font=Enum.Font.GothamBold,TextSize=11,TextColor3=Color3.new(1,1,1),BackgroundTransparency=1,BorderSizePixel=0,AutoButtonColor=false,ZIndex=2},tabBar)
    tabs[group]=button
    connect(button.Activated,function() controller.axle=group refresh() end)
end
local function setValue(spec,value)
    if not value or value~=value or math.abs(value)==math.huge then refresh() return end
    value=math.clamp(math.round(value/spec.step)*spec.step,spec.min,spec.max)
    if spec.onSet then spec.onSet(value) return end
    apply(controller.axle,spec.key,value)
    refresh()
end
for i,spec in ipairs(specs) do
    local y=50+(i-1)*62
    local card=create('Frame',{Size=pxOffset(340,56),Position=pxOffset(20,y-3),BackgroundColor3=Color3.fromRGB(23,26,31),BorderSizePixel=0},pageS)
    corner(card,14)
    create('UIGradient',{Color=ColorSequence.new(Color3.fromRGB(27,30,35),Color3.fromRGB(20,23,27)),Rotation=90},card)
    local cardStroke=create('UIStroke',{Color=Color3.fromRGB(80,110,128),Transparency=0.7,Thickness=1},card)
    connect(card.MouseEnter,function() Tween:Create(cardStroke,TweenInfo.new(0.2),{Color=TEAL,Transparency=0.45}):Play() end)
    connect(card.MouseLeave,function() Tween:Create(cardStroke,TweenInfo.new(0.2),{Color=Color3.fromRGB(80,110,128),Transparency=0.7}):Play() end)
    create('TextLabel',{Size=pxOffset(224,22),Position=pxOffset(32,y),BackgroundTransparency=1,Text=spec.label..(spec.unit~='' and ' · '..spec.unit or ''),TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=Color3.fromRGB(222,228,235)},pageS)
    local box=create('TextBox',{Size=pxOffset(72,24),Position=pxOffset(276,y),BackgroundColor3=Color3.fromRGB(36,40,46),BorderSizePixel=0,TextColor3=Color3.fromRGB(214,229,226),Font=Enum.Font.GothamBold,TextSize=12,ClearTextOnFocus=false,Text='0'},pageS)
    corner(box,8)
    local boxStroke=create('UIStroke',{Color=TEAL,Transparency=0.8,Thickness=1},box)
    connect(box.Focused,function() Tween:Create(boxStroke,TweenInfo.new(0.15),{Transparency=0.1}):Play() end)
    connect(box.FocusLost,function() Tween:Create(boxStroke,TweenInfo.new(0.2),{Transparency=0.8}):Play() end)
    local track=create('TextButton',{Text='',AutoButtonColor=false,Size=pxOffset(316,22),Position=pxOffset(32,y+27),BackgroundTransparency=1,BorderSizePixel=0},pageS)
    local rail=create('Frame',{Size=pxUDim(1,0,0,6),Position=pxOffset(0,8),BackgroundColor3=Color3.fromRGB(36,40,46),BorderSizePixel=0},track)
    corner(rail,3)
    local fill=create('Frame',{Size=UDim2.fromScale(0.5,1),BackgroundColor3=TEAL,BorderSizePixel=0},rail)
    corner(fill,3)
    create('UIGradient',{Color=ColorSequence.new(Color3.fromRGB(116,159,155),MINT)},fill)
    local knob=create('Frame',{Size=pxOffset(16,16),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),BackgroundColor3=Color3.fromRGB(221,235,232),BorderSizePixel=0},rail)
    corner(knob,8)
    create('UIStroke',{Color=TEAL,Thickness=2.5},knob)
    rows[spec.key]={box=box,fill=fill,track=track,knob=knob}
    connect(box.FocusLost,function() setValue(spec,tonumber(box.Text)) end)
    connect(track.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            controller.dragging={spec=spec,track=track,input=input}
            setValue(spec,spec.min+math.clamp((input.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)*(spec.max-spec.min))
        end
    end)
end
-- ===== Engine stages and drivetrain =====
local ATTRS={hp='HorsepowerMultiplier',drive='DrivetrainType',bias='AWDBias'}
local CARD,LIGHT,MUTED,INK=Color3.fromRGB(23,26,31),Color3.fromRGB(222,228,235),Color3.fromRGB(166,177,188),Color3.fromRGB(12,17,18)
local function ownCar()
    local vehicles=workspace:FindFirstChild('PlayerVehicles')
    return vehicles and vehicles:FindFirstChild(player.Name.."'s Car")
end
local function carSig(car)
    return tostring(car:GetAttribute(ATTRS.hp))..'|'..tostring(car:GetAttribute(ATTRS.drive))..'|'..tostring(car:GetAttribute(ATTRS.bias))
end
local function tuneHp(car)
    local module=car and car:FindFirstChild('A-Chassis Tune')
    if not module then return nil end
    local ok,tune=pcall(require,module)
    return ok and type(tune)=='table' and tonumber(tune.Horsepower) or nil
end
local function enforcePower(car)
    -- The first value seen (or any later server change) is the car's own base; ours is written over it.
    local b=powerBase[car]
    if not b then b={set={}} powerBase[car]=b end
    local before=carSig(car)
    local p=controller.power
    local want={hp=p.stage>0 and math.floor((1+STAGE_STEP*p.stage)*100+0.5)/100 or nil,drive=p.drive~='ORIG' and p.drive or nil,bias=p.bias}
    for k,attr in pairs(ATTRS) do
        local cur=car:GetAttribute(attr)
        if cur~=b.set[k] then b[k]=cur end
        local target=want[k]
        if target==nil then target=b[k] end
        if cur~=target then car:SetAttribute(attr,target) end
        b.set[k]=target
    end
    if carSig(car)~=before then controller.sigLog[car]={old=before,t=os.clock()} end
end
local function reloadDrive(gui)
    -- Drive reads stage, drivetrain and aspiration once at start: restart it, never edit it.
    local drive
    for _,child in ipairs(gui:GetChildren()) do
        if child:IsA('LocalScript') and string.sub(child.Name,1,5)=='Drive' then drive=child break end
    end
    if not drive then return false end
    local fresh=drive:Clone()
    drive:Destroy()
    local controls=gui:FindFirstChild('Controls')
    if controls and controls:IsA('Folder') then controls:Destroy() end
    fresh.Parent=gui
    return true
end
local function tickPower(seated,seat)
    local own=ownCar()
    if own then enforcePower(own) end
    if seated and seated~=own then enforcePower(seated) end
    if not seated or seated~=controller.car then return end
    local gui=player.PlayerGui:FindFirstChild('A-Chassis Interface')
    local value=gui and gui:FindFirstChild('Car')
    if not value or value.Value~=seated then return end
    local cur=carSig(seated)
    local seen=controller.loaded[gui]
    if seen==nil then
        local log=controller.sigLog[seated]
        seen=(log and os.clock()-log.t<6) and log.old or cur
        controller.loaded[gui]=seen
    end
    if seen~=cur then
        if seat.AssemblyLinearVelocity.Magnitude>5 then status.Text='Frena para aplicar motor / tracción.' return end
        if reloadDrive(gui) then controller.loaded[gui]=cur status.Text='Motor y tracción aplicados.' end
    end
end
local function optionCard(parent,x,y,w,h,title,sub,level,onClick)
    local btn=create('TextButton',{Size=pxOffset(w,h),Position=pxOffset(x,y),Text='',AutoButtonColor=false,BackgroundColor3=CARD,BorderSizePixel=0},parent)
    corner(btn,14) hover(btn)
    local stroke=create('UIStroke',{Color=Color3.fromRGB(80,110,128),Transparency=0.7,Thickness=1},btn)
    local t=create('TextLabel',{Size=pxOffset(w-28,22),Position=pxOffset(14,12),BackgroundTransparency=1,Text=title,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,TextSize=15,TextColor3=LIGHT},btn)
    local s=create('TextLabel',{Size=pxOffset(w-28,18),Position=pxOffset(14,36),BackgroundTransparency=1,Text=sub,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamMedium,TextSize=11,TextColor3=MUTED},btn)
    local bars={}
    for i=1,level and 3 or 0 do
        local barH=6+i*4
        bars[i]=create('Frame',{Size=pxOffset(6,barH),Position=pxOffset(w-14-(4-i)*9,16+(18-barH)),BackgroundColor3=TEAL,BorderSizePixel=0,Active=false},btn)
        corner(bars[i],2)
    end
    local card={sub=s}
    function card.set(on)
        local info=TweenInfo.new(0.22,Enum.EasingStyle.Quint,Enum.EasingDirection.Out)
        Tween:Create(btn,info,{BackgroundColor3=on and TEAL or CARD}):Play()
        Tween:Create(t,info,{TextColor3=on and INK or LIGHT}):Play()
        Tween:Create(s,info,{TextColor3=on and Color3.fromRGB(28,48,48) or MUTED}):Play()
        Tween:Create(stroke,info,{Transparency=on and 1 or 0.7}):Play()
        for i,bar in ipairs(bars) do
            local filled=i<=level
            Tween:Create(bar,info,{BackgroundColor3=filled and (on and INK or TEAL) or (on and Color3.fromRGB(88,118,117) or Color3.fromRGB(45,50,57))}):Play()
        end
    end
    connect(btn.Activated,onClick)
    return card
end
local function sectionLabel(page,text)
    create('TextLabel',{Size=pxOffset(300,16),Position=pxOffset(24,0),BackgroundTransparency=1,Text=text,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,TextSize=10,TextColor3=TEAL},page)
end
local function infoCard(page,y,h)
    local card=create('Frame',{Size=pxOffset(340,h),Position=pxOffset(20,y),BackgroundColor3=CARD,BorderSizePixel=0},page)
    corner(card,14)
    create('UIStroke',{Color=Color3.fromRGB(80,110,128),Transparency=0.7,Thickness=1},card)
    return card
end
local powerChanged
local engineCards,driveCards={}, {}
sectionLabel(pageE,'STAGE DEL MOTOR')
for i,def in ipairs({{0,'ORIGINAL','Sin cambios'},{1,'STAGE 1','+10% potencia'},{2,'STAGE 2','+20% potencia'},{3,'STAGE 3','+30% potencia'}}) do
    local stage=def[1]
    engineCards[stage]=optionCard(pageE,20+((i-1)%2)*174,24+math.floor((i-1)/2)*92,166,84,def[2],def[3],stage,function()
        controller.power.stage=stage
        queuePower() powerChanged()
    end)
end
local hpCard=infoCard(pageE,212,92)
create('TextLabel',{Size=pxOffset(300,16),Position=pxOffset(14,10),BackgroundTransparency=1,Text='Potencia efectiva',TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamMedium,TextSize=11,TextColor3=MUTED},hpCard)
local hpValue=create('TextLabel',{Size=pxOffset(300,34),Position=pxOffset(14,28),BackgroundTransparency=1,Text='—',TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,TextSize=26,TextColor3=Color3.fromRGB(214,229,226)},hpCard)
local hpSub=create('TextLabel',{Size=pxOffset(300,16),Position=pxOffset(14,66),BackgroundTransparency=1,Text='Sin carro cerca',TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamMedium,TextSize=11,TextColor3=MUTED},hpCard)
create('TextLabel',{Size=pxOffset(340,32),Position=pxOffset(20,312),BackgroundTransparency=1,Text='Mismos porcentajes que el taller · solo local · se aplica con el carro detenido',TextWrapped=true,Font=Enum.Font.GothamMedium,TextSize=10,TextColor3=MUTED},pageE)
sectionLabel(pageD,'TRACCIÓN')
for i,def in ipairs({{'ORIG','ORIGINAL','De fábrica'},{'FWD','FWD','Delantera'},{'RWD','RWD','Trasera'},{'AWD','AWD','Integral'}}) do
    local key=def[1]
    driveCards[key]=optionCard(pageD,20+((i-1)%2)*174,24+math.floor((i-1)/2)*76,166,68,def[2],def[3],nil,function()
        controller.power.drive=key
        queuePower() powerChanged()
    end)
end
local biasCard=infoCard(pageD,184,56)
local biasLabel=create('TextLabel',{Size=pxOffset(224,22),Position=pxOffset(12,3),BackgroundTransparency=1,Text='Reparto trasero · %',TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=LIGHT},biasCard)
local biasBox=create('TextBox',{Size=pxOffset(72,24),Position=pxOffset(256,3),BackgroundColor3=Color3.fromRGB(36,40,46),BorderSizePixel=0,TextColor3=Color3.fromRGB(214,229,226),Font=Enum.Font.GothamBold,TextSize=12,ClearTextOnFocus=false,Text='50'},biasCard)
corner(biasBox,8)
local biasTrack=create('TextButton',{Text='',AutoButtonColor=false,Size=pxOffset(316,22),Position=pxOffset(12,30),BackgroundTransparency=1,BorderSizePixel=0},biasCard)
local biasRail=create('Frame',{Size=pxUDim(1,0,0,6),Position=pxOffset(0,8),BackgroundColor3=Color3.fromRGB(36,40,46),BorderSizePixel=0},biasTrack)
corner(biasRail,3)
local biasFill=create('Frame',{Size=UDim2.fromScale(0.5,1),BackgroundColor3=TEAL,BorderSizePixel=0},biasRail)
corner(biasFill,3)
local biasKnob=create('Frame',{Size=pxOffset(16,16),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),BackgroundColor3=Color3.fromRGB(221,235,232),BorderSizePixel=0},biasRail)
corner(biasKnob,8)
create('UIStroke',{Color=TEAL,Thickness=2.5},biasKnob)
create('TextLabel',{Size=pxOffset(340,44),Position=pxOffset(20,252),BackgroundTransparency=1,Text='Original conserva la tracción de fábrica. El reparto solo actúa en AWD. Solo local · se aplica con el carro detenido',TextWrapped=true,Font=Enum.Font.GothamMedium,TextSize=10,TextColor3=MUTED},pageD)
local biasSpec={key='bias',min=0,max=100,step=5,onSet=function(rear)
    controller.power.bias=math.clamp(rear/50-1,-1,1)
    queuePower() powerChanged()
end}
connect(biasBox.FocusLost,function() setValue(biasSpec,tonumber(biasBox.Text)) end)
connect(biasTrack.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        controller.dragging={spec=biasSpec,track=biasTrack,input=input}
        setValue(biasSpec,math.clamp((input.Position.X-biasTrack.AbsolutePosition.X)/biasTrack.AbsoluteSize.X,0,1)*100)
    end
end)
refreshPower=function()
    local p=controller.power
    for stage,card in pairs(engineCards) do card.set(p.stage==stage) end
    for key,card in pairs(driveCards) do card.set(p.drive==key) end
    local car=ownCar() or controller.car
    local b=car and powerBase[car]
    local factory=b and b.drive or (car and car:GetAttribute('FactoryDrivetrainType'))
    driveCards.ORIG.sub.Text='De fábrica · '..tostring(factory or '—')
    local effective=p.drive~='ORIG' and p.drive or factory
    biasCard.Visible=effective=='AWD'
    local rear=math.clamp(math.round(((p.bias or (b and tonumber(b.bias)) or 0)+1)*50),0,100)
    biasBox.Text=tostring(rear)
    Tween:Create(biasFill,TweenInfo.new(0.12),{Size=UDim2.fromScale(rear/100,1)}):Play()
    Tween:Create(biasKnob,TweenInfo.new(0.12),{Position=UDim2.fromScale(rear/100,0.5)}):Play()
    biasLabel.Text='Reparto F:R · '..(100-rear)..':'..rear
    local hp=tuneHp(car)
    local mult=car and math.clamp(tonumber(car:GetAttribute(ATTRS.hp)) or 1,1,1.3) or 1
    hpValue.Text=hp and string.format('%d hp',math.round(hp*mult)) or '—'
    hpSub.Text=hp and string.format('Base %d hp  ·  ×%.2f',math.round(hp),mult) or 'Sin carro cerca'
end
powerChanged=function()
    local own=ownCar()
    if own then enforcePower(own) end
    local seated=seatedCar()
    if seated and seated~=own then enforcePower(seated) end
    refreshPower()
    status.Text='Motor / tracción guardados · se aplican con el carro detenido.'
end
local reset=create('TextButton',{Size=pxOffset(236,38),Position=pxOffset(20,472),Text='Restaurar suspensión',Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.fromRGB(12,17,18),BackgroundColor3=TEAL,BorderSizePixel=0,AutoButtonColor=false},body)
resetButton=reset
corner(reset,12) hover(reset)
create('UIGradient',{Color=ColorSequence.new(MINT,Color3.fromRGB(161,189,184)),Rotation=90},reset)
local close=create('TextButton',{Size=pxOffset(92,38),Position=pxOffset(268,472),Text='Cerrar',Font=Enum.Font.GothamBold,TextSize=12,TextColor3=Color3.fromRGB(220,198,203),BackgroundColor3=Color3.fromRGB(30,25,29),BorderSizePixel=0,AutoButtonColor=false},body)
corner(close,12) hover(close)
create('UIStroke',{Color=Color3.fromRGB(255,120,140),Transparency=0.7,Thickness=1},close)
legend=create('TextLabel',{Size=pxOffset(360,24),Position=pxOffset(10,522),BackgroundTransparency=1,Text='Offset +: hacia fuera   ·   Camber −: hacia dentro',Font=Enum.Font.GothamMedium,TextSize=10,TextColor3=Color3.fromRGB(166,177,188)},body)
connect(reset.Activated,function()
    if controller.section=='engine' then
        controller.power.stage=0 queuePower() powerChanged() status.Text='Motor original restaurado.' return
    elseif controller.section=='drive' then
        controller.power.drive='ORIG' controller.power.bias=nil queuePower() powerChanged() status.Text='Tracción original restaurada.' return
    end
    local car,seat=seatedCar()
    if car and seat.AssemblyLinearVelocity.Magnitude<=5 and controller.records[car] then
        restore(controller.records[car])
        controller.records[car]=nil
        capture(car,seat)
        saveRecord(controller.records[car])
        status.Text='Valores originales restaurados.' refresh()
    else status.Text='Deten tu carro antes de restaurar.' end
end)
function controller:Destroy()
    if not self.alive then return end
    self.alive=false
    for _,t in ipairs(self.effectTweens or {}) do t:Cancel() end
    for _,c in ipairs(self.connections) do c:Disconnect() end
    if self.pending then
        local result=storage('POST',{key=generalKey,settings=self.pending})
        if result and result.saved then self.pending=nil end
    end
    if self.powerPending then
        local result=storage('POST',{key=powerKey,settings=self.powerPending})
        if result and result.saved then self.powerPending=nil end
    end
    self.gui:Destroy()
    if env.MojaveSuspensionPanel==self then env.MojaveSuspensionPanel=nil end
end
connect(close.Activated,function() controller:Destroy() end)
local collapsed=false
connect(toggle.Activated,function()
    collapsed=not collapsed toggle.Text=collapsed and '+' or '−'
    local token=(controller.collapseToken or 0)+1
    controller.collapseToken=token
    if not collapsed then body.Visible=true end
    -- The panel height tween supplies the transition without an input-blocking group.
    body.Visible=not collapsed
    local t=Tween:Create(panel,TweenInfo.new(0.32,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=pxOffset(380,collapsed and 76 or PANEL_H)})
    t:Play()
    t.Completed:Connect(function() if controller.collapseToken==token and collapsed then body.Visible=false end end)
end)
local windowDrag
connect(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then windowDrag={input=input,start=input.Position,pos=panel.Position} end
end)
connect(UIS.InputChanged,function(input)
    if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then
        local d=controller.dragging
        if d and (input.UserInputType~=Enum.UserInputType.Touch or input==d.input) then
            setValue(d.spec,d.spec.min+math.clamp((input.Position.X-d.track.AbsolutePosition.X)/d.track.AbsoluteSize.X,0,1)*(d.spec.max-d.spec.min))
        end
        if windowDrag and (input.UserInputType~=Enum.UserInputType.Touch or input==windowDrag.input) then
            local delta=input.Position-windowDrag.start
            panel.Position=windowDrag.pos+UDim2.fromOffset(math.round(delta.X),math.round(delta.Y))
        end
    end
end)
connect(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then controller.dragging=nil windowDrag=nil end
end)
connect(UIS.WindowFocusReleased,function() controller.dragging=nil windowDrag=nil end)
task.spawn(function()
    while controller.alive do
        local car,seat=seatedCar()
        if car~=controller.car then
            controller.car=car
            if car then
                local r=controller.records[car]
                local err
                if not r then r,err=capture(car,seat) end
                if r then
                    r.seat=seat
                    -- Never replace this car's preset with another car's settings
                    -- on reseating or a driver handoff. Existing records already
                    -- contain the applied values and their original baselines.
                    r.saved=r.lockedSettings or r.saved
                    if r.saved then
                        for _,group in ipairs({'F','R'}) do
                            for _,spec in ipairs(specs) do
                                local v=r.saved[group] and r.saved[group][spec.key]
                                if type(v)=='number' and v==v and v>=spec.min and v<=spec.max then apply(group,spec.key,v,true) end
                            end
                        end
                        r.saved=nil
                    end
                end
                status.Text=r and ('Preset del vehículo · bloqueo local') or err
            else status.Text='Ajustes conservados. Sientate para editar.' end
            refresh()
        end
        local powerOk,powerErr=pcall(tickPower,car,seat)
        if not powerOk then controller.powerError=tostring(powerErr) end
        for vehicle,r in pairs(controller.records) do
            if not vehicle.Parent then controller.records[vehicle]=nil
            else
                if r.settings then
                    for _,b in ipairs(r.wheels) do
                        local s=r.settings[b.group]
                        if b.spring.Parent then
                            b.spring.MinLength=math.max(0,b.min+s.height)
                            b.spring.MaxLength=math.max(b.spring.MinLength+0.05,b.max+s.height)
                            b.spring.FreeLength=math.max(0.05,b.free+s.height)
                            b.spring.Damping=s.damping
                            b.spring.Stiffness=s.stiffness
                        end
                        if b.appliedC1 and b.joint and b.joint.Parent then b.joint.C1=b.appliedC1 end
                    end
                end
            end
        end
        -- The pending save belongs to the panel, even if its car is removed.
        if controller.pending and os.clock()>=controller.saveAfter then
            local revision=controller.revision
            local result,err=storage('POST',{key=generalKey,settings=controller.pending})
            if result and result.saved then
                if revision==controller.revision then controller.pending=nil end
                status.Text='Preset guardado · vehículo conservado localmente.'
            else
                controller.saveAfter=os.clock()+5
                status.Text=err or 'No se pudo guardar el preset general.'
            end
        end
        if controller.powerPending and os.clock()>=controller.powerSaveAfter then
            local revision=controller.powerRevision
            local result,err=storage('POST',{key=powerKey,settings=controller.powerPending})
            if result and result.saved then
                if revision==controller.powerRevision then controller.powerPending=nil end
                status.Text='Motor y tracción guardados en tu preset.'
            else
                controller.powerSaveAfter=os.clock()+5
                status.Text=err or 'No se pudo guardar motor / tracción.'
            end
        end
        task.wait(0.5)
    end
end)
refresh()
setSection('susp')
-- Black compact hub: slide in without rasterizing text.
panel.Position=home-pxOffset(36,0)
local enter=TweenInfo.new(0.45,Enum.EasingStyle.Quint,Enum.EasingDirection.Out)
Tween:Create(panel,enter,{Position=home}):Play()
task.delay(0.46,function() controller.shown=true end)
return 'Hub A-Chassis actualizado: suspensión, motor y transmisión. Ajustes conservados.'
