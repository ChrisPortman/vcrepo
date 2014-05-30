require 'fileutils'

class Repositories::Repo::Apt < Repositories::Repo
  attr_reader :os, :name, :version, :arch, :source, :dir
  
  def self.annex_include
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
    
    register()
    git_init()
  end
  
end
