require 'tmpdir'
module Pod
  class Command
    class Package < Command
      self.summary = 'Package a podspec into a static library.'
      self.arguments = [
        CLAide::Argument.new('NAME', true),
        CLAide::Argument.new('SOURCE', false)
      ]

      def self.options
        [
          ['--force',     'Overwrite existing files.'],
          ['--no-mangle', 'Do not mangle symbols of depedendant Pods.'],
          ['--embedded',  'Generate embedded frameworks.'],
          ['--local',     'Use local state rather than published versions.'],
          ['--exclude-deps', 'Exclude symbols from dependencies.'],
          ['--configuration', 'Build the specified configuration (e.g. Debug). Defaults to Release'],
          ['--subspecs', 'Only include the given subspecs'],
          ['--spec-sources=private,https://github.com/CocoaPods/Specs.git', 'The sources to pull dependent ' \
            'pods from (defaults to https://github.com/CocoaPods/Specs.git)']
        ]
      end

      def initialize(argv)
        @embedded = argv.flag?('embedded')
        @local = argv.flag?('local', false)
        @package_type = :static_framework
        @force = argv.flag?('force')
        @mangle = argv.flag?('mangle', true)
        @exclude_deps = argv.flag?('exclude-deps', false)
        @name = argv.shift_argument
        @source = argv.shift_argument
        @spec_sources = argv.option('spec-sources', 'https://github.com/CocoaPods/Specs.git').split(',')

        subspecs = argv.option('subspecs')
        @subspecs = subspecs.split(',') unless subspecs.nil?

        @config = argv.option('configuration', 'Release')

        @source_dir = Dir.pwd
        @is_spec_from_path = false
        @spec = spec_with_path(@name)
        @is_spec_from_path = true if @spec
        @spec ||= spec_with_name(@name)
        super
      end

      def validate!
        super
        help! 'A podspec name or path is required.' unless @spec
        help! 'podspec has binary-only depedencies, mangling not possible.' if @mangle && binary_only?(@spec)
        help! '--local option can only be used when a local `.podspec` path is given.' if @local && !@is_spec_from_path
      end

      def run
        if @spec.nil?
          help! "Unable to find a podspec with path or name `#{@name}`."
          return
        end

        target_dir, work_dir = create_working_directory
        puts  "create target_dir: #{target_dir}, work_dir: #{work_dir}"
        return if target_dir.nil?

        Dir.chdir(work_dir)
        puts "chdir #{work_dir}"

        build_package
        `mv "#{work_dir}" "#{target_dir}"`
        puts "mv work_dir：#{work_dir} to target_dir：#{target_dir}"
        Dir.chdir(@source_dir)
        
        puts "chdir #{@source_dir}"
      end

      private

      def build_in_sandbox(platform)
        # 当前目录设置为安装目录
        config.installation_root = Pathname.new(Dir.pwd)
        config.sandbox_root = 'Pods'
        # 构建静态沙盒
        static_sandbox = build_static_sandbox(false)
        # 安装pods
        static_installer = install_pod(platform.name, static_sandbox)

        begin
          # 执行构建，获取返回的 sim_framework 和 framework
          frameworks = perform_build(platform, static_sandbox, static_installer)
          return frameworks
        ensure # in case the build fails; see Builder#xcodebuild.
          Pathname.new(config.sandbox_root).rmtree
          FileUtils.rm_f('Podfile.lock')
          puts  "移除Pods、Podfile.lock"
        end
      end


      def build_package
        builder = SpecBuilder.new(@spec, @source, @embedded, false)
        newspec = builder.spec_metadata
        @spec.available_platforms.each do |platform|

          framework, sim_framework = build_in_sandbox(platform)

          puts "build finished! sim_framework:#{sim_framework}, framework:#{framework}"

          newspec += builder.spec_platform(platform)

          puts "pwd: #{Dir.pwd}"

          tmp_framework = Dir.exist?(sim_framework) ? sim_framework : framework

          unless tmp_framework.nil?
            resources_spec, resource_bundles_spec = generate_resources_and_bundles(tmp_framework)
            newspec += " s.resources = #{resources_spec}\n"
            newspec += " s.resource_bundles = #{resource_bundles_spec}\n"

            # 生成.zip
            zip_framework(tmp_framework)
          end

        end

        newspec += builder.spec_close
        File.open(@spec.name + '.podspec', 'w') { |file| file.write(newspec) }

      end

      def zip_framework(framework_path)
        parent_path = File.dirname(framework_path)

        framework_name = File.basename(framework_path)

        # 使用系统的 zip 命令来压缩文件夹
        zipfile_name = " #{framework_name}.zip"
        `cd #{parent_path} && zip -r #{zipfile_name} #{framework_name}`
        # 检查命令是否成功执行
        if $?.success?
          puts "Successfully created #{zipfile_name}"
        else
          puts "Failed to create zip file"
        end
      end


      # 生成 s.resources 和 s.resource_bundles
      def generate_resources_and_bundles(framework_path)
        resources = []
        resource_bundles = {}

        # 使用 Pathname 处理路径
        resources_path = Pathname.new(framework_path) + 'Resources'

        puts "resources_path:#{resources_path}"
        # 获取所有资源文件（排除 .bundle 文件）
        Dir.glob("#{resources_path}/*") do |file|
          puts "遍历Resource 资源：#{file}"
          # 如果是 bundle 文件，放入 s.resource_bundles
          if File.extname(file) == '.bundle'
            bundle_name = File.basename(file, '.bundle')
            resource_bundles[bundle_name] ||= []
            resource_bundles[bundle_name] << file
          else
            # 否则是普通资源文件，放入 s.resources
            resources << file
          end
        end

        # 格式化为 podspec 的 resources 和 resource_bundles
        resources_spec = resources.map { |file| "Resources/#{Pathname.new(file).relative_path_from(resources_path)}" }
        resource_bundles_spec = resource_bundles.map do |bundle_name, files|
          "#{bundle_name} => #{files.map { |file| "Resources/#{Pathname.new(file).relative_path_from(resources_path)}" }.join(' ')}"
        end

        return resources_spec, resource_bundles_spec
      end
      def create_target_directory
        target_dir = "#{@source_dir}/#{@spec.name}-#{@spec.version}"
        if File.exist? target_dir
          if @force
            Pathname.new(target_dir).rmtree
          else
            UI.puts "Target directory '#{target_dir}' already exists."
            return nil
          end
        end
        target_dir
      end

      def create_working_directory
        target_dir = create_target_directory
        return if target_dir.nil?
        work_dir = Dir.tmpdir + '/cocoapods-' + Array.new(8) { rand(36).to_s(36) }.join
        Pathname.new(work_dir).mkdir
        [target_dir, work_dir]
      end
      def perform_build(platform, static_sandbox, static_installer)
        # 即Pods 目录
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
          @exclude_deps
        )
        frameworks = builder.build
        frameworks
      end
    end
  end
end
