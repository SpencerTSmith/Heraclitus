package main

import "base:runtime"
import "core:strings"
import "core:log"

import "vendor:glfw"
import vk "vendor:vulkan"


VK_Queue_Kind :: enum
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

Vulkan_State :: struct
{
  instance:   vk.Instance,
  messenger:  vk.DebugUtilsMessengerEXT,
  physical:   vk.PhysicalDevice,
  logical:    vk.Device,
  queues:     [VK_Queue_Kind]vk.Queue,
  surface:    vk.SurfaceKHR,
  swapchain:  Swapchain,
  frames:     [3]Frame_State,
  curr_frame: int,
}

@(private="file")
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
                             needed_device_extensions: []cstring,) -> (physical: vk.PhysicalDevice, queue_indices: [VK_Queue_Kind]union{u32})
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

    // TODO: Metaprogramming, can just read struct fields

    props: vk.PhysicalDeviceProperties
    vk.GetPhysicalDeviceProperties(device, &props)
    queue_families: []vk.QueueFamilyProperties
    {
      queue_family_count: u32
      vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)
      queue_families = make([]vk.QueueFamilyProperties, queue_family_count, context.temp_allocator)
      vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_families))
    }

    // Support for all needed queues
    indices: [VK_Queue_Kind]union{u32}
    for family, idx in queue_families
    {
      idx := u32(idx)

      if .GRAPHICS in family.queueFlags { indices[.GRAPHICS] = idx}

      present_support: b32
      vk.GetPhysicalDeviceSurfaceSupportKHR(device, idx, surface, &present_support)
      if present_support { indices[.PRESENT] = idx }
    }

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

init_vulkan :: proc(window: Window) -> (vks: Vulkan_State)
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

    queue_indices: [VK_Queue_Kind]union{u32}
    vks.physical, queue_indices = pick_physical_device(vks.instance, vks.surface, needed_device_features, needed_device_extensions)

    if vks.physical != nil
    {
      // // //
      // Logical Device
      // // //

      // Collect only unique queues
      priority: f32 = 1.0
      queue_infos:  [dynamic; len(VK_Queue_Kind)]vk.DeviceQueueCreateInfo
      used_indices: [dynamic; len(VK_Queue_Kind)]u32
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

      surface_format := choose_surface_format(vks.physical, vks.surface)
      present_mode := choose_present_mode(vks.physical, vks.surface)
      extent, image_count, capabilities := choose_surface_capabilities(window, vks.physical, vks.surface)

      image_count = min(image_count, cap(vks.swapchain.targets))

      swapchain_info: vk.SwapchainCreateInfoKHR =
      {
        sType            = .SWAPCHAIN_CREATE_INFO_KHR,
        surface          = vks.surface,
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
      }

      // HACK: Not really sure what this would really entail, but tutorials say to do this.
      if queue_indices[.GRAPHICS] != queue_indices[.PRESENT]
      {
        as_array := []u32{queue_indices[.GRAPHICS].(u32), queue_indices[.PRESENT].(u32)}
        swapchain_info.imageSharingMode = .CONCURRENT
        swapchain_info.queueFamilyIndexCount = u32(len(as_array))
        swapchain_info.pQueueFamilyIndices   = raw_data(as_array)
      }

      vk_assert(vk.CreateSwapchainKHR(vks.logical, &swapchain_info, nil, &vks.swapchain.handle),
                "Unable to create vulkan swapchain.")

      vks.swapchain.format = surface_format.format
      vks.swapchain.extent = extent

      {
        image_count: u32
        vk.GetSwapchainImagesKHR(vks.logical, vks.swapchain.handle, &image_count, nil)
        assert(image_count <= cap(vks.swapchain.targets))
        temp_images: [cap(vks.swapchain.targets)]vk.Image
        vk.GetSwapchainImagesKHR(vks.logical, vks.swapchain.handle, &image_count, raw_data(temp_images[:]))

        resize(&vks.swapchain.targets, image_count)
        for &target, i in &vks.swapchain.targets
        {
          target.image = temp_images[i]

          view_info: vk.ImageViewCreateInfo =
          {
            sType    = .IMAGE_VIEW_CREATE_INFO,
            image    = target.image,
            format   = vks.swapchain.format,
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

          vk_assert(vk.CreateImageView(vks.logical, &view_info, nil, &target.view),
                    "Unable to create vulkan swapchain image view.")

          semaphore_info: vk.SemaphoreCreateInfo =
          {
            sType = .SEMAPHORE_CREATE_INFO,
          }
          vk_assert(vk.CreateSemaphore(vks.logical, &semaphore_info, nil, &target.semaphore),
                    "Unable to create vulkan swapchain image semaphore.")
        }
      }

      // // //
      // Command Stuff
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
    }
    else
    {
      log.errorf("Unable to find suitable physical device for vulkan.")
    }
  }

  return vks
}

