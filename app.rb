require 'rubygems'
require 'sinatra/base'
require 'json'
require 'uri'

require_relative './lib/vcrepo'

class Vcrepo::App < Sinatra::Base

  # Before/After hooks
  before '/api/*' do
    @url = url('/api/')
    content_type 'application/json'
  end

  after '/api/*' do
    response.body = response.body.to_json
  end

  # Helpers
  helpers do
    def find_class(namespace)
      mod = nil
      begin
        namespace.split(/::/).each do |p|
          if mod
            if mod.const_defined?(p)
              mod = mod.const_get(p)
            else
              return nil
            end
          else
            if Module.const_defined?(p)
              mod = Module.const_get(p)
            end
          end
        end
      rescue NameError
        return nil
      end
      return mod
    end

    def uri_join( *parts )
      joined = parts.join('/')
      joined.gsub(/(?<!:)\/\//,'/')
    end

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
            elsif repo.dir?(@path, @rev)
              contents = repo.contents(@path, @rev)
              dirs  = contents.select { |item| item[:type] == :tree }.collect { |tree| File.join(@path, tree[:name].to_s) }.sort
              files = contents.select { |item| item[:type] == :blob }.collect { |blob| File.join(@path, blob[:name].to_s) }.sort
              show_dir(dirs, files)
            else
              [ 404, "Not Found" ]
            end
          else
            [ 404, "No such repository" ]
          end
        else
          show_dir(Vcrepo::Repository.all_enabled.keys.sort)
        end
      rescue RepoError => e
        [ e.status, e.message ].to_json
      end
    end
  end

  #API routes come here.
  get '/api/?*?' do
    path_parts = params[:splat].first.split('/')

    namespace = "Vcrepo::Api"
    operation = nil
    args      = []

    #Identify the appropriate namespace to handle the request by mapping collections to the API namespace
    #Any ID fields become arguments or an operation if the part is a valid action for the namespace.
    path_parts.each do |part|
      if our_class = find_class([namespace, part.capitalize].join('::'))
        namespace = [namespace, part.capitalize].join('::')
      elsif our_class = find_class(namespace)
        if our_class.methods.include?(:actions) and our_class.method('actions').call.include?(part.to_sym)
          operation = part
        else
          args.push(part)
        end
      else
        [ 404, "Unknown API" ]
      end
    end

    if our_class = find_class(namespace)
      if operation
        if our_class.methods.include?(operation.to_sym)
          our_method = our_class.method(operation)
          our_method.call(args.push(params))
        else
          [ 400, "Invalid action or collection" ]
        end

      else
        ret = our_class.method('find').call(args)

        if ret.is_a? Hash or ret.first.is_a? Hash
          #This is a specific item
          if our_class.methods.include?(:sub_collections)
            our_method = our_class.method('sub_collections')
            cols = our_method.call.collect do |c|
              {
                :id   => c,
                :href => uri_join(url, c),
              }
            end
            ret['links'] = cols if cols and !cols.empty?
          end
  
          if our_class.methods.include?(:actions)
            our_method = our_class.method('actions')
            actions = our_method.call.collect do |a|
              {
                :id   => a,
                :href => uri_join(url, a),
              }
            end
            ret['actions'] = actions if actions and !actions.empty?
          end
        elsif !ret.first.is_a? Integer
          ret = ret.collect do |c|
            if c.respond_to?('name')
              id = c.name
            elsif c.respond_to?('oid')
              id = c.oid
            else
              id = c
            end

            {
              :id   => id,
              :href => uri_join(url, id)
            }
          end
        end

        if ret.is_a? Array
          ret
        else
          [ret]
        end
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
    @rev       = Vcrepo.config['default_revision'] ||'master'
    @repo_name = params[:repo]
    @path      = params[:splat].first
    generate_output()
  end
end

  #~ get '/api/?' do
    #~ #Show all the top level collections
    #~ valid_collections = [ 'repository' ]
    #~
    #~ ret = []
    #~ valid_collections.each do |col|
      #~ ret.push(
        #~ {
          #~ :id   => col,
          #~ :href => uri_join(url,col),
        #~ }
      #~ )
    #~ end
    #~ ret
  #~ end
  #~
  #~ get '/api/repository/?' do
    #~ #Show all the repositories
    #~ ret = []
    #~ Vcrepo::Repository.all.keys.each do |repo|
      #~ ret.push(
        #~ {
          #~ :id   => repo,
          #~ :href => uri_join(url,repo),
        #~ }
      #~ )
    #~ end
    #~ ret
  #~ end
#~
  #~ get '/api/repository/:repo/?' do
    #~ #Show details of specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ actions = [ 'sync' ].collect do |a|
        #~ {
          #~ :id   => a,
          #~ :href => uri_join(url, a),
        #~ }
      #~ end
      #~
      #~ relations = [ 'commit', 'tag', 'branch' ].collect do |r|
        #~ {
          #~ :id   => r,
          #~ :href => uri_join(url, r),
        #~ }
      #~ end
      #~
      #~ [
        #~ {
          #~ :id        => repo.name,
          #~ :name      => repo.name,
          #~ :source    => repo.source,
          #~ :type      => repo.type,
          #~ :dir       => repo.dir,
          #~ :enabled   => repo.enabled,
          #~ :actions   => actions,
          #~ :relations => relations,
        #~ }
      #~ ]
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/commit/?' do
    #~ #Show commit collection relative to specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ start  = params[:start]  || 0
      #~ max    = params[:max]    || 50
      #~ branch = params[:branch] || 'master'
      #~
      #~ ret = []
      #~ repo.git_repo.branch_commits(branch).each do |c|
        #~ ret.push(
          #~ {
            #~ :id   => c.oid,
            #~ :desc => "#{c.message.slice(0,20)}...",
            #~ :href => uri_join(url,c.oid),
          #~ }
        #~ )
      #~ end
      #~ ret.slice(start,max)
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/commit/:commit_id/?' do
    #~ #show details of specified commit relatative to specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ if commit = repo.git_repo.lookup_commit(params[:commit_id])
        #~ actions = Vcrepo::Api::Repository::Commit.actions.collect do |a|
          #~ {
            #~ :id   => a,
            #~ :href => uri_join(url, a)
          #~ }
        #~ end
        #~
        #~ [
          #~ {
            #~ :id        => commit.oid,
            #~ :author    => commit.author,
            #~ :committer => commit.committer,
            #~ :message   => commit.message,
            #~ :time      => commit.time,
            #~ :actions   => actions,
          #~ }
        #~ ]
      #~ else
        #~ [ 404, "Not a valid commit id for repo #{params[:repo]}." ]
      #~ end
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/commit/:commit_id/:action/?' do
    #~ #Perform specified action against specified commit in specified repository
    #~ valid_actions = [ 'tag' ]
    #~
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ if Vcrepo::Api::Repository::Commit.respond_to?(params[:action])
        #~ Vcrepo::Api::Repository::Commit.method(params[:action]).call(repo.git_repo.repo, params)
      #~ else
        #~ [400, "#{params[:action]} is not a valid repository action"]
      #~ end
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/tag/?' do
    #~ #Show tag collection relative to specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ ret = []
      #~ repo.git_repo.tags.each do |t|
        #~ ret.push(
          #~ {
            #~ :id   => t.name,
            #~ :href => uri_join(url,t.name)
          #~ }
        #~ )
      #~ end
      #~ ret
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/tag/:tag_id/?' do
    #~ #show details of specified tag relatative to specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ if tag = repo.git_repo.lookup_tag(params[:tag_id])
        #~ actions = Vcrepo::Api::Repository::Tag.actions.collect do |a|
          #~ {
            #~ :id   => a,
            #~ :href => uri_join(url, a),
          #~ }
        #~ end
        #~
        #~ target = {
          #~ :id   => tag.target.oid,
          #~ :hfef => url.sub(/#{request.path}/, "/api/repository/#{params[:repo]}/commit/#{tag.target.oid}"),
        #~ }
        #~
        #~ ret = {
          #~ :id      => tag.name,
          #~ :target  => target,
          #~ :actions => actions,
        #~ }
        #~ ret[:annotation] = tag.annotation.to_hash if tag.annotated?
#~
        #~ [ ret ]
      #~ else
        #~ [ 404, "No such tag #{params[:tag_id]} in repository #{params[:repo]}." ]
      #~ end
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/tag/:tag_id/:action/?' do
    #~ #Perform specified action against specified tag in specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ if Vcrepo::Api::Repository::Tag.respond_to?(params[:action])
        #~ Vcrepo::Api::Repository::Tag.method(params[:action]).call(repo.git_repo.repo, params)
      #~ else
        #~ [400, "#{params[:action]} is not a valid repository action"]
      #~ end
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/branch/?' do
    #~ #Show branch collection relative to specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ ret = []
      #~ repo.git_repo.branches.each do |b|
        #~ ret.push(
          #~ {
            #~ :id   => b.name,
            #~ :href => uri_join(url,b.name),
          #~ }
        #~ )
      #~ end
      #~ ret
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/branch/:branch_id/?' do
    #~ #show details of specified branch relatative to specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ if branch = repo.git_repo.lookup_branch(params[:branch_id])
        #~ actions = Vcrepo::Api::Repository::Branch.actions.collect do |a|
          #~ {
            #~ :id   => a,
            #~ :href => uri_join(url, a),
          #~ }
        #~ end
#~
        #~ target = {
          #~ :id   => branch.target.oid,
          #~ :href => url.sub(/#{request.path}/, "/api/repository/#{params[:repo]}/commit/#{branch.target.oid}"),
        #~ }
        #~
        #~ [
          #~ {
            #~ :id      => branch.name,
            #~ :target  => target,
            #~ :actions => actions,
          #~ }
        #~ ]
      #~ else
        #~ [ 404, "No such branch #{params[:branch_id]} for repository #{params[:repo]}." ]
      #~ end
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/branch/:branch_id/:action/?' do
    #~ #Perform specified action against specified branch in specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ if Vcrepo::Api::Repository::Branch.respond_to?(params[:action])
        #~ Vcrepo::Api::Repository::Branch.method(params[:action]).call(repo.git_repo.repo, params)
      #~ else
        #~ [400, "#{params[:action]} is not a valid repository action"]
      #~ end
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ get '/api/repository/:repo/:action/?' do
    #~ #Perform specified action against specified repository
    #~ valid_actions = [ 'sync' ]
    #~ if repo = Vcrepo::Repository.find(params[:repo])
      #~ if valid_actions.include?(params[:action])
        #~ if repo.respond_to?(params[:action])
          #~ repo.method(params[:action]).call
        #~ else
          #~ [400, "#{params[:action]} is not a valid repository action"]
        #~ end
      #~ else
        #~ [400, "#{params[:action]} is not a valid repository action"]
      #~ end
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end
#~
  #~ post '/api/repository/:repo/:action/?' do
    #~ #Perform specified action against specified repository
    #~ if repo = Vcrepo::Repository.find(params[:repo])
    #~ else
      #~ [ 404, "No such repository #{params[:repo]}." ]
    #~ end
  #~ end

  #Browse the files like an Index.  This provides machines access to the repos
  #These should come last so that they form default resoponces to anything not
  #API related.
