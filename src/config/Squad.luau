-- Squads (spec: Social table "Up to 4 players, shared incident rewards, squad emblem, squad ping"; remotes
-- Squad.Invite, Squad.Accept, Squad.Leave {userId or squadId} 1/s, Squad.State on change; Mission.Enter
-- "party size 4 or less"; Map "party"). Allies never hit each other, even with PvP flags on.
return {
	max = 4,
	inviteLife = 30, -- seconds an invite waits for an answer
	shareRange = 250, -- squadmates this close to a cleared incident get its reward too
	missionRange = 120, -- squadmates this close to the leader join a mission with them
	pingSquad = true, -- squad pings reach the whole squad at any range
	colors = { { 255, 200, 60 }, { 120, 210, 255 }, { 120, 240, 160 }, { 255, 130, 200 } }, -- member slots
}
