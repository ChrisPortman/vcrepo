require 'fileutils'

module Repositories
  class Repo::Yum < Repositories::Repo
    attr_reader :os, :name, :version, :arch, :source, :dir, :full_id
    
    def self.annex_include
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
    
    def initialize(os, name, version, arch, source)
      os      or raise RuntimeError, "Repo must have an OS"
      name    or raise RuntimeError, "Repo must have a name"
      version or raise RuntimeError, "Repo must have a version"
      arch    or raise RuntimeError, "Repo must have an arch"
      source  or raise RuntimeError, "Repo must have a source"
      
      @os       = os
      @name     = name
      @version  = version
      @arch     = arch
      @source   = source
      @dir      = check_dir
      @repo_dir = check_repo_dir
      
      @full_id  = "#{@os}-#{version}-#{arch}-#{name}"
      
      register()
      git_init()
    end
    
    def check_dir
      base = Repositories.config['repo_base_location']
      dir  = File.join(base, @os, @version, @arch, @name)
      File.directory?(dir) || FileUtils.mkdir_p(dir)
      dir
    end
    
    def check_repo_dir
      dir = File.join(@dir, 'repo')
      File.directory?(dir) || FileUtils.mkdir_p(dir)
      dir
    end
  
    def sync
      Repositories.log('Starting Sync', self.full_id)
      case
        when source =~ /^http/
          http_sync()
        when source =~ /^rhns/
          rhns_sync()
        when source =~ /^file/
          local_sync()
      end
    end
    
    def rhns_sync
      fork do 
        log_file = File.join(Repositories.config['logdir'], "#{os}-#{version}-#{name}-#{arch}.log")
        gen_systemid()
        git_cmd('checkout master')
        rhnuser = Repositories.config['rhn_username']
        rhnpass = Repositories.config['rhn_password']
        %x{rhnget --username=#{rhnuser} --password=#{ rhnpass} --systemid=#{ File.join(@dir, 'systemid') } -v #{ @source } #{ @repo_dir }/ >> #{log_file}}
        generate_repo
        git_commit()
      end
    end
    
    def generate_repo
      %x{createrepo --database --update #{@repo_dir}}
    end    
    
    def gen_systemid
      unless File.file?(File.join(@dir, 'systemid'))
        rhnuser = Repositories.config['rhn_username']
        rhnpass = Repositories.config['rhn_password']
        %x{/usr/bin/gensystemid -u #{rhnuser} -p #{rhnpass} --release=#{@version}Server --arch=#{@arch} #{@dir}/}
      end
    end
  end
end
