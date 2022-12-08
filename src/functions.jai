// Input   :: #import "Input";
WC      :: #import "Window_Creation";
Windows :: #import "Windows";
#import "Basic";
#import "Math";
#import "Random";
#import "Windows";
#import "Windows_Utf8";




fps_man: struct {
  last_frame_count: int;
  frame_count: int;
  last_time: float64;

  fps: int;
  ready: bool;

  update :: (using instance: *type_of(fps_man)) {
    frame_count += 1;

    elapsed := get_time() - last_time;
    if elapsed < .5  return;

    last_time = get_time();
    fps = cast(int)( (frame_count - last_frame_count) / elapsed );
    last_frame_count = frame_count;
    ready = true;
  }
}


dt_man: struct {

  dt: float;
  last_time: float64;

  update :: (using instance: *type_of(dt_man)) {
    now := get_time();
    dt = xx (now - last_time);
    last_time = now;
  }
}


Mouse: struct {
  WC :: #import "Window_Creation";

  Point :: struct {x: s32; y: s32;}

  pos :: (hwnd: WC.Window_Type) -> Point {
    x, y := WC.get_mouse_pointer_position(hwnd, false);
    pos: Point = ---;
    pos.x = xx x;
    pos.y = xx y;
    return pos;
  }

  pos_global :: () -> Point {
    Windows :: #import "Windows";
    p: Windows.POINT = ---;
    Windows.GetCursorPos(*p);
    pos: Point = ---;
    pos.x = p.x;
    pos.y = p.y;
    return pos;
  }
}


Monitor: struct {

  _size: struct {x, y, w, h :s32;};
  size :: () -> type_of(_size) { ensure_init(); return Monitor._size; }

  Windows :: #import "Windows";
  init :: () {
    info: Windows.MONITORINFO = ---;
    info.cbSize = size_of(type_of(info));
    success := Windows.GetMonitorInfoW(Windows.MonitorFromWindow(hwnd, Windows.MONITOR_DEFAULTTONEAREST), *info);
    if !success  die("failed to get monitor size");

    Monitor._size.x = info.rcMonitor.left;
    Monitor._size.y = info.rcMonitor.top;
    Monitor._size.w = info.rcMonitor.right - Monitor._size.x;
    Monitor._size.h = info.rcMonitor.bottom - Monitor._size.y;
  }

  ensure_init :: () {
    if Monitor._size.w != 0  return;
    Monitor.init();
  }
}





set_window_title :: (title: string) {
  windows_utf8 :: #import "Windows_Utf8";
  Windows.SetWindowTextW(hwnd, windows_utf8.utf8_to_wide(title));
}


tfree :: reset_temporary_storage;
mylog :: (args:..Any) {for args print("% ", it); print("\n"); }
mylog :: (str: string) #expand {print("%\n", interp(str)); }
die :: (args: ..Any) {mylog("[Fatal Error]"); mylog(..args); exit(1); }

Global :: (str: string) #expand {
  Compiler :: #import "Compiler";
  #run Compiler.add_build_string(str);
}

window_size :: (hwnd: WC.Window_Type) -> w: s32, h: s32 {
  rect: RECT;
  GetClientRect(hwnd, *rect);
  return rect.right, rect.bottom;
}

chance :: (percent: float = .5) -> bool {
  Random :: #import "Random";
  return Random.random_get_zero_to_one() < percent;
}


mapnumber :: (value: float, from1: float, from2: float, to1: float, to2:float, exponent:float=0, clamp:=true) -> float {
  Math :: #import "Math";
  adist := from2 - from1;
  bdist := to2 - to1;
  ratio := (value - from1) / adist;
  isnegative := ratio < 0;

  if exponent {
    ratio = Math.pow(Math.abs(ratio), exponent);
    if isnegative then ratio = -ratio;
  }

  if clamp {
    if ratio > 1 then ratio = 1;
    else if ratio < -1 then ratio = -1;
  }

  return bdist*ratio + to1;
}

