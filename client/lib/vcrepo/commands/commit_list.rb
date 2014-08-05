module Vcrepo
  class Commands::Commit_list
    def self.run(*args)
      args   = args.first
      repo   = args.shift
      branch = args.shift
      
      unless repo
        return help
      end

      uri = "/api/repository/#{repo}/commit"
      if branch
        uri = uri + "?branch=#{branch}"
      end
      
      Vcrepo.callapi(uri).collect do |c|
        id  = c['id']
        uri = "/api/repository/#{repo}/commit/#{id}"
        commit = Vcrepo.callapi(uri).first
        commit.delete('actions')
        commit.delete('author')
        commit.delete('committer')
        commit
      end
    end
    
    def self.help
      <<-END.gsub(/^\s*/,'')
        Usage:
        vcrepo.rb commit_list <reponame> [<branch>]
        
        Branch defaults to 'master'
      END
    end
  end
end
