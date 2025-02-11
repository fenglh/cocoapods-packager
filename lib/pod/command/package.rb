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
          ['--distribution', '为发布构建库。默认 false'],
          ['--no-mangle', '不对依赖的 Pods 进行符号混淆。默认true'],
          ['--exclude-deps', '排除依赖的符号。'],
          ['--configuration', '构建指定的配置（例如 Debug）。默认为 Release。'],
          ['--subspecs', '仅包含指定的子规格。'],
          ['--spec-sources=private,https://github.com/CocoaPods/Specs.git', '从指定的源拉取依赖的 Pod（默认为 https://github.com/CocoaPods/Specs.git）']
        ]
      end

      def initialize(argv)
        # 初始化实例变量
        @embedded = argv.flag?('embedded')
        @distribution = argv.flag?('distribution', false)
        @mangle = argv.flag?('mangle', true)
        @exclude_deps = argv.flag?('exclude-deps', true)
        @name = argv.shift_argument
        @source = argv.shift_argument
        @spec_sources = argv.option('spec-sources', 'https://gitit.cc/social-infra/ios/cocoapods-repo.git,https://github.com/CocoaPods/Specs.git').split(',')
        @config = argv.option('configuration', 'Release')
        @all = argv.flag?('all', false)
        super
      end

      def validate!
        super
      end

      def run

        @source_dir = Dir.pwd
        @succeed_count = 0
        @failed_count = 0
        @artifact_repo_url = "http://192.168.5.173:8080/frameworks"
        @use_json = false

        puts "cocoapods repo sources: #{@spec_sources}"

        if @all
          all_specs = find_all_specs()

          flat_pod_names = flat_pods()

          specs = all_specs.select { | spec | flat_pod_names.include?(spec.name) }

          help! "准备制作framework个数:#{specs.count}" unless !specs.empty?

          puts "准备制作framework个数:#{specs.count}"
          start(specs)
        else
          spec = spec_with_path(@name)
          help! "无法找到`#{@name}` 的 podspec。" unless spec
          start([spec])
        end

      end

      # def flat_pods
      #   [
      #     'BSText', 'CrushGuard', 'FLLaunchView', 'FlatAnimation', 'FlatBase',
      #     'FlatBiz', 'FlatDNS', 'FlatDokit', 'FlatGame', 'FlatKtv', 'FlatLive',
      #     'FlatLogin', 'FlatPageView', 'FlatReport', 'FlatResource', 'FlatSecurity',
      #     'FlatTouchRipple', 'FlatWeb', 'PerformanceReport', 'TCCommon', 'TCFoundation',
      #     'TCUIKit', 'TCUtil', 'YLActivation', 'YLAnimation', 'YLAudit', 'YLBizJSBridge',
      #     'YLCache', 'YLCloudConfig', 'YLConfig', 'YLConfigLangs', 'YLConstellation',
      #     'YLCore', 'YLDNS', 'YLDokit', 'YLEvent', 'YLGame', 'YLGoldenEye', 'YLHyperosloCache',
      #     'YLKaKaJSON', 'YLLaunchView', 'YLLeaksFinder', 'YLLive', 'YLLog', 'YLLogUploader',
      #     'YLLogin', 'YLMixLog', 'YLMixPlayer', 'YLNetHook', 'YLNetwork', 'YLPageView',
      #     'YLPayment', 'YLPerformanceReport', 'YLProtect', 'YLPullPush', 'YLRaynet',
      #     'YLReport', 'YLResource', 'YLRouter', 'YLSVGAPlayer', 'YLSecurity', 'YLStatistic',
      #     'YLStoreKit', 'YLSwan', 'YLTiercel', 'YLTouchRipple', 'YLUI', 'YLUpgrade',
      #     'YLVIMediaCache', 'YLWeb', 'YLWebSocket', 'YLWorkQueue'
      #   ]
      # end

      def flat_pods
          [
            'YLLeaksFinder'
          ]
      end

      private

      def start(specs)
        specs.each_with_index do |spec, index|
          target_dir, work_dir = create_working_directory(spec)
          next if target_dir.nil?

          puts "=======================Start========================="
          puts "开始制作第#{index + 1}个framework:#{spec}, swift version:#{spec.swift_version}"
          Dir.chdir(work_dir)

          build_package(spec)
          `mv "#{work_dir}" "#{target_dir}"`
          Dir.chdir(@source_dir)
        end
      end



      def find_all_specs
        sources = Pod::Config.instance.podfile.sources
        specs = []
        lockfile = Pod::Config.instance.lockfile
        lockfile.pod_names.each do |pod_name|
          pod_version = lockfile.version(pod_name)
          # puts "found spec: #{pod_name} (#{pod_version})"
          spec = find_spec_in_sources(sources, pod_name, pod_version)
          specs << spec if spec
        end
        specs
      end

      def find_spec_in_sources(sources, pod_name, pod_version)
        sources.each do |source_url|
          source = Pod::Config.instance.sources_manager.source_with_name_or_url(source_url)
          begin
            # 尝试从每个 source 中找到对应的 podspec
            spec = source.specification(pod_name, pod_version.to_s)
            return spec
          rescue StandardError => e
            next
          end
        end
        nil  # 如果没有源提供，也可以返回 nil
      end


      # 构建静态沙盒并安装 Pod
      def build_in_sandbox(spec, spec_sources, platform)
        temp_dir = Dir.mktmpdir
        config.installation_root = Pathname.new(temp_dir)
        config.sandbox_root = 'Pods'
        static_sandbox = make_sandbox()
        static_installer = install_pod(spec, spec_sources,platform.name, static_sandbox)
        begin
          frameworks = perform_build(spec, platform, static_sandbox, static_installer)
          return frameworks
        ensure
          clean_up_sandbox
        end
      end

      # 清理临时文件夹
      def clean_up_sandbox
        # Pathname.new(config.sandbox_root).rmtree
        # FileUtils.rm_f('Podfile.lock')
        # puts "已移除 Pods 和 Podfile.lock"
      end

      # 打包框架并生成新 podspec
      def build_package(spec)

        # builder = SpecBuilder.new(spec, @source, @embedded, false)
        # newspec = builder.spec_metadata

        spec.available_platforms.each do |platform|
          next unless platform.name.to_s == 'ios'
          puts "framework 平台: #{platform.name}"

          frameworks = build_in_sandbox(spec, @spec_sources,platform)
          sim_framework = frameworks[0]
          framework = nil
          framework_library_file = "./#{sim_framework}/#{spec.name}"

          if !File.exist?(framework_library_file)
            @failed_count += 1
            puts  "framework 生成失败: #{spec.name}，失败总数量: #{@failed_count}"
            next
          end

          @succeed_count += 1

          puts  "framework 生成成功: #{spec.name}，成功总数量: #{@succeed_count}"

          # newspec += builder.spec_platform(platform)
          tmp_framework = Dir.exist?(sim_framework) ? sim_framework : framework
          unless tmp_framework.nil?
            # 生成并压缩框架文件
            zip_framework(tmp_framework)
            generate_framework_podspec(spec, @source_dir, tmp_framework, platform)
          end
        end

      end

      def generate_framework_podspec(source_podspec, stage_dir, framework_path, platform)
        name = source_podspec.name

        begin
          # 初始化 SpecGenerator
          puts "SpecGenerator 初始化 podspec: #{source_podspec}, artifact_repo_url: #{@artifact_repo_url}, framework_path: #{framework_path}"
          spec_generator = Pod::SpecBuilder.new(source_podspec, @artifact_repo_url, framework_path, platform)
          puts "SpecGenerator 初始化成功"

          # 生成 spec
          spec = spec_generator.generate

          # 根据配置保存为 JSON 或 Ruby 文件
          if @use_json
            binary_spec_path = File.join(stage_dir, name + '.podspec.json')
            File.open(binary_spec_path, 'w') { |file| file.write(spec.to_pretty_json) }
          else
            binary_spec_path = File.join(stage_dir, name + '.podspec')
            File.open(binary_spec_path, 'w') { |file| file.write(spec_generator.generate_ruby_string) }
          end

          # 设置文件路径
          spec.instance_variable_set(:@defined_in_file, Pathname.new(binary_spec_path))

          puts "Podspec 生成成功: #{binary_spec_path}"
          spec

        rescue => e
          # 捕获异常并记录错误信息
          STDERR.puts "生成 Framework Podspec 失败: #{e.message}"
          STDERR.puts e.backtrace.join("\n")

          # 根据需求，选择是返回 nil，重新抛出异常，还是其他处理方式
          nil
        end
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

      def target_directory(name, version)
        "#{@source_dir}/#{name}-#{version}"
      end

      # 创建目标目录
      def create_target_directory(spec)
        target_dir = target_directory(spec.name, spec.version.to_s)
        if File.exist? target_dir
          Pathname.new(target_dir).rmtree
        end
        target_dir
      end

      # 创建临时工作目录
      def create_working_directory(spec)
        target_dir = create_target_directory(spec)
        return if target_dir.nil?

        work_dir = Dir.tmpdir + '/cocoapods-' + Array.new(8) { rand(36).to_s(36) }.join
        Pathname.new(work_dir).mkdir
        [target_dir, work_dir]
      end

      # 执行构建操作
      def perform_build(spec,platform, static_sandbox, static_installer)
        static_sandbox_root = config.sandbox_root.to_s
        builder = Pod::Builder.new(
          platform,
          static_installer,
          @source_dir,
          static_sandbox_root,
          nil,
          static_sandbox.public_headers.root,
          spec,
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
