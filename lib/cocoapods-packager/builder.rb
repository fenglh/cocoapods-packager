module Pod
  class Builder
    def initialize(platform, static_installer, source_dir, static_sandbox_root, dynamic_sandbox_root, public_headers_root, spec, embedded, mangle, dynamic, config, bundle_identifier, exclude_deps)
      @platform = platform
      @static_installer = static_installer
      @source_dir = source_dir
      @static_sandbox_root = static_sandbox_root
      @dynamic_sandbox_root = dynamic_sandbox_root
      @public_headers_root = public_headers_root
      @spec = spec
      @embedded = embedded
      @mangle = mangle
      @dynamic = dynamic
      @config = config
      @bundle_identifier = bundle_identifier
      @exclude_deps = exclude_deps
      @file_accessors = @static_installer.pod_targets.select { |t| t.pod_name == @spec.name }.flat_map(&:file_accessors)
    end

    def make_output_dir
      `mkdir -p #{@static_sandbox_root}`
    end

    def framework_output_dir(sim = false)
      return sim ? "sim_framework" : "framework"
    end

    def build

      # 构建真机架构
      framework = build_framework

      # 构建模拟器架构
      framework_sim = build_sim_framework

      [framework, framework_sim]
    end

    def build_framework
      framework_output_path = framework_output_dir( false)
      `mkdir -p #{framework_output_path}`
      framework = xcodebuild(false)
      framework
    end

    def  build_sim_framework
      sim_framework_output_path = framework_output_dir( true)
      `mkdir -p #{sim_framework_output_path}`
      framework_sim = xcodebuild(true)
      framework_sim
    end



    def expand_paths(path_specs)
      path_specs.map do |path_spec|
        Dir.glob(File.join(@source_dir, path_spec))
      end
    end



    def vendored_libraries
      if @vendored_libraries
        @vendored_libraries
      end
      file_accessors = if @exclude_deps
                         @file_accessors
                       else
                         @static_installer.pod_targets.flat_map(&:file_accessors)
                       end
      libs = file_accessors.flat_map(&:vendored_static_frameworks).map { |f| f + f.basename('.*') } || []
      libs += file_accessors.flat_map(&:vendored_static_libraries)
      @vendored_libraries = libs.compact.map(&:to_s)
      @vendored_libraries
    end

   

    def xcodebuild(is_sim = false, build_dir = 'build', target = 'Pods-packager', project_root = @static_sandbox_root, config = @config)

      args = 'BUILD_LIBRARY_FOR_DISTRIBUTION=NO ENABLE_BITCODE=NO GCC_PREPROCESSOR_DEFINITIONS=\'$(inherited)\''

      if defined?(Pod::DONT_CODESIGN)
        args = "#{args} CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO"
      end

      defines = is_sim ? '-sdk iphonesimulator' : '-sdk iphoneos'


      command = "xcodebuild #{defines} #{args} clean build -configuration #{config} -target #{target} -project #{project_root}/Pods.xcodeproj"


      # command = "xcodebuild #{defines} #{args} clean build -configuration #{config} -target #{target} -project #{project_root}/Pods.xcodeproj"

      output = `pwd`
      puts "当前目录:#{output}"
      puts "执行命名: #{command}"
      output = `#{command}`.lines.to_a

      if $?.exitstatus != 0
        puts UI::BuildFailedReport.report(command, output)

        UI.puts "\n----- #{$?.exitstatus}"
        # Note: We use `Process.exit` here because it fires a `SystemExit`
        # exception, which gives the caller a chance to clean up before the
        # process terminates.
        #
        # See http://ruby-doc.org/core-1.9.3/Process.html#method-c-exit
        Process.exit
      end

      system_build_dir = "build/Release-iphoneos"
      if is_sim
        system_build_dir = "build/Release-iphonesimulator"
      end

      build_framework_path = "#{system_build_dir}/#{@spec.name}/#{@spec.name}.framework"

      output_dir = framework_output_dir(is_sim)

      new_framewwork_dir = is_sim ? "#{output_dir}/#{@spec.name}.framework" : "#{output_dir}/#{@spec.name}.framework"

      `cp -rp #{build_framework_path} #{new_framewwork_dir}`

      new_framewwork_dir
    end
  end
end
