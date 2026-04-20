package slang

when ODIN_OS == .Windows
{
  foreign import lib "src/slang/lib/slang.lib"
}
when ODIN_OS == .Linux
{
  foreign import lib "lib/libslang.so"
}

SLANG_API_VERSION :: 0

Result    :: distinct i32
ProfileID :: distinct i32

result_failed :: #force_inline proc(r: Result) -> bool { return r < 0 }

CompileTarget :: enum i32
{
	UNKNOWN,
	None,
	GLSL,
	GLSL_VULKAN_DEPRECATED,
	GLSL_VULKAN_ONE_DESC_DEPRECATED,
	HLSL,
	SPIRV,
	SPIRV_ASM,
	DXBC,
	DXBC_ASM,
	DXIL,
	DXIL_ASM,
	C_SOURCE,
	CPP_SOURCE,
	HOST_EXECUTABLE,
	SHADER_SHARED_LIBRARY,
	SHADER_HOST_CALLABLE,
	CUDA_SOURCE,
	PTX,
	CUDA_OBJECT_CODE,
	OBJECT_CODE,
	HOST_CPP_SOURCE,
	HOST_HOST_CALLABLE,
	CPP_PYTORCH_BINDINGS,
	METAL,
	METAL_LIB,
	METAL_LIB_ASM,
	HOST_SHARED_LIBRARY,
	WGSL,
	WGSL_SPIRV_ASM,
	WGSL_SPIRV,
	HOST_VM,
}

TargetFlags :: enum u32
{
  GENERATE_SPIRV_DIRECTLY = 1 << 10,
}

