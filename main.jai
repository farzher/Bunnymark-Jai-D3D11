/*
  jai bunnymark by farzher
  just checking how fast computers can go
*/

#load "indirectx.jai";
#load "functions.jai";


window_width         :: 1920/2;
window_height        :: 1080/2;

VSYNC                :: false;
DEBUG                :: #run cmdline_flag("DEBUG", or=false); // disables shader optimization
DISABLE_MOUSE_EVENTS :: true; // this prevents fps drops when moving the mouse.

MAX_BUNNIES          :: 2_000_000; // for static memory allocation. game crashes if there's more bunnies than this
INITIAL_BUNNY_COUNT  :: 1;
AMOUNT_TO_ADD        :: 1;

ROTATION             :: true;
GRAVITY              :: 33/10; // gravity of 0 gives a lot higher fps for some reason (something to do with the positions being rendered)

PIXEL_DISCARD_ALPHA  :: .5;
ALPHA_BLENDING       :: false;
DEPTH_BUFFER         :: false;

WRITE_ONLY_NECESSARY_DATA_TO_GPU :: true;
JUNK_BYTES                       :: 0; // 1024; // extra unnecessary bytes to store in the Bunny structure


main :: () {

  init_window();
  init_d3d_device();

  init_bunnies();
  init_instance_buffer();
  init_load_textures();
  init_bunny_shader();

  while true {

    inputs();
    update();
    render();

    tfree();

  }
}


Bunny :: struct {

  using           bunny_gpu_data : GpuData;
                  vel            : Vector2;
  #if JUNK_BYTES  junk_bytes     : [JUNK_BYTES]u8;

  GpuData :: struct {
    using         pos      : Vector2;
    #if ROTATION  rotation : float;
  }


  init :: (using this: *Bunny, index: int) {
    vel = xy(random_get_within_range(-1,1), random_get_within_range(-1,1));
    #if ROTATION rotation = xx index;
  }

  update :: inline (using this: *Bunny) {
    vel.y -= GRAVITY * dt;

    x += vel.x * dt;
    y += vel.y * dt;
    #if ROTATION rotation += vel.x*360 * dt;

    if y < -1 { // the most common case: collision with the ground
      y = -1;
      vel.y *= -.85/2;
      if chance(.5*dt*1000) vel.y += random_get_zero_to_one() * 2;
    }
    else if x >  1 then vel.x = -abs(vel.x);
    else if x < -1 then vel.x =  abs(vel.x);
  }

  // this renders all bunnies, for performance reasons there's no way to render 1 bunny
  render :: () {
    // Write bunny data to the gpu instance_buffer
      #if !WRITE_ONLY_NECESSARY_DATA_TO_GPU then gpu_memcpy(instance_buffer, bunnies.data, bunnies.count * size_of(Bunny));
      #if  WRITE_ONLY_NECESSARY_DATA_TO_GPU {
        // this uses a for expansion because writing to gpu memory requires a setup and teardown
        instance_buffer.count = xx bunnies.count;
        for instance_buffer  memcpy(it, *bunnies[it_index], size_of(Bunny.GpuData));
      }

    // Set the correct shader
      bind_shader(bunny_shader);

    // Bind the correct buffers to the shader
      bind_buffer(0, six_vertex_for_a_quad_buffer);
      bind_buffer(1, instance_buffer);

    // Instanced Draw call
      ID3D11DeviceContext_DrawInstanced(d3d_context, 6, xx bunnies.count, 0, 0);
  }
}

bunnies: [] Bunny;
init_bunnies :: () {
  bunnies = NewArray(MAX_BUNNIES, Bunny);
  for 0..MAX_BUNNIES-1 Bunny.init(*bunnies[it], it);
  bunnies.count = INITIAL_BUNNY_COUNT;
}


ismousedown := false;
inputs :: () {
  #import "Input";
  update_window_events(); for event: events_this_frame {
    if event.type     == .QUIT               exit(0);
    if event.key_code == .ESCAPE             exit(0);
    if event.key_code == .MOUSE_BUTTON_LEFT  ismousedown = xx event.key_pressed;
  }

  #if DISABLE_MOUSE_EVENTS {
    ismousedown = xx (GetAsyncKeyState(VK_LBUTTON) & 0x8000);
    mousepos := Mouse.pos(hwnd);

    is_mouse_over_windows_frame_bar := mousepos.x >= -10 && mousepos.x <= window_width + 10
                                    && mousepos.y >= -30 && mousepos.y <= 0;
    if is_mouse_over_windows_frame_bar enable_mouse_events(); else disable_mouse_events();
  }
}


