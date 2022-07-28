-- Settings
local ESP = {
	Enabled = false,
	Players = true,
	Names = true,
    Distance = false,
	Boxes = true,
    Health = true,
    HealthOffsetX = 4,
    HealthOffsetY = -2,
    Items = false,
    ItemTextSize = 17,
	Tracers = false,
	FaceCamera = false,
	TeamColor = true,
	TeamMates = true,
	Font = "UI",
	TextSize = 15,
	BoxShift = CFrame.new(0, -1.5, 0),
	BoxSize = Vector3.new(4, 6, 0),
	Color = Color3.fromRGB(255, 170, 0),
	Thickness = 2,
	AttachShift = 1,
	Objects = setmetatable({}, { __mode = "kv" }),
	Overrides = {},
	IgnoreHumanoids = false,
}

--Declarations--
local cam = workspace.CurrentCamera
local plrs = game:GetService("Players")
local plr = plrs.LocalPlayer
local mouse = plr:GetMouse()

local V3new = Vector3.new
local WorldToViewportPoint = cam.WorldToViewportPoint

--Functions--
local function Draw(obj, props)
	local new = Drawing.new(obj)
	
	props = props or {}
	for i,v in pairs(props) do
		new[i] = v
	end
	return new
end

ESP.Draw = Draw

function ESP:GetTeam(p)
	local ov = self.Overrides.GetTeam
	if ov then
		return ov(p)
	end
	
	return p and p.Team
end

function ESP:IsTeamMate(p)
	local ov = self.Overrides.IsTeamMate
	if ov then
		return ov(p)
	end
	
	return self:GetTeam(p) == self:GetTeam(plr)
end

function ESP:GetColor(obj)
	local ov = self.Overrides.GetColor
	if ov then
		return ov(obj)
	end
	local p = self:GetPlrFromChar(obj)
	return p and self.TeamColor and p.Team and p.Team.TeamColor.Color or self.Color
end

function ESP:GetPlrFromChar(char)
	local ov = self.Overrides.GetPlrFromChar
	if ov then
		return ov(char)
	end
	
	return plrs:GetPlayerFromCharacter(char)
end

function ESP:Toggle(bool)
	self.Enabled = bool
	if not bool then
		for i,v in pairs(self.Objects) do
			if v.Type == "Box" then --fov circle etc
				if v.Temporary then
					v:Remove()
				else
					for i,v in pairs(v.Components) do
						v.Visible = false
					end
				end
			end
		end
	end
end

function ESP:GetBox(obj)
	return self.Objects[obj]
end

function ESP:AddObjectListener(parent, options)
	local function NewListener(c)
		if type(options.Type) == "string" and c:IsA(options.Type) or options.Type == nil then
			if type(options.Name) == "string" and c.Name == options.Name or options.Name == nil then
				if not options.Validator or options.Validator(c) then
					local box = ESP:Add(c, {
						PrimaryPart = type(options.PrimaryPart) == "string" and c:WaitForChild(options.PrimaryPart) or type(options.PrimaryPart) == "function" and options.PrimaryPart(c),
						Color = type(options.Color) == "function" and options.Color(c) or options.Color,
						ColorDynamic = options.ColorDynamic,
						Name = type(options.CustomName) == "function" and options.CustomName(c) or options.CustomName,
						IsEnabled = options.IsEnabled,
						RenderInNil = options.RenderInNil
					})
					--TODO: add a better way of passing options
					if options.OnAdded then
						coroutine.wrap(options.OnAdded)(box)
					end
				end
			end
		end
	end

	if options.Recursive then
		parent.DescendantAdded:Connect(NewListener)
		for i,v in pairs(parent:GetDescendants()) do
			coroutine.wrap(NewListener)(v)
		end
	else
		parent.ChildAdded:Connect(NewListener)
		for i,v in pairs(parent:GetChildren()) do
			coroutine.wrap(NewListener)(v)
		end
	end
end

local boxBase = {}
boxBase.__index = boxBase

function boxBase:Remove()
	ESP.Objects[self.Object] = nil
	for i,v in pairs(self.Components) do
		v.Visible = false
		v:Remove()
		self.Components[i] = nil
	end
end

