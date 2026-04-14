package main

import "base:runtime"
import "core:strings"
import "core:log"
import "core:mem"

import "vendor:glfw"
import vk "vendor:vulkan"

Renderer_Internal :: distinct u64

Queue_Kind :: enum
{
  GRAPHICS,
  PRESENT,
}

Swapchain :: struct
{
  handle: vk.SwapchainKHR,
  targets: [dynamic; 3]struct
  {
    image:     vk.Image,
    view:      vk.ImageView,
    // NOTE: grouping the 'render_finished' semaphore with targets, not frames is correct, see: https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html
    semaphore: vk.Semaphore,
  },
  format: vk.Format,
  extent: vk.Extent2D,
}

Frame_State :: struct
{
  pool:      vk.CommandPool,
  buffer:    vk.CommandBuffer,
  fence:     vk.Fence,
  semaphore: vk.Semaphore,
}

Vulkan_Arena_Kind :: enum
{
  DEVICE,
  HOST,
}

Vulkan_Arena :: struct
{
  memory: vk.DeviceMemory,
  memory_type:   u32,
  memory_offset: vk.DeviceSize,
  memory_size:   vk.DeviceSize,

  buffer: vk.Buffer,
  buffer_offset: vk.DeviceSize,
  buffer_size:   vk.DeviceSize,
}

Vulkan_Image :: struct
{
  image: vk.Image,
  view:  vk.ImageView,
}

Vulkan_Pipeline :: struct
{
  pipeline: vk.Pipeline,
  layout:   vk.PipelineLayout,
}

// Internal API Objects
Vulkan_Internal :: union
{
  Vulkan_Image,
  Vulkan_Pipeline,
}

Vulkan_State :: struct
{
  instance:   vk.Instance,
  messenger:  vk.DebugUtilsMessengerEXT,
  physical:   vk.PhysicalDevice,
  logical:    vk.Device,
  queues:     [Queue_Kind]vk.Queue,
  surface:    vk.SurfaceKHR,
  swapchain:  Swapchain,
  frames:     [3]Frame_State,
  curr_index: [enum {FRAME,TARGET}]u32, // Is this voodoo?
  arenas:     [Vulkan_Arena_Kind]Vulkan_Arena,

  // API Object Pool
  internals: [dynamic; 512]Vulkan_Internal,
}

@(private="file")
vks: Vulkan_State

vk_assert :: proc(result: vk.Result, message: string)
{
  assert(result == .SUCCESS, message)
}

@(private="file")
check_instance_extensions :: proc(needed_extensions: []cstring) -> (found_all: bool)
{
  supported_extensions: []vk.ExtensionProperties
  {
    supported_extension_count: u32
    vk.EnumerateInstanceExtensionProperties(nil, &supported_extension_count, nil)
    supported_extensions = make([]vk.ExtensionProperties, supported_extension_count, context.temp_allocator)
    vk.EnumerateInstanceExtensionProperties(nil, &supported_extension_count, raw_data(supported_extensions))
  }

  found_all = true
  for needed in needed_extensions
  {
    found := false
    for &supported in supported_extensions
    {
      if cstring(raw_data(supported.extensionName[:])) == needed
      {
        found = true
        break
      }
    }

    if found
    {
      log.infof("Necessary VK extension: %v is supported.", needed)
    }
    else
    {
      log.fatalf("Necessary VK extension: %v is NOT supported.", needed)
      found_all = false
      // Don't break just so it will continue and see the other extensions that might be missing or supported.
    }
  }

  return found_all
}

@(private="file")
check_device_extensions :: proc(device: vk.PhysicalDevice, needed_extensions: []cstring) -> (found_all: bool)
{
  supported_extensions: []vk.ExtensionProperties
  {
    supported_extension_count: u32
    vk.EnumerateDeviceExtensionProperties(device, nil, &supported_extension_count, nil)
    supported_extensions = make([]vk.ExtensionProperties, supported_extension_count, context.temp_allocator)
    vk.EnumerateDeviceExtensionProperties(device, nil, &supported_extension_count, raw_data(supported_extensions))
  }

  found_all = true
  for needed in needed_extensions
  {
    found := false
    for &supported in supported_extensions
    {
      if cstring(raw_data(supported.extensionName[:])) == needed
      {
        found = true
        break
      }
    }

    if found
    {
      log.infof("Necessary VK Device extension: %v is supported.", needed)
    }
    else
    {
      log.fatalf("Necessary VK Device extension: %v is NOT supported.", needed)
      found_all = false
      // Don't break just so it will continue and see the other extensions that might be missing or supported.
    }
  }

  return found_all
}

@(private="file")
pick_physical_device :: proc(instance: vk.Instance, surface: vk.SurfaceKHR, needed_device_features: vk.PhysicalDeviceFeatures2,
                             needed_device_extensions: []cstring,) -> (physical: vk.PhysicalDevice, queue_indices: [Queue_Kind]union{u32})
{
  physical_devices: []vk.PhysicalDevice
  {
    device_count: u32
    vk.EnumeratePhysicalDevices(instance, &device_count, nil)
    physical_devices = make([]vk.PhysicalDevice, device_count, context.temp_allocator)
    vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(physical_devices))
  }

  for device in physical_devices
  {
    supported_device_features13: vk.PhysicalDeviceVulkan13Features =
    {
      sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
    }
    supported_device_features12: vk.PhysicalDeviceVulkan12Features =
    {
      sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
      bufferDeviceAddress = true,
      descriptorIndexing  = true,
      pNext = &supported_device_features13,
    }
    supported_device_features11: vk.PhysicalDeviceVulkan11Features =
    {
      sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
      pNext = &supported_device_features12,
    }
    supported_device_features: vk.PhysicalDeviceFeatures2 =
    {
      sType = .PHYSICAL_DEVICE_FEATURES_2,
      pNext = &supported_device_features11,
    }
    vk.GetPhysicalDeviceFeatures2(device, &supported_device_features)

    props: vk.PhysicalDeviceProperties
    vk.GetPhysicalDeviceProperties(device, &props)

    indices := get_queue_indices(device, surface)

    suitable := props.deviceType == .DISCRETE_GPU
    // Check all families supported
    for family in indices
    {
      suitable &= family != nil
    }

    suitable &= check_device_extensions(device, needed_device_extensions)

    mode_count: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &mode_count, nil)

    format_count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, nil)

    suitable &= format_count != 0 && mode_count != 0

    if suitable
    {
      physical = device
      queue_indices = indices
      break
    }
  }

  return physical, queue_indices
}

