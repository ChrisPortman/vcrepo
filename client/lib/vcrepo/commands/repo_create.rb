module Vcrepo
  class Commands::Repo_create
    def self.run(*args)
      args    = args.first
      repo    = args.shift

      params = {}
      args.each do |a|
        next unless a =~ /=/
        k,v = a.split('=')
        params[k] = v
      end

      unless repo and params['source'] and params['type']
        return help
      end

      uri = "/api/repository/#{repo}/create?source=#{params['source']}&type=#{params['type']}"
      Vcrepo.callapi(uri)
    end
    
    def self.help
      <<-END.gsub(/^\s*/,'')
        Usage:
        vcrepo.rb repo_create <reponame> type=<type> source=<source>
      END
    end
  end
end