function boxBase:Update()
	if not self.PrimaryPart then
		--warn("not supposed to print", self.Object)
		return self:Remove()
	end

	local color
	if ESP.Highlighted == self.Object then
	   color = ESP.HighlightColor
	else
		color = self.Color or self.ColorDynamic and self:ColorDynamic() or ESP:GetColor(self.Object) or ESP.Color
	end

	local allow = true
	if ESP.Overrides.UpdateAllow and not ESP.Overrides.UpdateAllow(self) then
		allow = false
	end
	if self.Player and not ESP.TeamMates and ESP:IsTeamMate(self.Player) then
		allow = false
	end
	if self.Player and not ESP.Players then
		allow = false
	end
	if self.IsEnabled and (type(self.IsEnabled) == "string" and not ESP[self.IsEnabled] or type(self.IsEnabled) == "function" and not self:IsEnabled()) then
		allow = false
	end
	if not workspace:IsAncestorOf(self.PrimaryPart) and not self.RenderInNil then
		allow = false
	end

	if not allow then
		for i,v in pairs(self.Components) do
			v.Visible = false
		end
		return
	end

	if ESP.Highlighted == self.Object then
		color = ESP.HighlightColor
	end

	local IsPlrHighlighted = (ESP.Highlighted == self.Object and self.Player ~= nil)

	--calculations--
	local cf = self.PrimaryPart.CFrame
	if ESP.FaceCamera then
		cf = CFrame.new(cf.p, cam.CFrame.p)
	end

	local distance = math.floor((cam.CFrame.p - cf.p).magnitude)
	if self.Player and ESP.UsePlrDistance and distance > ESP.MaxPlrDistance then
		for i,v in pairs(self.Components) do
			v.Visible = false
		end
		return
	end

	self.Distance = distance;

	local size = self.Size
	local locs = {
		TopLeft 	= cf * ESP.BoxShift * CFrame.new(size.X   / 2,  size.Y / 2, 0),
		TopRight 	= cf * ESP.BoxShift * CFrame.new(-size.X  / 2,  size.Y / 2, 0),
		BottomLeft 	= cf * ESP.BoxShift * CFrame.new(size.X   / 2, -size.Y / 2, 0),
		BottomRight = cf * ESP.BoxShift * CFrame.new(-size.X  / 2, -size.Y / 2, 0),
		TagPos 		= cf * ESP.BoxShift * CFrame.new(0,			 	size.Y / 2, 0),
		Torso 		= cf * ESP.BoxShift
	}

	if ESP.Boxes then
		local TopLeft, Vis1 = WorldToViewportPoint(cam, locs.TopLeft.p)
		local TopRight, Vis2 = WorldToViewportPoint(cam, locs.TopRight.p)
		local BottomLeft, Vis3 = WorldToViewportPoint(cam, locs.BottomLeft.p)
		local BottomRight, Vis4 = WorldToViewportPoint(cam, locs.BottomRight.p)

		if self.Components.Quad then
			if Vis1 or Vis2 or Vis3 or Vis4 then
				self.Components.Quad.Visible = true
				self.Components.Quad.PointA = Vector2.new(TopRight.X, TopRight.Y)
				self.Components.Quad.PointB = Vector2.new(TopLeft.X, TopLeft.Y)
				self.Components.Quad.PointC = Vector2.new(BottomLeft.X, BottomLeft.Y)
				self.Components.Quad.PointD = Vector2.new(BottomRight.X, BottomRight.Y)
				self.Components.Quad.Color = color

				self.Components.Quad.ZIndex = IsPlrHighlighted and 2 or 1
			else
				self.Components.Quad.Visible = false
			end
		end
	else
		self.Components.Quad.Visible = false
	end

    if ESP.Names then
        local TagPos, Vis5 = WorldToViewportPoint(cam, locs.TagPos.p)

        if Vis5 then
            self.Components.Name.Visible = true
            self.Components.Name.Position = Vector2.new(TagPos.X, TagPos.Y)
            self.Components.Name.Text = self.Name
            self.Components.Name.Color = color
        else
            self.Components.Name.Visible = false
        end
    else
        self.Components.Name.Visible = false
    end

	if ESP.Distance then
        local TagPos, Vis6 = WorldToViewportPoint(cam, locs.TagPos.p)

        if Vis6 then
            self.Components.Distance.Visible = true
            self.Components.Distance.Position = Vector2.new(TagPos.X, TagPos.Y + 28)
            self.Components.Distance.Text = math.floor((cam.CFrame.p - cf.p).magnitude) .."m"
            self.Components.Distance.Color = color
        else
            self.Components.Distance.Visible = false
        end
    else
        self.Components.Distance.Visible = false
    end
	
	if ESP.Tracers then
		local TorsoPos, Vis7 = WorldToViewportPoint(cam, locs.Torso.p)

		if Vis7 then
			self.Components.Tracer.Visible = true
			self.Components.Tracer.From = Vector2.new(TorsoPos.X, TorsoPos.Y)
			self.Components.Tracer.To = Vector2.new(cam.ViewportSize.X/2,cam.ViewportSize.Y/ESP.AttachShift)
			self.Components.Tracer.Color = color

			self.Components['Tracer'].ZIndex = IsPlrHighlighted and 2 or 1
		else
			self.Components.Tracer.Visible = false
		end
	else
		self.Components.Tracer.Visible = false
	end

    if ESP.Health then
        local TorsoPos, Vis8 = WorldToViewportPoint(cam, locs.Torso.p)
        
        if Vis8 then
            local TagPos = WorldToViewportPoint(cam, locs.TagPos.p)
            local DistanceOff = math.clamp((Vector2.new(TagPos.X, TagPos.Y) - Vector2.new(TorsoPos.X, TorsoPos.Y)).Magnitude, 2, math.huge)
            local b = (Vector2.new(TorsoPos.X - DistanceOff, TorsoPos.Y - DistanceOff*2) - Vector2.new(TorsoPos.X - DistanceOff, TorsoPos.Y + DistanceOff*2)).Magnitude
            local offset = nil;
			
	         if self.Object:FindFirstChildWhichIsA("Humanoid") then
                offset = self.Object.Humanoid.Health / self.Object.Humanoid.MaxHealth * b
	        end
            local hOffsetX = ESP.HealthOffsetX
            local hOffsetY = ESP.HealthOffsetY
            self.Components.Health.Visible = true
            self.Components.Health2.Visible = true
            
            self.Components.Health2.From = Vector2.new(TorsoPos.X - DistanceOff - hOffsetX, TorsoPos.Y - DistanceOff*hOffsetY)
            self.Components.Health2.To = Vector2.new(TorsoPos.X - DistanceOff - hOffsetX, TorsoPos.Y - DistanceOff*hOffsetY - offset)
            
            self.Components.Health.From = Vector2.new(TorsoPos.X - DistanceOff - hOffsetX, TorsoPos.Y - DistanceOff*hOffsetY)
            self.Components.Health.To = Vector2.new(TorsoPos.X - DistanceOff - hOffsetX, TorsoPos.Y - DistanceOff*hOffsetY)
            
            local g = Color3.fromRGB(0, 255, 8)
            local r = Color3.fromRGB(255, 0, 0)
            self.Components.Health2.Color = r:lerp(g, self.Object.Humanoid.Health / self.Object.Humanoid.MaxHealth)
        else
            self.Components.Health.Visible = false
            self.Components.Health2.Visible = false
        end
    else
        self.Components.Health.Visible = false
        self.Components.Health2.Visible = false
    end
    
    if ESP.Items then
        local TorsoPos, Vis9 = WorldToViewportPoint(cam, locs.Torso.p)
        
        if Vis9 then        
	        if self.Object:FindFirstChildWhichIsA("Tool") then
            	self.Components.Items.Text = tostring(self.Object:FindFirstChildWhichIsA("Tool").Name)
	        end
            self.Components.Items.Position = Vector2.new(TorsoPos.X, TorsoPos.Y)
            self.Components.Items.Visible = true
	    self.Components.Items.Size = ESP.ItemTextSize
            self.Components.Items.Color = color
        else
            self.Components.Items.Visible = false
        end
    else
        self.Components.Items.Visible = false
    end
