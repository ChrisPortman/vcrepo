require 'fileutils'

module Vcrepo
  class Repository::Yum < Vcrepo::Repository
    attr_reader :name, :source, :type, :dir, :enabled, :git_repo, :logger

    def self.package_patterns
      [
        "*.rpm",
        "*.src.*",
        "*.srpm",
      ]
    end

    def self.http_sync_include
      [
        "*.rpm",
      ]
    end

    def self.http_sync_exclude
      [
        "/headers/",
        "/repodata/",
        "/SRPMS/",
        "*.src.rpm",
      ]
    end

    def initialize(name, source)
      @name     = name
      @source   = source
      @type     = 'yum'
      @logger   = create_log
      @enabled  = false

      if @dir = check_dir
        @git_repo = Vcrepo::Git.new(@dir, @name)
        repo_dir
        @enabled = true
      end
    end

    def sync_source
      case
        when source =~ /^http/
          http_sync()
        when source =~ /^yum/
          yum_sync()
        when source =~ /^redhat_yum/
          redhat_yum_sync()
        when source =~ /^local/
          local_sync()
        else
          raise RepoError, "Unrecognised source type: #{source}"
      end
      generate_repo
    end

    def redhat_yum_sync
      client_cert = Vcrepo.config['redhat_client_cert'] or
        raise RepoError, "Syncing Redhat repos requires 'redhat_client_cert' config value"
      client_key  = Vcrepo.config['redhat_client_key'] or
        raise RepoError, "Syncing Redhat repos requires 'redhat_client_key' config value"
      ca_cert     = Vcrepo.config['redhat_ca_cert'] or
        raise RepoError, "Syncing Redhat repos requires 'redhat_ca_cert' config value"

      yum_var_path  = '/etc/yum/vars/'
      yum_var_files = {
        'sslclientcert' => client_cert,
        'sslclientkey'  => client_key,
        'sslcacert'     => ca_cert,
      }

      yum_var_files.each do |key, val|
        var_file = File.join(yum_var_path, key)
        if File.file?( var_file )
          File.readable?(var_file) or raise RepoError, "Cannot read #{var_file} to validate yum config"
          content = File.open(var_file) { |io| io.read }.chomp
          unless content == val
            File.open(var_file, "w") { |io| io.write(val) }
          end
        else
          if File.exists?( var_file )
            raise RepoError, "Cannot set yum variable #{key}.  #{var_file} exists but is not a file."
          end

          begin
            File.open(var_file, "w") { |io| io.write(val) }
          rescue Exception => e
            raise RepoError, "Cannot set yum variable #{key}.  Could not open #{var_file} for write: #{e.message}"
          end
        end
      end

      yum_sync
    end

    def yum_sync
      system('which reposync > /dev/null 2>&1') or
        raise RepoError, "Program, 'reposync' is not available in the path"

      yum_repo = @source.split('://').last

      sync_cmd = "reposync -r #{yum_repo} -p #{repo_dir}"
      IO.popen(sync_cmd).each do |line|
        logger.info( line.split("\n").first.chomp )
      end
    end

    def generate_repo
      %x{createrepo -C --database --update #{repo_dir}}
    end
  end
end
