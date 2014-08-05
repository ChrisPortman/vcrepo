module Vcrepo
  class Commands::Commit_tag
    def self.run(*args)
      args   = args.first
      repo   = args.shift
      commit = args.shift
      tag    = args.shift
      
      unless repo and commit and tag
        return help
      end

      uri = "/api/repository/#{repo}/commit/#{commit}/tag?tag_name=#{tag}"

      Vcrepo.callapi(uri)
    end
    
    def self.help
      <<-END.gsub(/^\s*/,'')
        Usage:
        vcrepo.rb commit_tag <reponame> <commit_id> <tag_name>
      END
    end
  end
end
