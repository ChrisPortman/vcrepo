require 'rubygems'
require 'sinatra/base'
require 'json'

require_relative './lib/vcrepo'

class Vcrepo::App < Sinatra::Base

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
    
    def generate_output
      begin
        if @repo_name
          if repo = Vcrepo::Repository.find(@repo_name)
            if @path.empty?
              contents = repo.contents(nil, @rev)
              dirs  = contents.select { |item| item[:type] == :tree }.collect { |tree| tree[:name].to_s }.sort
              files = contents.select { |item| item[:type] == :blob }.collect { |blob| blob[:name].to_s }.sort
              show_dir(dirs, files)
            elsif repo.link?(@path, @rev)
              file_name = @path.match(/([^\/]+)$/)[1]
              send_file repo.file(@path, @rev), :disposition => 'attachment', :filename => file_name, :type => 'application/octet-stream'
            elsif repo.file?(@path, @rev)
              content_type 'application/octet-stream'
              repo.file(@path, @rev)
            else
              contents = repo.contents(@path, @rev)
              dirs  = contents.select { |item| item[:type] == :tree }.collect { |tree| File.join(@path, tree[:name].to_s) }.sort
              files = contents.select { |item| item[:type] == :blob }.collect { |blob| File.join(@path, blob[:name].to_s) }.sort
              show_dir(dirs, files)
            end
          else
            [ 404, "No such repository" ]
          end
        else
          show_dir(Vcrepo::Repository.all.keys.sort)
        end
      rescue RepoError => e
        [ e.status, e.message ].to_json
      end
    end
  end

  get '/rev/:rev/?:repo?/?*' do
    @explicit_rev = true
    @rev          = params[:rev]
    @repo_name    = params[:repo]
    @path         = params[:splat].first
    
    generate_output()
  end

  get '/?:repo?/?*' do
    puts "No revision"
    @rev       = Vcrepo.config['default_revision'] ||'master'
    @repo_name = params[:repo]
    @path      = params[:splat].first
    generate_output()
  end

  #API commands for managing the repos.
  #~ get '/api/repos' do
    #~ Vcrepo::Repository.all.keys.to_json
  #~ end

  #~ get '/api/sync-repo' do
    #~ params[:repo] or error 402, "Must supply a repo"
#~ 
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ begin
        #~ repo.sync.to_json
      #~ rescue RepoError => e
        #~ [ e.status, e.message ].to_json
      #~ end
    #~ else
      #~ [ 404, "Repo #{params[:repo]} does not exist" ].to_json
    #~ end
  #~ end
end
