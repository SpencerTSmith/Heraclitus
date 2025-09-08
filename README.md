# Build and Run:
Need Odin compiler, and that's it
```bash
odin run src -keep-executable -out:heraclitus -debug -vet -strict-style
```

# To Do:
- Immediate rendering system needs rework, immediate_begin should only be called by user code, not internally unless absolutely nessecary...
    - Will simplify internals, and make it easier to add functionality without changing every single immediate call
    - Complete for drawing quads
- More sophisticated UI Layout system
    - Will probably need to do caching and multiple passes
    - Probably builder code should only add widgets to list, build the tree links, and perhaps do input
        - If doing input then it will probably be based on the last frame's cached layout, if doing multiple passes that will probably require one frame of input lag
- More AZDO:
    - Multi-draw indirect
        - Try with just doing so for models with multiple mesh primitives... looks simple to do before doing next step
    - Put all normal geometry into one vertex buffer, both for locality reasons and to allow for big multi-draw-indirect
- Cache calculated world AABB's, have dirty flag if world transform has changed and need to recalculate
- Switch fully to PBR lighting model
- Editor
    - Rotation and scaling gizmo's
    - Editable entity fields
- Sort of just normalizing vectors everywhere, almost certainly redundantly... profile and find out if this is significant enough to fix
- Thread pool loading of assets
    - Need to have a fence before we begin drawing to actually upload gpu data, as that can only be done from the thread with the gl context
        - But there is still work that can be done in parallel that actually takes a bit of time, namely computing tangents for models that don't have them
        - Could also look into mapped staging buffers... need pbo for textures, but vertex geometry should be very simple... write into the mapped buffer from threads and issue the copy to gpu memory from main thread at the beginning of frame...

# Complete:
- Shader hot-reloading
- Asset system basics:
    - Will only load assets once, keeps hashes of file paths to check
    - Handle system, no hashing needed once the asset is loaded to retrieve it
- Cool GLSL metaprogramming
    - Generates GLSL code that needs to match up with host code (uniform struct definitions, buffer binding locations, etc) so less tedious and only need to edit one spot
- AABB basic collision detection and response
- Quake-like player-movement (Bunny-hopping, wall-running, strafe-jumping)
- AZDO OpenGL techniques:
    - Frames in flight sync, triple-up persistently mapped buffers
    - Bindless textures for model materials (Still doing traditional binding api for less commonly bound textures like shadow maps, skybox, etc)
- Immediate vertex rendering system, will batch calls and only submit them once we have synced the frame
    - AABB, sphere, and vector debug visuals
    - Text rendering
- Point light shadow mapping
    - Cube map array render target... pretty efficient storage, and can minimize draw calls with instanced rendering (6 instances for each map side)
    - Culls entities if not intersecting light radius sphere
    - Configurable, can have cheaper non shadow casting point lights
        - These are stored together on CPU in the same array (just a bool to distinguish) but are uploaded separately to GPU... Little less branchy in shader.
- Sun shadow mapping
- Editor
    - Axis and plane move gizmos
- Full blinn-phong shading model
- Menu (press ESC)
- Zoom (scroll wheel)
- GLTF model loading (works as far as I can tell, obviously not even close to all the features)
