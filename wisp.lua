local Event = game:GetService("Players").LocalPlayer.PlayerGui.Classes.Frame.MainClassEvent

local words = {
	"Warrior", "Magic", "Storm", "Thunder", "Shadow",
	"Blaze", "Omega", "Phantom", "Vortex", "Crystal", "Dragon",
	"Spirit", "Galaxy", "Quantum", "Inferno", "Lightning",
	"Rogue", "Mirage", "Tornado", "Nebula", "Eclipse",
	"Chaos", "Nova", "Titan", "Cyber", "Pulse"
}


local typeMin = 0.12
local typeMax = 0.16
local deleteMin = 0.05
local deleteMax = 0.09

local typoChance = 0.18
local thinkChance = 0.20
local thinkMin = 0.4
local thinkMax = 3.0

local blinkSpeed = 0.25

local function randomDelay(min, max)
	task.wait(math.random() * (max - min) + min)
end

local function shuffle(tbl)
	for i = #tbl, 2, -1 do
		local j = math.random(i)
		tbl[i], tbl[j] = tbl[j], tbl[i]
	end
end

local function send(text)
	Event:FireServer("Equip", 0, text)
end

while true do
	shuffle(words)

	for _, word in ipairs(words) do

		local typed = ""

		if math.random() < thinkChance then
			task.wait(math.random() * (thinkMax - thinkMin) + thinkMin)
		end

		for i = 1, #word do
			local char = word:sub(i, i)

			if math.random() < typoChance then
				local typoChar = string.char(math.random(97, 122))
				typed = typed .. typoChar
				send(typed)
				randomDelay(typeMin, typeMax)

				typed = typed:sub(1, #typed - 1)
				send(typed)
				randomDelay(typeMin, typeMax)
			end

			typed = typed .. char
			send(typed)
			randomDelay(typeMin, typeMax)
		end

		task.wait(0.6)

		for i = #typed, 1, -1 do
			typed = typed:sub(1, i - 1)
			send(typed)
			randomDelay(deleteMin, deleteMax)
		end

		for _ = 1, math.random(3, 6) do
			send("|")
			task.wait(blinkSpeed)
			send("")
			task.wait(blinkSpeed)
		end

		task.wait(0.3)
	end
end
