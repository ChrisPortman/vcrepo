require 'fileutils'

module Vcrepo
  class Repository::Yum < Vcrepo::Repository
    attr_reader :name, :source, :dir

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
      @logger   = create_log

      @dir      = check_dir
      @git_repo = Vcrepo::Git.new(@dir, @name)
      repo_dir
    end

    def sync_source
      case
        when source =~ /^http/
          http_sync()
        when source =~ /^rhns/
          rhns_sync()
        when source =~ /^local/
          local_sync()
        else
          raise RepoError, "Unrecognised source type: #{source}"
      end
    end

    def rhns_sync
      system('which rhnget > /dev/null 2>&1') or
        raise RepoError, "Program, 'rhnget' is not available in the path"

      gen_systemid()

      rhnuser = Vcrepo.config['rhn_username'] or raise RepoError, "No RHN username ('rhn_username') configured"
      rhnpass = Vcrepo.config['rhn_password'] or raise RepoError, "No RHN password ('rhn_password') configured"

      sync_cmd = "rhnget --username=#{rhnuser} --password=#{rhnpass} --systemid=#{ File.join(@git_repo.workdir, 'systemid') } -v #{ @source } #{ repo_dir }/"
      IO.popen(sync_cmd).each do |line|
        @logger.info( line.chomp )
      end
    end

    def generate_repo
      %x{createrepo -C --database --update #{repo_dir}}
    end

    def gen_systemid
      unless File.file?(File.join(@git_repo.workdir, 'systemid'))
        system('which gensystemid > /dev/null 2>&1') or
          raise RepoError, "Program, 'gensystemid' is not available in the path"

        rhnuser = Vcrepo.config['rhn_username']
        rhnpass = Vcrepo.config['rhn_password']
        system( "/usr/bin/gensystemid -u #{rhnuser} -p #{rhnpass} --release=#{@version}Server --arch=#{@arch} #{@git_repo.workdir}/" )
      end
    end
  end
end
