# meshdump.py: every mesh object's world vertices (and, under "<name>#faces", its triangles) in an FBX, as Blender reads it back (meshcheck.py runs this).
#   $HOME/tools/bpyenv/bin/python art/upload/meshdump.py IN.fbx OUT.json
import json
import sys

import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=sys.argv[1])
out = {}
for ob in bpy.context.scene.objects:
    if ob.type == "MESH":
        M = ob.matrix_world
        name = ob.name.split(".")[0]
        out[name] = [tuple(M @ v.co) for v in ob.data.vertices]
        ob.data.calc_loop_triangles()
        out[name + "#faces"] = [tuple(t.vertices) for t in ob.data.loop_triangles]
json.dump(out, open(sys.argv[2], "w"))
print(len(out), "meshes")
