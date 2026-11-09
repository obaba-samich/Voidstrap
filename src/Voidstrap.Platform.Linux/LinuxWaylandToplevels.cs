using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Voidstrap.Platform.Linux;

public static unsafe partial class LinuxWaylandToplevels
{
	private const string Library = "libwayland-client.so.0";
	private const uint MarshalDestroy = 1;
	private const uint ActivatedState = 2;

	private enum Kind : long
	{
		Registry = 1,
		List,
		Handle,
		CosmicHandle,
		XdgOutput
	}

	private sealed class Toplevel
	{
		public nint Cosmic;
		public string AppId = "";
		public nint Output;
		public int X;
		public int Y;
		public int Width;
		public int Height;
		public bool Active;
	}

	private sealed class Output
	{
		public int X;
		public int Y;
	}

	private static readonly object Sync = new();
	private static readonly Dictionary<nint, Toplevel> Toplevels = [];
	private static readonly Dictionary<nint, nint> CosmicToHandle = [];
	private static readonly Dictionary<nint, Output> Outputs = [];
	private static readonly Dictionary<nint, nint> XdgToOutput = [];
	private static nint _display;
	private static nint _registry;
	private static nint _list;
	private static nint _info;
	private static nint _outputManager;
	private static nint _outputInterface;
	private static nint _registryInterface;
	private static nint _listInterface;
	private static nint _handleInterface;
	private static nint _infoInterface;
	private static nint _cosmicHandleInterface;
	private static nint _managerInterface;
	private static nint _xdgOutputInterface;
	private static int _started;
	private static bool _available;

	public static bool Available
	{
		get
		{
			EnsureStarted();
			return _available;
		}
	}

	public static bool TryGetRuntimeWindow(out int left, out int top, out int width, out int height, out bool active)
	{
		left = top = width = height = 0;
		active = false;
		if (!Available)
			return false;
		lock (Sync)
		{
			foreach (Toplevel toplevel in Toplevels.Values)
			{
				if (!toplevel.AppId.Contains("sober", StringComparison.OrdinalIgnoreCase)
					|| toplevel.Width <= 0
					|| toplevel.Height <= 0
					|| !Outputs.TryGetValue(toplevel.Output, out Output? output))
					continue;
				left = output.X + toplevel.X;
				top = output.Y + toplevel.Y;
				width = toplevel.Width;
				height = toplevel.Height;
				active = toplevel.Active;
				return true;
			}
		}
		return false;
	}

