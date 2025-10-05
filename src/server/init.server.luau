local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TeamsService = game:GetService("Teams")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local REMOTE_KICK = Remotes.getRemote("KickRequest")
local REMOTE_SPRINT = Remotes.getRemote("SprintState")
local REMOTE_SCORE = Remotes.getRemote("ScoreUpdate")

local FOOTBALL_NAME = "Football"
local FOOTBALL_TEMPLATE = "FootballTemplate"
local FOOT_NAME = "StinkyFoot"
local FOOT_TEMPLATE = "StinkyFootTemplate"

local function ensureTeam(name : string, color : BrickColor)
	local team = TeamsService:FindFirstChild(name)
	if team then
		return team
	end

	team = Instance.new("Team")
	team.Name = name
	team.TeamColor = color
	team.AutoAssignable = false
	team.Parent = TeamsService
	return team
end

local TEAM_RED = ensureTeam("Red", BrickColor.new("Bright red"))
local TEAM_BLUE = ensureTeam("Blue", BrickColor.new("Bright blue"))

local scoreByTeam = {
	[TEAM_RED] = 0,
	[TEAM_BLUE] = 0,
}

local function broadcastScore()
	if REMOTE_SCORE then
		REMOTE_SCORE:FireAllClients({
			[TEAM_RED.Name] = scoreByTeam[TEAM_RED],
			[TEAM_BLUE.Name] = scoreByTeam[TEAM_BLUE],
		})
	end
end

local function addScore(team : Team, points : number)
	if not scoreByTeam[team] then
		return
	end

	scoreByTeam[team] += points
	print(('[Score] %s +%d | Red=%d Blue=%d'):format(team.Name, points, scoreByTeam[TEAM_RED], scoreByTeam[TEAM_BLUE]))
	broadcastScore()
end

Players.PlayerAdded:Connect(function(player)
	local redCount = #TeamsService:GetPlayersOnTeam(TEAM_RED)
	local blueCount = #TeamsService:GetPlayersOnTeam(TEAM_BLUE)
	player.Team = (blueCount <= redCount) and TEAM_BLUE or TEAM_RED
	player:SetAttribute("Sprinting", false)
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute("Sprinting", nil)
end)

local function randomUnitXZ()
	local theta = math.random() * math.pi * 2
	return Vector3.new(math.cos(theta), 0, math.sin(theta))
end

local function findAncestorNamed(inst : Instance, target : string)
	local current = inst
	while current do
		if current.Name == target then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getAssemblyInfo(part : BasePart)
	local footModel = findAncestorNamed(part, FOOT_NAME)
	if footModel and footModel:IsA("Model") then
		local primary = footModel.PrimaryPart or footModel:FindFirstChildWhichIsA("BasePart") or part
		return "StinkyFoot", footModel, primary
	end

	if part.Name == FOOT_NAME then
		return "StinkyFoot", nil, part
	end

	local footballModel = findAncestorNamed(part, FOOTBALL_NAME)
	if footballModel and footballModel:IsA("Model") then
		local primary = footballModel.PrimaryPart or footballModel:FindFirstChildWhichIsA("BasePart") or part
		return "Football", footballModel, primary
	end

	if part.Name == FOOTBALL_NAME then
		return "Football", nil, part
	end

	return nil, nil, part
end