@(private="file")
pick_memory_type :: proc(physical: vk.PhysicalDevice, needed_requirements: vk.MemoryRequirements,
                         needed_properties: vk.MemoryPropertyFlags) -> (index: u32, ok: bool)
{
  memory_properties: vk.PhysicalDeviceMemoryProperties
  vk.GetPhysicalDeviceMemoryProperties(physical, &memory_properties)

  for memory_type, idx in memory_properties.memoryTypes[:memory_properties.memoryTypeCount]
  {
    idx := u32(idx)
    if needed_requirements.memoryTypeBits & (1 << idx) != 0 &&
       memory_type.propertyFlags >= needed_properties // Weird odin syntax for bit sets, means 'is superset'
    {
      index = idx
      ok = true
      break
    }
  }

  return index, ok
}

@(private="file")
check_layers :: proc(needed_layers: []cstring) -> (found_all: bool)
{
  supported_layers: []vk.LayerProperties
  {
    supported_layer_count: u32
    vk.EnumerateInstanceLayerProperties(&supported_layer_count, nil)
    supported_layers = make([]vk.LayerProperties, supported_layer_count, context.temp_allocator)
    vk.EnumerateInstanceLayerProperties(&supported_layer_count, raw_data(supported_layers))
  }

  found_all = true
  for needed in needed_layers
  {
    found := false
    for &supported in supported_layers
    {
      if cstring(raw_data(supported.layerName[:])) == needed
      {
        found = true
        break
      }
    }

    if found
    {
      log.infof("Necessary VK validation layer: %v is supported.", needed)
    }
    else
    {
      log.warnf("Necessary VK validation layer: %v is NOT supported.", needed)
      found_all = false
      // Don't break just so it will continue and see the other layers that might be missing or supported.
    }
  }

  return found_all
}

@(private="file")
vk_debug_callback :: proc "system" (severity: vk.DebugUtilsMessageSeverityFlagsEXT,
                                    type:     vk.DebugUtilsMessageTypeFlagsEXT,
                                    data:     ^vk.DebugUtilsMessengerCallbackDataEXT,
                                    userdata: rawptr) -> b32
{
  context = runtime.default_context()
  context.logger = (cast(^runtime.Logger)userdata)^

  log_proc: proc(fmt_str: string, args: ..any, location := #caller_location)
  if .ERROR in severity
  {
    log_proc = log.errorf
  }
  else if .WARNING in severity
  {
    log_proc = log.warnf
  }
  else if .INFO in severity
  {
    log_proc = log.debugf
  }
  else
  {
    log_proc = log.infof
  }

  if log_proc != nil
  {
    log_proc("VK: %v", data.pMessage)
  }

  return false
}

@(private="file")
choose_surface_format :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (format: vk.SurfaceFormatKHR)
{
  surface_formats: []vk.SurfaceFormatKHR
  {
    format_count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, nil)
    surface_formats = make([]vk.SurfaceFormatKHR, format_count, context.temp_allocator)
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &format_count, raw_data(surface_formats))
  }

  assert(len(surface_formats) != 0, "Chosen VK Device has no surface formats.")
  format = surface_formats[0]

  for available in surface_formats
  {
    if available.format == .B8G8R8A8_SRGB &&
       available.colorSpace == .COLORSPACE_SRGB_NONLINEAR
    {
      format = available
      break
    }
  }

  return format
}

@(private="file")
choose_present_mode :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (mode: vk.PresentModeKHR)
{
  present_modes: []vk.PresentModeKHR
  {
    mode_count: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &mode_count, nil)
    present_modes = make([]vk.PresentModeKHR, mode_count, context.temp_allocator)
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &mode_count, raw_data(present_modes))
  }

  mode = .FIFO

  for available in present_modes
  {
    if available == .MAILBOX
    {
      mode = available
      break
    }
  }

  return mode
}

