package main

import "base:runtime"
import "core:strings"
import "core:log"

import "vendor:glfw"
import vk "vendor:vulkan"

Vulkan_State :: struct
{
  instance:  vk.Instance,
  messenger: vk.DebugUtilsMessengerEXT,
  physical:  vk.PhysicalDevice,
}

@(private="file")
vk_assert :: proc(result: vk.Result, message: string)
{
  assert(result == .SUCCESS, message)
}

@(private="file")
check_extensions :: proc(needed_extensions: []cstring) -> (found_all: bool)
{
  supported_extension_count: u32
  vk.EnumerateInstanceExtensionProperties(nil, &supported_extension_count, nil)
  supported_extensions := make([]vk.ExtensionProperties, supported_extension_count, context.temp_allocator)
  vk.EnumerateInstanceExtensionProperties(nil, &supported_extension_count, raw_data(supported_extensions))

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
check_layers :: proc(needed_layers: []cstring) -> (found_all: bool)
{
  supported_layer_count: u32
  vk.EnumerateInstanceLayerProperties(&supported_layer_count, nil)
  supported_layers := make([]vk.LayerProperties, supported_layer_count, context.temp_allocator)
  vk.EnumerateInstanceLayerProperties(&supported_layer_count, raw_data(supported_layers))

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

  log_proc("VK: %v", data.pMessage)

  return false
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

  needed_extensions := make([dynamic]cstring, context.temp_allocator)
  append(&needed_extensions, ..glfw_extensions)
  when ODIN_DEBUG { append(&needed_extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME) }

  if check_extensions(needed_extensions[:])
  {
    instance_info: vk.InstanceCreateInfo =
    {
      sType            = .INSTANCE_CREATE_INFO,
      pApplicationInfo = &app_info,
      ppEnabledExtensionNames = raw_data(needed_extensions),
      enabledExtensionCount = u32(len(needed_extensions)),
    }

    debug_messenger_info: vk.DebugUtilsMessengerCreateInfoEXT =
    {
      sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
      messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
      messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE,},
      pfnUserCallback = vk_debug_callback,
      pUserData       = &state.main_context.logger
    }

    when ODIN_DEBUG
    {
      needed_layers: []cstring =
      {
        "VK_LAYER_KHRONOS_validation",
      }

      if check_layers(needed_layers)
      {
        instance_info.enabledLayerCount = u32(len(needed_layers))
        instance_info.ppEnabledLayerNames = raw_data(needed_layers)
        instance_info.pNext = &debug_messenger_info
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

    device_count: u32
    vk.EnumeratePhysicalDevices(vks.instance, &device_count, nil)
    assert(device_count != 0, "No devices with vulkan support.")
    physical_devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
    vk.EnumeratePhysicalDevices(vks.instance, &device_count, raw_data(physical_devices))

    for device in physical_devices
    {
      props: vk.PhysicalDeviceProperties
      feats: vk.PhysicalDeviceFeatures
      vk.GetPhysicalDeviceProperties(device, &props)
      vk.GetPhysicalDeviceFeatures(device, &feats)

      queue_family_count: u32
      vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)
      queue_families := make([]vk.QueueFamilyProperties, queue_family_count, context.temp_allocator)
      vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_families))

      Family_Indices :: enum
      {
        GRAPHICS,
      }
      indices: [Family_Indices]union{u32}
      for family, idx in queue_families
      {
        if .GRAPHICS in family.queueFlags { indices[.GRAPHICS] = u32(idx)}
      }

      suitable := props.deviceType == .DISCRETE_GPU
      for family in indices // Check all families supported
      {
        suitable &= family != nil
      }

      if suitable
      {
        vks.physical = device
        break
      }
    }

    if vks.physical != nil
    {
      log.infof("Found device!")
    }
    else
    {
      log.errorf("Unable to find suitable physical device for vulkan.")
    }
  }

  return vks
}

free_vulkan :: proc(vk_state: ^Vulkan_State)
{
  when ODIN_DEBUG { vk.DestroyDebugUtilsMessengerEXT(vk_state. instance, vk_state.messenger, nil) }
  vk.DestroyInstance(vk_state.instance, nil)

  vk_state^ = {}
}