dt: type_of(dt_man.dt);
update :: () {

  fps_man.update(*fps_man);
  dt_man.update(*dt_man);
  dt = dt_man.dt;


  // add bunnies if mousedown
    if ismousedown {
      mousepos := Mouse.pos(hwnd);
      w, h := window_size(hwnd);
      for i: 0..AMOUNT_TO_ADD-1 #no_abc {
        bunnies[bunnies.count].x = mapnumber(xx mousepos.x, 0,xx w, -1,  1);
        bunnies[bunnies.count].y = mapnumber(xx mousepos.y, 0,xx h,  1, -1);
        bunnies.count += 1;
      }
    }


  // update window title with stats every once in a while
    Global("max_dt: float;");
    if dt > max_dt max_dt = dt;
    if fps_man.ready { fps_man.ready = false;
      worst_fps : int = xx (1000 / (max_dt*1000));
      set_window_title(interp("Bunnymark Jai D3D11 | FPS: #{fps_man.fps} | 0% Low: #{`worst_fps} | Buns: #{bunnies.count}"));
      max_dt = 0;
    }


  // cpu processing update bunnies
    for * bunny: bunnies  bunny.update(bunny);
}



render :: () {
  Bunny.render();
  present(xx VSYNC);
}










hwnd: HWND;
init_window :: () {
  #import "Window_Creation";
  hwnd = create_window(
    window_name="",
    width=window_width, height=window_height,
    window_x=Monitor.size().w/2-window_width/2,
    window_y=Monitor.size().h/2-window_height/2,
  );
}

instance_buffer: GpuBuffer;
init_instance_buffer :: () {
  #if  WRITE_ONLY_NECESSARY_DATA_TO_GPU then instance_buffer = gpu_alloc(MAX_BUNNIES, Bunny.GpuData);
  #if !WRITE_ONLY_NECESSARY_DATA_TO_GPU then instance_buffer = gpu_alloc(MAX_BUNNIES, Bunny);
}

init_load_textures :: () {
  #import "Compiler";
  #import "File";
  bunnies_png_bytes :: #run add_global_data(xx read_entire_file("bunnies.png"), .READ_ONLY);
  bunny_texture := load_texture_from_memory(bunnies_png_bytes);
  bind_texture(0, bunny_texture);
}

bunny_shader: GpuShader;
init_bunny_shader :: () {

  // Create the input layout
    layout := make_input_layout();
    layout_add(*layout, "TEXCOORD", buffer_slot=0, size=six_vertex_for_a_quad_buffer.type_size);
    layout_add(*layout, "POSITION", buffer_slot=1, instanced=1, size=size_of(type_of(Bunny.pos)));
    #if ROTATION
    layout_add(*layout, "ROT"     , buffer_slot=1, instanced=1, size=size_of(type_of(Bunny.rotation)));

  bunny_shader = make_shader(bunny_shader_text, layout);

  bunny_shader_text :: #run interp(#string HLSL
    #define PI 3.1415926538
    #define ROTATION %{ifx ROTATION 1 else 0}

    struct VSOut {
      float4 vert : SV_POSITION;
      float2 uv   : UV;
    };

    VSOut VS(
      float2 uv  : TEXCOORD,
      float2 pos : POSITION,
      #if ROTATION
        float rot  : ROT,
      #endif
      uint id : SV_InstanceID) {
      float2 scale = float2(.05, .1);

      VSOut o;

      #if ROTATION
        // float rotation = id;
        float rotation = rot;

        float rads = -rotation * PI / 180;
        float2 p = float2(uv.x, uv.y)-.5;
        float2 q;
        q.x = p.x*cos(rads) - p.y*sin(rads);
        q.y = p.x*sin(rads) + p.y*cos(rads);
        o.vert = float4(q*scale + pos, 0, 1);
      #else
        float2 q = float2(uv.x, uv.y)-.5;
        o.vert = float4(q*scale + pos, 0, 1);
      #endif

      o.uv = float2(1.0/12*(id/1000%12), 1-uv.y); // texture is upside down... need to flip uvs
      if(uv.x==1) o.uv.x += 1.0/12;

      return o;
    }

    Texture2D my_texture;
    SamplerState my_sampler;
    float4 PS(VSOut input) : SV_Target {
      float4 color = my_texture.Sample(my_sampler, input.uv);

      #if %{ifx PIXEL_DISCARD_ALPHA 1 else 0}
        clip(color.a < %{PIXEL_DISCARD_ALPHA} ? -1 : 1);
      #endif

      return color;
    }
  HLSL);
}
