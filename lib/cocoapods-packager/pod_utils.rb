module Pod
  class Command
    class Package < Command
      private

      def make_sandbox()
        static_sandbox_root = Pathname.new(config.sandbox_root)
        Sandbox.new(static_sandbox_root)
      end


      def install_pod(spec, spec_sources, platform_name, sandbox)

        puts "执行 pod install：#{sandbox.sources_root}"

        # 调用 podfile_from_spec 方法生成一个 Podfile 对象
        # 传入参数包括：spec 的定义文件路径、spec 名称、平台名称、部署目标、subspecs 和源
        podfile = podfile_from_spec(
          spec.defined_in_file,
          spec.name,
          platform_name,
          spec.swift_version,
          spec.deployment_target(platform_name),
          nil,
          spec_sources
        )

        # 创建一个新的安装器（Installer）实例，传入 sandbox 和生成的 podfile
        static_installer = Installer.new(sandbox, podfile)


        # 调用安装器的 install! 方法开始安装 Pod
        static_installer.install!

        # 如果安装器不为空，则进行后续配置
        unless static_installer.nil?
          # 遍历所有 Pod 项目的 targets
          static_installer.pods_project.targets.each do |target|

            # 遍历每个 target 的构建配置
            target.build_configurations.each do |config|
              # 配置构建设置

              # 启用模块自动链接
              config.build_settings['CLANG_MODULES_AUTOLINK'] = 'YES'

              # 禁用 GCC 的调试符号生成（对于发布版本可能有用）
              config.build_settings['GCC_GENERATE_DEBUGGING_SYMBOLS'] = 'NO'

              # 禁用为分发构建库（对于静态库的构建通常会禁用）
              config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'NO'

              # 禁用 Bitcode（如果不需要 Bitcode，可以关闭它）
              config.build_settings['ENABLE_BITCODE'] = 'NO'

              # 设置生成的二进制文件类型为静态库
              config.build_settings['MACH_O_TYPE'] = 'staticlib'

              # 设置 iOS 部署目标为 13.0
              config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'

              # 设置 Swift 版本为 5.0
              config.build_settings['SWIFT_VERSION'] = '5.0'
            end
          end

          # 保存对 pods 项目的所有更改
          static_installer.pods_project.save
        end

        # 返回安装器实例（可以用于后续的操作或调试）
        static_installer
      end




      def podfile_from_spec(path, spec_name, platform_name, swift_version, deployment_target, subspecs, sources, use_modular_headers = true)



        # 创建一个空的 options 哈希，存储 podspec 相关的配置信息
        options = {}

        # 如果传入了 podspec 的路径，添加到 options 中
        if path
          options[:podspec] = path
        end

        # 输出 Podfile 的 deployment_target 以供调试查看
        puts "Podfile deployment_target: #{deployment_target}"

        # 如果 subspecs 存在，添加到 options 中
        options[:subspecs] = subspecs if subspecs

        # 创建一个新的 Podfile
        Pod::Podfile.new do

          # 设置 Podfile 的源，遍历 sources 数组，为每个源调用 source 方法
          sources.each { |s| source s }

          # 设置平台和部署目标（例如 iOS 10.0）
          platform(platform_name, deployment_target)

          # 根据传入参数决定是否使用 modular headers
          use_modular_headers! if use_modular_headers

          # 强制使用 frameworks 而非 static libraries
          use_frameworks!

          # 添加主 pod 依赖
          # spec_name 是 pod 的名称，options 是配置项，包括 podspec 路径、subspec 等
          pod(spec_name, options)

          # 安装时的额外配置项
          install!('cocoapods',
                   :integrate_targets => false,  # 禁用 target 集成
                   :deterministic_uuids => false)  # 禁用 deterministic UUIDs

          target('packager') do
            # 继承完整的设置（包括所有配置）
            inherit! :complete
          end

          # 兼容个别pod 的podspec没有显式指定swift version
          pre_install do |installer|
            puts "pre_install 处理"
            swift_pod_targets = installer.pod_targets.select(&:uses_swift?)
            # 遍历所有 pod 目标
            swift_pod_targets.each do |pod_target|
              target_definitions = pod_target.target_definitions
              target_definitions.each do |target_definition|
                target_definition.swift_version = swift_version
              end
              # puts "#{pod_target.target_definitions.map { |td| "target:`#{td.name}`(swift version:`#{td.swift_version.to_s}`)" }.to_sentence}集成Pod`#{pod_target.name}`(swift_version: `#{swift_version}`)"
            end
          end

        end
      end



      def binary_only?(spec)
        deps = spec.dependencies.map { |dep| spec_with_name(dep.name) }
        [spec, *deps].each do |specification|
          %w(vendored_frameworks vendored_libraries).each do |attrib|
            if specification.attributes_hash[attrib]
              return true
            end
          end
        end

        false
      end

      def spec_with_name(name)
        return if name.nil?

        set = Pod::Config.instance.sources_manager.search(Dependency.new(name))
        return nil if set.nil?

        set.specification.root
      end

      # 定义一个方法，用于从给定路径加载一个 Podspec 文件
      def spec_with_path(path)
        # 如果传入的 path 是 nil，则直接返回，不做任何操作
        return if path.nil?

        # 将传入的 path 转换为 Pathname 对象，这样可以方便地操作路径
        path = Pathname.new(path)

        # 如果传入的路径不是绝对路径（即没有以根目录 / 开头），则将当前工作目录与该路径拼接，形成绝对路径
        path = Pathname.new(Dir.pwd).join(path) unless path.absolute?

        # 如果拼接后的路径不存在，则直接返回
        return unless path.exist?

        # 将 path 转换为绝对路径（规范化路径），并赋值给实例变量 @path
        absolutePath = path.expand_path

        # 如果路径指向的是一个目录，而不是文件，给出提示并返回
        if absolutePath.directory?
          help! absolutePath + ': is a directory.'
          return
        end

        # 如果文件扩展名既不是 .podspec 也不是 .json，给出提示并返回
        unless ['.podspec', '.json'].include? absolutePath.extname
          help! absolutePath + ': is not a podspec.'
          return
        end

        # 如果路径有效且符合要求，尝试从文件中加载 Specification 对象
        Specification.from_file(absolutePath)
      end


      #----------------------
      # Dynamic Project Setup
      #----------------------

      def build_dynamic_sandbox(_static_sandbox, _static_installer)
        dynamic_sandbox_root = Pathname.new(config.sandbox_root + '/Dynamic')
        dynamic_sandbox = Sandbox.new(dynamic_sandbox_root)

        dynamic_sandbox
      end

      # @param [Pod::Sandbox] dynamic_sandbox
      #
      # @param [Pod::Sandbox] static_sandbox
      #
      # @param [Pod::Installer] static_installer
      #
      # @param [Pod::Platform] platform
      #
      def install_dynamic_pod(dynamic_sandbox, static_sandbox, static_installer, platform)
        # 1 Create a dynamic target for only the spec pod.
        dynamic_target = build_dynamic_target(dynamic_sandbox, static_installer, platform)

        # 2. Build a new xcodeproj in the dynamic_sandbox with only the spec pod as a target.
        project = prepare_pods_project(dynamic_sandbox, dynamic_target.name, static_installer)

        # 3. Copy the source directory for the dynamic framework from the static sandbox.
        copy_dynamic_target(static_sandbox, dynamic_target, dynamic_sandbox)

        # 4. Create the file references.
        install_file_references(dynamic_sandbox, [dynamic_target], project)

        # 5. Install the target.
        install_library(dynamic_sandbox, dynamic_target, project)

        # 6. Write the actual .xcodeproj to the dynamic sandbox.
        write_pod_project(project, dynamic_sandbox)
      end

      # @param [Pod::Installer] static_installer
      #
      # @return [Pod::PodTarget]
      #
      def build_dynamic_target(dynamic_sandbox, static_installer, platform)
        spec_targets = static_installer.pod_targets.select do |target|
          target.name == @spec.name
        end
        static_target = spec_targets[0]

        file_accessors = create_file_accessors(static_target, dynamic_sandbox)

        archs = []
        dynamic_target = Pod::PodTarget.new(dynamic_sandbox, true, static_target.user_build_configurations, archs, platform, static_target.specs, static_target.target_definitions, file_accessors)
        dynamic_target
      end

      # @param [Pod::Sandbox] dynamic_sandbox
      #
      # @param [String] spec_name
      #
      # @param [Pod::Installer] installer
      #
      def prepare_pods_project(dynamic_sandbox, spec_name, installer)
        # Create a new pods project
        pods_project = Pod::Project.new(dynamic_sandbox.project_path)

        # Update build configurations
        installer.analysis_result.all_user_build_configurations.each do |name, type|
          pods_project.add_build_configuration(name, type)
        end

        # Add the pod group for only the dynamic framework
        local = dynamic_sandbox.local?(spec_name)
        path = dynamic_sandbox.pod_dir(spec_name)
        was_absolute = dynamic_sandbox.local_path_was_absolute?(spec_name)
        pods_project.add_pod_group(spec_name, path, local, was_absolute)
        pods_project
      end

      def copy_dynamic_target(static_sandbox, _dynamic_target, dynamic_sandbox)
        command = "cp -a #{static_sandbox.root}/#{@spec.name} #{dynamic_sandbox.root}"
        `#{command}`
      end

      def create_file_accessors(target, dynamic_sandbox)
        pod_root = dynamic_sandbox.pod_dir(target.root_spec.name)

        path_list = Sandbox::PathList.new(pod_root)
        target.specs.map do |spec|
          Sandbox::FileAccessor.new(path_list, spec.consumer(target.platform))
        end
      end

      def install_file_references(dynamic_sandbox, pod_targets, pods_project)
        installer = Pod::Installer::Xcode::PodsProjectGenerator::FileReferencesInstaller.new(dynamic_sandbox, pod_targets, pods_project)
        installer.install!
      end

      def install_library(dynamic_sandbox, dynamic_target, project)
        return if dynamic_target.target_definitions.flat_map(&:dependencies).empty?
        target_installer = Pod::Installer::Xcode::PodsProjectGenerator::PodTargetInstaller.new(dynamic_sandbox, project, dynamic_target)
        result = target_installer.install!
        native_target = result.native_target

        # Installs System Frameworks
        if dynamic_target.should_build?
          dynamic_target.file_accessors.each do |file_accessor|
            file_accessor.spec_consumer.frameworks.each do |framework|
              native_target.add_system_framework(framework)
            end
            file_accessor.spec_consumer.libraries.each do |library|
              native_target.add_system_library(library)
            end
          end
        end
      end

      def write_pod_project(dynamic_project, dynamic_sandbox)
        UI.message "- Writing Xcode project file to #{UI.path dynamic_sandbox.project_path}" do
          dynamic_project.pods.remove_from_project if dynamic_project.pods.empty?
          dynamic_project.development_pods.remove_from_project if dynamic_project.development_pods.empty?
          dynamic_project.sort(:groups_position => :below)
          dynamic_project.recreate_user_schemes(false)

          # Edit search paths so that we can find our dependency headers
          dynamic_project.targets.first.build_configuration_list.build_configurations.each do |config|
            config.build_settings['HEADER_SEARCH_PATHS'] = "$(inherited) #{Dir.pwd}/Pods/Static/Headers/**"
            config.build_settings['USER_HEADER_SEARCH_PATHS'] = "$(inherited) #{Dir.pwd}/Pods/Static/Headers/**"
            config.build_settings['OTHER_LDFLAGS'] = '$(inherited) -ObjC'
          end
          dynamic_project.save
        end
      end
    end
  end
end