parse_compile_time_argument_from_command_line_flag :: cmdline_flag;
cmdline_flag :: (varname: string, or: $T) -> bool
{
  Compiler :: #import "Compiler";
  val :bool= xx or;
  for Compiler.get_build_options().compile_time_command_line {
    if it == varname  val = true;
    if it == tprint("%=0", varname)  val = false;
  }
  return val;
}


// this prevents fps drops, but doesn't allow us to move or close the window ...
enable_mouse_events   :: (enable  := true) { disable_mouse_events(!enable); }
disable_mouse_events  :: (disable := true) {
  HID_USAGE_PAGE_GENERIC  :: 0x01;
  HID_USAGE_GENERIC_MOUSE :: 0x02;
  RIDEV_INPUTSINK         :: 0x00000100;
  RIDEV_NOLEGACY          :: 0x00000030;

  riMouse: RAWINPUTDEVICE;
  riMouse.usUsagePage = HID_USAGE_PAGE_GENERIC;
  riMouse.usUsage     = HID_USAGE_GENERIC_MOUSE;
  if disable {
    riMouse.dwFlags     = RIDEV_INPUTSINK | RIDEV_NOLEGACY;
    riMouse.hwndTarget  = hwnd;
  }
  RegisterRawInputDevices(*riMouse, 1, size_of(type_of(riMouse)));
}


windows_improve_performance :: () {
  #if OS == .WINDOWS {

    kernel32    :: #foreign_system_library "kernel32";
    SetPriorityClass :: (hProcess: Windows.HANDLE, dwPriorityClass: Windows.DWORD) -> Windows.BOOL #foreign kernel32;
    HIGH_PRIORITY_CLASS :: 0x00000080;

    {
      SetProcessDPIAware();
      // windows junk to improve frame times
      SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS);
      SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
      timeBeginPeriod(1); // makes sleep accurate down to 1ms instead of ~15ms which is the default
    }
  }
}


// string interpolation.
// example: interp("hello %{name}") will compile to tprint("hello %", name)
// argument is a Code instead of string because we need some way to get a
// Code of the caller's scope to #insert,scope(code) into it
// this seems a bit weird? but works
interp :: (code: Code) -> string #expand {
  #insert,scope(code) -> string {
    String :: #import "String";

    str := String.replace(#insert code, "\n", "\\n");

    format_str: String_Builder;
    arguments: [..] string;

    // loop through str char by char, translating it into a format_str
    for i: 0 .. str.count-1 {

      is_start_of_interpolated_code := (str[i] == #char"#" || str[i] == #char"%" || str[i] == #char"$") && str[i+1] == #char"{";

      // if this character is a % that's not part of code, transform it into %% so it's interpreted as a normal %
      if !is_start_of_interpolated_code && str[i] == #char"%" {
        append(*format_str, "%%");
        continue;
      }

      // if this character is just a normal part of the string, write the character to format_str as is
      if !is_start_of_interpolated_code {
        append(*format_str, str[i]);
        continue;
      }

      // we have a block of interpolated code. write % to the format_str and push the code into arguments
      if is_start_of_interpolated_code i += 2;
      if is_start_of_interpolated_code {
        closing_brace_index := String.find_index_from_left(str, "}", i+1);
        assert(closing_brace_index != -1);

        arg := String.slice(str, i, closing_brace_index - i);
        array_add(*arguments, arg);

        append(*format_str, tprint("%%%", arguments.count));

        i = xx closing_brace_index;
        continue;
      }
    }

    arguments_string := "";
    if arguments.count {
      builder: String_Builder;
      for arguments append(*builder, tprint(", %", it));
      arguments_string = builder_to_string(*builder);
    }

    return tprint("return tprint(\"%\"%);", builder_to_string(*format_str), arguments_string);
  }
}
