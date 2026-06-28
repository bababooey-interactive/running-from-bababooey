-- =============================================================
--  TaskSystem.server.luau
--  Server-side task counter management + win condition
--  Path: game/src/ServerScriptService/TaskSystem.server.luau
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SoundManager = require(script.Parent.SoundManager)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_TaskProgress = Remotes:WaitForChild("TaskProgress")
local RE_TaskInteract = Remotes:WaitForChild("TaskInteract")
local RE_GameWin = Remotes:WaitForChild("GameWin")
local RE_SyncState = Remotes:WaitForChild("SyncState")

-- ─────────────────────────────────────────────
--  STATE — battery dihapus
-- ─────────────────────────────────────────────
local taskState = {
	coal_done = 0,
	coal_total = 0,
	lever_done = 0,
	lever_total = 0,
	won = false,
}

local completedTasks: { [string]: boolean } = {}
local taskObjectsCache: { [string]: Instance } = {}

-- ─────────────────────────────────────────────
--  INIT
-- ─────────────────────────────────────────────
local function initTaskCounts(level: number)
	local extra = math.max(0, level - 1) * Constants.TASK_ADD_PER_LEVEL
	taskState.coal_total = Constants.TASK_COAL_COUNT + extra
	taskState.lever_total = Constants.TASK_LEVER_COUNT + extra
	taskState.coal_done = 0
	taskState.lever_done = 0
	taskState.won = false
	completedTasks = {}
end

-- ─────────────────────────────────────────────
--  BROADCAST — tanpa battery
-- ─────────────────────────────────────────────
local function broadcastProgress()
	RE_TaskProgress:FireAllClients({
		coal_done = taskState.coal_done,
		coal_total = taskState.coal_total,
		lever_done = taskState.lever_done,
		lever_total = taskState.lever_total,
	})
end

-- ─────────────────────────────────────────────
--  WIN CHECK — tanpa battery
-- ─────────────────────────────────────────────
local function checkWin()
	if taskState.won then
		return
	end

	if taskState.coal_done >= taskState.coal_total and taskState.lever_done >= taskState.lever_total then
		taskState.won = true
		print("[TaskSystem] WIN — semua task selesai!")
		RE_GameWin:FireAllClients()

		task.delay(5, function()
			for _, player in ipairs(Players:GetPlayers()) do
				game:GetService("TeleportService"):Teleport(Constants.LOBBY_PLACE_ID, player)
			end
		end)
	end
end

-- ─────────────────────────────────────────────
--  LEVER: cari model di workspace by TaskId
-- ─────────────────────────────────────────────
local function findLeverModel(taskId: string): Model?
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute("TaskId") == taskId then
			return descendant
		end
	end
	return nil
end

-- ─────────────────────────────────────────────
--  LEVER: animasi handle rotate
-- ─────────────────────────────────────────────
local function animateLever(leverModel: Model)
	local base = leverModel:FindFirstChild("Lever_Base")
	if not base or not base:IsA("BasePart") then
		return
	end

	local handle = base:FindFirstChild("Lever_Handle")
	local knob = base:FindFirstChild("Lever_Knob")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local weld = handle:FindFirstChildOfClass("WeldConstraint")
	if weld then
		weld:Destroy()
	end

	local initialHandlePivot = handle:GetPivot()
	local initialKnobPivot = (knob and knob:IsA("BasePart")) and knob:GetPivot() or nil

	local pivotPos = initialHandlePivot.Position
	local rotationAxis = base.CFrame.RightVector
	local startAngle = -45
	local endAngle = 45

	SoundManager.leverPull(base.Position)

	local angleValue = Instance.new("NumberValue")
	angleValue.Value = startAngle
	angleValue.Parent = leverModel

	local tween = TweenService:Create(
		angleValue,
		TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = endAngle }
	)

	angleValue.Changed:Connect(function(angle)
		local deltaAngle = math.rad(angle - startAngle)
		local rotationCF = CFrame.fromAxisAngle(rotationAxis, deltaAngle)
		local newHandlePivot = rotationCF * (initialHandlePivot - pivotPos) + pivotPos
		handle:PivotTo(newHandlePivot)
		if initialKnobPivot and knob and knob.Parent then
			knob:PivotTo(rotationCF * (initialKnobPivot - pivotPos) + pivotPos)
		end
	end)

	tween:Play()
	tween.Completed:Connect(function()
		angleValue:Destroy()
	end)

	for _, desc in leverModel:GetDescendants() do
		if desc:IsA("ProximityPrompt") then
			desc.Enabled = false
		end
	end
end

