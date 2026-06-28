-- =============================================================
--  ReviveSystem.server.luau
--  Path: game/src/ServerScriptService/ReviveSystem.server.luau
--
--  Alur:
--  1. Player mati (Humanoid.Died) → masuk state DOWNED
--  2. Server spawn "GhostAnchor" di posisi mati + ProximityPrompt
--  3. Player lain bisa hold prompt 5 detik → revive (HP full)
--  4. Countdown 60 detik → kalau tidak di-revive → PERMANENT DEAD
--  5. Semua player permanent dead → Game Over
--
--  RemoteEvents:
--  RE_PlayerDowned   server→all   : { playerName, timeLeft }
--  RE_PlayerRevived  server→all   : { playerName }
--  RE_ReviveProgress server→rescu : progress 0→1 (untuk progress bar)
--  RE_GameOver       server→all   : (sudah ada di RemoteSetup)
-- =============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local TweenService      = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE_PlayerDowned = Remotes:WaitForChild("PlayerDowned")
local RE_PlayerRevived = Remotes:WaitForChild("PlayerRevived")
local RE_GameOver = Remotes:WaitForChild("GameOver")

-- ─────────────────────────────────────────────
--  CONFIG
-- ─────────────────────────────────────────────
local REVIVE_COUNTDOWN = Constants.REVIVE_TIMER or 60 -- detik sebelum permanent dead
local REVIVE_HOLD = 5 -- detik hold prompt
local PROMPT_DISTANCE = 20 -- stud max aktivasi prompt
local GHOST_ANCHOR_NAME = "GhostAnchor"

-- ─────────────────────────────────────────────
--  STATE
-- ─────────────────────────────────────────────
-- downerState[userId] = {
--   player      : Player,
--   anchor      : BasePart,        -- part di posisi mati
--   prompt      : ProximityPrompt,
--   timeLeft    : number,           -- detik tersisa
--   thread      : thread,           -- coroutine countdown
--   permanent   : boolean,
-- }
local downedState: {
	[number]: {
		player: Player,
		anchor: BasePart,
		prompt: ProximityPrompt,
		timeLeft: number,
		thread: thread?,
		permanent: boolean,
	},
} =
	{}

-- ─────────────────────────────────────────────
--  HELPER: semua player permanent dead?
-- ─────────────────────────────────────────────
local function checkGameOver()
	local allPlayers = Players:GetPlayers()
	if #allPlayers == 0 then
		return
	end

	for _, player in ipairs(allPlayers) do
		local state = downedState[player.UserId]
		-- Kalau ada player yang TIDAK permanent dead = masih hidup/bisa diselamatkan
		if not state or not state.permanent then
			return
		end
	end

	-- Semua permanent dead → Game Over
	print("[ReviveSystem] Semua player permanent dead — GAME OVER")
	RE_GameOver:FireAllClients()
end

-- ─────────────────────────────────────────────
--  CLEANUP anchor & prompt player tertentu
-- ─────────────────────────────────────────────
local function cleanupAnchor(userId: number)
	local state = downedState[userId]
	if not state then
		return
	end

	if state.prompt and state.prompt.Parent then
		state.prompt:Destroy()
	end
	if state.anchor and state.anchor.Parent then
		state.anchor:Destroy()
	end
end

-- ─────────────────────────────────────────────
--  PERMANENT DEATH
-- ─────────────────────────────────────────────
local function makePermanentDead(userId: number)
	local state = downedState[userId]
	if not state or state.permanent then
		return
	end

	state.permanent = true
	cleanupAnchor(userId)

	print(string.format("[ReviveSystem] %s permanent dead.", state.player.Name))

	-- Beritahu semua client
	RE_PlayerDowned:FireAllClients({
		playerName = state.player.Name,
		timeLeft = 0,
		permanent = true,
	})

	checkGameOver()
end

-- ─────────────────────────────────────────────
--  SPAWN GHOST ANCHOR
--  Part transparan di posisi mati sebagai adornee ProximityPrompt
-- ─────────────────────────────────────────────

