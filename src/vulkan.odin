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

Vulkan_State :: struct
{
  instance:  vk.Instance,
  messenger: vk.DebugUtilsMessengerEXT,
  physical:  vk.PhysicalDevice,
  logical:   vk.Device,
  queues:    [VK_Queue_Kind]vk.Queue,
  surface:   vk.SurfaceKHR,
  swapchain: vk.SwapchainKHR,
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
    physical_devices: []vk.PhysicalDevice
    {
      device_count: u32
      vk.EnumeratePhysicalDevices(vks.instance, &device_count, nil)
      physical_devices = make([]vk.PhysicalDevice, device_count, context.temp_allocator)
      vk.EnumeratePhysicalDevices(vks.instance, &device_count, raw_data(physical_devices))
    }

    queue_indices: [VK_Queue_Kind]union{u32}

    needed_device_extensions: []cstring =
    {
      vk.KHR_SWAPCHAIN_EXTENSION_NAME,
    }

    for device in physical_devices
    {
      props: vk.PhysicalDeviceProperties
      feats: vk.PhysicalDeviceFeatures
      vk.GetPhysicalDeviceProperties(device, &props)
      vk.GetPhysicalDeviceFeatures(device, &feats)

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
        vk.GetPhysicalDeviceSurfaceSupportKHR(device, idx, vks.surface, &present_support)
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
      vk.GetPhysicalDeviceSurfacePresentModesKHR(device, vks.surface, &mode_count, nil)

      format_count: u32
      vk.GetPhysicalDeviceSurfaceFormatsKHR(device, vks.surface, &format_count, nil)

      suitable &= format_count != 0 && mode_count != 0

      if suitable
      {
        vks.physical = device
        queue_indices = indices
        break
      }
    }

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

      device_feats: vk.PhysicalDeviceFeatures
      device_info: vk.DeviceCreateInfo =
      {
        sType                   = .DEVICE_CREATE_INFO,
        pQueueCreateInfos       = raw_data(&queue_infos),
        queueCreateInfoCount    = u32(len(queue_infos)),
        pEnabledFeatures        = &device_feats,
        enabledLayerCount       = u32(len(needed_layers)),
        ppEnabledLayerNames     = raw_data(needed_layers),
        enabledExtensionCount   = u32(len(needed_device_extensions)),
        ppEnabledExtensionNames = raw_data(needed_device_extensions),
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

      swapchain_info: vk.SwapchainCreateInfoKHR =
      {
        sType            = .SWAPCHAIN_CREATE_INFO_KHR,
        surface          = vks.surface,
        minImageCount    = image_count,
        imageFormat      = surface_format.format,
        imageColorSpace  = surface_format.colorSpace,
        imageExtent      = extent,
        imageArrayLayers = 1,
        imageUsage       = {.COLOR_ATTACHMENT},
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

      vk_assert(vk.CreateSwapchainKHR(vks.logical, &swapchain_info, nil, &vks.swapchain),
                "Unable to create vulkan swapchain.")

      log.fatalf("HERE!")
    }
    else
    {
      log.errorf("Unable to find suitable physical device for vulkan.")
    }
  }

  return vks
}

free_vulkan :: proc(vks: ^Vulkan_State)
{
  vk.DestroySwapchainKHR(vks.logical, vks.swapchain, nil)
  vk.DestroySurfaceKHR(vks.instance, vks.surface, nil)
  vk.DestroyDevice(vks.logical, nil)
  when ODIN_DEBUG { vk.DestroyDebugUtilsMessengerEXT(vks. instance, vks.messenger, nil) }
  vk.DestroyInstance(vks.instance, nil)

  vks^ = {}
}
