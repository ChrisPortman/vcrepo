require 'rubygems'
require 'sinatra/base'
require 'json'
#require 'require_relative'

require_relative './lib/repositories'

class Repositories::App < Sinatra::Base
  
  # Before/After hooks
  before '/api/*' do
    content_type 'application/json'
  end
  
  # Helpers
  helpers do
    def show_dir(dirs=[], files=[])
      @dirs  = dirs
      @files = files
      begin
        erb 'directory'.to_sym
      rescue
        [ 404, "File not found!" ]
      end
    end
  
  end
  
  get '/:rev?/?repos/?:repo?/?*' do
    @rev       = params[:rev] || 'master'
    @repo_name = params[:repo]
    @path      = params[:splat].first
    
    if @repo_name and repo = Repositories::Repo.repo(@repo_name)
      puts repo.inspect
      if @path.empty?
        contents = repo.contents
        dirs  = contents.select{|f| f[:type] == 'tree' }.collect{|f| f[:file] }
        files = contents.select{|f| f[:type] == 'blob' }.collect{|f| f[:file] }

        show_dir(dirs, files)
      elsif repo.link?(@path, @rev)
        file_name = @path.match(/([^\/]+)$/)[1]
        send_file repo.file(@path, @rev).sub(/^../, repo.dir), :disposition => 'attachment', :filename => file_name, :type => 'application/octet-stream'
      elsif repo.file?(@path, @rev)
        content_type 'application/octet-stream'
        repo.file(@path, @rev)
      else
        contents = repo.contents(@path)
        dirs  = contents.select{|f| f[:type] == 'tree' }.collect{|f| f[:file] }
        files = contents.select{|f| f[:type] == 'blob' }.collect{|f| f[:file] }

        show_dir(dirs, files)
      end
    else
      show_dir(Repositories::Repo.all.keys)
    end
  end
  
  #API commands for managing the repos.
  get '/api/repos' do
    Repositories::Repo.all.keys.to_json
  end
  
  get '/api/sync-repo' do
    params[:repo] or error 402, "Must supply a repo"
    
    if repo = Repositories::Repo.repo(params[:repo])
      repo.sync
      [ 200, "Sync of #{params[:repo]} has been started." ].to_json
    else
      [ 404, "Repo #{params[:repo]} does not exist" ].to_json
    end
  end
    
end
