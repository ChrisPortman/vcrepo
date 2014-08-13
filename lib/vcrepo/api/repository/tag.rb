module Vcrepo
  class Api::Repository::Tag

    def self.valid?(*args)
      args     = args.first
      reponame = args.shift
      if repo = Vcrepo::Repository.find(reponame)
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
      if repo = Vcrepo::Repository.find(reponame)
        if repo = repo.git_repo.repo
          if tags = repo.tags
            tags.collect { |t| t.name }
          else
            []
          end
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
        if repo = Vcrepo::Repository.find(reponame)
          repo = repo.git_repo
          if tag = repo.lookup_tag(id)
            ret = {
              :id      => tag.name,
              :target  => tag.target.oid,
            }
            ret[:annotation] = tag.annotation.to_hash if tag.annotated?
            ret
          else
            [ 404, "Tag #{id} not found." ]
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
      args = args.first
      repo = args.shift
      id   = args.shift

      if repo = Vcrepo::Repository.find(repo)
        repo = repo.git_repo.repo
        if repo.tags[id]
          repo.tags.delete(id)
          if repo.tags[id]
            [ 400, "Failed to tag #{id}" ]
          end
            [ 200, "Tag #{id} deleted" ]
        else
          [ 404, "Tag #{id} does not exist" ]
        end
      else
        [ 400, "The repo #{reponame} is not valid" ]
      end
    end
  end
end
