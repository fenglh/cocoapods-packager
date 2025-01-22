module Pod
  class Builder
    def initialize(platform, static_installer, source_dir, static_sandbox_root, dynamic_sandbox_root,
                   public_headers_root, spec, embedded, mangle, dynamic, config, bundle_identifier,
                   exclude_deps, build_for_distribution)
      # 实例化时保存参数
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
      @distribution = build_for_distribution

      # 选择特定 pod 的 file_accessors
      @file_accessors = @static_installer.pod_targets.select { |t| t.pod_name == @spec.name }.flat_map(&:file_accessors)
    end

    # 创建输出目录
    def make_output_dir
      `mkdir -p #{@static_sandbox_root}`
    end

    # 根据是否模拟器返回框架目录
    def framework_output_dir(sim = false)
      sim ? "sim_framework" : "framework"
    end

    # 构建框架
    def build
      # 构建真机架构和模拟器架构
      # [build_framework(false), build_framework(true)]

      [build_framework(false)]
    end

    # 构建Framework
    def build_framework(is_sim)
      framework_output_path = framework_output_dir(is_sim)
      `mkdir -p #{framework_output_path}`
      xcodebuild(is_sim)
    end


    # 扩展路径
    def expand_paths(path_specs)
      path_specs.flat_map { |path_spec| Dir.glob(File.join(@source_dir, path_spec)) }
    end

    # 获取所有的 vendored 库
    def vendored_libraries
      return @vendored_libraries if @vendored_libraries

      # 根据是否排除依赖决定 file_accessors 来源
      file_accessors = @exclude_deps ? @file_accessors : @static_installer.pod_targets.flat_map(&:file_accessors)

      # 获取 vendored 静态库和框架
      libs = file_accessors.flat_map(&:vendored_static_frameworks).map { |f| f + f.basename('.*') } || []
      libs += file_accessors.flat_map(&:vendored_static_libraries)
      @vendored_libraries = libs.compact.map(&:to_s)
    end

    # 执行 xcodebuild 命令
    def xcodebuild(is_sim = false, build_dir = 'build', target = 'Pods-packager', project_root = @static_sandbox_root, config = @config)
      args = build_xcode_args(is_sim)

      # 构建最终的 xcodebuild 命令
      command = "xcodebuild #{args[:defines]} #{args[:args].join(' ')} clean build -configuration #{config} -target #{target} -project #{project_root}/Pods.xcodeproj"
      puts "执行命令: #{command}"

      # 执行命令并检查返回状态
      output = `#{command}`.lines.to_a
      handle_build_failure(command, output) unless $?.success?

      # 复制框架到最终输出目录
      copy_framework(is_sim, output)
    end

    private

    # 构建 xcodebuild 命令的参数
    def build_xcode_args(is_sim)
      args = [
        'SKIP_INSTALL=NO',
        'ENABLE_BITCODE=NO',
        'GCC_PREPROCESSOR_DEFINITIONS=\'$(inherited)\''
      ]

      args << 'BUILD_LIBRARY_FOR_DISTRIBUTION=YES' if @distribution
      args << 'CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO' if defined?(Pod::DONT_CODESIGN)

      defines = is_sim ? '-sdk iphonesimulator' : '-sdk iphoneos'

      { defines: defines, args: args }
    end

    # 处理构建失败
    def handle_build_failure(command, output)
      puts UI::BuildFailedReport.report(command, output)
      UI.puts "\n----- #{$?.exitstatus}"
      Process.exit
    end

    # 复制构建的框架文件
    def copy_framework(is_sim, output)
      system_build_dir = is_sim ? "build/Release-iphonesimulator" : "build/Release-iphoneos"
      build_framework_path = "#{system_build_dir}/#{@spec.name}/#{@spec.name}.framework"
      output_dir = framework_output_dir(is_sim)
      new_framework_path = "#{output_dir}/#{@spec.name}.framework"

      `cp -rp #{build_framework_path} #{new_framework_path}`

      # 拷贝资源文件
      copy_resources(new_framework_path)
      new_framework_path
    end

    # 拷贝资源文件
    def copy_resources(framework_path)
      resources_path = Pathname.new(framework_path) + 'Resources'
      resources_path.mkpath unless resources_path.exist?

      # 拷贝 .bundle 文件
      move_bundles(framework_path, resources_path)

      # 拷贝其他资源
      move_resources(framework_path, resources_path)
    end

    # 拷贝 .bundle 文件
    def move_bundles(framework_path, resources_path)
      bundles = Dir.glob("#{framework_path}/**/*.bundle")
      bundle_names = get_bundle_names

      matched_bundles = bundles.select do |bundle|
        bundle_name = File.basename(bundle, '.bundle')
        bundle_names.include?(bundle_name)
      end

      unless matched_bundles.empty?
        FileUtils.mv(matched_bundles, resources_path.to_path)
        puts "移动了以下 bundle 文件: #{matched_bundles.join(', ')}"
      end
    end

    # 获取所有需要的 .bundle 文件名称
    def get_bundle_names
      [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(@platform)
        consumer.resource_bundles.keys + consumer.resources.map do |r|
          File.basename(r, '.bundle') if File.extname(r) == '.bundle'
        end
      end.compact.uniq
    end

    # 拷贝其他资源文件
    def move_resources(framework_path, resources_path)
      resource_names = get_resource_names

      resources = resource_names.flat_map do |pattern|
        Dir.glob(File.join(framework_path, pattern)).map do |file|
          puts "找到资源文件: #{file}"
          file
        end
      end.compact.uniq

      unless resources.empty?
        FileUtils.mv(resources, resources_path.to_path)
        puts "拷贝资源文件: #{resources.join(', ')}"
      end
    end

    # 获取所有资源文件名称
    def get_resource_names
      [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(@platform)
        consumer.resources.map { |r| File.basename(r) }
      end
    end
  end
end
