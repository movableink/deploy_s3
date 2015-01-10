require 'fog'

module DeployS3
  class Main
    def initialize(options)
      config_path = options[:config_file] || "./.deploy"
      @config = YAML::load_file(config_path)

      raise "Missing s3: option in .deploy file" unless @config['s3']

      @path = @config['s3'].split("/")
      @bucket = @path.shift
      @options = options
    end

    def environment
      @options[:environment]
    end

    def save_sha
      directory = connection.directories.get(@bucket)
      file = directory.files.create(:key => key,
                                    :body => local_sha)
      @_remote_sha = nil
    end

    def run!
      if @config['before_hook']
        `#{@config['before_hook']}`
      end

      save_sha

      if @config['after_hook']
        `#{@config['after_hook']}`
      end
    end

    def connection
      @_connection ||= Fog::Storage.new(:provider => 'AWS')
    end

    def remote_sha
      return @_remote_sha if @_remote_sha

      directory = connection.directories.get(@bucket)
      file = directory.files.get(key)
      @_remote_sha = file.body if file
    end

    def filename
      [environment, 'sha'].join('.')
    end

    def key
      [@path, filename].join("/")
    end

    def up_to_date
      local_sha == remote_sha
    end

    def local_sha
      rev = @options[:rev] || @config[:branch] || 'head'
      `git rev-parse --verify --short #{rev}`.chomp
    end

    def diff
      `git log --pretty=format:'    %h %<(20)%an %ar\t   %s' -10 #{remote_sha}..#{local_sha}`
    end

    def reverse_diff
      `git log --pretty=format:'    %h %<(20)%an %ar\t   %s' -10 #{local_sha}..#{remote_sha}`
    end

    def older_local_sha
      return false unless remote_sha
      `git merge-base --is-ancestor #{local_sha} #{remote_sha}` && $?.exitstatus == 0
    end

    def commit_count
      diff.split("\n").size
    end
  end

  class Remote
    def self.comparison(from, to)
      origin_url = `git config --get remote.origin.url`.chomp

      github_url = self.github_from_url origin_url
      "#{github_url}/compare/#{from}...#{to}" if github_url
    end

    def self.github_from_url(url)
      if url =~ /git@github.com:(.*?).git/
        "https://github.com/#{$1}"
      elsif url =~ /(.*?):\/\/github.com\/(.*?).git/
        "https://github.com/#{$1}"
      end
    end
  end
end
