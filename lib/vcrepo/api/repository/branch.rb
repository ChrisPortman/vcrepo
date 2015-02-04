module Vcrepo
  class Api::Repository::Branch

    def self.valid?(*args)
      args     = args.first
      reponame = args.shift
      if repo = Vcrepo::Repository.load(reponame)
        repo.git_repo ? true : false
      else
        false
      end
    end

    def self.actions(*args)
      [ :delete ]
    end

    #Getters for collection and individuals.
    def self.collect(reponame)
      if repo = Vcrepo::Repository.load(reponame)
        repo = repo.git_repo.repo
        if branches = repo.branches
          branches.collect { |b| b.name }
        else
          []
        end
      else
        [ 404, "No such repo #{reponame}" ]
      end
    end

    def self.find(*args)
      args     = args.first
      reponame = args.shift
      id       = args.shift

      if id
        if repo = Vcrepo::Repository.load(reponame)
          repo = repo.git_repo.repo

          if branch = repo.branches[id]
            {
              :id      => branch.name,
              :target  => branch.target.oid,
            }
          else
            [ 404, "Branch #{id} not found." ]
          end
        else
          [ 404, "The repo #{reponame} is not valid" ]
        end
      else
        collect(reponame)
      end
    end

    #Actions
    def self.delete(*args)
      [ 404, "Action not yet implemented" ]
    end
  end
end
