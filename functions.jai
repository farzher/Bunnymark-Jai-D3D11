Input   :: #import "Input";
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



// tstr
TStr :: struct {#as str: string; }
tstr: TStr;
to_tstr :: (str: string) -> TStr {
   s: TStr = ---;
   s.str = str;
   return s;
}
tstr_join :: (a:string, b:string) -> string {
    bytes := 0;
    bytes += a.count;
    bytes += b.count;
    if !bytes return "";

    result: string;
    result.count = bytes;
    result.data  = talloc(bytes);
    assert(result.data != null);

    cursor := result.data;
    memcpy(cursor, a.data, a.count);
    cursor += a.count;
    memcpy(cursor, b.data, b.count);

    cursor += b.count;
    assert(cursor == result.data + result.count);

    return result;
}
operator + :: (a: TStr, b: TStr)   -> TStr            {return to_tstr(tstr_join(a.str, b.str)); }
operator + :: (a: TStr, b: string) -> TStr #symmetric {return a + to_tstr(b); }
operator + :: (a: TStr, b: int)    -> TStr #symmetric {return to_tstr(tprint("%0%", a.str, b)); }
operator + :: (a: TStr, b: float)  -> TStr #symmetric {return to_tstr(tprint("%0%", a.str, b)); }


interp :: (_str: string) -> string #expand {
  #insert -> string {
    String :: #import "String";

    builder: String_Builder;

    str := String.replace(_str, "\n", "\\n");

    codestart := 0;
    strstart := 0;

    for i: 0 .. str.count-1 {

      //
      if (str[i] == #char"#" || str[i] == #char"%") && str[i+1] == #char"{" {

        append(*builder, tstr+ "+\""+String.slice(str, strstart, i-strstart)+"\"");

        i += 2;
        codestart = i;
        continue;
      }

      if codestart {
        if str[i] == #char"}" {
          code := String.slice(str, codestart, i-codestart);
          code = String.replace(code, "'", "\"");
          append(*builder, tstr+ "+("+code+")");
          i += 1;
          strstart = i;
          codestart = 0;
        }
      }

      if i == str.count-1 {
        append(*builder, tstr+ "+\""+String.slice(str, strstart, strstart+i+1)+"\"");
      }
    }

    return tstr+ "return tstr" + builder_to_string(*builder) + ";";
  }
}
