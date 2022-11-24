














#if  DEBUG #import "d3d11"()(INCLUDE_DEBUG_BINDINGS = true);
#if !DEBUG #import "d3d11";

#import "d3d_compiler";
#import "dxgi";

init_d3d_device :: () {

  Global("driver_type        := D3D_DRIVER_TYPE.HARDWARE;");
  Global("feature_level      : D3D_FEATURE_LEVEL;");
  Global("d3d_device         : *ID3D11Device;");
  Global("d3d_context        : *ID3D11DeviceContext;");
  Global("swap_chain         : *IDXGISwapChain;");
  Global("render_target_view : *ID3D11RenderTargetView;");

  // get the window size
    window_rect: RECT;
    GetClientRect(hwnd, *window_rect);
    width := window_rect.right - window_rect.left;
    height := window_rect.bottom - window_rect.top;


  mylog("crate d3d device and swap chain");
    flags : D3D11_CREATE_DEVICE_FLAG;
    #if DEBUG flags |= .DEBUG;

    feature_levels := D3D_FEATURE_LEVEL.[._11_1, ._11_0, ._10_1, ._10_0];

    // swap chain config
      sd: DXGI_SWAP_CHAIN_DESC;
      sd.BufferCount = 1;
      sd.BufferDesc.Width = xx width;
      sd.BufferDesc.Height = xx height;
      sd.BufferDesc.Format = .R8G8B8A8_UNORM;
      sd.BufferDesc.RefreshRate.Numerator = 60;
      sd.BufferDesc.RefreshRate.Denominator = 1;
      sd.BufferUsage = .RENDER_TARGET_OUTPUT;
      sd.OutputWindow = hwnd;
      sd.SampleDesc.Count = 1;
      sd.SampleDesc.Quality = 0;
      sd.Windowed = BOOL.TRUE;

    handle_hr(D3D11CreateDeviceAndSwapChain(null, .HARDWARE, null, xx flags, feature_levels.data, feature_levels.count, D3D11_SDK_VERSION, *sd, *swap_chain, *d3d_device, *feature_level, *d3d_context ));

    assert(d3d_device != null);
    mylog("Created D3D11 .HARDWARE device with feature level", feature_level);


  mylog("create render_target_view");
    back_buffer: *ID3D11Texture2D;
    handle_hr(IDXGISwapChain_GetBuffer(swap_chain, 0, *uid(ID3D11Texture2D_UUID), xx *back_buffer));
    handle_hr(ID3D11Device_CreateRenderTargetView(d3d_device, back_buffer, null, *render_target_view));
    IUnknown_Release(back_buffer);


  mylog("set viewport");
    vp: D3D11_VIEWPORT;
    vp.Width = xx width;
    vp.Height = xx height;
    vp.MinDepth = 0.0;
    vp.MaxDepth = 1.0;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;
    ID3D11DeviceContext_RSSetViewports(d3d_context, 1, *vp);

  init_depth_buffer();
  init_alpha_blending();
  init_six_vertex_for_a_quad_buffer();
}


init_depth_buffer :: () {
  #if !DEPTH_BUFFER {
    ID3D11DeviceContext_OMSetRenderTargets(d3d_context, 1, *render_target_view, null);
  } else {
    // depth stencil
    depth_stencil_desc: D3D11_TEXTURE2D_DESC;
    depth_stencil_desc.Width = xx window_width;
    depth_stencil_desc.Height = xx window_height;
    depth_stencil_desc.MipLevels = 1;
    depth_stencil_desc.ArraySize = 1;
    depth_stencil_desc.Format = .DXGI_FORMAT_D24_UNORM_S8_UINT;
    depth_stencil_desc.SampleDesc.Count = 1;
    depth_stencil_desc.SampleDesc.Quality = 0;
    depth_stencil_desc.Usage = .D3D11_USAGE_DEFAULT;
    depth_stencil_desc.BindFlags = .D3D11_BIND_DEPTH_STENCIL;

    depth_stencil_buffer: *ID3D11Texture2D;
    handle_hr(ID3D11Device_CreateTexture2D(d3d_device, *depth_stencil_desc, null, *depth_stencil_buffer));

    Global("depth_stencil_view: *ID3D11DepthStencilView;");
    handle_hr(ID3D11Device_CreateDepthStencilView(d3d_device, depth_stencil_buffer, null, *depth_stencil_view));

    ID3D11DeviceContext_OMSetRenderTargets(d3d_context, 1, *render_target_view, depth_stencil_view);
  }
}

