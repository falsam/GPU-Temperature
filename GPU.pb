;for ATI
Structure AdapterInfo
    iSize.l
    iAdapterIndex.l
    strUDID.c[256];	
    iBusNumber.l
    iDeviceNumber.l
    iFunctionNumber.l
    iVendorID.l
    strAdapterName.c[256];
    strDisplayName.c[256];
    iPresent.l			
    iExist.l
    strDriverPath.c[256];
	 strDriverPathExt.c[256];
    strPNPString.c[256];
    iOSDisplayIndex.l
EndStructure

Structure ADLTemperature
	iSize.l
	iTemperature.l
EndStructure

;for NVidia
Structure sensor
	controller.l
	defaultMinTemp.l
	defaultMaxTemp.l
	currentTemp.l
	target.l
EndStructure

Structure NV_GPU_THERMAL_SETTINGS
	version.l
	count.l
	sensors.sensor[3]
EndStructure 

CompilerIf #PB_Compiler_Processor = #PB_Processor_x64
	ImportC "nvapi64.lib"
CompilerElse
	ImportC "nvapi.lib"
CompilerEndIf
NvAPI_Initialize()
NvAPI_EnumPhysicalGPUs(*GpuHandles, *gpus)
NvAPI_GPU_GetFullName(Handle.l, *name)
NvAPI_GPU_GetThermalSettings(Handle.l, i.l, *point.NV_GPU_THERMAL_SETTINGS)
EndImport

;some global stuff
Global gpus.l, realgpus.l, Dim GpuHandles.i(64), Dim NVGPUNames.s(64)
Global Dim adapters.AdapterInfo(1), FoundATI.l = #False, FoundNVidia.l = #False

Procedure ATIGPUClockUpdater(Value.i)	; "Value" not used, but necessary
	adlt.ADLTemperature
	ii.l=-1
	Repeat
		ii = -1
		For i=0 To gpus-1
			If PeekS(@adapters(i)\strUDID) <> Space(10)
				ii+1
				If CallCFunction(0,"ADL_Overdrive5_Temperature_Get", adapters(i)\iAdapterIndex,0, @adlt) = 0
					far.l=(adlt\iTemperature /1000) * 1.8 + 32
					SetGadgetText(ii, Str(adlt\iTemperature /1000) + Chr(176)+"C  (" + Str(far) + " " + Chr(176) + "F)")
				EndIf
			EndIf
		Next
		Delay(1000)
	ForEver
EndProcedure

Procedure NVidiaGPUClockUpdater(Value.i)	; "Value" not used, but necessary
settings.NV_GPU_THERMAL_SETTINGS
Repeat	
	For i=0 To gpus-1
		settings\version = SizeOf(NV_GPU_THERMAL_SETTINGS) | (1<<16)
		settings\count = 0
		settings\sensors[0]\controller = -1
		settings\sensors[0]\target = 1
		If NvAPI_GPU_GetThermalSettings(GpuHandles(i), 0, @settings) <> 0
			MessageRequester("error","Unable to get thermal settings")
			ProcedureReturn
		EndIf
			far.l = settings\sensors[0]\currentTemp * 1.8 + 32
			SetGadgetText(i, Str(settings\sensors[0]\currentTemp) + Chr(176) + "C  (" + Str(far) + " " + Chr(176) + "F)")
	Next
	Delay(1000)
ForEver
EndProcedure

Procedure ATIGPU()
If CallCFunction(0,"ADL_Main_Control_Create", 1) <> 0 
	MessageRequester("error","Unable to Create Main Control")
	;ProcedureReturn
EndIf
i= CallCFunction(0,"ADL_Adapter_NumberOfAdapters_Get", @gpus) 
If gpus = 0
	MessageRequester("error","Unable to get the number of adapters")
	;ProcedureReturn
EndIf
ReDim adapters.AdapterInfo(gpus)
If CallCFunction(0,"ADL_Adapter_AdapterInfo_Get", @adapters(), SizeOf(AdapterInfo) *gpus) <> 0
	MessageRequester("error","Unable to get adapter's info")
	;ProcedureReturn