@(private="file")
choose_surface_capabilities :: proc(window: Window, device: vk.PhysicalDevice, surface: vk.SurfaceKHR
                                   ) -> (extent: vk.Extent2D, image_count: u32, capabilities: vk.SurfaceCapabilitiesKHR)
{
  vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities)

  extent = capabilities.currentExtent

  if capabilities.currentExtent.width == max(u32)
  {
    width, height := glfw.GetFramebufferSize(window.handle)

    extent =
    {
      clamp(u32(width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
      clamp(u32(height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    }
  }

  image_count = capabilities.minImageCount + 1
  if capabilities.maxImageCount != 0
  {
    image_count = clamp(image_count, capabilities.minImageCount, capabilities.maxImageCount)
  }

  return extent, image_count, capabilities
}

init_vulkan :: proc(window: Window) -> (ok: bool)
{
  vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))

  app_name := strings.clone_to_cstring(window.title, state.perm_alloc)
  app_info: vk.ApplicationInfo =
  {
    sType              = .APPLICATION_INFO,
    pApplicationName   = app_name,
    applicationVersion = vk.MAKE_VERSION(1, 0, 0),
    pEngineName        = cstring("None"),
    engineVersion      = vk.MAKE_VERSION(1, 0, 0),
    apiVersion         = vk.API_VERSION_1_3,
  }

  glfw_extensions := glfw.GetRequiredInstanceExtensions()

  needed_instance_extensions := make([dynamic]cstring, context.temp_allocator)
  append(&needed_instance_extensions, ..glfw_extensions)
  when ODIN_DEBUG { append(&needed_instance_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME) }

  if check_instance_extensions(needed_instance_extensions[:])
  {
    instance_info: vk.InstanceCreateInfo =
    {
      sType            = .INSTANCE_CREATE_INFO,
      pApplicationInfo = &app_info,
      ppEnabledExtensionNames = raw_data(needed_instance_extensions),
      enabledExtensionCount = u32(len(needed_instance_extensions)),
    }

    debug_messenger_info: vk.DebugUtilsMessengerCreateInfoEXT =
    {
      sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
      messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
      messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE,},
      pfnUserCallback = vk_debug_callback,
      pUserData       = &state.main_context.logger
    }

    needed_layers: []cstring
    when ODIN_DEBUG
    {
      needed_layers =
      {
        "VK_LAYER_KHRONOS_validation",
      }

      if check_layers(needed_layers)
      {
        instance_info.enabledLayerCount   = u32(len(needed_layers))
        instance_info.ppEnabledLayerNames = raw_data(needed_layers)
        instance_info.pNext               = &debug_messenger_info
      }
      else
      {
        log.warnf("Validation layers not enabled.")
      }
    }

    vk_assert(vk.CreateInstance(&instance_info, nil, &vks.instance),
              "Unable to create vulkan instance.")

    vk.load_proc_addresses_instance(vks.instance)

    when ODIN_DEBUG
    {
      vk_assert(vk.CreateDebugUtilsMessengerEXT(vks.instance, &debug_messenger_info, nil, &vks.messenger),
                "Unable to create vulkan debug messenger.")
    }

    // // //
    // Surface
    // // //

    vk_assert(glfw.CreateWindowSurface(vks.instance, window.handle, nil, &vks.surface),
              "Unable to create vulkan window surface.")

    // // //
    // Pick Physical Device
    // // //

    needed_device_extensions: []cstring =
    {
      vk.KHR_SWAPCHAIN_EXTENSION_NAME,
    }

    needed_device_features13: vk.PhysicalDeviceVulkan13Features =
    {
      sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
      synchronization2 = true,
      dynamicRendering = true,
    }
    needed_device_features12: vk.PhysicalDeviceVulkan12Features =
    {
      sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
      bufferDeviceAddress = true,
      descriptorIndexing  = true,
      pNext = &needed_device_features13,
    }
    needed_device_features11: vk.PhysicalDeviceVulkan11Features =
    {
      sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
      pNext = &needed_device_features12,
    }
    needed_device_features: vk.PhysicalDeviceFeatures2 =
    {
      sType = .PHYSICAL_DEVICE_FEATURES_2,
      pNext = &needed_device_features11,
    }

    queue_indices: [Queue_Kind]union{u32}
    vks.physical, queue_indices = pick_physical_device(vks.instance, vks.surface, needed_device_features, needed_device_extensions)

    if vks.physical != nil
    {
      // // //
      // Logical Device
      // // //

      // Collect only unique queues
      priority: f32 = 1.0
      queue_infos:  [dynamic; len(Queue_Kind)]vk.DeviceQueueCreateInfo
      used_indices: [dynamic; len(Queue_Kind)]u32
      for index in queue_indices
      {
        used_index := false
        for used in used_indices
        {
          if used == index.(u32)
          {
            used_index = true
            break
          }
        }

        if !used_index
        {
          append(&queue_infos, vk.DeviceQueueCreateInfo {
            sType            = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = index.(u32),
            queueCount       = 1,
            pQueuePriorities = &priority,
          })
          append(&used_indices, index.(u32))
        }
      }

      device_info: vk.DeviceCreateInfo =
      {
        sType                   = .DEVICE_CREATE_INFO,
        pQueueCreateInfos       = raw_data(&queue_infos),
        queueCreateInfoCount    = u32(len(queue_infos)),
        enabledLayerCount       = u32(len(needed_layers)),
        ppEnabledLayerNames     = raw_data(needed_layers),
        enabledExtensionCount   = u32(len(needed_device_extensions)),
        ppEnabledExtensionNames = raw_data(needed_device_extensions),
        pNext                   = &needed_device_features,
      }

      vk_assert(vk.CreateDevice(vks.physical, &device_info, nil, &vks.logical),
                "Unable to create vulkan logical device.")

      vk.load_proc_addresses_device(vks.logical)

      // Grab queues
      for index, kind in queue_indices
      {
        vk.GetDeviceQueue(vks.logical, index.(u32), 0, &vks.queues[kind])
      }

      // // //
      // Create Swapchain
      // // //

      vks.swapchain = make_swapchain(window, vks.logical, vks.physical, vks.surface, {})

      // // //
      // Frame stuff
      // // //

      for &frame in vks.frames
      {
        pool_info: vk.CommandPoolCreateInfo =
        {
          sType = .COMMAND_POOL_CREATE_INFO,
          flags = {.TRANSIENT},
          queueFamilyIndex = queue_indices[.GRAPHICS].(u32)
        }
        vk_assert(vk.CreateCommandPool(vks.logical, &pool_info, nil, &frame.pool),
                  "Unable to create vulkan command pool.")

        buffer_info: vk.CommandBufferAllocateInfo =
        {
          sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
          commandPool        = frame.pool,
          commandBufferCount = 1,
          level              = .PRIMARY,
        }
        vk_assert(vk.AllocateCommandBuffers(vks.logical, &buffer_info, &frame.buffer),
                  "Unable to allocate vulkan command buffer.")

        fence_info: vk.FenceCreateInfo =
        {
          sType = .FENCE_CREATE_INFO,
          flags = {.SIGNALED},
        }
        vk_assert(vk.CreateFence(vks.logical, &fence_info, nil, &frame.fence),
                  "Unable to create vulkan fence")

        semaphore_info: vk.SemaphoreCreateInfo =
        {
          sType = .SEMAPHORE_CREATE_INFO,
        }
        vk_assert(vk.CreateSemaphore(vks.logical, &semaphore_info, nil, &frame.semaphore),
                  "Unable to create vulkan frame semaphore")
      }

      // // //
      // Memory
      // // //
      // FIXME: Ok should probably just be a variable.
      ok: bool
      vks.arenas[.DEVICE], ok = make_vulkan_arena(vks.logical, vks.physical,
                                                  256 * mem.Megabyte, {.TRANSFER_DST, .STORAGE_BUFFER, .VERTEX_BUFFER, .INDEX_BUFFER},
                                                  {.DEVICE_LOCAL}, 256 * mem.Megabyte)
      if !ok { log.fatalf("Unable to create device local vulkan arena.") }

      vks.arenas[.HOST], ok = make_vulkan_arena(vks.logical, vks.physical,
                                                256 * mem.Megabyte, {.TRANSFER_SRC, .UNIFORM_BUFFER, .STORAGE_BUFFER, .VERTEX_BUFFER, .INDEX_BUFFER},
                                                {.HOST_VISIBLE, .HOST_COHERENT}, 256 * mem.Megabyte)
      if !ok { log.fatalf("Unable to create host vulkan arena.") }
    }
    else
    {
      log.fatalf("Unable to find suitable physical device for vulkan.")
    }
  }

  // TODO:
  return true
}

