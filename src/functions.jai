// Input   :: #import "Input";
WC      :: #import "Window_Creation";
Windows :: #import "Windows";
using Basic :: #import "Basic"()(ENABLE_ASSERT=!RELEASE);
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
    fps = xx floor(.5+ (frame_count - last_frame_count) / elapsed );
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
Global :: (code: Code) #expand {
  Compiler :: #import "Compiler";
  #run Compiler.add_build_string(tprint("%;", code2string(code)));
}
code2string :: (code: Code) -> string #expand {
  PP       :: #import "Program_Print";
  Compiler :: #import "Compiler";
  code_node := Compiler.compiler_get_nodes(code);
  builder: String_Builder;
  PP.print_expression(*builder, code_node);
  return builder_to_string(*builder, allocator=temp);
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
    else if ratio < 0 then ratio = 0;
  }

  return bdist*ratio + to1;
}

RELEASE :: #run () -> bool {Compiler :: #import "Compiler"; return Compiler.get_build_options().optimization_level == .RELEASE; }();

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

    kernel32    :: #system_library "kernel32";
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

embed_file :: (file_path: string) -> []u8 {
  File :: #import "File";
  return xx File.read_entire_file(file_path);
}


// string interpolation.
// example: tprinti("hello %{name}") compiles to tprint("hello %", name)
// perf: is calling append for every single character slow?
// fixme: api isn't finalized. what should this function be called and how should allocation work? some ideas below
sprinti :: #bake_arguments string_interpolation(allocator = .{});
tprinti :: #bake_arguments string_interpolation(allocator = temp);
// printi  :: ($str: string, caller_scope := #caller_code) #expand {print(tprinti(str, caller_scope=caller_scope)); } // should this exist? but then what about logi, etc
_       :: string_interpolation;
// $       :: string_interpolation; // $ isn't a valid identifier ezsadge
interp  :: string_interpolation;
string_interpolation :: ($_str: string, allocator: Allocator = temp, caller_scope := #caller_code) -> string #expand {
  a := ifx allocator.proc then allocator else context.allocator;
  push_allocator(a); // sprint doesn't accept an allocator, so we have to push_allocator to the context

  #insert,scope(caller_scope) -> string {

    String :: #import "String";

    str := _str; // to make str not constant
    // when using #string you can have newlines in your string
    // we need to rewrite these actual newlines to \n because our string to sprint can't have real newline in it
    str = String.replace(str, "\n", "\\n");
    // all " need to be escaped
    str = String.replace(str, "\"", "\\\"");

    // loop through str char by char, building the format_str and arguments
    format_str: String_Builder;
    arguments : [..] string;
    for i: 0 .. str.count-1 {

      is_start_of_interpolated_code := (str[i] == #char"#" || str[i] == #char"%" || str[i] == #char"$") && (i+1 < str.count-1 && str[i+1] == #char"{");

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

      // we have a block of interpolated code. write %0 to the format_str and push the code into arguments
      if is_start_of_interpolated_code {
        append(*format_str, "%0");
        i += 2;

        closing_brace_index := -1;
        j := i; while j < str.count { defer j += 1;
          // if we're in a string, skip to the end without checking for } inside the string ex %{'{}{}{}'}
          if str[j] == #char"'" j = String.find_index_from_left(str, "'", j+1); // this can return -1, should probably assert on this
          if str[j] == #char"}" {closing_brace_index = j; break; }
        }
        assert(closing_brace_index != -1);

        arg := String.slice(str, i, closing_brace_index - i);
        arg = String.replace(arg, "'", "\""); // rewrite ' to " ex "Mode: %{ifx SOA 'SOA' else 'AOS'}"
        array_add(*arguments, arg);

        i = xx closing_brace_index;
        continue;
      }
    }

    arguments_string := "";
    if arguments.count {
      builder: String_Builder;
      for arguments {
        append(*builder, ", ");
        append(*builder, it);
      }
      arguments_string = builder_to_string(*builder);
    }

    return tprint("return sprint(\"%\"%);", builder_to_string(*format_str), arguments_string);
  }
}
