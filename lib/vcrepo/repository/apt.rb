require 'uri'

module Vcrepo
  class Repository::Apt < Vcrepo::Repository

    def self.package_patterns
    [
      "*.deb",
      "*.sdeb",
    ]
    end

    def self.http_sync_include
      [
        "*.deb",
      ]
    end

    def self.http_sync_exclude
      []
    end

    def sync_deb
      if match = source.match(/^deb ([^\s]+) ([^\s]+) (.+)$/)
        repo_root = URI(match[1])

        #symlink the silly dir structure that apt-mirror uses to something sane
        download_dir = File.join(git_repo.workdir, 'packages', repo_root.host, repo_root.path).sub(/\/$/,'')
        dest_dir     = File.join(git_repo.workdir, 'packages')

        FileUtils.mkdir_p(download_dir)        #Create the tree
        FileUtils.rm_rf(download_dir)          #Lop the tip of the tree
        FileUtils.ln_s(dest_dir, download_dir, :force => true) #Link the tip back to our root
        
        conf_file = File.join(git_repo.workdir, 'apt-mirror.conf')

        File.open(conf_file, 'w') do |f|
          f.write(apt_mirror_config)
        end

        sync_cmd = "perl #{Vcrepo.config.root_dir}/support/apt-mirror/apt-mirror #{conf_file}"

        IO.popen(sync_cmd).each do |line|
          line.chomp!
          logger.info( line ) unless line.empty?
        end
        
        FileUtils.rm_rf(File.join(git_repo.workdir, 'packages', repo_root.host))
      end
    end

    def apt_mirror_config
      archs = ['i386', 'amd64' ]
      <<-END.gsub(/^\s{8}/, '')
        set base_path      #{git_repo.workdir}
        set mirror_path    $base_path/packages
        set skel_path      $base_path/skel
        set var_path       $base_path/var
        set clean_script   $var_path/clean.sh
        set run_postmirror 0
        
        #{archs.collect { |a| source.sub(/^deb\s/, "deb-#{a} ")}.join("\n")}
      END
    end

    def generate_repo
      #Dont run any generation process for repos synced from apt sources.
      unless source =~ /^deb\s/
        system('which dpkg-scanpackages > /dev/null 2>&1') or
          raise RepoError, "Program, 'dpkg-scanpackages' is not available in the path"
        %x{dpkg-scanpackages #{package_dir} /dev/null | gzip -9c > #{package_dir}/Packages.gz}
      end
    end
  end
end