init_alpha_blending :: () {
  #if ALPHA_BLENDING {
    depth_stencil_desc2: D3D11_DEPTH_STENCIL_DESC;
    depth_stencil_desc2.DepthEnable = xx true;
    depth_stencil_desc2.DepthWriteMask = .ALL;
    depth_stencil_desc2.DepthFunc = .LESS_EQUAL; // kills fps
    Global("depth_stencil_state: *ID3D11DepthStencilState;");
    ID3D11Device_CreateDepthStencilState(d3d_device, *depth_stencil_desc2, *depth_stencil_state);
    ID3D11DeviceContext_OMSetDepthStencilState(d3d_context, depth_stencil_state, 0);

    blendDesc: D3D11_BLEND_DESC;
    blendDesc.AlphaToCoverageEnable = 0;
    blendDesc.IndependentBlendEnable = 0;

    blendDesc.RenderTarget[0].BlendEnable = 1;
    blendDesc.RenderTarget[0].SrcBlend = .SRC_ALPHA;
    blendDesc.RenderTarget[0].DestBlend = .INV_SRC_ALPHA;
    blendDesc.RenderTarget[0].BlendOp = .ADD;
    blendDesc.RenderTarget[0].SrcBlendAlpha = .ONE;
    blendDesc.RenderTarget[0].DestBlendAlpha = .ZERO;
    blendDesc.RenderTarget[0].BlendOpAlpha = .ADD;
    blendDesc.RenderTarget[0].RenderTargetWriteMask = xx D3D11_COLOR_WRITE_ENABLE.ALL;

    Global("blend_state: *ID3D11BlendState;");
    handle_hr(ID3D11Device_CreateBlendState(d3d_device, *blendDesc, *blend_state));

    blend_factor := float.[1, 1, 1, 1];
    sample_mask := cast(u32)0xffffffff;
    ID3D11DeviceContext_OMSetBlendState(d3d_context, blend_state, *blend_factor, sample_mask);
  }
}

init_six_vertex_for_a_quad_buffer :: () {
  Vert :: Vector2;
  verts := Vert.[.{1,0}, .{0,0}, .{0,1}, .{1,0}, .{0,1}, .{1,1}];

  Global("six_vertex_for_a_quad_buffer: GpuBuffer;");
  six_vertex_for_a_quad_buffer = gpu_alloc(verts.count, Vert, data=verts.data);
}


bind_buffer :: (slot: u32, buffer: GpuBuffer) {
  strides: [1] u32;           strides[0] = buffer.type_size;
  offsets: [1] u32;           offsets[0] = 0;
  buffers: [1] *ID3D11Buffer; buffers[0] = *buffer;
  ID3D11DeviceContext_IASetVertexBuffers(d3d_context, slot, 1, buffers.data, strides.data, offsets.data);
}

GpuTexture :: struct {
  #as texture2d: *ID3D11Texture2D;
  shader_resource_view: *ID3D11ShaderResourceView;
}