CompilerOptionName :: enum i32
{
  MacroDefine, // stringValue0: macro name;  stringValue1: macro value
  DepFile,
  EntryPointName,
  Specialize,
  Help,
  HelpStyle,
  Include, // stringValue: additional include path.
  Language,
  MatrixLayoutColumn,         // bool
  MatrixLayoutRow,            // bool
  ZeroInitialize,             // bool
  IgnoreCapabilities,         // bool
  RestrictiveCapabilityCheck, // bool
  ModuleName,                 // stringValue0: module name.
  Output,
  Profile, // intValue0: profile
  Stage,   // intValue0: stage
  Target,  // intValue0: CodeGenTarget
  Version,
  WarningsAsErrors, // stringValue0: "all" or comma separated list of warning codes or names.
  DisableWarnings,  // stringValue0: comma separated list of warning codes or names.
  EnableWarning,    // stringValue0: warning code or name.
  DisableWarning,   // stringValue0: warning code or name.
  DumpWarningDiagnostics,
  InputFilesRemain,
  EmitIr,                        // bool
  ReportDownstreamTime,          // bool
  ReportPerfBenchmark,           // bool
  ReportCheckpointIntermediates, // bool
  SkipSPIRVValidation,           // bool
  SourceEmbedStyle,
  SourceEmbedName,
  SourceEmbedLanguage,
  DisableShortCircuit,            // bool
  MinimumSlangOptimization,       // bool
  DisableNonEssentialValidations, // bool
  DisableSourceMap,               // bool
  UnscopedEnum,                   // bool
  PreserveParameters, // bool: preserve all resource parameters in the output code.
                      // Target

  Capability,                // intValue0: CapabilityName
  DefaultImageFormatUnknown, // bool
  DisableDynamicDispatch,    // bool
  DisableSpecialization,     // bool
  FloatingPointMode,         // intValue0: FloatingPointMode
  DebugInformation,          // intValue0: DebugInfoLevel
  LineDirectiveMode,
  Optimization, // intValue0: OptimizationLevel
  Obfuscate,    // bool

  VulkanBindShift, // intValue0 (higher 8 bits): kind; intValue0(lower bits): set; intValue1:
                   // shift
  VulkanBindGlobals,       // intValue0: index; intValue1: set
  VulkanInvertY,           // bool
  VulkanUseDxPositionW,    // bool
  VulkanUseEntryPointName, // bool
  VulkanUseGLLayout,       // bool
  VulkanEmitReflection,    // bool

  GLSLForceScalarLayout,   // bool
  EnableEffectAnnotations, // bool

  EmitSpirvViaGLSL,     // bool (will be deprecated)
  EmitSpirvDirectly,    // bool (will be deprecated)
  SPIRVCoreGrammarJSON, // stringValue0: json path
  IncompleteLibrary,    // bool, when set, will not issue an error when the linked program has
                        // unresolved extern function symbols.

                        // Downstream

  CompilerPath,
  DefaultDownstreamCompiler,
  DownstreamArgs, // stringValue0: downstream compiler name. stringValue1: argument list, one
                  // per line.
  PassThrough,

  // Repro

  DumpRepro,
  DumpReproOnError,
  ExtractRepro,
  LoadRepro,
  LoadReproDirectory,
  ReproFallbackDirectory,

  // Debugging

  DumpAst,
  DumpIntermediatePrefix,
  DumpIntermediates, // bool
  DumpIr,            // bool
  DumpIrIds,
  PreprocessorOutput,
  OutputIncludes,
  ReproFileSystem,
  REMOVED_SerialIR, // deprecated and removed
  SkipCodeGen,      // bool
  ValidateIr,       // bool
  VerbosePaths,
  VerifyDebugSerialIr,
  NoCodeGen, // Not used.

  // Experimental

  FileSystem,
  Heterogeneous,
  NoMangle,
  NoHLSLBinding,
  NoHLSLPackConstantBufferElements,
  ValidateUniformity,
  AllowGLSL,
  EnableExperimentalPasses,
  BindlessSpaceIndex, // int
  SPIRVResourceHeapStride,
  SPIRVSamplerHeapStride,

  // Internal

  ArchiveType,
  CompileCoreModule,
  Doc,

  IrCompression, //< deprecated

  LoadCoreModule,
  ReferenceModule,
  SaveCoreModule,
  SaveCoreModuleBinSource,
  TrackLiveness,
  LoopInversion, // bool, enable loop inversion optimization

  ParameterBlocksUseRegisterSpaces, // Deprecated
  LanguageVersion,                  // intValue0: SlangLanguageVersion
  TypeConformance, // stringValue0: additional type conformance to link, in the format of
                   // "<TypeName>:<IInterfaceName>[=<sequentialId>]", for example
                   // "Impl:IFoo=3" or "Impl:IFoo".
  EnableExperimentalDynamicDispatch, // bool, experimental
  EmitReflectionJSON,                // bool

  CountOfParsableOptions,

  // Used in parsed options only.
  DebugInformationFormat,  // intValue0: DebugInfoFormat
  VulkanBindShiftAll,      // intValue0: kind; intValue1: shift
  GenerateWholeProgram,    // bool
  UseUpToDateBinaryModule, // bool, when set, will only load
                           // precompiled modules if it is up-to-date with its source.
  EmbedDownstreamIR,       // bool
  ForceDXLayout,           // bool

  // Add this new option to the end of the list to avoid breaking ABI as much as possible.
  // Setting of EmitSpirvDirectly or EmitSpirvViaGLSL will turn into this option internally.
  EmitSpirvMethod, // enum SlangEmitSpirvMethod

  SaveGLSLModuleBinSource,

  SkipDownstreamLinking, // bool, experimental
  DumpModule,

  GetModuleInfo,              // Print serialized module version and name
  GetSupportedModuleVersions, // Print the min and max module versions this compiler supports

  EmitSeparateDebug, // bool

  // Floating point denormal handling modes
  DenormalModeFp16,
  DenormalModeFp32,
  DenormalModeFp64,

  // Bitfield options
  UseMSVCStyleBitfieldPacking, // bool

  ForceCLayout, // bool

  ExperimentalFeature, // bool, enable experimental features

  ReportDetailedPerfBenchmark, // bool, reports detailed compiler performance benchmark
                               // results
  ValidateIRDetailed,          // bool, enable detailed IR validation
  DumpIRBefore,                // string, pass name to dump IR before
  DumpIRAfter,                 // string, pass name to dump IR after

  EmitCPUMethod,    // enum SlangEmitCPUMethod
  EmitCPUViaCPP,    // bool
  EmitCPUViaLLVM,   // bool
  LLVMTargetTriple, // string
  LLVMCPU,          // string
  LLVMFeatures,     // string

  EnableRichDiagnostics, // bool, enable the experimental rich diagnostics

  ReportDynamicDispatchSites, // bool

  EnableMachineReadableDiagnostics, // bool, enable machine-readable diagnostic output
                                    // (implies EnableRichDiagnostics)

  DiagnosticColor, // intValue0: SlangDiagnosticColor (always, never, auto)

  CountOf,
}

CompilerOptionValueKind :: enum i32
{
  Int,
  String,
}

CompilerOptionValue :: struct
{
  kind:         CompilerOptionValueKind,
  intValue0:    i32,
  intValue1:    i32,
  stringValue0: cstring,
  stringValue1: cstring,
}

CompilerOptionEntry :: struct
{
  name:  CompilerOptionName,
  value: CompilerOptionValue,
}

TargetDesc :: struct {
  structureSize:               uint,
  format:                      CompileTarget,
  profile:                     ProfileID,
  flags:                       TargetFlags,
  floatingPointMode:           i32,
  lineDirectiveMode:           i32,
  forceGLSLScalarBufferLayout: bool,
  compilerOptionEntries:       [^]CompilerOptionEntry,
  compilerOptionEntryCount:    u32,
}

