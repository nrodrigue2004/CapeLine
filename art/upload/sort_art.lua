local SETS={__SETS__}
local RS=game:GetService("ReplicatedStorage")
local art=RS:FindFirstChild("Art") or Instance.new("Folder")
art.Name="Art" art.Parent=RS
local want={} for _,n in SETS do want[string.lower(n)]=n end
local moved,lines,unknown={}, {}, {}
for _,m in workspace:GetChildren() do
	if m:IsA("Model") then
		local key=string.lower((string.gsub(m.Name,"%.fbx$","")))
		local name=want[key]
		if name then
			local old=art:FindFirstChild(name) if old then old:Destroy() end
			m.Name=name m.Parent=art table.insert(moved,m)
			for _,p in m:GetDescendants() do
				if p:IsA("MeshPart") then table.insert(lines,name.."/"..p.Name.."="..(string.match(p.MeshId,"%d+$") or "?")) end
				if p:IsA("SurfaceAppearance") then pcall(function() table.insert(lines,name.."/"..p.Parent.Name.."#maps="..(string.match(p.ColorMap,"%d+$") or "0")..","..(string.match(p.NormalMap,"%d+$") or "0")..","..(string.match(p.RoughnessMap,"%d+$") or "0")..","..(string.match(p.MetalnessMap,"%d+$") or "0")) end) end
			end
		elseif #m:GetDescendants()>0 and m:FindFirstChildWhichIsA("MeshPart",true) then table.insert(unknown,m.Name) end
	end
end
local s=Instance.new("ModuleScript") s.Name="CapelineMeshIds"
s.Source="CAPELINE MESH IDS "..#moved.." sets\n"..table.concat(lines,"\n") s.Parent=workspace
game:GetService("Selection"):Set(moved)
print("Capeline art sorted:",#moved,"models moved into ReplicatedStorage.Art and selected.")
if #unknown>0 then print("Not recognised (rename to its file name and run again):",table.concat(unknown,", ")) end
pcall(function() game:GetService("ScriptEditorService"):OpenScriptDocumentAsync(s) end)
