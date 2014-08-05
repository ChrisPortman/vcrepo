module Vcrepo
  class Commands::Tag_delete
    def self.run(*args)
      args   = args.first
      repo   = args.shift
      tag    = args.shift
      
      unless repo and tag
        return help
      end

      uri = "/api/repository/#{repo}/tag/#{tag}/delete"

      Vcrepo.callapi(uri)
    end
    
    def self.help
      <<-END.gsub(/^\s*/,'')
        Usage:
        vcrepo.rb tag_delete <reponame> <tag_name>
      END
    end
  end
end