Else
;first, check for duplicate entries
	realgpus = gpus
	For i=0 To gpus-1
		For ii=1 To gpus-1
			If adapters(i)\iBusNumber = 0 And PeekS(@adapters(i)\strUDID) <> Space(10); gpu cannot be on bus 0.
				realgpus -1
				PokeS(@adapters(i)\strUDID,Space(10))
			ElseIf i <> ii; we do not need to check every gpu with itself.
				If adapters(i)\iBusNumber = adapters(ii)\iBusNumber And adapters(i)\iDeviceNumber = adapters(ii)\iDeviceNumber And adapters(i)\iFunctionNumber = adapters(ii)\iFunctionNumber And PeekS(@adapters(i)\strUDID) <> Space(10)
					realgpus -1
					PokeS(@adapters(ii)\strUDID,Space(10));we erase the content of strUDID because we need something to stand on to see later which gpus to monitor, and it is something not really usefull to us.
				EndIf
			EndIf
		Next
	Next
	For i=0 To gpus-1
		CallCFunction(0,"ADL_Adapter_Active_Get",adapters(i)\iAdapterIndex,@IsActive.l)
		Debug "AdapterIndex: " + Str(adapters(i)\iAdapterIndex)
		;Debug "IsActive: " + Str(IsActive)
		;Debug "AdapterName: " + PeekS(@adapters(i)\strAdapterName)
		;Debug "UDID: " + PeekS(@adapters(i)\strUDID)
		;Debug "Present: " + Str(adapters(i)\iPresent)
		;Debug "VendorID: " + Hex(adapters(i)\iVendorID)
		;Debug "BusNumber: " + Str(adapters(i)\iBusNumber)
		;Debug "DeviceNumber: " + Str(adapters(i)\iDeviceNumber)
		;Debug "FunctionNumber: " + Str(adapters(i)\iFunctionNumber)		
		CallCFunction(0,"ADL_Adapter_ID_Get",adapters(i)\iAdapterIndex,@AdapterID.l)
	Next
EndIf
;ProcedureReturn
EndProcedure

Procedure NVidiaGPU()
If NvAPI_Initialize() <> 0
	MessageRequester("error","Unable to Initialize NVAPI.")
	ProcedureReturn
EndIf
If NvAPI_EnumPhysicalGPUs(@GpuHandles(0), @gpus) <> 0
	MessageRequester("error","Unable to take number of physical gpus.")
	ProcedureReturn
EndIf
For i=0 To gpus-1
	name.s = Space(64)
	NvAPI_GPU_GetFullName(GpuHandles(i), @name)
	NVGPUNames(i) = name
	NvAPI_EnumPhysicalGPUs(@GpuHandles(0), @dummy.l); this function needs to run again because if not, the program may crash in some cases.
Next
realgpus = gpus
EndProcedure

If OpenLibrary(0,"atiadlxx.dll") = 0
	CloseLibrary(0)
	If OpenLibrary(0,"atiadlxy.dll") = 0
		;no ATI? check NVidia
		If OpenLibrary(0,"nvapi64.dll") = 0; x64 library
			If OpenLibrary(0,"nvapi.dll") = 0; x86 library
				MessageRequester("error","Unable to load API library")
				End
			Else
				FoundNVidia = #True
				NVidiaGPU()
			EndIf
		Else
			FoundNVidia = #True
			NVidiaGPU()
		EndIf
	Else
		FoundATI = #True
		ATIGPU()
	EndIf
Else
	FoundATI = #True
	ATIGPU()
EndIf

If OpenWindow (0, 0, 0, 288, 97, "GPU Temperature", #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_ScreenCentered) 
LoadFont(4,"MS Sans Serif",24, #PB_Font_Bold)
If realgpus > 1
	ResizeWindow(0, #PB_Ignore, #PB_Ignore, 280, realgpus * 61)
EndIf
thrd.i
If FoundATI = #True
	tmpi.l=-1
	For i=0 To gpus - 1			      
		If PeekS(@adapters(i)\strUDID) <> Space(10)
			tmpi + 1
			FrameGadget(tmpi+10,14,8+tmpi*55,253,50,"GPU # " +Str(tmpi) + "   -   " + PeekS(@adapters(i)\strAdapterName))
			TextGadget(tmpi, 15, 20+tmpi*55, 250, 35, "Please wait", #PB_Text_Center)
			SetGadgetFont(tmpi, FontID(4))
		EndIf
	Next
	thrd = CreateThread(@ATIGPUClockUpdater(),189)
ElseIf FoundNVidia = #True
	For i=0 To gpus - 1			      
			FrameGadget(i+10,24,8+i*55,233,50,"GPU # " +Str(i) + "   -   " + NVGPUNames(i))
			TextGadget(i, 25, 20+i*55, 230, 35, "Please wait", #PB_Text_Center)
			SetGadgetFont(i, FontID(4))
	Next
	thrd = CreateThread(@NVidiaGPUClockUpdater(),189)
EndIf

Repeat
		Select WaitWindowEvent()
			Case #PB_Event_CloseWindow
			Break
		EndSelect
ForEver
KillThread(thrd)
If FoundATI = #True
	CallCFunction(0,"ADL_Main_Control_Destroy")
EndIf
EndIf
CloseLibrary(0)

; IDE Options = PureBasic 5.31 (Windows - x86)
; CursorPosition = 123
; FirstLine = 91
; Folding = ------
; EnableXP
; Executable = D:\Users\Doctorized\Desktop\GPU_temperature_x64.exe
; DisableDebugger
; CompileSourceDirectory