module Pod
  class SpecBuilder
    def initialize(spec, source, embedded, dynamic)
      @spec = spec
      @source = source.nil? ? '{ :path => \'.\' }' : source
      @embedded = embedded
      @dynamic = dynamic
    end

    def framework_name
      @spec.name + '.framework'
    end

    def spec_resources(platform, framework_path)
      resource_names = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
        consumer = spec.consumer(platform)
        consumer.resources.map do |r|
          File.basename(r)
        end
      end
      puts "所有资源名字: #{resource_names}"
      # 用来存放匹配的相对路径
      matched_files = []
      resource_names.each do |pattern|
        # 使用 Dir.glob 查找匹配的文件
        puts "搜索目录: #{framework_path}"
        Dir.glob(File.join(framework_path, pattern)) do |file|
          # 计算文件的相对路径
          puts "spec 指定的resource: #{file}"
          relative_path = Pathname.new(file).relative_path_from(Pathname.new(framework_path)).to_s
          matched_files << relative_path
        end
      end
      ret = "  s.resources = [#{matched_files.map { |item| "'#{item}'" }.join(', ')}]\n"
      ret
    end

    def spec_platform(platform)
      fwk_base = platform.name.to_s + '/' + framework_name

      spec = <<~RB
      s.#{platform.name}.deployment_target = '#{platform.deployment_target}'
      s.#{platform.name}.vendored_framework = '#{fwk_base}'
  RB

      # 遍历属性，添加相关的配置
      %w(frameworks weak_frameworks libraries requires_arc xcconfig).each do |attribute|
        attributes_hash = @spec.attributes_hash[platform.name.to_s]
        next if attributes_hash.nil?
        value = attributes_hash[attribute]
        next if value.nil?
        value = "'#{value}'" if value.class == String
        spec += "  s.#{platform.name}.#{attribute} = #{value}\n"
      end

      spec
    end


    def spec_metadata
      spec = spec_header
      spec
    end

    def spec_close
      "end\n"
    end

    private

    def spec_header
      spec = "Pod::Spec.new do |s|\n"

      %w(name version summary license authors homepage description social_media_url
         docset_url documentation_url screenshots frameworks weak_frameworks libraries requires_arc
         deployment_target xcconfig).each do |attribute|
        value = @spec.attributes_hash[attribute]
        next if value.nil?
        value = value.dump if value.class == String
        spec += "  s.#{attribute} = #{value}\n"
      end

      spec + "  s.source = #{@source}\n\n"
    end
  end
end