local function spawnGhostAnchor(position: Vector3, player: Player): (BasePart, ProximityPrompt)
	local anchor = Instance.new("Part")
	anchor.Name = GHOST_ANCHOR_NAME .. "_" .. player.Name
	anchor.Size = Vector3.new(3, 3, 3)

	-- Raise it by 2 studs so it sits ON the ground, not IN the ground
	-- Set Y offset to exactly half the height (1.5) so it sits flat on the floor
	anchor.CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0))
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = true -- INI HARUS TRUE BIAR PROMPT BISA DITEKAN	-- Make it an actual visible glowing blue hologram so it can't be missed
	anchor.Transparency = 0.5
	anchor.Material = Enum.Material.ForceField
	anchor.Color = Color3.fromRGB(50, 150, 255)
	anchor.Parent = workspace

	-- Visual: glow putih
	local glow = Instance.new("SelectionBox")
	glow.Adornee = anchor
	glow.Color3 = Color3.fromRGB(220, 220, 255)
	glow.LineThickness = 0.05
	glow.SurfaceTransparency = 0.8
	glow.Parent = anchor

	-- Billboard nama di atas anchor
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(220, 220, 255)
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = "💀 " .. player.Name
	nameLabel.Parent = billboard

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 0.4, 0)
	timerLabel.Position = UDim2.new(0, 0, 0.6, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	timerLabel.TextSize = 13
	timerLabel.Font = Enum.Font.Gotham
	timerLabel.Text = string.format("%.0fs", REVIVE_COUNTDOWN)
	timerLabel.Parent = billboard

	-- ProximityPrompt untuk revive
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Selamatkan"
	prompt.ObjectText = player.Name
	prompt.HoldDuration = REVIVE_HOLD
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	return anchor, prompt, timerLabel
end

-- ─────────────────────────────────────────────
--  REVIVE PLAYER
-- ─────────────────────────────────────────────
local function revivePlayer(downedPlayer: Player, rescuer: Player)
	local state = downedState[downedPlayer.UserId]
	if not state or state.permanent then
		return
	end

	-- Cancel countdown
	if state.thread then
		task.cancel(state.thread)
		state.thread = nil
	end

	cleanupAnchor(downedPlayer.UserId)
	downedState[downedPlayer.UserId] = nil

	-- Respawn player
	-- Respawn player (Cast to 'any' to silence the false positive LSP warning)
	(downedPlayer :: any):LoadCharacter() -- DeprecatedApi: Member 'LoadCharacter' is deprecated

	-- Tunggu karakter selesai load, lalu set HP full
	task.spawn(function()
		local newChar = downedPlayer.Character or downedPlayer.CharacterAdded:Wait()
		local hum = newChar:WaitForChild("Humanoid", 5)
		if hum then
			hum.Health = hum.MaxHealth
		end

		-- Posisikan di dekat rescuer kalau bisa
		local rescuerChar = rescuer.Character
		local rescuerRoot = rescuerChar and rescuerChar:FindFirstChild("HumanoidRootPart")
		if rescuerRoot then
			local spawnCF = rescuerRoot.CFrame * CFrame.new(0, 0, -3)
			local hrp = newChar:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = spawnCF
			end
		end
	end)

	print(string.format("[ReviveSystem] %s di-revive oleh %s", downedPlayer.Name, rescuer.Name))

	RE_PlayerRevived:FireAllClients({
		playerName = downedPlayer.Name,
		rescuerName = rescuer.Name,
	})
end

-- ─────────────────────────────────────────────
--  HANDLE PLAYER DOWNED
-- ─────────────────────────────────────────────
local function onPlayerDowned(player: Player, deathPosition: Vector3)
	-- SOLO (1 player in server): immediate Game Over, no revive
	-- if #Players:GetPlayers() <= 1 then
	-- 	RE_GameOver:FireAllClients()
	-- 	return
	-- end

	-- Kalau sudah downed sebelumnya, cleanup dulu
	if downedState[player.UserId] then
		cleanupAnchor(player.UserId)
		local existingThread = downedState[player.UserId].thread
		if existingThread then
			task.cancel(existingThread)
		end
		downedState[player.UserId] = nil
	end

	-- Spawn anchor di posisi mati
	local anchor, prompt, timerLabel = spawnGhostAnchor(deathPosition, player)

	local state = {
		player = player,
		anchor = anchor,
		prompt = prompt,
		timeLeft = REVIVE_COUNTDOWN,
		thread = nil,
		permanent = false,
	}
	downedState[player.UserId] = state

	-- Broadcast downed ke semua client
	RE_PlayerDowned:FireAllClients({
		playerName = player.Name,
		timeLeft = REVIVE_COUNTDOWN,
		permanent = false,
	})

	-- Hook prompt triggered → revive
	prompt.Triggered:Connect(function(rescuer: Player)
		-- Jangan revive diri sendiri (tidak relevan tapi buat jaga-jaga)
		if rescuer == player then
			return
		end
		-- Jangan revive kalau sudah permanent
		local currentState = downedState[player.UserId]
		if not currentState or currentState.permanent then
			return
		end

		revivePlayer(player, rescuer)
	end)

	-- Countdown thread
	state.thread = task.spawn(function()
		local elapsed = 0
		while elapsed < REVIVE_COUNTDOWN do
			task.wait(1)
			elapsed += 1

			local currentState = downedState[player.UserId]
			if not currentState then
				return
			end -- sudah di-revive
			if currentState.permanent then
				return
			end

			currentState.timeLeft = REVIVE_COUNTDOWN - elapsed

			-- Update timer label di billboard
			if timerLabel and timerLabel.Parent then
				timerLabel.Text = string.format("%.0fs", currentState.timeLeft)
				-- Makin merah saat mendekati 0
				local ratio = currentState.timeLeft / REVIVE_COUNTDOWN
				timerLabel.TextColor3 = Color3.new(1, ratio * 0.4, ratio * 0.4)
			end

			-- Broadcast update ke client (untuk countdown UI)
			RE_PlayerDowned:FireAllClients({
				playerName = player.Name,
				timeLeft = currentState.timeLeft,
				permanent = false,
			})
		end

		-- Waktu habis → permanent dead
		makePermanentDead(player.UserId)
	end)

	print(
		string.format(
			"[ReviveSystem] %s downed di %s — %ds sebelum permanent",
			player.Name,
			tostring(deathPosition),
			REVIVE_COUNTDOWN
		)
	)
end

-- ─────────────────────────────────────────────
--  HOOK HUMANOID.DIED PER CHARACTER
-- ─────────────────────────────────────────────
local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local hrp = character:WaitForChild("HumanoidRootPart", 10)

	humanoid.Died:Connect(function()
		local deathPos = hrp and hrp.Position or Vector3.new(0, 5, 0)
		task.wait(1) -- Change this to 1 second so the death UI has time to pop up and camera settles
		onPlayerDowned(player, deathPos)
	end)
end

-- ─────────────────────────────────────────────
--  SETUP: matikan auto-respawn
--  CharacterAutoLoads = false supaya kita yang kontrol
--  kapan player respawn (saat di-revive atau permanent dead → game over)
-- ─────────────────────────────────────────────
Players.CharacterAutoLoads = false

local ReviveSystem = {}

function ReviveSystem.init()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(hookCharacter, player, character)
		end)
		player:LoadCharacter()
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			task.spawn(hookCharacter, player, character)
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		else
			player:LoadCharacter()
		end
	end

	-- ─────────────────────────────────────────────
	--  CLEANUP saat player leave
	-- ─────────────────────────────────────────────
	Players.PlayerRemoving:Connect(function(player)
		local state = downedState[player.UserId]
		if state then
			if state.thread then
				task.cancel(state.thread)
			end
			cleanupAnchor(player.UserId)
			downedState[player.UserId] = nil
		end
		-- Cek game over setelah player leave
		task.defer(checkGameOver)
	end)

	print("[ReviveSystem] Initialized — REVIVE_TIMER:", REVIVE_COUNTDOWN, "s | HOLD:", REVIVE_HOLD, "s")
end

return ReviveSystem