local function applyImpulseToAssembly(part : BasePart, impulse : Vector3)
	local _, footModel, primaryPart = getAssemblyInfo(part)
	local target = primaryPart or part
	target:ApplyImpulse(impulse * target.AssemblyMass)

	if footModel then
		for _, descendant in ipairs(footModel:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant ~= target then
				descendant:ApplyImpulse(impulse * descendant:GetMass())
			end
		end
	end
end

local function applyAngularImpulse(part : BasePart, angularImpulse : Vector3)
	local _, footModel, primaryPart = getAssemblyInfo(part)
	local target = primaryPart or part
	target:ApplyAngularImpulse(angularImpulse * target.AssemblyMass)

	if footModel then
		for _, descendant in ipairs(footModel:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant ~= target then
				descendant:ApplyAngularImpulse(angularImpulse * descendant:GetMass())
			end
		end
	end
end

local function applyKick(targetPart : BasePart, forceDirection : Vector3)
	local base = forceDirection.Unit * Config.KICK_BASE_FORCE
	local sideways = randomUnitXZ() * Config.KICK_RANDOM_SIDE * Config.KICK_BASE_FORCE
	local impulse = base + sideways

	applyImpulseToAssembly(targetPart, impulse)

	local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	if axis.Magnitude < 1e-3 then
		axis = Vector3.new(0, 1, 0)
	end
	local angularImpulse = axis.Unit * Config.KICK_RANDOM_TORQUE
	applyAngularImpulse(targetPart, angularImpulse)
end

if REMOTE_KICK then
	REMOTE_KICK.OnServerEvent:Connect(function(player, target)
		if typeof(target) ~= "Instance" or not target:IsA("BasePart") then
			return
		end

		local kind = select(1, getAssemblyInfo(target))
		if kind ~= "Football" and kind ~= "StinkyFoot" then
			return
		end

		local character = player.Character
		local primary = character and character.PrimaryPart
		if not primary then
			return
		end

		local distance = (target.Position - primary.Position).Magnitude
		if distance > Config.KICK_RANGE then
			return
		end

		local direction = (target.Position - primary.Position)
		applyKick(target, direction)
	end)
end

local staminaByPlayer : {[Player]: number} = {}

local function setWalkSpeed(player : Player, speed : number)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

Players.PlayerAdded:Connect(function(player)
	staminaByPlayer[player] = Config.SPRINT_STAMINA_MAX
	player.CharacterAdded:Connect(function()
		staminaByPlayer[player] = Config.SPRINT_STAMINA_MAX
		setWalkSpeed(player, 16)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	staminaByPlayer[player] = nil
end)

if REMOTE_SPRINT then
	REMOTE_SPRINT.OnServerEvent:Connect(function(player, isSprinting)
		if staminaByPlayer[player] and staminaByPlayer[player] > 0 then
			player:SetAttribute("Sprinting", isSprinting and true or false)
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(0.1)
		for player, current in pairs(staminaByPlayer) do
			local sprinting = player:GetAttribute("Sprinting") == true
			if sprinting then
				current = math.max(0, current - Config.SPRINT_STAMINA_DRAIN * 0.1)
				if current <= 0 then
					player:SetAttribute("Sprinting", false)
					setWalkSpeed(player, 16)
				else
					setWalkSpeed(player, Config.SPRINT_SPEED)
				end
			else
				current = math.min(Config.SPRINT_STAMINA_MAX, current + Config.SPRINT_STAMINA_REGEN * 0.1)
				setWalkSpeed(player, 16)
			end
			staminaByPlayer[player] = current
		end
	end
end)

local spawnFolder = Workspace:FindFirstChild("BallSpawnPoints")

local function chooseSpawnCFrame()
	if not spawnFolder then
		return CFrame.new(0, 6, 0)
	end
	local children = spawnFolder:GetChildren()
	if #children == 0 then
		return CFrame.new(0, 6, 0)
	end
	local marker = children[math.random(1, #children)]
	if marker:IsA("BasePart") then
		return marker.CFrame
	elseif marker:IsA("Attachment") then
		return marker.WorldCFrame
	end
	return CFrame.new(0, 6, 0)
end

local recentRespawns : {[BasePart]: number} = {}

local function resetAssembly(target : Instance)
	if target:IsA("BasePart") then
		target.AssemblyLinearVelocity = Vector3.zero
		target.AssemblyAngularVelocity = Vector3.zero
	elseif target:IsA("Model") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

local function tagRecent(target : Instance, timestamp : number)
	if target:IsA("BasePart") then
		recentRespawns[target] = timestamp
	elseif target:IsA("Model") then
		for _, descendant in ipairs(target:GetDescendants()) do
			if descendant:IsA("BasePart") then
				recentRespawns[descendant] = timestamp
			end
		end
	end
end

local function respawnBall(part : BasePart)
	local kind, footModel, primary = getAssemblyInfo(part)
	local now = tick()

	if kind == "StinkyFoot" and footModel then
		footModel:PivotTo(Config.RESPAWN_CFRAME)
		resetAssembly(footModel)
		tagRecent(footModel, now)
		return
	end

	local basePart = primary or part
	basePart.CFrame = Config.RESPAWN_CFRAME
	resetAssembly(basePart)
	recentRespawns[basePart] = now
end

local function spawnTemplate(templateName : string, desiredName : string)
	local template = ServerStorage:FindFirstChild(templateName)
	if not template then
		warn(('[Spawner] Missing template %s in ServerStorage'):format(templateName))
		return nil
	end

	local clone = template:Clone()
	clone.Name = desiredName
	clone.Parent = Workspace

	local spawnCFrame = chooseSpawnCFrame()
	local now = tick()

	if clone:IsA("BasePart") then
		clone.CFrame = spawnCFrame
		resetAssembly(clone)
		tagRecent(clone, now)
		return clone
	elseif clone:IsA("Model") then
		local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
		if not primary then
			warn(('[Spawner] Template %s has no BasePart to position'):format(templateName))
			clone:Destroy()
			return nil
		end
		clone.PrimaryPart = primary
		clone:PivotTo(spawnCFrame)
		resetAssembly(clone)
		tagRecent(clone, now)
		return clone
	else
		warn(('[Spawner] Template %s must be a BasePart or Model'):format(templateName))
		clone:Destroy()
		return nil
	end
end

local function spawnFootball()
	return spawnTemplate(FOOTBALL_TEMPLATE, FOOTBALL_NAME)
end

local function spawnStinkyFoot()
	return spawnTemplate(FOOT_TEMPLATE, FOOT_NAME)
end

local function countActiveBalls()
	local total = 0
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and child.Name == FOOTBALL_NAME then
			total += 1
		elseif child:IsA("Model") and child.Name == FOOT_NAME then
			total += 1
		end
	end
	return total
end

task.spawn(function()
	while true do
		task.wait(Config.FOOTBALL_SPAWN_INTERVAL)

		local count = countActiveBalls()
		if count >= Config.MAX_FOOTBALLS then
			continue
		end

		if math.random() < Config.STINKY_FOOT_CHANCE then
			spawnStinkyFoot()
		else
			spawnFootball()
		end
	end
end)

local function hookGoal(goalPart : BasePart?, team : Team, basePoints : number, allowFootBonus : boolean)
	if not goalPart then
		warn(('[Goals] Missing goal part for %s'):format(team.Name))
		return
	end

	goalPart.Touched:Connect(function(hit)
		if not hit:IsA("BasePart") then
			return
		end

		local kind, footModel, rootPart = getAssemblyInfo(hit)
		if not kind then
			return
		end

		local keyPart = rootPart or hit
		local lastRespawn = recentRespawns[hit] or recentRespawns[keyPart]
		if lastRespawn and tick() - lastRespawn < Config.BALL_RESPAWN_LOCK then
			return
		end

		local points = basePoints
		if kind == "StinkyFoot" then
			if allowFootBonus then
				points = Config.POINT_STINKY_FOOT
			else
				return
			end
		end

		addScore(team, points)
		respawnBall(keyPart)
	end)
end
hookGoal(Workspace:FindFirstChild("Goal_Red_Soccer"), TEAM_RED, Config.POINT_SOCCER_GOAL, true)
hookGoal(Workspace:FindFirstChild("Goal_Blue_Soccer"), TEAM_BLUE, Config.POINT_SOCCER_GOAL, true)
hookGoal(Workspace:FindFirstChild("Goal_Red_Posts"), TEAM_RED, Config.POINT_FIELD_GOAL, false)
hookGoal(Workspace:FindFirstChild("Goal_Blue_Posts"), TEAM_BLUE, Config.POINT_FIELD_GOAL, false)

broadcastScore()








