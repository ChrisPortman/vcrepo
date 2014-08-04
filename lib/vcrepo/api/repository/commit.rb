module Vcrepo
  class Api::Repository::Commit

    def self.actions
      [ :tag ]
    end

    #Getters for collection and individuals.
    def self.collect(reponame)
      if repo = Vcrepo::Repository.find(reponame)
        repo = repo.git_repo
        if commits = repo.branch_commits('master')
          commits.collect { |c| c.oid }
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
          if commit = repo.lookup_commit(id)
            {
              :id        => commit.oid,
              :author    => commit.author,
              :committer => commit.committer,
              :message   => commit.message,
              :time      => commit.time,
            }
          else
            [ 404, "Commit #{id} not found." ]
          end
        else
          [ 404, "The repo #{reponame} is not valid" ]
        end
      else
        collect(reponame)
      end
    end

    #Actions
    def self.tag(*args)
      args   = args.first
      repo   = args.shift
      id     = args.shift
      params = args.shift
      
      if params[:tag_name]
        if repo = Vcrepo::Repository.find(repo)
          repo = repo.git_repo.repo
          tag_name  = params[:tag_name]
          
          if repo.tags[tag_name]
            [400, "Tag #{tag_name} already exists"]
          else    
            #Optional for annotation
            tagger    = params[:tagger]  || nil
            message   = params[:message] || nil 
      
            commit = repo.lookup(id)
            if commit and commit.type == :commit
              if tagger and message
                repo.tags.create(tag_name, id, {
                  :tagger  => { :name => tagger, :email => "#{tagger}@vcreopo.local", :time => Time.now },
                  :message => message,
                })
              else
                repo.tags.create(tag_name, id)
              end
      
              if repo.tags[tag_name]
                [ 200, "Commit #{id} tagged as #{tag_name}" ]
              else
                [ 400, "Failed to tag commit #{id} with #{tag_name}" ]
              end
            else
              [ 404, "#{id} is not a valid commit ID" ]
            end
          end
        else
          [ 404, "The repo #{reponame} is not valid" ]
        end
      else
        [ 400, "Must supply tag_name" ]
      end
    end
  end
end
