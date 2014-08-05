module Vcrepo
  class Commands::Repo_list
    def self.run(*args)
      uri = "/api/repository"
      Vcrepo.callapi(uri).collect do |r|
        r['id']
      end
    end
    
    def self.help
      <<-END.gsub(/^\s*/,'')
        Usage:
        vcrepo.rb repo_list
      END
    end
  end
end
