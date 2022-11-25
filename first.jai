
RELEASE :: #run get_build_options().optimization_level == .RELEASE;
main_filepath :: "main.jai";
exe_icon_path :: "bunny.ico";

#run build();


build :: () {
  w := compiler_create_workspace();
  options := get_build_options(); set_build_options_dc(.{do_output=false});

  { // build for debug or release

    options.output_executable_name = "bunnymark";

    #if !RELEASE {
      options.backend = .X64;
    }
    #if  RELEASE {
      set_optimization_level(*options, 2, 0);
      options.stack_trace = false;
      #run WR.disable_runtime_console();
    }
  }

  // done setting options
  set_build_options(options, w);


  { // compile
    compiler_begin_intercept(w);

    add_build_file(main_filepath, w);

    // waiting for our exe to finish so we can set its icon
    while true {
      message := compiler_wait_for_message();
      if !message continue;
      if message.workspace != w continue;
      if message.kind == .COMPLETE break;
    }
    compiler_end_intercept(w);
  }

  // set exe icon
  exe_path := tprint("%1%2.exe", options.output_path, options.output_executable_name);
  WR.set_icon_by_filename(exe_path, exe_icon_path);

  // delete .pdb if release
  #if RELEASE  File.file_delete("bunnymark.pdb");
}

#import "Basic";
#import "Compiler";
WR   :: #import "Windows_Resources";
File :: #import "File";