load_image_into_gpu_texture :: load_texture;
load_texture :: (filename: string) -> GpuTexture {

  ensure_default_texture_sampler();
  ensure_default_texture_sampler :: () {
    Global("default_texture_sampler: *ID3D11SamplerState;");
    if default_texture_sampler  return;

    mylog("create and set a default texture sampler");
      // sampler
      image_sampler_desc: D3D11_SAMPLER_DESC;
      image_sampler_desc.Filter = .D3D11_FILTER_MIN_MAG_MIP_LINEAR;
      image_sampler_desc.AddressU = .D3D11_TEXTURE_ADDRESS_CLAMP;
      image_sampler_desc.AddressV = .D3D11_TEXTURE_ADDRESS_CLAMP;
      image_sampler_desc.AddressW = .D3D11_TEXTURE_ADDRESS_CLAMP;
      image_sampler_desc.MipLODBias = 0.0;
      image_sampler_desc.MaxAnisotropy = 1;
      image_sampler_desc.ComparisonFunc = .D3D11_COMPARISON_NEVER;
      image_sampler_desc.BorderColor[0] = 1.0;
      image_sampler_desc.BorderColor[1] = 1.0;
      image_sampler_desc.BorderColor[2] = 1.0;
      image_sampler_desc.BorderColor[3] = 1.0;
      image_sampler_desc.MinLOD = -1000000000/*FLT_MAX*/;
      image_sampler_desc.MaxLOD = 1000000000/*FLT_MAX*/;

      handle_hr(ID3D11Device_CreateSamplerState(d3d_device, *image_sampler_desc, *default_texture_sampler));

      ID3D11DeviceContext_PSSetSamplers(d3d_context, 0, 1, *default_texture_sampler);
  }

  // load image from disk to ram
  data, w, h := load_image(filename);
  defer free_image(data);

  // dx texture
  image_texture_desc: D3D11_TEXTURE2D_DESC;
  image_texture_desc.Width = xx w;
  image_texture_desc.Height = xx h;
  image_texture_desc.MipLevels = 1;
  image_texture_desc.ArraySize = 1;
  image_texture_desc.Format = .DXGI_FORMAT_R8G8B8A8_UNORM_SRGB;
  image_texture_desc.SampleDesc.Count = 1;
  image_texture_desc.SampleDesc.Quality = 0;
  image_texture_desc.Usage = .D3D11_USAGE_IMMUTABLE;
  image_texture_desc.BindFlags = .D3D11_BIND_SHADER_RESOURCE;
  image_subresource_data: D3D11_SUBRESOURCE_DATA;
  image_subresource_data.pSysMem = data;
  image_subresource_data.SysMemPitch = xx (w*4);

  gpu_texture: GpuTexture;
  handle_hr(ID3D11Device_CreateTexture2D(d3d_device, *image_texture_desc, *image_subresource_data, *gpu_texture.texture2d));

  // shaderresourceview is an indirect way of binding textures to your shader... idk doesn't make sense to me
  handle_hr(ID3D11Device_CreateShaderResourceView(d3d_device, *gpu_texture, null, *gpu_texture.shader_resource_view));

  return gpu_texture;
}

bind_texture :: (slot: u32, texture: GpuTexture) {
  // put image in the shader
  ID3D11DeviceContext_PSSetShaderResources(d3d_context, slot, 1, *texture.shader_resource_view);
}

GpuShader :: struct {
  vertex_shader: *ID3D11VertexShader;
  pixel_shader: *ID3D11PixelShader;
}
make_shader :: (shader_text: string, layout: [] D3D11_INPUT_ELEMENT_DESC) -> GpuShader {
  gpu_shader: GpuShader;
  gpu_shader.vertex_shader = make_vertex_shader(shader_text, layout);
  gpu_shader.pixel_shader  = make_pixel_shader(shader_text);
  return gpu_shader;
}

make_vertex_shader :: (shader: string, layout: [] D3D11_INPUT_ELEMENT_DESC) -> *ID3D11VertexShader {
  vs, hr := compile_shader(shader, "VS", "vs_4_0");
  defer free(vs);
  handle_hr(hr);

  vertex_shader: *ID3D11VertexShader;
  handle_hr(ID3D11Device_CreateVertexShader(d3d_device, vs.data, cast(u64) vs.count, null, *vertex_shader));

  // make a vertex layout. this is very weird to be here @cleanup
    Global("vertex_layout: *ID3D11InputLayout;");
    handle_hr(ID3D11Device_CreateInputLayout(d3d_device, layout.data, cast(u32) layout.count, vs.data, cast(u64) vs.count, *vertex_layout));

  // Set the input layout
    ID3D11DeviceContext_IASetInputLayout(d3d_context, vertex_layout);

  return vertex_shader;
}
make_pixel_shader :: (shader: string) -> *ID3D11PixelShader {
  ps, hr := compile_shader(shader, "PS", "ps_4_0");
  defer free(ps);
  handle_hr(hr);

  pixel_shader: *ID3D11PixelShader;
  handle_hr(ID3D11Device_CreatePixelShader(d3d_device, ps.data, cast(u64) ps.count, null, *pixel_shader));
  return pixel_shader;
}

bind_shader :: (shader: GpuShader) {
  ID3D11DeviceContext_VSSetShader(d3d_context, shader.vertex_shader, null, 0);
  ID3D11DeviceContext_PSSetShader(d3d_context, shader.pixel_shader,  null, 0);
}




