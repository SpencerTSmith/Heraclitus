# Build and Run:
Need Odin compiler and shaderc as a system library
```bash
odin run src -keep-executable -out:heraclitus -debug -extra-linker-flags:"-lshaderc_combined -lglslang -lglslang-default-resource-limits -lSPIRV -lSPIRV-Tools -lSPIRV-Tools-opt -lstdc++ -lm"
```

# To Do:
- More sophisticated UI Layout system
    - Will probably need to do caching and multiple passes
    - Probably builder code should only add widgets to list, build the tree links, and perhaps do input
        - If doing input then it will probably be based on the last frame's cached layout, if doing multiple passes that will probably require one frame of input lag
- Switch fully to PBR lighting model
- Editor
    - Rotation and scaling gizmo's
    - Editable entity fields
- Audio in general

- Potential ideas that could possibly be worth it:
    - Sort of just normalizing vectors everywhere, almost certainly redundantly... profile and find out if this is significant enough to fix
    - Cache calculated world AABB's, have dirty flag if world transform has changed and need to recalculate
    - Clean up mega_draw uniform extraction, helper for grabbing model etc so that can refactor into another level of indexing (a per object instead of per draw) rather than storing model matrix directly in the per draw uniform.
    - Thread pool loading of assets

# Complete:
- Frustum culling
- Shader hot-reloading
- Asset system basics:
    - Will only load assets once, keeps hashes of file paths to check
    - Handle system, no hashing needed once the asset is loaded to retrieve it
- Cool GLSL metaprogramming
    - Generates GLSL code that needs to match up with odin code (uniform struct definitions, buffer binding locations, etc) so less tedious and only need to edit one spot
- AABB basic collision detection and response
- Quake-style player-movement
- Fully bindless rendering architecture
    - 2 memory arenas currently, one which is full device local, and another which is device local, host visible, host coherent
        - 1 single vulkan buffer api object for each
        - All actual 'GPU_Buffer' structs are bump allocated out of these single buffers
        - Buffer device address
    - Indirect Drawing
    - Frames in flight, tripled-up persistently mapped buffers
    - Single descriptor array for each sampler type required
    - ALL mesh data in one big buffer
    - Vertex pulling
- Immediate vertex rendering system, will batch groups
    - AABB, sphere, and vector debug visuals
    - Text rendering
- Point light shadow mapping
    - Cube map array render target... pretty efficient storage, instanced rendering (6 instances, one for each map side)
    - Culls entities if not intersecting light radius sphere
    - Configurable, can have cheaper non shadow casting point lights
        - These are stored together on CPU in the same array (just a bool to distinguish) but are uploaded separately to GPU... Little less branchy in shader.
- Sun shadow mapping
- Editor
    - Axis and plane move gizmos
- Full blinn-phong shading model
- Menu... press ESC
- Zoom... scroll wheel
- GLTF model loading (obviously not even close to all the features)
