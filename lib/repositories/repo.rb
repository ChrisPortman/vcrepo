require 'git'

module Repositories
  class Repo
    @@metadata     = {}
    @@repositories = {}
    
    def initialize(type, os, name, version, arch, source)
      unless @@repositories["#{os}-#{name}"]
        case type
          when 'yum'
            @@repositories["#{os}-#{version}-#{arch}-#{name}"] = Repositories::Repo::Yum.new(os, name, version, arch, source)
          when 'apt'
            @@repositories["#{os}-#{version}-#{arch}-#{name}"] = Repositories::Repo::Apt.new(os, name, version, arch, source)
          else
        end
      end
    end
  
    def self.all
      @@repositories
    end
    
    def self.repo(name)
      ret = nil
      @@repositories.each do |n,repo|
        if name == n
          ret = repo 
        end
      end
      ret
    end
    
    def self.oslist
      @@metadata.keys
    end
    
    def self.version_list(os)
      @@metadata[os].keys
    end
    
    def self.archs(os, version)
      @@metadata[os][version].keys
    end
  
    def self.repo_names(os, version, arch)
      @@metadata[os][version][arch].keys
    end
    
  
    def self.sync_all
      @repositories.each do |name, repo|
        repo.sync
      end
    end
    
    def register
      @@metadata[@os]                         ||= {}
      @@metadata[@os][@version]               ||= {}
      @@metadata[@os][@version][@arch]        ||= {}
      @@metadata[@os][@version][@arch][@name] ||= {}
    end
    
    def http_sync
      fork do 
        git_cmd('checkout master')
        
        http_sync_includes = self.class.http_sync_include.collect { |inc| "-I #{inc}" }.join(' ')
        http_sync_excludes = self.class.http_sync_exclude.collect { |exc| "-X \"#{exc}\"" }.join(' ')
  
        sync_cmd = "/usr/bin/lftp -c '; mirror -P -c -e -vvv #{http_sync_includes} #{http_sync_excludes} #{@source} #{@repo_dir}'"
        IO.popen(sync_cmd).each do |line|
          Repositories.log( line, self.full_id)
        end
  
        generate_repo
        git_commit()
      end
    end
  
    def files(path='', rev="master")
      files = git_cmd("ls-tree --long #{rev} #{path}").split("\n").collect do |file|
        attrs = file.split(/\s+/)
        {
          :mode => attrs[0],
          :type => attrs[1],
          :hash => attrs[2],
          :size => attrs[3],
          :name => attrs[4],
        }
      end
    end
  
    def git_init
      unless File.directory?(git_dir)
        git_cmd("init")
      end
      
      unless File.directory?( File.join(git_dir, 'annex'))
        git_cmd("annex init")
      end
    end
  
    def git_cmd(cmd, noop=false)
      command = "git --work-tree=#{ git_work_tree } --git-dir=#{ git_dir } #{cmd}"
      Repositories.log("Running Git command: #{command}", self.full_id)
      unless noop
        %x{#{command}}
      end
    end
  
    def git_commit
      unless git_cmd('status --porcelain').empty?
        time = Time.new
        date = "%04d" % time.year + "%02d" % time.month + "%02d" % time.mday
  
        annex_include_string = self.class.annex_include.collect do |expr|
          "-name '#{expr}'"
        end.join(' -or ')
  
        command = "find #{@dir} \\( #{annex_include_string} \\)"
        
        anexed_files = %x{#{command}}.split("\n")
        anexed_files.each do |file|
          git_cmd("annex add --force #{file}")
        end
        
        git_cmd("add --all")
        git_cmd("commit -m #{date}")
      end
    end
  
    def git_work_tree
      @dir
    end
    
    def git_dir
      File.join( git_work_tree, '.git' )
    end
    
    def file?(file, release='master')
      file = git_cmd("ls-tree --long #{release} repo/#{file}").split("\n")
      if file[1]
        false
      else
        if file[0].split(/\s+/)[0] != '120000' and file[0].split(/\s+/)[1] == 'blob'
          true
        else
          false
        end
      end
    end
  
    def link?(file, release='master')
      file = git_cmd("ls-tree --long #{release} repo/#{file}").split("\n")
      if file[1]
        false
      else
        if file[0].split(/\s+/)[0] == '120000' and file[0].split(/\s+/)[1] == 'blob'
          true
        else
          false
        end
      end
    end
    
    def file(file, release='master')
      attrs = git_cmd("ls-tree --long master repo/#{file}").split("\n").first.split(/\s+/)
      mode = attrs[0]
      type = attrs[1]
      
      if type == 'blob'
        git_cmd("show #{release}:repo/#{file}")
      end
    end
    
    def contents(path='', release='master')
      contents = []
      git_cmd("ls-tree --long #{release} repo/#{path}").split("\n").each do |line|
        attrs = line.split(/\s+/)
        contents.push( {
          :mode => attrs[0],
          :type => attrs[1],
          :hash => attrs[2],
          :size => attrs[3],
          :file => attrs[4].sub(/repo\//,''),
        } )
      end
      contents
    end
  end
end

require_relative 'repo/yum'
require_relative 'repo/apt'
