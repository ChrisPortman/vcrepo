require 'fileutils'

module Repositories
  class Repo::Yum < Repositories::Repo
    attr_reader :os, :name, :version, :arch, :source, :dir, :full_id
    
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
      @name     = name   or raise RuntimeError, "Repo must have a name"
      @source   = source or raise RuntimeError, "Repo must have a source"
      @type     = 'yum'
      @logger   = Logger.new(File.join(Repositories.config['logdir'] || './logs', @name))

      @dir      = check_dir
      @git_repo = check_git_repo
      @repo_dir = check_repo_dir
    end
    
    def sync
      if locked?
        return [ 402, "Sync is already in progress" ]
      end
      
      checkout('master')      
      
      @logger.info('Starting Sync')
      case
        when source =~ /^http/
          http_sync()
        when source =~ /^rhns/
          rhns_sync()
        when source =~ /^local/
          local_sync()
        else
          return [402, "No sync method for source: #{source}"]
      end
    end
    
    def rhns_sync
      system('which rhnget > /dev/null 2>&1') or
        raise RepoError, "Program, 'rhnget' is not available in the path"

      pid = fork do 
        lock
        gen_systemid()
        
        rhnuser = Repositories.config['rhn_username'] or raise RepoError, "No RHN username ('rhn_username') configured"
        rhnpass = Repositories.config['rhn_password'] or raise RepoError, "No RHN password ('rhn_password') configured"

        sync_cmd = "rhnget --username=#{rhnuser} --password=#{rhnpass} --systemid=#{ File.join(@dir, 'systemid') } -v #{ @source } #{ @repo_dir }/"
        IO.popen(sync_cmd).each do |line|
          @logger.info( line.chomp )
        end

        generate_repo
        git_commit()
        @logger.info('Sync complete')
        unlock
      end
      Process.detach(pid)
      [ 200, "Sync of #{@full_id} has been started." ]
    end
    
    def generate_repo
      %x{createrepo -C --database --update #{@repo_dir}}
    end    
    
    def gen_systemid
      unless File.file?(File.join(@dir, 'systemid'))
        system('which gensystemid > /dev/null 2>&1') or
          raise RepoError, "Program, 'gensystemid' is not available in the path"
          
        rhnuser = Repositories.config['rhn_username']
        rhnpass = Repositories.config['rhn_password']
        system( "/usr/bin/gensystemid -u #{rhnuser} -p #{rhnpass} --release=#{@version}Server --arch=#{@arch} #{@dir}/" )
      end
    end
  end
end