current_frame :: proc(vks: Vulkan_State) -> (frame: Frame_State)
{
  return vks.frames[vks.curr_frame]
}

begin_draw :: proc(vks: ^Vulkan_State)
{
  A_SECOND :: 1000000000

  frame := current_frame(vks^)
  vk_assert(vk.WaitForFences(vks.logical, 1, &frame.fence, true, A_SECOND),
            "Unable to wait on vulkan fence.")

  vk_assert(vk.ResetFences(vks.logical, 1, &frame.fence),
            "Unable to reset vulkan fence.")

  // Try to acquire an image, when we do: signal this frames semaphore we can start rendering.
  image_index: u32
  vk_assert(vk.AcquireNextImageKHR(vks.logical, vks.swapchain.handle, A_SECOND,
            frame.semaphore, {}, &image_index),
            "Unable to acquire next vulkan swapchain image.")

  vk_assert(vk.ResetCommandPool(vks.logical, frame.pool, {}),
            "Unable to reset vulkan command pool.")

  target := vks.swapchain.targets[image_index]

  buffer_info: vk.CommandBufferBeginInfo =
  {
    sType = .COMMAND_BUFFER_BEGIN_INFO,
    flags = {.ONE_TIME_SUBMIT},
  }
  vk_assert(vk.BeginCommandBuffer(frame.buffer, &buffer_info),
            "Unable to begin vulkan command buffer recording.")

  // Barrier on swapchain image to be writable
  transition_image(frame.buffer, target.image,
                   .UNDEFINED, .GENERAL,
                   {.TOP_OF_PIPE}, {}, // Top of pipe since we already waited on sem, no src access
                   {.COLOR_ATTACHMENT_OUTPUT}, {.COLOR_ATTACHMENT_WRITE}) // Writing to the color part


  range := image_range({.COLOR})
  color: vk.ClearColorValue = { float32 = LEARN_OPENGL_BLUE }
  vk.CmdClearColorImage(frame.buffer, target.image, .GENERAL, &color, 1, &range)

  // Barrier for all color writes to be finished to the final image
  transition_image(frame.buffer, target.image,
                   .GENERAL, .PRESENT_SRC_KHR,
                   {.COLOR_ATTACHMENT_OUTPUT}, {.COLOR_ATTACHMENT_WRITE}, // We've written to it
                   {.BOTTOM_OF_PIPE}, {}) // We are done with this image

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
    pImageIndices      = &image_index,
  }
  vk_assert(vk.QueuePresentKHR(vks.queues[.PRESENT], &present_info),
            "Unable to submit vulkan image presentation.")

  vks.curr_frame = (vks.curr_frame + 1) % len(vks.frames)
}

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
@(private="file")
image_range :: proc(aspects: vk.ImageAspectFlags,
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

transition_image :: proc(cmd: vk.CommandBuffer, image: vk.Image,
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
    subresourceRange = image_range(new == .DEPTH_ATTACHMENT_OPTIMAL ? {.DEPTH} : {.COLOR}),
  }

  dependency: vk.DependencyInfo =
  {
    sType                   = .DEPENDENCY_INFO,
    pImageMemoryBarriers    = &barrier,
    imageMemoryBarrierCount = 1,
  }

  vk.CmdPipelineBarrier2(cmd, &dependency)
}

free_vulkan :: proc(vks: ^Vulkan_State)
{
  vk.DeviceWaitIdle(vks.logical)
  for frame in vks.frames
  {
    vk.DestroyCommandPool(vks.logical, frame.pool, nil)
    vk.DestroyFence(vks.logical, frame.fence, nil)
    vk.DestroySemaphore(vks.logical, frame.semaphore, nil)
  }
  for target in vks.swapchain.targets
  {
    vk.DestroyImageView(vks.logical, target.view, nil)
    vk.DestroySemaphore(vks.logical, target.semaphore, nil)
  }
  vk.DestroySwapchainKHR(vks.logical, vks.swapchain.handle, nil)
  vk.DestroySurfaceKHR(vks.instance, vks.surface, nil)
  vk.DestroyDevice(vks.logical, nil)
  when ODIN_DEBUG { vk.DestroyDebugUtilsMessengerEXT(vks. instance, vks.messenger, nil) }
  vk.DestroyInstance(vks.instance, nil)

  vks^ = {}
}
