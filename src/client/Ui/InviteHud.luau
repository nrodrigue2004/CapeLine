-- InviteHud (Everything Left 350): INVITE FRIENDS in the MENU drawer opens Roblox's own invite prompt
-- (SocialService), so a player can bring friends straight into this server. Nothing is paid for an invite (the
-- invite reward waits on nate's Roblox policy check, open call 7). Where Roblox says invites can't be sent
-- (privacy settings, some devices), the button says so briefly instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Kit = require(script.Parent.Kit)

local InviteHud = {}

local LABEL = "INVITE FRIENDS"
local busy = false

function InviteHud.prompt(button: TextButton?)
	if busy then
		return
	end
	busy = true
	local player = Players.LocalPlayer
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and can then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	elseif button then
		button.Text = "INVITES ARE OFF HERE"
		task.delay(2.5, function()
			button.Text = LABEL
		end)
	end
	busy = false
end

function InviteHud.init()
	local T = Config.Ui.touchTarget
	local open: TextButton
	open = Kit.button({
		Name = "InviteButton",
		Text = LABEL,
		Size = UDim2.fromOffset(T * 3, T - 10),
		BackgroundColor3 = Kit.color.paper,
	}, function()
		task.spawn(InviteHud.prompt, open)
	end)
	Kit.dock(open, "Invite", 12) -- the MENU drawer, after SETTINGS
end

return InviteHud
