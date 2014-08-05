module Vcrepo
  class Commands::Repo_sync
    def self.run(*args)
      args = args.first
      repo = args.shift
      
      unless repo
        return help
      end

      uri = "/api/repository/#{repo}/sync"
      Vcrepo.callapi(uri)
    end
    
    def self.help
      <<-END.gsub(/^\s*/,'')
        Usage:
        vcrepo.rb repo_sync <reponame>
      END
    end
  end
end
