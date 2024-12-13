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
    

    def build_static_framework
      xcodebuild(false)

    end

    def build_sim_static_framework
      xcodebuild(true)
    end

    

    def build_with_mangling(options)
      UI.puts 'Mangling symbols'
      defines = Symbols.mangle_for_pod_dependencies(@spec.name, @static_sandbox_root)
      defines << ' ' << @spec.consumer(@platform).compiler_flags.join(' ')

      UI.puts 'Building mangled framework'
      xcodebuild(defines, options)
      defines
    end

    def clean_directory_for_dynamic_build
      # Remove static headers to avoid duplicate declaration conflicts
      FileUtils.rm_rf("#{@static_sandbox_root}/Headers/Public/#{@spec.name}")
      FileUtils.rm_rf("#{@static_sandbox_root}/Headers/Private/#{@spec.name}")

      # Equivalent to removing derrived data
      FileUtils.rm_rf('Pods/build')
    end

    

    def expand_paths(path_specs)
      path_specs.map do |path_spec|
        Dir.glob(File.join(@source_dir, path_spec))
      end
    end

    def static_libs_in_sandbox(build_dir = 'build')
      if @exclude_deps
        UI.puts 'Excluding dependencies'
        Dir.glob("#{@static_sandbox_root}/#{build_dir}/lib#{@spec.name}.a")
      else
        Dir.glob("#{@static_sandbox_root}/#{build_dir}/lib*.a")
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

      args = 'BUILD_LIBRARY_FOR_DISTRIBUTION=NO ENABLE_BITCODE=NO'

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

      system_build_dir = File.join(@static_sandbox_root, "..","/build/Release-iphoneos")
      if is_sim
        system_build_dir = File.join(@static_sandbox_root, "..","/build/Release-iphonesimulator")
      end
      
      result_dir = "#{@static_sandbox_root}/.."
      `cp -rp #{system_build_dir}/#{@spec.name}/ #{result_dir}`

    end
  end
end
