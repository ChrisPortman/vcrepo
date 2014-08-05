module Vcrepo
  class Commands::Tag_list
    def self.run(*args)
      args   = args.first
      repo   = args.shift

      unless repo
        return help
      end

      uri = "/api/repository/#{repo}/tag"
      
      Vcrepo.callapi(uri).collect do |t|
        id  = t['id']
        uri = "/api/repository/#{repo}/tag/#{id}"
        tag = Vcrepo.callapi(uri).first
        tag.delete('actions')
        tag
      end
    end
    
    def self.help
      <<-END.gsub(/^\s*/,'')
        Usage:
        vcrepo.rb tag_list <reponame>'
      END
    end
  end
end
