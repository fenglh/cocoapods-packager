require 'tmpdir'

module Pod
  class Command
    class Package < Command
      self.summary = '将 podspec 打包为静态库。'
      self.arguments = [
        CLAide::Argument.new('NAME', true),
        CLAide::Argument.new('SOURCE', false)
      ]

      # 配置选项
      def self.options
        [
          ['--force',     '覆盖已存在的文件。默认 true'],
          ['--distribution', '为发布构建库。默认 false'],
          ['--no-mangle', '不对依赖的 Pods 进行符号混淆。默认true'],
          ['--local',     '使用本地状态而非发布版本。'],
          ['--exclude-deps', '排除依赖的符号。'],
          ['--configuration', '构建指定的配置（例如 Debug）。默认为 Release。'],
          ['--subspecs', '仅包含指定的子规格。'],
          ['--spec-sources=private,https://github.com/CocoaPods/Specs.git', '从指定的源拉取依赖的 Pod（默认为 https://github.com/CocoaPods/Specs.git）']
        ]
      end

      def initialize(argv)
        # 初始化实例变量
        @embedded = argv.flag?('embedded')
        @local = argv.flag?('local', false)
        @force = argv.flag?('force', true)
        @distribution = argv.flag?('distribution', false)
        @mangle = argv.flag?('mangle', true)
        @exclude_deps = argv.flag?('exclude-deps', true)
        @name = argv.shift_argument
        @source = argv.shift_argument
        @spec_sources = argv.option('spec-sources', 'git@gitit.cc:social-infra/ios/cocoapods-repo.git,https://github.com/CocoaPods/Specs.git').split(',')
        @subspecs = argv.option('subspecs')&.split(',')
        @config = argv.option('configuration', 'Release')

        @source_dir = Dir.pwd
        @is_spec_from_path = false
        @spec = spec_with_path(@name) || spec_with_name(@name)
        @is_spec_from_path = true if @spec

        super
      end

      def validate!
        super
        help! '需要提供 podspec 名称或路径。' unless @spec
        help! 'podspec 包含二进制依赖，无法进行符号混淆。' if @mangle && binary_only?(@spec)
        help! '--local 选项只能在给定本地 `.podspec` 路径时使用。' if @local && !@is_spec_from_path
      end

      def run
        # 如果无法找到 podspec，报错并退出
        help! "无法找到名为 `#{@name}` 的 podspec。" unless @spec

        target_dir, work_dir = create_working_directory
        return if target_dir.nil?

        Dir.chdir(work_dir)
        puts "已切换到工作目录：#{work_dir}"

        build_package
        `mv "#{work_dir}" "#{target_dir}"`
        puts "已将工作目录移动到目标目录：#{target_dir}"

        Dir.chdir(@source_dir)
        puts "已返回原始目录：#{@source_dir}"
      end

      private

      # 构建静态沙盒并安装 Pod
      def build_in_sandbox(platform)
        config.installation_root = Pathname.new(Dir.pwd)
        config.sandbox_root = 'Pods'

        static_sandbox = build_static_sandbox(false)
        static_installer = install_pod(platform.name, static_sandbox)

        begin
          frameworks = perform_build(platform, static_sandbox, static_installer)
          return frameworks
        ensure
          clean_up_sandbox
        end
      end

      # 清理临时文件夹
      def clean_up_sandbox
        Pathname.new(config.sandbox_root).rmtree
        FileUtils.rm_f('Podfile.lock')
        puts "已移除 Pods 和 Podfile.lock"
      end

      # 打包框架并生成新 podspec
      def build_package
        builder = SpecBuilder.new(@spec, @source, @embedded, false)
        newspec = builder.spec_metadata

        @spec.available_platforms.each do |platform|
          framework, sim_framework = build_in_sandbox(platform)
          puts "构建完成！模拟器框架：#{sim_framework}，真机框架：#{framework}"

          newspec += builder.spec_platform(platform)

          tmp_framework = Dir.exist?(sim_framework) ? sim_framework : framework
          unless tmp_framework.nil?
            resources_spec, resource_bundles_spec = generate_resources_and_bundles(tmp_framework)
            newspec += "  s.resources = #{resources_spec}\n"
            newspec += "  s.resource_bundles = #{resource_bundles_spec}\n"

            # 生成并压缩框架文件
            zip_framework(tmp_framework)
          end
        end

        newspec += builder.spec_close
        File.write(@spec.name + '.podspec', newspec)
      end

      # 压缩框架文件为 .zip 格式
      def zip_framework(framework_path)
        parent_path = File.dirname(framework_path)
        framework_name = File.basename(framework_path)
        zipfile_name = "#{framework_name}.zip"

        `cd #{parent_path} && zip -r #{zipfile_name} #{framework_name}`

        if $?.success?
          puts "成功创建了 #{zipfile_name}"
        else
          puts "创建 zip 文件失败"
        end
      end

      # 生成资源和资源包配置
      def generate_resources_and_bundles(framework_path)
        resources = []
        resource_bundles = {}
        resources_path = Pathname.new(framework_path) + 'Resources'

        puts "资源路径：#{resources_path}"

        Dir.glob("#{resources_path}/*") do |file|
          puts "遍历资源文件：#{file}"

          if File.extname(file) == '.bundle'
            bundle_name = File.basename(file, '.bundle')
            resource_bundles[bundle_name] ||= []
            resource_bundles[bundle_name] << file
          else
            resources << file
          end
        end

        resources_spec = resources.map { |file| "Resources/#{Pathname.new(file).relative_path_from(resources_path)}" }
        resource_bundles_spec = resource_bundles.map do |bundle_name, files|
          "#{bundle_name} => #{files.map { |file| "Resources/#{Pathname.new(file).relative_path_from(resources_path)}" }.join(' ')}"
        end

        return resources_spec, resource_bundles_spec
      end

      # 创建目标目录
      def create_target_directory
        target_dir = "#{@source_dir}/#{@spec.name}-#{@spec.version}"

        if File.exist? target_dir
          if @force
            Pathname.new(target_dir).rmtree
          else
            UI.puts "目标目录 '#{target_dir}' 已经存在。"
            return nil
          end
        end
        target_dir
      end

      # 创建临时工作目录
      def create_working_directory
        target_dir = create_target_directory
        return if target_dir.nil?

        work_dir = Dir.tmpdir + '/cocoapods-' + Array.new(8) { rand(36).to_s(36) }.join
        Pathname.new(work_dir).mkdir
        [target_dir, work_dir]
      end

      # 执行构建操作
      def perform_build(platform, static_sandbox, static_installer)
        static_sandbox_root = config.sandbox_root.to_s
        builder = Pod::Builder.new(
          platform,
          static_installer,
          @source_dir,
          static_sandbox_root,
          nil,
          static_sandbox.public_headers.root,
          @spec,
          @embedded,
          @mangle,
          false,
          @config,
          nil,
          @exclude_deps,
          @distribution
        )
        builder.build
      end
    end
  end
end
