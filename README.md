# Fix Soon:
- Better render pass state tracking... maybe push and pop GL state procs? Since we are caching them we'll be able to check those calls and not do em if not necessary
- Split shadow-casting point lights and non-shadow-casting lights... this can just be a bool... but should be separate arrays in the global frame uniform
- AABB collision response
- Batching layer on top of immediate rendering system


# Complete:
- AABB wireframe rendering and collision detection
- Frames in flight sync, triple-up persistently mapped buffers
- Immediate vertex rendering system, flushes vertices when needed (switching textures, modes, coordinate space)
- Text rendering (backed by the immediate system)
- Point light shadow mapping
- Sun shadow mapping
- Full blinn-phong shading model
- Menu (press ESC)
- Zoom (scroll wheel)
- GLTF model loading (works as far as I can tell, obviously not even close to all the features)
