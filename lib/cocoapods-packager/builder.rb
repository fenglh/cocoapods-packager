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



    # "xcodebuild #{defines} #{args} clean build -configuration #{config} -target #{target} -project #{project_root}/Pods.xcodeproj"
    def build_static_framework
      xcodebuild(false)

    end

    def build_sim_static_framework
      xcodebuild(true)
    end

    # def build_static_framework
    #
    #   puts "开始构建#{@config}模式的Arm64静态framework #{@spec} "
    #   defines = compile
    #   puts "完成编#{@config}模式的Arm64静态framework #{@spec} "
    #
    #   puts "开始构建#{@config}模式的X86_64静态framework #{@spec} "
    #   build_sim_libraries(defines)
    #   puts "完成编#{@config} 模式的X86_64静态framework #{@spec} "
    #
    #   create_framework
    #   output = @fwk.versions_path + Pathname.new(@spec.name)
    #
    #   puts "创建framework文件夹：#{output}"
    #
    #   puts "开始合并X86_64、Arm64静态库 #{@spec} "
    #   # build_static_library_for_ios(output)
    #
    #   puts "构建完成! 开始拷贝数据:"
    #
    #   copy_headers
    #   copy_license
    #   copy_resources
    # end
    #
    # def link_embedded_resources
    #   target_path = @fwk.root_path + Pathname.new('Resources')
    #   target_path.mkdir unless target_path.exist?
    #
    #   Dir.glob(@fwk.resources_path.to_s + '/*').each do |resource|
    #     resource = Pathname.new(resource).relative_path_from(target_path)
    #     `ln -sf #{resource} #{target_path}`
    #   end
    # end


    # 构建模拟器库
    # def build_sim_libraries(defines)
    #   if @platform.name == :ios
    #     xcodebuild(defines, '-sdk iphonesimulator', 'build-sim')
    #   end
    # end

    # def build_static_library_for_ios(output)
    #   static_libs = static_libs_in_sandbox('build') + static_libs_in_sandbox('build-sim') + vendored_libraries
    #   puts "静态库目录:#{static_libs.join(' ')}"
    #   libs = ios_architectures.map do |arch|
    #     puts "--arch: #{arch}"
    #     library = "#{@static_sandbox_root}/build/package-#{arch}.a"
    #     cmd = "libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}"
    #     puts "执行libtool命令:#{cmd}"
    #     `#{cmd}`
    #     puts "生成静态库:#{library}"
    #     library
    #   end
    #
    #   cmd = "lipo -create -output #{output} #{libs.join(' ')}"
    #   puts "执行lipo命令:#{cmd}"
    #   `#{cmd}`
    # end


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

    # def compile
    #
    #
    #   output = `pwd`
    #   puts "当前目录:#{output}"
    #   defines = "GCC_PREPROCESSOR_DEFINITIONS='$(inherited) PodsDummy_Pods_#{@spec.name}=PodsDummy_PodPackage_#{@spec.name}'"
    #   defines << ' ' << @spec.consumer(@platform).compiler_flags.join(' ')
    #
    #   puts "defines: #{defines}"
    #
    #   options = ios_build_options
    #
    #   # codebuild GCC_PREPROCESSOR_DEFINITIONS='$(inherited) PodsDummy_Pods_YLActivation=PodsDummy_PodPackage_YLActivation'  ARCHS='arm64' OTHER_CFLAGS='-fembed-bitcode -Qunused-arguments' clean build -configuration Release -target Pods-packager -project Pods/Pods.xcodeproj
    #   # defines: 是指"GCC_PREPROCESSOR_DEFINITIONS='$(inherited) PodsDummy_Pods_YLActivation=PodsDummy_PodPackage_YLActivation'" 这段宏
    #   # options: 是指“ARCHS='arm64' OTHER_CFLAGS='-fembed-bitcode -Qunused-arguments'” 这段参数
    #   xcodebuild(defines, options)
    #
    #   if @mangle
    #     return build_with_mangling(options)
    #   end
    #
    #   defines
    # end

    # def copy_headers
    #   puts "开始拷贝头文件"
    #   headers_source_root = "#{@public_headers_root}/#{@spec.name}"
    #   puts "遍历目录及子目录：#{headers_source_root}下所有的.h文件"
    #
    #   # 拷贝头文件
    #   copy_header_files(headers_source_root)
    #
    #   # 处理 module_map 生成
    #   module_map = generate_module_map
    #   if module_map
    #     # 如果有 module_map 生成则写入文件
    #     write_module_map(module_map)
    #   end
    # end
    #
    # # 拷贝所有头文件
    # def copy_header_files(headers_source_root)
    #   Dir.glob("#{headers_source_root}/**/*.h").each do |h|
    #     puts "遍历到.h文件: #{h}"
    #     # 使用 ditto 命令复制文件
    #     destination = "#{@fwk.headers_path}/#{h.sub(headers_source_root, '')}"
    #     cmd = "ditto #{h} #{destination}"
    #     puts "执行ditto命令: #{cmd}"
    #     system(cmd)
    #   end
    # end
    #
    # # 根据条件生成 module_map
    # def generate_module_map
    #   # 如果指定了 module_map，直接读取它
    #   if @spec.module_map
    #     module_map_file = @file_accessors.flat_map(&:module_map).first
    #     puts "#{@spec.name} spec 指定module_map：#{module_map_file}"
    #     return File.read(module_map_file) if Pathname(module_map_file).exist?
    #
    #     # 如果没有指定，且有头文件，则生成默认的 module_map
    #   elsif header_file = find_header_file
    #     puts "#{@spec.name} spec 没指定module_map，创建默认的module_map：#{header_file}"
    #     return generate_default_module_map(header_file)
    #   end
    #
    #   nil # 如果没有匹配条件，返回 nil
    # end

    # 查找头文件，支持 .h 和 -umbrella.h 后缀
  #   def find_header_file
  #     ["#{@spec.name}.h", "#{@spec.name}-umbrella.h"].find do |file|
  #       File.exist?("#{@public_headers_root}/#{@spec.name}/#{file}")
  #     end
  #   end
  #
  #   # 生成默认的 module_map
  #   def generate_default_module_map(header_file)
  #     <<~MAP
  # framework module #{@spec.name} {
  #   umbrella header "#{header_file}"
  #
  #   export *
  #   module * { export * }
  # }
  # MAP
  #   end

    # 写入生成的 module_map 文件
    # def write_module_map(module_map)
    #   @fwk.module_map_path.mkpath unless @fwk.module_map_path.exist?
    #   File.write("#{@fwk.module_map_path}/module.modulemap", module_map)
    #   puts "#{@spec.name} spec 生成 #{@fwk.module_map_path}/module.modulemap"
    # end
    #
    #
    # def copy_license
    #   license_file = @spec.license[:file] || 'LICENSE'
    #   license_file = Pathname.new("#{@static_sandbox_root}/#{@spec.name}/#{license_file}")
    #   FileUtils.cp(license_file, '.') if license_file.exist?
    # end
    #
    # def copy_resources
    #   bundles = Dir.glob("#{@static_sandbox_root}/build/*.bundle")
    #   if @dynamic
    #     resources_path = "ios/#{@spec.name}.framework"
    #     `cp -rp #{@static_sandbox_root}/build/*.bundle #{resources_path} 2>&1`
    #   else
    #     `cp -rp #{@static_sandbox_root}/build/*.bundle #{@fwk.resources_path} 2>&1`
    #     resources = expand_paths(@spec.consumer(@platform).resources)
    #     if resources.count == 0 && bundles.count == 0
    #       @fwk.delete_resources
    #       return
    #     end
    #     if resources.count > 0
    #       `cp -rp #{resources.join(' ')} #{@fwk.resources_path}`
    #     end
    #   end
    # end

    # def create_framework
    #   @fwk = Framework::Tree.new(@spec.name, @platform.name.to_s, @embedded)
    #   @fwk.make
    # end

    # def dependency_count
    #   count = @spec.dependencies.count
    #
    #   @spec.subspecs.each do |subspec|
    #     count += subspec.dependencies.count
    #   end
    #
    #   count
    # end

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

    # def static_linker_flags_in_sandbox
    #   linker_flags = static_libs_in_sandbox.map do |lib|
    #     lib.slice!('lib')
    #     lib_flag = lib.chomp('.a').split('/').last
    #     "-l#{lib_flag}"
    #   end
    #   linker_flags.reject { |e| e == "-l#{@spec.name}" || e == '-lPods-packager' }
    # end

    # def ios_build_options
    #   "ARCHS=\'#{ios_architectures.join(' ')}\' OTHER_CFLAGS=\'-Qunused-arguments\'"
    # end

    # def ios_architectures
    #   archs = %w(x86_64 arm64)
    #   vendored_libraries.each do |library|
    #     archs = `lipo -info #{library}`.split & archs
    #   end
    #   archs
    # end

    def xcodebuild(is_sim = false, build_dir = 'build', target = 'Pods-packager', project_root = @static_sandbox_root, config = @config)

      args = 'BUILD_LIBRARY_FOR_DISTRIBUTION=YES'

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

      # system_build_dir = File.join(@static_sandbox_root, "..","/build/Release-iphoneos")
      # if is_sim
      #   system_build_dir = File.join(@static_sandbox_root, "..","/build/Release-iphonesimulator")
      # end
      #
      # result_dir = "#{@static_sandbox_root}/.."
      # `cp -rp #{system_build_dir}/#{@spec.name}/ #{result_dir}`

    end
  end
end