SessionDesc :: struct {
  structureSize:            uint,
  targets:                  [^]TargetDesc,
  targetCount:              int,
  flags:                    i32,
  defaultMatrixLayoutMode:  u32,
  searchPaths:              [^]cstring,
  searchPathCount:          int,
  preprocessorMacros:       rawptr,
  preprocessorMacroCount:   int,
  fileSystem:               rawptr,
  enableEffectAnnotations:  b32,
  allowGLSLSyntax:          b32,
  compilerOptionEntries:    [^]CompilerOptionEntry,
  compilerOptionEntryCount: u32,
  skipSPIRVValidation:      bool,
}

IUnknown :: struct
{
	using vtable: ^IUnknown_VTable,
}

IUnknown_VTable :: struct
{
	queryInterface: rawptr,
	addRef:         rawptr,
	release:        proc "system" (self: ^IUnknown) -> u32,
}

IBlob :: struct #raw_union
{
	#subtype iunknown: IUnknown,
	using vtable: ^struct
  {
		using iunknown_vtable: IUnknown_VTable,
		getBufferPointer:      proc "system"(self: ^IBlob) -> rawptr,
		getBufferSize:         proc "system"(self: ^IBlob) -> uint,
	},
}

IComponentType_VTable :: struct
{
  using iunknown_vtable:       IUnknown_VTable,
  getSession:                  rawptr,
  getLayout:                   rawptr,
  getSpecializationParamCount: rawptr,
  getEntryPointCode:           proc "system" (self: ^IComponentType, entryPointIndex: int, targetIndex: int, outCode: ^^IBlob, outDiagnostics: ^^IBlob) -> Result,
  getResultAsFileSystem:       rawptr,
  getEntryPointHash:           rawptr,
  specialize:                  rawptr,
  link:                        proc "system" (self: ^IComponentType, outLinkedComponentType: ^^IComponentType, outDiagnostics: ^^IBlob) -> Result,
  getEntryPointHostCallable:   rawptr,
  renameEntryPoint:            rawptr,
  linkWithOptions:             rawptr,
  getTargetCode:               proc "system" (self: ^IComponentType, targetIndex: int, outCode: ^^IBlob, outDiagnostics: ^^IBlob) -> Result,
  getTargetMetadata:           rawptr,
  getEntryPointMetadata:       rawptr,
}

IEntryPoint :: struct #raw_union
{
	#subtype icomponenttype: IComponentType,
	using vtable: ^struct
  {
		using icomponenttype_vtable: IComponentType_VTable,
		getFunctionReflection:       rawptr,
	},
}

IComponentType :: struct #raw_union
{
	#subtype iunknown: IUnknown,
	using vtable: ^IComponentType_VTable,
}

IModule :: struct #raw_union
{
	#subtype icomponenttype: IComponentType,
	using vtable: ^struct
  {
		using icomponenttype_vtable: IComponentType_VTable,
		findEntryPointByName:        proc "system"(self: ^IModule, name: cstring, outEntryPoint: ^^IEntryPoint) -> Result,
	},
}

ISession :: struct #raw_union {
	#subtype iunknown: IUnknown,
	using vtable: ^struct
  {
		using iunknown_vtable:                 IUnknown_VTable,
		getGlobalSession:                      rawptr,
		loadModule:                            rawptr,
		loadModuleFromSource:                  rawptr,
		createCompositeComponentType:          proc "system"(self: ^ISession, componentTypes: [^]^IComponentType, componentTypeCount: int, outCompositeComponentType: ^^IComponentType, outDiagnostics: ^^IBlob) -> Result,
		specializeType:                        rawptr,
		getTypeLayout:                         rawptr,
		getContainerType:                      rawptr,
		getDynamicType:                        rawptr,
		getTypeRTTIMangledName:                rawptr,
		getTypeConformanceWitnessMangledName:  rawptr,
		getTypeConformanceWitnessSequentialID: rawptr,
		createCompileRequest:                  rawptr,
		createTypeConformanceComponentType:    rawptr,
		loadModuleFromIRBlob:                  rawptr,
		getLoadedModuleCount:                  rawptr,
		getLoadedModule:                       rawptr,
		isBinaryModuleUpToDate:                rawptr,
		loadModuleFromSourceString:            proc "system"(self: ^ISession, moduleName, path, str: cstring, outDiagnostics: ^^IBlob) -> ^IModule,
		getDynamicObjectRTTIBytes:             rawptr,
		loadModuleInfoFromIRBlob:              rawptr,
	},
}

IGlobalSession :: struct #raw_union
{
	#subtype iunknown: IUnknown,
	using vtable: ^struct
  {
		using iunknown_vtable: IUnknown_VTable,
		createSession                     : proc "system"(self: ^IGlobalSession, desc: ^SessionDesc, outSession: ^^ISession) -> Result,
		findProfile                       : proc "system"(self: ^IGlobalSession, name: cstring) -> ProfileID,
	},
}

@(default_calling_convention = "c")
@(link_prefix = "slang_")
foreign lib
{
  createGlobalSession :: proc(apiVersion: i32, outGlobalSession: ^^IGlobalSession) -> Result ---
}
