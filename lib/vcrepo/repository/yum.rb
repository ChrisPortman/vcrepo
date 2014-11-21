require 'fileutils'
require 'pty'
require 'expect'

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

    def sync_redhat_yum
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

      sync_yum
    end

    def sync_yum
      system('which reposync > /dev/null 2>&1') or
        raise RepoError, "Program, 'reposync' is not available in the path"

      yum_repo = @source.split('://').last

      sync_cmd = "reposync -t #{cache_dir} -r #{yum_repo} -p #{package_dir}"
      create_cachedir

      IO.popen(sync_cmd).each do |line|
        logger.info( line.split("\n").first.chomp )
      end
      
      remove_cachedir
    end

    def generate_repo
      sign_rpms
      system('which createrepo > /dev/null 2>&1') or
        raise RepoError, "Program, 'createrepo' is not available in the path"
      %x{createrepo -C --database --update #{package_dir}}
      sign_repodata
    end

    def check_gpg_key
      keyname = Vcrepo.config['gpg_key_name']
      if `gpg --list-keys #{keyname}`.match(/#{keyname}/)
        keyfile = File.join(package_dir, "RPM-GPG-KEY-#{keyname}")
        unless File.exist?(keyfile)
          logger.info("Putting GPG public key into repository (#{keyfile})")
          system("gpg --export -a VCRepo > #{keyfile}")
        end
        true
      else
        false
      end
    end

    def sign_rpms
      if gpg_name = Vcrepo.config['gpg_key_name'] and check_gpg_key
        logger.info("Signing RPMS...")
        PTY.spawn("rpm -D '%_signature gpg' -D '%_gpg_name #{gpg_name}' --resign #{File.join(package_dir, '*.rpm')}") do |r,w,p|
          begin
            r.expect('Enter pass phrase:', 5) do
              logger.info("Passphrase requested, sending passphrase")
              w.puts (Vcrepo.config['gpg_key_pass'] || "")
            end
            r.each { |line| logger.info(line.chomp) }
          rescue
          end
        end
        logger.info("Signing RPMs complete")
      else
        logger.info("No valid GPG key for signing... Skipping")
      end  
    end

    def sign_repodata
      if gpg_name = Vcrepo.config['gpg_key_name'] and check_gpg_key
        sigfile = File.join(package_dir, 'repodata', 'repomd.xml.asc')
        File.delete(sigfile) if File.exist?(sigfile)
        
        passphrase = Vcrepo.config['gpg_key_pass'] || ""
        logger.info("Signing Repodata...")

        command = "echo #{passphrase} | gpg --detach-sign --armor -u #{gpg_name} --batch --passphrase-fd 0 #{File.join(package_dir, 'repodata', 'repomd.xml')}"
        system(command)
      else
        logger.info("No valid GPG key for signing... Skipping")
      end  
    end
    
    def cache_dir
      File.join(Vcrepo.config['repo_base_dir'], '.yum_caches', name)
    end
    
    def create_cachedir
      remove_cachedir
      FileUtils.mkdir_p(cache_dir)
    end
    
    def remove_cachedir
      if File.exists?(cache_dir)
        FileUtils.rm_rf(cache_dir)
      end
    end
  end
end