-- ─────────────────────────────────────────────
--  CORE: completeTask
--  Dipanggil dari:
--  1. RE_TaskInteract handler (lever dari ItemInteract.client)
--  2. ItemPickup.server.luau langsung via require (coal deposit)
--
--  Signature: (taskType, taskId, player) — sama di dua tempat
-- ─────────────────────────────────────────────
local function completeTask(taskType: string, taskId: string, player: Player)
	if taskState.won then
		return
	end
	if completedTasks[taskId] then
		return
	end

	local char = player.Character
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end

	if taskType == "coal" and taskState.coal_done < taskState.coal_total then
		completedTasks[taskId] = true
		taskState.coal_done += 1
		print(
			string.format("[TaskSystem] Coal %d/%d — oleh %s", taskState.coal_done, taskState.coal_total, player.Name)
		)
	elseif taskType == "lever" and taskState.lever_done < taskState.lever_total then
		completedTasks[taskId] = true
		taskState.lever_done += 1
		print(
			string.format(
				"[TaskSystem] Lever %d/%d — oleh %s",
				taskState.lever_done,
				taskState.lever_total,
				player.Name
			)
		)

		-- FIX: Set attribute so all clients can replicate the completion state instantly
		local leverModel = findLeverModel(taskId)
		if leverModel then
			leverModel:SetAttribute("Completed", true)
			animateLever(leverModel)
		end
	else
		return
	end
	local taskObj = taskObjectsCache[taskId]
	if taskObj then
		-- Tell clients to hide the prompt (covers coal deposits too!)
		taskObj:SetAttribute("Completed", true)

		-- Turn it green
		if taskObj:IsA("BasePart") then
			taskObj.BrickColor = BrickColor.new("Bright green")
		end
	end

	broadcastProgress()
	checkWin()
end
-- ─────────────────────────────────────────────
--  HANDLER: RE_TaskInteract (lever dari ItemInteract.client)
-- ─────────────────────────────────────────────
RE_TaskInteract.OnServerEvent:Connect(function(player: Player, payload: { taskType: string, taskId: string })
	if not payload or not payload.taskType or not payload.taskId then
		return
	end
	completeTask(payload.taskType, payload.taskId, player)
end)

-- ─────────────────────────────────────────────
--  LATE-JOIN SYNC — tanpa battery
-- ─────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	RE_SyncState:FireClient(player, {
		coal_done = taskState.coal_done,
		coal_total = taskState.coal_total,
		lever_done = taskState.lever_done,
		lever_total = taskState.lever_total,
		won = taskState.won,
	})
end)

-- ─────────────────────────────────────────────
--  HOOK TASK OBJECTS (disable prompt saat selesai)
-- ─────────────────────────────────────────────
local function hookTaskObject(obj: Instance)
	local taskType = obj:GetAttribute("TaskType")
	local taskId = obj:GetAttribute("TaskId")
	if not taskType or not taskId then
		return
	end
	taskObjectsCache[taskId] = obj

	-- task.spawn(function()
	-- while not taskState.won do
	-- 	task.wait(0.5)
	-- 	if completedTasks[taskId] then
	-- 		local prompt = obj:FindFirstChildOfClass("ProximityPrompt")
	-- 			or obj:FindFirstChild("ProximityPrompt", true)
	-- 		if prompt then
	-- 			prompt.Enabled = false
	-- 		end
	-- 		if obj:IsA("BasePart") then
	-- 			obj.BrickColor = BrickColor.new("Bright green")
	-- 		end
	-- 		break
	-- 	end
	-- end
	-- end)
end

local function scanTaskObjects()
	local taskFolder = workspace:WaitForChild("TaskObjects", 10)
	if not taskFolder then
		warn("[TaskSystem] Folder 'TaskObjects' tidak ditemukan!")
		return
	end
	for _, obj in ipairs(taskFolder:GetDescendants()) do
		if obj:GetAttribute("TaskType") then
		--if obj:IsA("BasePart") and obj:GetAttribute("TaskType") then
			hookTaskObject(obj)
		end
	end
	taskFolder.DescendantAdded:Connect(function(obj)
		
		--if obj:IsA("BasePart") and obj:GetAttribute("TaskType") then
			hookTaskObject(obj)
		end
	end)
end

-- ─────────────────────────────────────────────
--  PUBLIC API
-- ─────────────────────────────────────────────
local TaskSystem = {}

function TaskSystem.init(level: number)
	initTaskCounts(level)
	broadcastProgress()
	scanTaskObjects()
	print(
		string.format(
			"[TaskSystem] Init level %d — Coal:%d Lever:%d",
			level,
			taskState.coal_total,
			taskState.lever_total
		)
	)
end

function TaskSystem.getState()
	return taskState
end

-- Dipanggil oleh ItemPickup.server.luau untuk coal deposit
function TaskSystem.completeTask(taskType: string, taskId: string, player: Player)
	completeTask(taskType, taskId, player)
end

return TaskSystem
