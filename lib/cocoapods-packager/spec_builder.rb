require_relative '../cocoapods_pack'

module Pod
  class SpecBuilder
    ROOT_ATTRIBUTES = %w[name version summary license authors homepage description social_media_url
                       docset_url documentation_url screenshots frameworks libraries requires_arc
                       deployment_target xcconfig pod_target_xcconfig user_target_xcconfig source vendored_frameworks
                       vendored_libraries resource_bundles resources preserve_paths cocoapods_version swift_versions].freeze
    PLATFORM_ATTRIBUTES = %w[frameworks libraries requires_arc xcconfig pod_target_xcconfig user_target_xcconfig].freeze

    attr_reader :podspec_path, :platform, :artifact_repo_url, :framework_path, :resources_path

    def initialize(source_podspec, artifact_repo_url, framework_path, platform)
      @podspec_path = source_podspec
      @artifact_repo_url = artifact_repo_url
      @framework_path = framework_path
      @platform = platform
      @resources_path = Pathname.new(framework_path) + 'Resources'
    end

    def generate_ruby_string
      root_attributes = hash_to_dsl(@podspec_path.attributes_hash.merge('source' => artifact_repo_hash), ROOT_ATTRIBUTES)
      sections = [root_attributes]
      sections << dependency_section
      sections << framework_section
      sections << library_section
      sections << resources_section
      sections << resource_bundles_section
      sections.push(*platform_sections)

      sections_str = sections.reject(&:empty?).map do |section|
        section.map { |lines| lines + "\n" }.join('')
      end.join("\n")
      "#{header}\n#{open}\n#{sections_str}#{close}\n"
    end

    def generate
      Pod::Specification.from_string(generate_ruby_string, "#{@podspec_path.name}.podspec")
    end


    private

    def platform_spec(platform, has_one_platform)
      ordered_keys = %w[platform source_files header_mappings_dir module_map vendored_frameworks vendored_libraries]
      platform_attributes_hash = @podspec_path.attributes_hash[platform.name.to_s] || {}
      platform_vendored_frameworks = Array(platform_attributes_hash['vendored_frameworks'])

      spec_framework = "#{@podspec_path.name}.framework"
      platform_vendored_frameworks << spec_framework unless platform_vendored_frameworks.include?(spec_framework)

      platform_vendored_libraries = Array(platform_attributes_hash['vendored_libraries'])
      hash = platform_spec_hash( platform_vendored_frameworks, platform_vendored_libraries)
      platform_prefix = "#{platform.name}."
      platform_section = []
      unless has_one_platform
        version = platform.deployment_target ? platform.deployment_target.version : nil
        platform_section << spec_line('deployment_target', version, platform_prefix)
      end
      platform_section.push(*hash_to_dsl(hash, ordered_keys, platform_prefix))
      platform_section.push(*hash_to_dsl(platform_attributes_hash, PLATFORM_ATTRIBUTES, platform_prefix)) if platform_attributes_hash
      platform_section
    end

    def platform_spec_hash(vendored_frameworks, vendored_libraries)
      platform_hash = {}
      platform_hash['vendored_frameworks'] ||= []
      platform_hash['vendored_frameworks'] += vendored_frameworks
      platform_hash['vendored_libraries'] = vendored_libraries
      platform_hash
    end

    def platform_sections
      ret = []
      has_one_platform = @platform.nil? ? false : true  # 如果@platform为空，认为没有平台
      if has_one_platform
        platform = @platform  # 直接使用@platform
        ret << [spec_line('platform', platform_spec_line(platform))]
      end
      ret.push(platform_spec(@platform, has_one_platform))
      ret
    end


    require 'set'
    def framework_section()
      frameworks = Set.new(@podspec_path.consumer(@platform).frameworks || [])
      # 遍历 subspecs 并将框架添加到 frameworks 中
      @podspec_path.subspecs.each do |subspec|
        frameworks.merge(subspec.consumer(@platform).frameworks || [])
      end
      # 转换为数组（如果需要返回一个数组而非 Set）并打印框架
      frameworks_array = frameworks.to_a
      # 将数组转换为符合语法的字符串，并返回
      frameworks_str = "  s.frameworks = #{frameworks_array.inspect}"

      # 返回这个字符串
      [frameworks_str]
    end

    def resource_bundles_section()
      resource_bundles = {}
      puts "查找 resource_bundles：#{@resources_path}"
      Dir.glob("#{@resources_path}/*") do |file|
        if File.extname(file) == '.bundle'
          bundle_name = File.basename(file, '.bundle')
          puts "匹配 resource_bundles：#{file}"

          resource_bundles[bundle_name] ||= []
          resource_bundles[bundle_name] << "Resources/#{Pathname.new(file).relative_path_from(@resources_path)}"
        end
      end

      # 格式化输出成 s.resource_bundles = { 'Name' => ['Path'], ... }
      formatted_str = "  s.resource_bundles = {\n"
      formatted_str += resource_bundles.map do |bundle_name, files|
        "  '#{bundle_name}' => #{files.inspect}"  # .inspect 生成 Ruby 数组格式
      end.join(",\n")
      formatted_str += "\n  }"
      [formatted_str]
    end


    def resources_section()
      resources = []
      puts "查找 resources：#{@resources_path}"
      Dir.glob("#{@resources_path}/*") do |file|
        if File.extname(file) != '.bundle'
          puts "匹配 resources：#{file}"
          resources << file
        end
      end
      resources = resources.map { |file| "\"Resources/#{Pathname.new(file).relative_path_from(@resources_path)}\"" }
      # 组装成 "s.resources = [...]" 的格式
      formatted_str = "  s.resources = [#{resources.join(', ')}]"
      [formatted_str]
    end



    def library_section()

      libraries = Set.new(@podspec_path.consumer(@platform).libraries || [])
      # 遍历 subspecs 并将框架添加到 frameworks 中
      @podspec_path.subspecs.each do |subspec|
        libraries.merge(subspec.consumer(@platform).libraries || [])
      end
      # 转换为数组（如果需要返回一个数组而非 Set）并打印框架
      libraries_array = libraries.to_a
      # 将数组转换为符合语法的字符串，并返回
      libraries_str = "  s.libraries = #{libraries_array.inspect}"
      # 返回这个字符串
      [libraries_str]
    end

    def dependency_section
      dependencies = []
      all_dependencies(@platform).each do |dependency|
        puts "dependency: #{dependency.name}"
        dependencies << dependency_line(dependency)
      end
      dependencies
    end

    def all_dependencies(platform = nil)
      # 获取主 podspec 的依赖
      deps = @podspec_path.consumer(platform).dependencies || []
      podspec_name = @podspec_path.name
      all_deps = Set.new(deps)
      # 合并 subspecs 的依赖，并过滤掉依赖名称包含 @podspec_path.name 的依赖
      @podspec_path.subspecs.each do |subspec|
        subspec_deps = subspec.consumer(platform).dependencies || []
        # 过滤掉依赖名称包含 @podspec_path.name 的依赖
        filtered_deps = subspec_deps.reject { |dependency| dependency.name.include?("#{podspec_name}/") }
        # 使用 Set 来自动去重并合并
        all_deps.merge(filtered_deps)
      end
      # 返回去重后的依赖列表
      all_deps.to_a
    end


    def platform_spec_line(platform)
      return [platform.symbolic_name] unless platform.deployment_target

      [platform.symbolic_name, platform.deployment_target.to_s]
    end

    def header
      "# Generated by cocoapods-pack #{Pod::Packager::VERSION} - Do not manually modify."
    end

    def open
      'Pod::Spec.new do |s|'
    end

    def close
      'end'
    end

    def artifact_repo_hash
      { http: "#{artifact_repo_url}/#{@podspec_path.name}/#{@podspec_path.version}/zip", type: "zip"}
    end

    def str(str)
      "'#{str.gsub(/\n/, '\n')}'"
    end

    def hash_to_dsl(hash, ordered_keys, extra_prefix = '')
      ret = []
      ordered_keys.each do |k|
        v = hash[k]
        ret << spec_line(k, v, extra_prefix) unless v.nil? || v == []
      end
      ret
    end

    def spec_line(key, value, extra_prefix = '')
      ['  ', 's.', extra_prefix, key.to_s, ' = ', value_of(value)].join('')
    end


    def dependency_line(dependency)
      name = dependency.name
      # 不支持subspec ，因此去掉/后面的字符串。例如：“YLReport/AppReport” 变成“YLReport”
      name = name.split('/').first
      reqstr = dependency.requirement.as_list.map { |s| value_of(s) }.join(', ')
      ['  ', 's.dependency ', value_of(name), ', ', reqstr].join('')
    end

    def value_of(value)
      return str(quote_quotes(value)) if value.is_a?(String)
      return value.map { |x| value_of(x) }.join(', ') if value.is_a?(Array)

      quote_quotes(value.inspect)
    end

    def quote_quotes(str)
      str.gsub(/'/, "\\\\'")
    end
  end
end
