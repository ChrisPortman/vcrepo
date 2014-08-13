module Vcrepo
  class Api::Repository
    def self.sub_collections(*args)
      args = args.first
      if repo = args.shift
        if repo = Vcrepo::Repository.find(repo) and repo.git_repo
          return [ :commit, :tag, :branch ]
        end
      end
      []
    end

    def self.actions(*args)
      [ :sync ]
    end
    
    def self.collect(*args)
      Vcrepo::Repository.all.keys
    end
    
    def self.find(*args)
      args = args.first
      repo = args.shift
      
      if repo
        if repo = Vcrepo::Repository.find(repo)
          {
            :id        => repo.name,
            :name      => repo.name,
            :source    => repo.source,
            :type      => repo.type,
            :dir       => repo.dir,
            :enabled   => repo.enabled,
          }
        else
          [ 404, "Repoistory #{repo} not found" ]
        end
      else
        collect
      end
    end
    
    def self.sync(*args)
      args     = args.first
      reponame = args.shift
      
      if reponame
        if repo = Vcrepo::Repository.find(reponame)
          repo.sync
        else
          [ 404, "Repoistory #{reponame} not found" ]
        end
      else
        [500, "Name of repo not supplied. This should not happen" ]
      end
    end
  end
end

require_relative 'repository/commit'
require_relative 'repository/branch'
require_relative 'repository/tag'
    
