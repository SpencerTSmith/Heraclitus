# TODO:
- Better render pass state tracking... maybe push and pop GL state procs? Since we are caching them we'll be able to check those calls and not do em if not necessary
- Split shadow-casting point lights and non-shadow-casting lights... this can just be a bool... but should be separate arrays in the global frame uniform
- AABB collision response
- Improve immediate rendering batching
    - Look for already started batches that match state and append... or...
    - Sort batches by state change when flushing
- Sort of just normalizing vectors everywhere, probably redundantly... profile and find out if this is significant enough to fix
- More AZDO:
    - Texture handles
    - Multi-draw indirect
        - Try with just doing so for models with multiple mesh primitives... looks simple before doing next step
    - Put all normal geometry into one vertex buffer, both for locality reasons and to allow for multi-draw-indirect

# Complete:
- AABB basic collision detection and response
- Quake-like player-movement (Bunny-hopping, wall-running, strafe-jumping)
- AZDO OpenGL techniques:
    - Frames in flight sync, triple-up persistently mapped buffers
- Immediate vertex rendering system, will batch calls and only submit them once we have synced the frame
    - AABB and vector debug visuals
    - Text rendering
- Point light shadow mapping
- Sun shadow mapping
- Full blinn-phong shading model
- Menu (press ESC)
- Zoom (scroll wheel)
- GLTF model loading (works as far as I can tell, obviously not even close to all the features)