	private static void EnsureStarted()
	{
		if (Interlocked.Exchange(ref _started, 1) != 0)
			return;
		if (!OperatingSystem.IsLinux() || string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WAYLAND_DISPLAY")))
			return;
		try
		{
			nint library = NativeLibrary.Load(Library);
			_outputInterface = NativeLibrary.GetExport(library, "wl_output_interface");
			_registryInterface = NativeLibrary.GetExport(library, "wl_registry_interface");
			BuildInterfaces();
			_display = wl_display_connect(0);
			if (_display == 0)
				return;
			WlArgument* args = stackalloc WlArgument[1];
			args[0] = default;
			_registry = wl_proxy_marshal_array_flags(_display, 1, _registryInterface, 1, 0, args);
			Listen(_registry, Kind.Registry);
			wl_display_roundtrip(_display);
			if (_list == 0 || _info == 0 || _outputManager == 0)
			{
				wl_display_disconnect(_display);
				_display = 0;
				return;
			}
			Listen(_list, Kind.List);
			wl_display_roundtrip(_display);
			_available = true;
			new Thread(Pump) { IsBackground = true, Name = "Voidstrap Wayland toplevels" }.Start();
		}
		catch (Exception)
		{
			_available = false;
		}
	}

	private static void Pump()
	{
		while (wl_display_dispatch(_display) >= 0)
		{
		}
		_available = false;
	}

	private static void Listen(nint proxy, Kind kind)
	{
		if (proxy != 0)
			wl_proxy_add_dispatcher(proxy, &Dispatch, (nint)kind, 0);
	}

	private static nint Bind(uint name, nint iface, uint version)
	{
		WlArgument* args = stackalloc WlArgument[4];
		args[0].U = name;
		args[1].P = Marshal.ReadIntPtr(iface);
		args[2].U = version;
		args[3].P = 0;
		return wl_proxy_marshal_array_flags(_registry, 0, iface, version, 0, args);
	}

	private static nint Create(nint parent, uint opcode, nint iface, nint argument)
	{
		WlArgument* args = stackalloc WlArgument[2];
		args[0].P = 0;
		args[1].P = argument;
		return wl_proxy_marshal_array_flags(parent, opcode, iface, wl_proxy_get_version(parent), 0, args);
	}

	private static void Destroy(nint proxy)
	{
		if (proxy != 0)
			wl_proxy_marshal_array_flags(proxy, 0, 0, wl_proxy_get_version(proxy), MarshalDestroy, null);
	}

	private static void AddOutput(nint output)
	{
		nint xdg = Create(_outputManager, 1, _xdgOutputInterface, output);
		Listen(xdg, Kind.XdgOutput);
		lock (Sync)
		{
			Outputs[output] = new Output();
			XdgToOutput[xdg] = output;
		}
	}

	[UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
	private static int Dispatch(nint implementation, nint target, uint opcode, nint message, WlArgument* args)
	{
		try
		{
			switch ((Kind)implementation)
			{
				case Kind.Registry when opcode == 0:
					OnGlobal(args[0].U, Marshal.PtrToStringUTF8(args[1].P) ?? "", args[2].U);
					break;
				case Kind.List when opcode == 0:
					OnToplevel(args[0].P);
					break;
				case Kind.Handle:
					OnHandle(target, opcode, args);
					break;
				case Kind.CosmicHandle:
					OnCosmicHandle(target, opcode, args);
					break;
				case Kind.XdgOutput when opcode == 0:
					lock (Sync)
						if (XdgToOutput.TryGetValue(target, out nint output) && Outputs.TryGetValue(output, out Output? state))
						{
							state.X = args[0].I;
							state.Y = args[1].I;
						}
					break;
			}
		}
		catch (Exception)
		{
		}
		return 0;
	}

	private static void OnGlobal(uint name, string iface, uint version)
	{
		switch (iface)
		{
			case "wl_output":
				nint output = Bind(name, _outputInterface, Math.Min(version, 2));
				if (_outputManager != 0)
					AddOutput(output);
				else
					lock (Sync)
						Outputs[output] = new Output();
				break;
			case "ext_foreign_toplevel_list_v1":
				_list = Bind(name, _listInterface, 1);
				break;
			case "zcosmic_toplevel_info_v1" when version >= 2:
				_info = Bind(name, _infoInterface, Math.Min(version, 3));
				break;
			case "zxdg_output_manager_v1":
				_outputManager = Bind(name, _managerInterface, Math.Min(version, 3));
				nint[] pending;
				lock (Sync)
					pending = Outputs.Keys.ToArray();
				foreach (nint known in pending)
					AddOutput(known);
				break;
		}
	}

	private static void OnToplevel(nint handle)
	{
		Listen(handle, Kind.Handle);
		nint cosmic = Create(_info, 1, _cosmicHandleInterface, handle);
		Listen(cosmic, Kind.CosmicHandle);
		lock (Sync)
		{
			Toplevels[handle] = new Toplevel { Cosmic = cosmic };
			CosmicToHandle[cosmic] = handle;
		}
	}

	private static void OnHandle(nint handle, uint opcode, WlArgument* args)
	{
		if (opcode == 0)
		{
			Toplevel? removed;
			lock (Sync)
			{
				if (!Toplevels.Remove(handle, out removed))
					return;
				CosmicToHandle.Remove(removed.Cosmic);
			}
			Destroy(removed.Cosmic);
			Destroy(handle);
		}
		else if (opcode == 3)
		{
			string appId = Marshal.PtrToStringUTF8(args[0].P) ?? "";
			lock (Sync)
				if (Toplevels.TryGetValue(handle, out Toplevel? toplevel))
					toplevel.AppId = appId;
		}
	}

	private static void OnCosmicHandle(nint cosmic, uint opcode, WlArgument* args)
	{
		lock (Sync)
		{
			if (!CosmicToHandle.TryGetValue(cosmic, out nint handle) || !Toplevels.TryGetValue(handle, out Toplevel? toplevel))
				return;
			if (opcode == 8)
			{
				WlArray* states = (WlArray*)args[0].P;
				toplevel.Active = false;
				for (nuint i = 0; i < states->Size / sizeof(uint); i++)
					if (((uint*)states->Data)[i] == ActivatedState)
						toplevel.Active = true;
			}
			else if (opcode == 9)
			{
				toplevel.Output = args[0].P;
				toplevel.X = args[1].I;
				toplevel.Y = args[2].I;
				toplevel.Width = args[3].I;
				toplevel.Height = args[4].I;
			}
		}
	}

	private static void BuildInterfaces()
	{
		_listInterface = AllocateInterface();
		_handleInterface = AllocateInterface();
		_infoInterface = AllocateInterface();
		_cosmicHandleInterface = AllocateInterface();
		_managerInterface = AllocateInterface();
		_xdgOutputInterface = AllocateInterface();
		FillInterface(_listInterface, "ext_foreign_toplevel_list_v1", 1,
			[("stop", "", []), ("destroy", "", [])],
			[("toplevel", "n", [_handleInterface]), ("finished", "", [])]);
		FillInterface(_handleInterface, "ext_foreign_toplevel_handle_v1", 1,
			[("destroy", "", [])],
			[("closed", "", []), ("done", "", []), ("title", "s", [0]), ("app_id", "s", [0]), ("identifier", "s", [0])]);
		FillInterface(_infoInterface, "zcosmic_toplevel_info_v1", 3,
			[("stop", "", []), ("get_cosmic_toplevel", "2no", [_cosmicHandleInterface, _handleInterface])],
			[("toplevel", "n", [_cosmicHandleInterface]), ("finished", "", []), ("done", "2", [])]);
		FillInterface(_cosmicHandleInterface, "zcosmic_toplevel_handle_v1", 3,
			[("destroy", "", [])],
			[
				("closed", "", []), ("done", "", []), ("title", "s", [0]), ("app_id", "s", [0]),
				("output_enter", "o", [_outputInterface]), ("output_leave", "o", [_outputInterface]),
				("workspace_enter", "o", [0]), ("workspace_leave", "o", [0]), ("state", "a", [0]),
				("geometry", "2oiiii", [_outputInterface, 0, 0, 0, 0]),
				("ext_workspace_enter", "3o", [0]), ("ext_workspace_leave", "3o", [0])
			]);
		FillInterface(_managerInterface, "zxdg_output_manager_v1", 3,
			[("destroy", "", []), ("get_xdg_output", "no", [_xdgOutputInterface, _outputInterface])],
			[]);
		FillInterface(_xdgOutputInterface, "zxdg_output_v1", 3,
			[("destroy", "", [])],
			[("logical_position", "ii", [0, 0]), ("logical_size", "ii", [0, 0]), ("done", "", []), ("name", "2s", [0]), ("description", "2s", [0])]);
	}

	private static nint AllocateInterface() => (nint)NativeMemory.AllocZeroed((nuint)sizeof(WlInterface));

	private static void FillInterface(nint target, string name, int version, (string Name, string Signature, nint[] Types)[] requests, (string Name, string Signature, nint[] Types)[] events)
	{
		WlInterface* iface = (WlInterface*)target;
		iface->Name = (nint)Utf8(name);
		iface->Version = version;
		iface->MethodCount = requests.Length;
		iface->Methods = Messages(requests);
		iface->EventCount = events.Length;
		iface->Events = Messages(events);
	}

	private static WlMessage* Messages((string Name, string Signature, nint[] Types)[] entries)
	{
		WlMessage* messages = (WlMessage*)NativeMemory.AllocZeroed((nuint)(Math.Max(1, entries.Length) * sizeof(WlMessage)));
		for (int i = 0; i < entries.Length; i++)
		{
			nint* types = (nint*)NativeMemory.AllocZeroed((nuint)(Math.Max(1, entries[i].Types.Length) * sizeof(nint)));
			for (int j = 0; j < entries[i].Types.Length; j++)
				types[j] = entries[i].Types[j];
			messages[i] = new WlMessage { Name = (nint)Utf8(entries[i].Name), Signature = (nint)Utf8(entries[i].Signature), Types = (nint)types };
		}
		return messages;
	}

	private static byte* Utf8(string value)
	{
		byte[] bytes = System.Text.Encoding.UTF8.GetBytes(value + "\0");
		byte* copy = (byte*)NativeMemory.Alloc((nuint)bytes.Length);
		bytes.CopyTo(new Span<byte>(copy, bytes.Length));
		return copy;
	}

	[StructLayout(LayoutKind.Sequential)]
	private struct WlInterface
	{
		public nint Name;
		public int Version;
		public int MethodCount;
		public WlMessage* Methods;
		public int EventCount;
		public WlMessage* Events;
	}

	[StructLayout(LayoutKind.Sequential)]
	private struct WlMessage
	{
		public nint Name;
		public nint Signature;
		public nint Types;
	}

	[StructLayout(LayoutKind.Sequential)]
	private struct WlArray
	{
		public nuint Size;
		public nuint Alloc;
		public nint Data;
	}

	[StructLayout(LayoutKind.Explicit, Size = 8)]
	private struct WlArgument
	{
		[FieldOffset(0)] public int I;
		[FieldOffset(0)] public uint U;
		[FieldOffset(0)] public nint P;
	}

	[LibraryImport(Library)]
	private static partial nint wl_display_connect(nint name);

	[LibraryImport(Library)]
	private static partial void wl_display_disconnect(nint display);

	[LibraryImport(Library)]
	private static partial int wl_display_roundtrip(nint display);

	[LibraryImport(Library)]
	private static partial int wl_display_dispatch(nint display);

	[LibraryImport(Library)]
	private static partial nint wl_proxy_marshal_array_flags(nint proxy, uint opcode, nint iface, uint version, uint flags, WlArgument* args);

	[LibraryImport(Library)]
	private static partial uint wl_proxy_get_version(nint proxy);

	[LibraryImport(Library)]
	private static partial int wl_proxy_add_dispatcher(nint proxy, delegate* unmanaged[Cdecl]<nint, nint, uint, nint, WlArgument*, int> dispatcher, nint implementation, nint data);
}
