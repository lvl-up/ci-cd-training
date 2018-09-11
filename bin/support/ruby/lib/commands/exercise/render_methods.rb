require 'digest'
require 'tmpdir'
require_relative 'instructions'
module Exercise
  module RenderMethods
    class EnvironmentVariableMissingError < StandardError
      def initialize(variable_name)
        super "Environment variable not set for: #{variable_name}"
      end
    end

    include Commandline::Output
    include Instructions

    def digest(path:, digest_component:, excludes: [])
      excludes = paths(*excludes)

      files = files(path).sort.reject do |f|
        excludes.include?(f) || ignored?(path, f)
      end

      content = files.map {|f| File.read(f)}.join
      Digest::MD5.hexdigest(content << digest_component).to_s
    end

    def env(variable_name)
      ENV[variable_name.to_s] || raise(EnvironmentVariableMissingError.new(variable_name))
    end

    def excluded_files(template)
      all_files_templates = files(templates_directory(template))
      rendered_files = all_files_templates.collect {|t| rendered_file_name(t)}.find_all {|f| File.exist?(f)}
      all_files_templates.reject{|file| file == template}.concat(rendered_files)
    end

    def paths *paths
      paths.find_all {|excluded_file| File.exist?(excluded_file)}.collect{|path|full_path(path)}
    end

    def render_exercise(template, digest_component: '')
      say "Rendering: #{template}"
      template = full_path(template)
      current_dir = Dir.pwd

      result = anonymise(render(template))
      rendered_file_name = rendered_file_name(template)


      parent_dir = full_path("#{templates_directory(template)}/..")
      result << "  \n\nRevision: #{digest(path: parent_dir,
                                          digest_component: digest_component.to_s,
                                          excludes: excluded_files(template))}"

      File.write(rendered_file_name, result)

      say ok "Finished: #{template}"
      true
    rescue StandardError => e
      say error "Failed to generate file from: #{template}"
      say "#{e.message}\n#{e.backtrace}"
      false
    ensure
      Dir.chdir(current_dir)
    end


    def render_file_path template
      template.gsub(%r{.templates/.*?erb}, File.basename(template)).gsub('.erb', '')
    end

    def substitute(hash)
      @substitutes = hash
    end

    def templates_directory(template)
      full_path(File.dirname(template))
    end

    private

    def anonymise(string)
      substitutes.each do |key, value|
        string = string.gsub(key, value)
      end
      string.gsub(/cic_container-[\w\d-]+/, 'cic_container-xxxxxxxxxxxxxxxx')
    end

    def files(path)
      files = paths(*Dir.glob("#{path}/**/*", ::File::FNM_DOTMATCH))
      files.find_all{|f| !File.directory?(f)}
    end

    def full_path path
      File.expand_path(path)
    end

    def git_ignore_content(path)
      git_ignore_file = "#{path}/.gitignore"
      File.exist?(git_ignore_file) ? File.read(git_ignore_file) : ''
    end

    def ignored? path, file
      ignored_files(path).find{|ignore| file.include?(ignore)}
    end

    def ignored_files(path)
      files = git_ignore_content(path).lines.collect {|line| sanitise(line)}
      files << '.git'
    end

    def render(template)
      template_content = File.read(File.expand_path(template))

      erb_template = ERB.new(template_content)
      if /<%#\s*instruction:run_in_temp_directory\s*%>/.match?(template_content)
        return anonymise(render_in_temp_dir(erb_template))
      end
      anonymise(erb_template.result(binding))
    ensure
      after_rendering_commands.each {|command| test_command(command)}
      say '' if quiet?
    end

    def rendered_file_name(template)
      "#{File.expand_path("#{File.dirname(template)}/..")}/#{File.basename(template, '.erb')}"
    end

    def render_in_temp_dir(erb_template)
      output = nil
      Dir.mktmpdir do |path|
        original_dir = Dir.pwd
        Dir.chdir(path)
        output = erb_template.result(binding)
        Dir.chdir(original_dir)
      end
      output
    end

    def sanitise string
      string.chomp.strip
    end

    def substitutes
      @substitutes ||= {}
    end
  end
end
