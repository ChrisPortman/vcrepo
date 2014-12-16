module Vcrepo
  class Api::Repository
    def self.sub_collections(*args)
      args = args.first
      if repo = args.shift
        if repo = Vcrepo::Repository.load(repo) and repo.git_repo
          return [ :commit, :tag, :branch ]
        end
      end
      []
    end

    def self.actions(*args)
      [ :sync, :create ]
    end
    
    def self.collect(*args)
      Vcrepo::Repository.all.collect{ |r| r.name }
    end
    
    def self.find(*args)
      args = args.first
      repo = args.shift
      
      if repo
        if repo = Vcrepo::Repository.load(repo)
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
        if repo = Vcrepo::Repository.load(reponame)
          repo.sync
        else
          [ 404, "Repoistory #{reponame} not found" ]
        end
      else
        [500, "Name of repo not supplied. This should not happen" ]
      end
    end
    
    def self.create(*args)
      args   = args.first
      name   = args.shift
      params = args.shift
      
      source = params[:source] or return [ 404, "repo_create requires source"]
      type   = params[:type]   or return [ 404, "repo_create requires type"]
      
      begin
        if Vcrepo::Repository.load(name)
          return [404, "Repository #{name} already exists"]
        end
      rescue
      end
      
      settings = {
        'type'   => type,
        'source' => source,
      }

      begin
        File::open(Vcrepo::Repository.config_file(name), 'w') { |fh| fh.write( YAML.dump(settings) ) }
      rescue Errno::EACCES
        return [500, "The config file for repo #{name} is not writable"]
      end
      
      [200, "Repository #{name} created"]
    end
  end
end

require_relative 'repository/commit'
require_relative 'repository/branch'
require_relative 'repository/tag'
    