get_queue_indices :: proc(physical: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (queue_indices: [Queue_Kind]union{u32})
{
  queue_families: []vk.QueueFamilyProperties
  {
    queue_family_count: u32
    vk.GetPhysicalDeviceQueueFamilyProperties(physical, &queue_family_count, nil)
    queue_families = make([]vk.QueueFamilyProperties, queue_family_count, context.temp_allocator)
    vk.GetPhysicalDeviceQueueFamilyProperties(physical, &queue_family_count, raw_data(queue_families))
  }

  for family, idx in queue_families
  {
    idx := u32(idx)

    if .GRAPHICS in family.queueFlags { queue_indices[.GRAPHICS] = idx}

    present_support: b32
    vk.GetPhysicalDeviceSurfaceSupportKHR(physical, idx, surface, &present_support)
    if present_support { queue_indices[.PRESENT] = idx }
  }

  return queue_indices
}

@(private="file")
make_swapchain :: proc(window: Window, logical: vk.Device, physical: vk.PhysicalDevice, surface: vk.SurfaceKHR, old: Swapchain) -> (new: Swapchain)
{
  if old.handle != 0
  {
    vk.DeviceWaitIdle(logical)
    free_swapchain(old)
  }

  surface_format := choose_surface_format(physical, surface)
  present_mode := choose_present_mode(physical, surface)
  extent, image_count, capabilities := choose_surface_capabilities(window, physical, surface)

  // Finally clamp image count less than defined max targets
  image_count = min(image_count, cap(new.targets))

  swapchain_info: vk.SwapchainCreateInfoKHR =
  {
    sType            = .SWAPCHAIN_CREATE_INFO_KHR,
    surface          = surface,
    minImageCount    = image_count,
    imageFormat      = surface_format.format,
    imageColorSpace  = surface_format.colorSpace,
    imageExtent      = extent,
    imageArrayLayers = 1,
    imageUsage       = {.COLOR_ATTACHMENT, .TRANSFER_DST},
    preTransform     = capabilities.currentTransform,
    compositeAlpha   = {.OPAQUE},
    presentMode      = present_mode,
    clipped          = true,
    imageSharingMode = .EXCLUSIVE, // By default
    oldSwapchain     = old.handle,
  }

  queue_indices := get_queue_indices(physical, surface)

  // HACK: Not really sure what this would really entail, but tutorials say to do this.
  if queue_indices[.GRAPHICS] != queue_indices[.PRESENT]
  {
    as_array := []u32{queue_indices[.GRAPHICS].(u32), queue_indices[.PRESENT].(u32)}
    swapchain_info.imageSharingMode = .CONCURRENT
    swapchain_info.queueFamilyIndexCount = u32(len(as_array))
    swapchain_info.pQueueFamilyIndices   = raw_data(as_array)
  }

  vk_assert(vk.CreateSwapchainKHR(logical, &swapchain_info, nil, &new.handle),
            "Unable to create vulkan swapchain.")

  new.format = surface_format.format
  new.extent = extent

  actual_image_count: u32
  vk.GetSwapchainImagesKHR(logical, new.handle, &actual_image_count, nil)
  assert(actual_image_count <= cap(new.targets) && actual_image_count == image_count)
  temp_images: [cap(new.targets)]vk.Image
  vk.GetSwapchainImagesKHR(logical, new.handle, &actual_image_count, raw_data(temp_images[:]))

  resize(&new.targets, actual_image_count)
  for &target, i in &new.targets
  {
    target.image = temp_images[i]

    view_info: vk.ImageViewCreateInfo =
    {
      sType    = .IMAGE_VIEW_CREATE_INFO,
      image    = target.image,
      format   = new.format,
      viewType = .D2,
      components = {.IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY},
      subresourceRange =
      {
        aspectMask     = {.COLOR},
        baseMipLevel   = 0,
        levelCount     = 1,
        baseArrayLayer = 0,
        layerCount     = 1,
      },
    }

    vk_assert(vk.CreateImageView(logical, &view_info, nil, &target.view),
              "Unable to create vulkan swapchain image view.")

    semaphore_info: vk.SemaphoreCreateInfo =
    {
      sType = .SEMAPHORE_CREATE_INFO,
    }
    vk_assert(vk.CreateSemaphore(logical, &semaphore_info, nil, &target.semaphore),
              "Unable to create vulkan swapchain image semaphore.")
  }

  return new
}

@(private="file")
make_vulkan_arena :: proc(logical: vk.Device, physical: vk.PhysicalDevice,
                            buffer_size: vk.DeviceSize, buffer_usage: vk.BufferUsageFlags,
                            memory_properties: vk.MemoryPropertyFlags,
                            extra_size: vk.DeviceSize) -> (arena: Vulkan_Arena, ok: bool)
{
  buffer_info: vk.BufferCreateInfo =
  {
    sType = .BUFFER_CREATE_INFO,
    size  = buffer_size,
    usage = buffer_usage,
    sharingMode = .EXCLUSIVE,
  }
  vk_assert(vk.CreateBuffer(logical, &buffer_info, nil, &arena.buffer),
            "Unable to create vulkan arena buffer.")

  buffer_memory_requirements: vk.MemoryRequirements
  vk.GetBufferMemoryRequirements(logical, arena.buffer, &buffer_memory_requirements)

  combined_memory_requirements := buffer_memory_requirements
  combined_memory_requirements.size += extra_size

  arena.memory_type, ok = pick_memory_type(physical, combined_memory_requirements, memory_properties)
  if ok
  {
    allocate_info: vk.MemoryAllocateInfo =
    {
      sType = .MEMORY_ALLOCATE_INFO,
      memoryTypeIndex = arena.memory_type,
      allocationSize  = combined_memory_requirements.size,
    }
    vk_assert(vk.AllocateMemory(logical, &allocate_info, nil, &arena.memory),
              "Unable to allocate memory for vulkan arena buffer.")

    vk_assert(vk.BindBufferMemory(logical, arena.buffer, arena.memory, 0),
              "Unable to bind memory to vulkan arena buffer.")

    arena.memory_size = allocate_info.allocationSize // Total
    // Push memory offset past the buffer, any further allocations shall go afterwards
    arena.memory_offset = buffer_memory_requirements.size
    arena.buffer_size = buffer_memory_requirements.size
  }
  else
  {
    log.errorf("Unable to find memory type for vulkan arena.")
  }

  return arena, ok
}

@(private="file")
vk_get_render_internal :: proc(internal: Renderer_Internal) -> (vulkan: Vulkan_Internal)
{
  return vks.internals[internal]
}

@(private="file")
vk_get_image :: proc(internal: Renderer_Internal) -> (image: Vulkan_Image)
{
  return vk_get_render_internal(internal).(Vulkan_Image)
}

begin_drawing :: proc(draw_into: Texture) -> (ok: bool)
{
  ok = true

  A_SECOND :: 1000000000

  frame := vks.frames[vks.curr_index[.FRAME]]
  vk_assert(vk.WaitForFences(vks.logical, 1, &frame.fence, true, A_SECOND),
            "Unable to wait on vulkan fence.")

  vk_assert(vk.ResetFences(vks.logical, 1, &frame.fence),
            "Unable to reset vulkan fence.")

  // Try to acquire an image, when we do: signal this frames semaphore we can start rendering.
  if acquire := vk.AcquireNextImageKHR(vks.logical, vks.swapchain.handle, A_SECOND, frame.semaphore, {}, &vks.curr_index[.TARGET]);
     acquire != .SUCCESS
  {
    if state.window.should_resize || acquire == .ERROR_OUT_OF_DATE_KHR
    {
      log.infof("Resizing swapchain.")
      vks.swapchain = make_swapchain(state.window, vks.logical, vks.physical, vks.surface, vks.swapchain)
      state.window.should_resize = false
    }
    else
    {
      log.errorf("Unable to acquire next vulkan swapchain image: %v.", acquire)
    }

    ok = false
  }

  if ok
  {
    vk_assert(vk.ResetCommandPool(vks.logical, frame.pool, {}),
      "Unable to reset vulkan command pool.")

    buffer_info: vk.CommandBufferBeginInfo =
    {
      sType = .COMMAND_BUFFER_BEGIN_INFO,
      flags = {.ONE_TIME_SUBMIT},
    }
    vk_assert(vk.BeginCommandBuffer(frame.buffer, &buffer_info),
      "Unable to begin vulkan command buffer recording.")

    draw_image := vk_get_image(draw_into.internal)

    vk_transition_image(frame.buffer, draw_image.image,
                        .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL,
                        {.TOP_OF_PIPE}, {},
                        {.COLOR_ATTACHMENT_OUTPUT}, {.COLOR_ATTACHMENT_WRITE})

    color: vk.ClearColorValue = { float32 = LEARN_OPENGL_ORANGE }
    color_attachment: vk.RenderingAttachmentInfo =
    {
      sType       = .RENDERING_ATTACHMENT_INFO,
      imageView   = draw_image.view,
      imageLayout = .COLOR_ATTACHMENT_OPTIMAL, // TODO
      loadOp      = .CLEAR,
      storeOp     = .STORE,
      clearValue  = { color = color }
    }
    rendering_info: vk.RenderingInfo =
    {
      sType                = .RENDERING_INFO,
      renderArea           = { extent = { draw_into.width, draw_into.height} },
      layerCount           = 1,
      colorAttachmentCount = 1,
      pColorAttachments    = &color_attachment,
    }

    vk.CmdBeginRendering(frame.buffer, &rendering_info)
    vk.CmdBindPipeline(frame.buffer, .GRAPHICS, vk_get_render_internal(triangle.internal).(Vulkan_Pipeline).pipeline)

    viewport: vk.Viewport =
    {
        width    = f32(draw_into.width),
        height   = f32(draw_into.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }
    scissor: vk.Rect2D =
    {
        offset = { 0, 0 },
        extent = { draw_into.width, draw_into.height },
    }
    vk.CmdSetViewport(frame.buffer, 0, 1, &viewport)
    vk.CmdSetScissor(frame.buffer, 0, 1, &scissor)
    vk.CmdSetCullMode(frame.buffer, {})
    vk.CmdSetFrontFace(frame.buffer, .COUNTER_CLOCKWISE)
    vk.CmdSetDepthTestEnable(frame.buffer, false)
    vk.CmdSetDepthWriteEnable(frame.buffer, false)
    vk.CmdSetDepthCompareOp(frame.buffer, .LESS_OR_EQUAL)
    vk.CmdSetDepthBiasEnable(frame.buffer, false)
    vk.CmdSetStencilTestEnable(frame.buffer, false)
    vk.CmdSetDepthBias(frame.buffer, 0, 0, 0)
    vk.CmdSetStencilOp(frame.buffer, {.FRONT, .BACK}, .KEEP, .KEEP, .KEEP, .ALWAYS)

    vk.CmdDraw(frame.buffer, 3, 1, 0, 0)

    vk.CmdEndRendering(frame.buffer)
  }

  return ok
}

flush_drawing :: proc(to_display: Texture)
{
  frame := vks.frames[vks.curr_index[.FRAME]]
  target := vks.swapchain.targets[vks.curr_index[.TARGET]]

  display_image := vk_get_image(to_display.internal)

  // Barrier for all color writes to be finished to the final image, and transition it to be src for transfer
  vk_transition_image(frame.buffer, display_image.image,
                      .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL,
                      {.COLOR_ATTACHMENT_OUTPUT}, {.COLOR_ATTACHMENT_WRITE}, // We've written to it
                      {.TRANSFER}, {.TRANSFER_READ}) // Now we want to writ it to the swapchain

  // Transfer swapchain image to be ready for blitting draw image to it.
  vk_transition_image(frame.buffer, target.image,
                      .UNDEFINED, .TRANSFER_DST_OPTIMAL,
                      {.TOP_OF_PIPE}, {}, // Top of pipe since we already waited on sem, no src access
                      {.TRANSFER}, {.TRANSFER_WRITE}) // Blit destination

  vk_blit_images(display_image.image, target.image, to_display.width, to_display.height,
                 vks.swapchain.extent.width, vks.swapchain.extent.height)

  vk_transition_image(frame.buffer, target.image,
                      .TRANSFER_DST_OPTIMAL, .PRESENT_SRC_KHR,
                      {.TRANSFER}, {.TRANSFER_WRITE},
                      {.BOTTOM_OF_PIPE}, {})

  vk_assert(vk.EndCommandBuffer(frame.buffer),
            "Unable to end vulkan command buffer recording.")

  cmd_info: vk.CommandBufferSubmitInfo =
  {
    sType         = .COMMAND_BUFFER_SUBMIT_INFO,
    commandBuffer = frame.buffer,
  }

  // We wait for this frame to acquire an image.
  wait_info   := semaphore_submit_info(frame.semaphore, {.COLOR_ATTACHMENT_OUTPUT})

  // After submitting we signal that this target is ready for presentation.
  signal_info := semaphore_submit_info(target.semaphore, {.ALL_GRAPHICS})

  submit_info: vk.SubmitInfo2 =
  {
    sType                    = .SUBMIT_INFO_2,
    pSignalSemaphoreInfos    = &signal_info,
    signalSemaphoreInfoCount = 1,
    pWaitSemaphoreInfos      = &wait_info,
    waitSemaphoreInfoCount   = 1,
    pCommandBufferInfos      = &cmd_info,
    commandBufferInfoCount   = 1,
  }

  // Submit all rendering commands for this frame, waiting for the image,
  // and signalling that we are done rendering
  // as well as fencing this frame
  vk_assert(vk.QueueSubmit2(vks.queues[.GRAPHICS], 1, &submit_info, frame.fence),
            "Unable to submit vulkan command buffer recording.")

  // Finally wait to present until this target is done with rendering.
  swap_handle := vks.swapchain.handle // To take pointer of
  present_info: vk.PresentInfoKHR =
  {
    sType              = .PRESENT_INFO_KHR,
    pSwapchains        = &swap_handle,
    swapchainCount     = 1,
    pWaitSemaphores    = &target.semaphore, // Wait for all draws to be done on this target
    waitSemaphoreCount = 1,
    pImageIndices      = &vks.curr_index[.TARGET],
  }

  if present := vk.QueuePresentKHR(vks.queues[.PRESENT], &present_info);
     present != .SUCCESS
  {
    if state.window.should_resize || present == .ERROR_OUT_OF_DATE_KHR
    {
      log.infof("Resizing swapchain.")
      vks.swapchain = make_swapchain(state.window, vks.logical, vks.physical, vks.surface, vks.swapchain)
      state.window.should_resize = false
    }
    else
    {
      log.errorf("Unable to submit vulkan image for presentation: %v.", present)
    }
  }

  vks.curr_index[.FRAME] = (vks.curr_index[.FRAME] + 1) % len(vks.frames)
}

// NOTE: Hardcoded for color, mostly just for blitting from a texture to a swap image
@(private="file")
vk_blit_images :: proc(src, dst: vk.Image, src_w, src_h, dst_w, dst_h: u32)
{
  blit_region :vk.ImageBlit2 =
  {
    sType = .IMAGE_BLIT_2,
    srcOffsets = {{0,0,0}, {i32(src_w), i32(src_h), 1}},
    srcSubresource =
    {
      aspectMask = {.COLOR},
      layerCount = 1,
    },
    dstOffsets = {{0,0,0}, {i32(dst_w), i32(dst_h), 1}},
    dstSubresource =
    {
      aspectMask = {.COLOR},
      layerCount = 1,
    },
  }

  blit_info: vk.BlitImageInfo2 =
  {
    sType          = .BLIT_IMAGE_INFO_2,
    srcImage       = src,
    srcImageLayout = .TRANSFER_SRC_OPTIMAL,
    dstImage       = dst,
    dstImageLayout = .TRANSFER_DST_OPTIMAL,
    filter         = .LINEAR,
    pRegions       = &blit_region,
    regionCount    = 1,
  }

  vk.CmdBlitImage2(vk_cmd(), &blit_info)
}

vk_cmd :: proc() -> (buffer: vk.CommandBuffer)
{
  buffer = vks.frames[vks.curr_index[.FRAME]].buffer
  assert(buffer != nil)

  return buffer
}

@(private="file")
vk_arena_push :: proc(arena: Vulkan_Arena_Kind, size: vk.DeviceSize, alignment: vk.DeviceSize) -> (aligned_offset: vk.DeviceSize)
{
  aligned_offset = (vks.arenas[arena].memory_offset + alignment - 1) & ~(alignment - 1)

  assert(aligned_offset + size < vks.arenas[arena].memory_size,
         "Vulkan arena out of memory.")

  vks.arenas[arena].memory_offset = aligned_offset + size

  return aligned_offset
}

@(private="file")
vk_push_internal :: proc(item: Vulkan_Internal) -> (internal: Renderer_Internal)
{
  assert(append(&vks.internals, item) == 1,
         "Too many items for vulkan api object pool.")

  return Renderer_Internal(len(vks.internals) - 1)
}

vk_format_table: [Pixel_Format]vk.Format =
{
  .NONE             = .UNDEFINED,
  .R8               = .R8_UNORM,
  .RGB8             = .R8G8B8_UNORM,
  .RGBA8            = .R8G8B8A8_UNORM,
  .SRGB8            = .R8G8B8_SRGB,
  .SRGBA8           = .R8G8B8A8_SRGB,
  .RGBA16F          = .R16G16B16A16_SFLOAT,
  .DEPTH32          = .D32_SFLOAT,
  .DEPTH24_STENCIL8 = .D24_UNORM_S8_UINT,
}

vk_alloc_texture :: proc(type: Texture_Type, format: Pixel_Format, sampler: Sampler_Preset,
                         width, height, samples, array_count, mip_count: u32, is_render_target: bool) -> (handle: Renderer_Internal)
{

  vk_samples: vk.SampleCountFlags
  switch samples
  {
    case:
      log.errorf("Invalid sample count requested for texture.")
      fallthrough // use 1 sample if invalid
    case 1: vk_samples = {._1}
    case 2: vk_samples = {._2}
    case 4: vk_samples = {._4}
    case 8: vk_samples = {._8}
  }

  usage: vk.ImageUsageFlags = {.TRANSFER_DST, .SAMPLED} // Always
  if mip_count > 1 { usage += {.TRANSFER_SRC} } // Will have to read to generate mips

  if is_render_target
  {
    usage += {.STORAGE, .TRANSFER_SRC}
    if format == .DEPTH32 || format == .DEPTH24_STENCIL8
    {
      usage += {.DEPTH_STENCIL_ATTACHMENT}
    }
    else
    {
      usage += {.COLOR_ATTACHMENT}
    }
  }

  flags: vk.ImageCreateFlags
  if type == .CUBE || type == .CUBE_ARRAY { flags |= {.CUBE_COMPATIBLE} }

  image_info: vk.ImageCreateInfo =
  {
    sType       = .IMAGE_CREATE_INFO,
    imageType   = .D2, // NOTE: Hardcoded.
    extent      = {width, height, 1}, // NOTE: Hardcoded.
    format      = vk_format_table[format],
    mipLevels   = mip_count, // TODO: Generate mipmaps.
    arrayLayers = array_count,
    samples     = vk_samples,
    tiling      = .OPTIMAL, // Currently not ever reading back textures sooo.
    usage       = usage,
  }

  image: Vulkan_Image

  vk_assert(vk.CreateImage(vks.logical, &image_info, nil, &image.image),
            "Unable to create vulkan image.")

  vk_view_type_table: [Texture_Type]vk.ImageViewType =
  {
    .NONE = .D1, // Shouldn't happen
    .D2   = .D2,
    .CUBE = .CUBE,
    .CUBE_ARRAY = .CUBE,
  }

  components: vk.ComponentMapping = {.IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY} if format != .R8 else {.R, .R, .R, .R }

  requirements: vk.MemoryRequirements
  vk.GetImageMemoryRequirements(vks.logical, image.image, &requirements)

  assert(requirements.memoryTypeBits & (1 << vks.arenas[.DEVICE].memory_type) != 0,
         "Image memory requirements not compatible with arena.")

  memory_offset := vk_arena_push(.DEVICE, requirements.size, requirements.alignment)

  vk_assert(vk.BindImageMemory(vks.logical, image.image, vks.arenas[.DEVICE].memory, memory_offset),
            "Unable to bind vulkan image memory.")

  view_info: vk.ImageViewCreateInfo =
  {
    sType      = .IMAGE_VIEW_CREATE_INFO,
    image      = image.image,
    format     = image_info.format,
    viewType   = vk_view_type_table[type],
    components = components,
    subresourceRange = vk_image_range(pixel_format_to_vk_aspects(format), mip_count = mip_count,  array_count = array_count)
  }

  vk_assert(vk.CreateImageView(vks.logical, &view_info, nil, &image.view),
            "Unable to create vulkan image view.")

  return vk_push_internal(image)
}

vk_make_pipeline :: proc(vert_code, frag_code: []byte, color_format, depth_format: Pixel_Format) -> (internal: Renderer_Internal)
{
  make_shader_module :: proc(code: []byte) -> (module: vk.ShaderModule)
  {
    info: vk.ShaderModuleCreateInfo =
    {
      sType    = .SHADER_MODULE_CREATE_INFO,
      pCode    = cast(^u32)raw_data(code),
      codeSize = len(code),
    }

    vk_assert(vk.CreateShaderModule(vks.logical, &info, nil, &module),
              "Unable to create vulkan shader module")

    return module
  }

  vert_mod := make_shader_module(vert_code)
  defer vk.DestroyShaderModule(vks.logical, vert_mod, nil)
  frag_mod := make_shader_module(frag_code)
  defer vk.DestroyShaderModule(vks.logical, frag_mod, nil)

  // // //
  // The Pain begins
  // // //

  stages: []vk.PipelineShaderStageCreateInfo =
  {
    { sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = vert_mod, pName = "main", },
    { sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag_mod, pName = "main", }
  }

  // Do vertex pulling.
  vertex: vk.PipelineVertexInputStateCreateInfo = { sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO, }

  assembly: vk.PipelineInputAssemblyStateCreateInfo =
  {
    sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
    topology = .TRIANGLE_LIST
  }

  // Always. From research most desktop gpus already have these in hardware as dynamic.
  dynamic_states: []vk.DynamicState =
  {
    .VIEWPORT,
    .SCISSOR,
    .CULL_MODE,
    .FRONT_FACE,
    .DEPTH_TEST_ENABLE,
    .DEPTH_WRITE_ENABLE,
    .DEPTH_COMPARE_OP,
    .DEPTH_BIAS_ENABLE,
    .DEPTH_BIAS,
    .STENCIL_OP,
    .STENCIL_TEST_ENABLE,
  }
  dynamic_info: vk.PipelineDynamicStateCreateInfo =
  {
    sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
    pDynamicStates    = raw_data(dynamic_states),
    dynamicStateCount = u32(len(dynamic_states)),
  }
  viewport: vk.PipelineViewportStateCreateInfo =
  {
    sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
    scissorCount  = 1,
    viewportCount = 1,
  }

  rasterize: vk.PipelineRasterizationStateCreateInfo =
  {
    sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
    polygonMode = .FILL,
    cullMode    = {.BACK},
    frontFace   = .COUNTER_CLOCKWISE,
    lineWidth   = 1.0,
  }

  // FIXME: Allow others
  multisample: vk.PipelineMultisampleStateCreateInfo =
  {
    sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
    rasterizationSamples = {._1},
  }

  // FIXME: Not allowing transparency
  blend_attach: vk.PipelineColorBlendAttachmentState =
  {
    colorWriteMask = {.R, .G, .B, .A},
    blendEnable    = false,
  }
  color_blend: vk.PipelineColorBlendStateCreateInfo =
  {
    sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
    pAttachments    = &blend_attach,
    attachmentCount = 1,
  }

  depth_stencil: vk.PipelineDepthStencilStateCreateInfo =
  {
    sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
  }

  vk_color_format   := vk_format_table[color_format]
  vk_depth_format   := vk_format_table[depth_format]
  vk_stencil_format := vk_format_table[depth_format] if depth_format == .DEPTH24_STENCIL8 else .UNDEFINED
  rendering: vk.PipelineRenderingCreateInfo =
  {
    sType                   = .PIPELINE_RENDERING_CREATE_INFO,
    colorAttachmentCount    = 1 if color_format != .NONE else 0,
    pColorAttachmentFormats = &vk_color_format,
    depthAttachmentFormat   = vk_depth_format,
    stencilAttachmentFormat = vk_stencil_format,
  }

  pipeline: Vulkan_Pipeline

  // FIXME!
  layout_info: vk.PipelineLayoutCreateInfo =
  {
    sType = .PIPELINE_LAYOUT_CREATE_INFO,
  }

  vk_assert(vk.CreatePipelineLayout(vks.logical, &layout_info, nil, &pipeline.layout),
            "Unable to create vulkan pipeline layout.")

  pipeline_info: vk.GraphicsPipelineCreateInfo =
  {
    sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
    pNext               = &rendering,
    stageCount          = u32(len(stages)),
    pStages             = raw_data(stages),
    pColorBlendState    = &color_blend,
    pDepthStencilState  = &depth_stencil,
    pDynamicState       = &dynamic_info,
    pInputAssemblyState = &assembly,
    pMultisampleState   = &multisample,
    pRasterizationState = &rasterize,
    pVertexInputState   = &vertex,
    pViewportState      = &viewport,
    layout              = pipeline.layout,
  }

  vk_assert(vk.CreateGraphicsPipelines(vks.logical, {}, 1, &pipeline_info, nil, &pipeline.pipeline),
            "Unable to create vulkan pipeline layout.")

  return vk_push_internal(pipeline)
}

@(private="file")
semaphore_submit_info :: proc(semaphore: vk.Semaphore, stage: vk.PipelineStageFlags2) -> (info: vk.SemaphoreSubmitInfo)
{
  info =
  {
    sType = .SEMAPHORE_SUBMIT_INFO,
    value = 1,
    stageMask = stage,
    semaphore = semaphore,
  }

  return info
}

// All mips and all layers by default
vk_image_range :: proc(aspects: vk.ImageAspectFlags,
                       mip_base: u32 = 0, mip_count: u32 = vk.REMAINING_MIP_LEVELS,
                       array_base: u32 = 0, array_count: u32 = vk.REMAINING_ARRAY_LAYERS) -> (range: vk.ImageSubresourceRange)
{
  range =
  {
    aspectMask     = aspects,
    baseArrayLayer = array_base,
    layerCount     = array_count,
    baseMipLevel   = mip_base,
    levelCount     = mip_count,
  }

  return range
}

@(private="file")
vk_transition_image :: proc(cmd: vk.CommandBuffer, image: vk.Image,
                            old, new:   vk.ImageLayout,
                            src_stage:  vk.PipelineStageFlags2,
                            src_access: vk.AccessFlags2,
                            dst_stage:  vk.PipelineStageFlags2,
                            dst_access: vk.AccessFlags2)
{
  barrier: vk.ImageMemoryBarrier2 =
  {
    sType         = .IMAGE_MEMORY_BARRIER_2,
    srcStageMask  = src_stage,
    srcAccessMask = src_access,
    dstStageMask  = dst_stage,
    dstAccessMask = dst_access,
    oldLayout     = old,
    newLayout     = new,
    image         = image,
    subresourceRange = vk_image_range(new == .DEPTH_ATTACHMENT_OPTIMAL ? {.DEPTH} : {.COLOR}),
  }

  dependency: vk.DependencyInfo =
  {
    sType                   = .DEPENDENCY_INFO,
    pImageMemoryBarriers    = &barrier,
    imageMemoryBarrierCount = 1,
  }

  vk.CmdPipelineBarrier2(cmd, &dependency)
}

@(private="file")
free_swapchain :: proc(swapchain: Swapchain)
{
  for target in vks.swapchain.targets
  {
    vk.DestroyImageView(vks.logical, target.view, nil)
    vk.DestroySemaphore(vks.logical, target.semaphore, nil)
  }
  vk.DestroySwapchainKHR(vks.logical, vks.swapchain.handle, nil)
}

free_vulkan :: proc()
{
  vk.DeviceWaitIdle(vks.logical)

  for internal in vks.internals
  {
    switch i in internal
    {
      case Vulkan_Image:
        vk.DestroyImage(vks.logical, i.image, nil)
        vk.DestroyImageView(vks.logical, i.view, nil)
      case Vulkan_Pipeline:
        vk.DestroyPipeline(vks.logical, i.pipeline, nil)
        vk.DestroyPipelineLayout(vks.logical, i.layout, nil)
    }
  }

  for arena, kind in vks.arenas
  {
    extra_used := arena.memory_offset - arena.buffer_size
    extra_max  := arena.memory_size - arena.buffer_size

    extra_percent  := f64(extra_used) / f64(extra_max)
    buffer_percent := f64(arena.buffer_offset) / f64(arena.buffer_size)

    log.infof("Arena %v:\n buffer used: %v/%v(%f)\n extra used: %v/%v(%f)",
              kind, arena.buffer_offset, arena.buffer_size, buffer_percent, extra_used, extra_max, extra_percent)
    vk.FreeMemory(vks.logical, arena.memory, nil)
    vk.DestroyBuffer(vks.logical, arena.buffer, nil)
  }
  for frame in vks.frames
  {
    vk.DestroyCommandPool(vks.logical, frame.pool, nil)
    vk.DestroyFence(vks.logical, frame.fence, nil)
    vk.DestroySemaphore(vks.logical, frame.semaphore, nil)
  }
  free_swapchain(vks.swapchain)
  vk.DestroySurfaceKHR(vks.instance, vks.surface, nil)
  vk.DestroyDevice(vks.logical, nil)
  when ODIN_DEBUG { vk.DestroyDebugUtilsMessengerEXT(vks. instance, vks.messenger, nil) }
  vk.DestroyInstance(vks.instance, nil)

  vks = {}
}