make_input_layout :: () -> [..] D3D11_INPUT_ELEMENT_DESC {
  layout: [..] D3D11_INPUT_ELEMENT_DESC;
  array_reserve(*layout, 1);
  return layout;
}
layout_add :: (layout: *[..]D3D11_INPUT_ELEMENT_DESC, name: *u8, buffer_slot: u32, size: int, instanced: u32 = 0) {
  info: D3D11_INPUT_ELEMENT_DESC;
  info.SemanticName = name;
  info.SemanticIndex = 0;

  info.Format =
    ifx size == 12 then DXGI_FORMAT.R32G32B32_FLOAT else
    ifx size ==  8 then DXGI_FORMAT.R32G32_FLOAT    else
    ifx size ==  4 then DXGI_FORMAT.R32_FLOAT       else 0;
  if info.Format == 0 then die("invalid size");

  info.InputSlot = buffer_slot;
  info.AlignedByteOffset = D3D11_APPEND_ALIGNED_ELEMENT;
  info.InputSlotClass = ifx instanced then D3D11_INPUT_CLASSIFICATION.D3D11_INPUT_PER_INSTANCE_DATA else .VERTEX_DATA;
  info.InstanceDataStepRate = instanced;
  array_add(layout, info);
}




handle_hr :: (hr: HRESULT) {assert(SUCCEEDED(hr)); }

compile_shader :: (source: string, entry_point: string, shader_model: string) -> string, HRESULT {
  flags := D3DCOMPILE.ENABLE_STRICTNESS;
  #if DEBUG {
    flags |= .DEBUG;
    flags |= .SKIP_OPTIMIZATION;
  }

  defines: [] string;
  bytecode, errors, hr := D3DCompile(source, "source", defines, null, entry_point, shader_model, xx flags, 0);
  defer free(errors);

  if errors  die("Shader Compiler Error:\n", errors);
  handle_hr(hr);

  return bytecode, hr;
}





// gpu buffer helpers
GpuBuffer :: struct {
  #as d3dbuffer: *ID3D11Buffer;
  type_size: u32;
  count: int;
}
for_expansion :: (buffer: GpuBuffer, body: Code, flags: For_Flags) #expand {
  resource: D3D11_MAPPED_SUBRESOURCE;
  ID3D11DeviceContext_Map(d3d_context, *buffer, 0, .D3D11_MAP_WRITE_NO_OVERWRITE, 0, *resource);
  `it := resource.pData;
  for `it_index: 0..buffer.count-1 {
    #insert body;
    it += buffer.type_size;
  }
  ID3D11DeviceContext_Unmap(d3d_context, *buffer, 0);
}
gpu_alloc :: (count: u32, $T: Type, data: *void = null) -> GpuBuffer #must {
  gpu_buffer: GpuBuffer;
  gpu_buffer.type_size = size_of(T);
  gpu_buffer.count = xx count;

  bd: D3D11_BUFFER_DESC;
  bd.ByteWidth = size_of(T) * count;
  // if type == "dynamic" {
    bd.Usage = .DYNAMIC;
    bd.BindFlags = .CONSTANT_BUFFER;
    bd.CPUAccessFlags = .WRITE;
  // } else {
  //   bd.Usage = .DEFAULT;
  //   bd.BindFlags = .VERTEX_BUFFER;
  // }

  if data {
    InitData : D3D11_SUBRESOURCE_DATA;
    InitData.pSysMem = data;
    handle_hr(ID3D11Device_CreateBuffer(d3d_device, *bd, *InitData, *gpu_buffer.d3dbuffer));
  } else {
    handle_hr(ID3D11Device_CreateBuffer(d3d_device, *bd,      null, *gpu_buffer.d3dbuffer));
  }

  return gpu_buffer;
}
gpu_memcpy :: (buffer: GpuBuffer, source: *void, count: s64) {
  resource: D3D11_MAPPED_SUBRESOURCE;
  ID3D11DeviceContext_Map(d3d_context, *buffer, 0, .D3D11_MAP_WRITE_NO_OVERWRITE, 0, *resource);
  // ID3D11DeviceContext_Map(d3d_context, *buffer, 0, .D3D11_MAP_WRITE_DISCARD, 0, *resource);
  memcpy(resource.pData, source, count);
  ID3D11DeviceContext_Unmap(d3d_context, *buffer, 0);
}


// image file loading / parsing helpers
#import "stb_image";
load_image :: (filename: string) -> data: *u8, w: s32, h: s32, channels: s32 {
  w, h, channels: s32;
  data := stbi_load(temp_c_string(filename), *w, *h, *channels, 0);
  assert(data != null);
  return data, w, h, channels;
}
free_image :: (data: *u8) {stbi_image_free(data);}

set_vertex_shader :: (vertex_shader: *ID3D11VertexShader) {
  ID3D11DeviceContext_VSSetShader(d3d_context, vertex_shader, null, 0);
}
set_pixel_shader :: (pixel_shader: *ID3D11PixelShader) {
  ID3D11DeviceContext_PSSetShader(d3d_context, pixel_shader,  null, 0);
}

present :: () {

}
