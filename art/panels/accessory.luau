-- accessory.luau: reads downloaded Roblox catalog accessories (rbxm or rbxmx, from art/panels/catalog.py) and
-- writes what the panel renders need to fit each one on the blocky head: the handle's class, its mesh and
-- texture ids, the SpecialMesh scale and offset (or the MeshPart's size), and the handle's attachment (its name
-- and CFrame) or the legacy AttachmentPoint. Data only: nothing in the files is run.
-- Run: lune run art/panels/accessory.luau <folder>   (reads <folder>/<id>.rbxm, writes <folder>/accessories.json)
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local dir = process.args[1] or "build/catalog/hair"
local function cf(c: any): { number }
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c:GetComponents()
	return { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end
local function idOf(s: string?): number?
	return s and tonumber(string.match(s, "(%d+)%s*$"))
end

local out = {}
for _, name in fs.readDir(dir) do
	local id = string.match(name, "^(%d+)%.rbxm$")
	if id then
		local ok, err = pcall(function()
			local model = roblox.deserializeModel(fs.readFile(dir .. "/" .. name))
			local acc = nil
			for _, inst in model do
				if inst:IsA("Accessory") or inst.ClassName == "Hat" then
					acc = inst
				end
			end
			assert(acc, "no accessory")
			local handle = acc:FindFirstChild("Handle")
			assert(handle, "no handle")
			local row: any = { id = tonumber(id), class = handle.ClassName, size = { handle.Size.X, handle.Size.Y, handle.Size.Z } }
			if acc.ClassName == "Accessory" then
				row.attachmentPoint = cf(acc.AttachmentPoint)
			end
			if handle.ClassName == "MeshPart" then
				row.mesh = idOf(handle.MeshId)
				row.texture = idOf(handle.TextureID)
			else
				local sm = handle:FindFirstChildOfClass("SpecialMesh")
				assert(sm, "no SpecialMesh")
				row.mesh = idOf(sm.MeshId)
				row.texture = idOf(sm.TextureId)
				row.scale = { sm.Scale.X, sm.Scale.Y, sm.Scale.Z }
				row.offset = { sm.Offset.X, sm.Offset.Y, sm.Offset.Z }
			end
			for _, c in handle:GetChildren() do
				if c:IsA("Attachment") then
					row.attachment = { name = c.Name, cframe = cf(c.CFrame) }
				end
			end
			table.insert(out, row)
		end)
		if not ok then
			print("accessory.luau: " .. name .. " skipped: " .. tostring(err))
		end
	end
end
fs.writeFile(dir .. "/accessories.json", serde.encode("json", out, true))
print(#out .. " accessories -> " .. dir .. "/accessories.json")