end

function ESP:Add(obj, options)
	if not obj.Parent and not options.RenderInNil then
		return warn(obj, "has no parent")
	end

	local box = setmetatable({
		Name = options.Name or obj.Name,
		Type = "Box",
		Color = options.Color,
		Size = options.Size or self.BoxSize,
		Object = obj,
		Player = options.Player or plrs:GetPlayerFromCharacter(obj),
		PrimaryPart = options.PrimaryPart or obj.ClassName == "Model" and (obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart")) or obj:IsA("BasePart") and obj,
		Components = {},
		IsEnabled = options.IsEnabled,
		Temporary = options.Temporary,
		ColorDynamic = options.ColorDynamic,
		RenderInNil = options.RenderInNil
	}, boxBase)

	if self:GetBox(obj) then
		self:GetBox(obj):Remove()
	end

	box.Components["Quad"] = Draw("Quad", {
		Thickness = self.Thickness,
		Color = color,
		Transparency = 1,
		Filled = false,
		Visible = self.Enabled and self.Boxes
	})

	box.Components["Name"] = Draw("Text", {
		Text = box.Name,
		Color = box.Color,
		Center = true,
		Outline = true,
		Size = self.TextSize,
		Visible = self.Enabled and self.Names
	})

	box.Components["Distance"] = Draw("Text", {
		Color = box.Color,
		Center = true,
		Outline = true,
		Size = self.TextSize,
		Visible = self.Enabled and self.Names
	})

    box.Components["Items"] = Draw("Text", {
	    Color = box.Color,
	    Center = true,
	    Outline = true,
	    Size = self.ItemTextSize,
	    Visible = self.Enabled and self.Items
	})

	box.Components["Health"] = Draw("Line", {
	    Transparency = 1,
	    Thickness = 4,
	    Visible = self.Enabled and self.Health
	})

	box.Components["Health2"] = Draw("Line", {
	    Transparency = 1,
	    Thickness = 2,
	    Visible = self.Enabled and self.Health
	})
	
	box.Components["Tracer"] = Draw("Line", {
		Thickness = ESP.Thickness,
		Color = box.Color,
		Transparency = 1,
		Visible = self.Enabled and self.Tracers
	})

    box.Components["Tracer"] = Draw("Line", {
		Thickness = ESP.Thickness,
		Color = box.Color,
		Transparency = 1,
		Visible = self.Enabled and self.Tracers
	})
	self.Objects[obj] = box
	
	obj.AncestryChanged:Connect(function(_, parent)
		if parent == nil and ESP.AutoRemove ~= false then
			box:Remove()
		end
	end)
	obj:GetPropertyChangedSignal("Parent"):Connect(function()
		if obj.Parent == nil and ESP.AutoRemove ~= false then
			box:Remove()
		end
	end)

	local hum = obj:FindFirstChildOfClass("Humanoid")
	if hum and (not ESP.IgnoreHumanoids) then
		hum.Died:Connect(function()
			if ESP.AutoRemove ~= false then
				box:Remove()
			end
		end)
	end

	return box
end

local function CharAdded(char)
	local p = plrs:GetPlayerFromCharacter(char)
	if not char:FindFirstChild("HumanoidRootPart") then
		local ev
		ev = char.ChildAdded:Connect(function(c)
			if c.Name == "HumanoidRootPart" then
				ev:Disconnect()
				ESP:Add(char, {
					Name = p.Name,
					Player = p,
					PrimaryPart = c
				})
			end
		end)
	else
		ESP:Add(char, {
			Name = p.Name,
			Player = p,
			PrimaryPart = char.HumanoidRootPart
		})
	end
end
local function PlayerAdded(p)
	p.CharacterAdded:Connect(CharAdded)
	if p.Character then
		coroutine.wrap(CharAdded)(p.Character)
	end
end
plrs.PlayerAdded:Connect(PlayerAdded)
for i,v in pairs(plrs:GetPlayers()) do
	if v ~= plr then
		PlayerAdded(v)
	end
end

game:GetService("RunService"):BindToRenderStep("ESP", 199, function()
	cam = workspace.CurrentCamera
	for i,v in (ESP.Enabled and pairs or ipairs)(ESP.Objects) do
		if v.Update then
			local s,e = pcall(v.Update, v)
			if not s then warn("[EU]", e, v.Object:GetFullName()) end
		end
	end
end)

return ESP
