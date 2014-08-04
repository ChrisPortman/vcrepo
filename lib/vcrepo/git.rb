require 'rugged'

module Vcrepo
  class Git
    attr_reader :repo

    def initialize(dir, package_repo)
      @real_workdir = dir
      @repo         = open_or_create()
      @package_repo = package_repo
    end

    def workdir
      @repo.workdir
    end

    def workdir=(dir)
      @repo.workdir=dir
    end

    def safe_checkout(branch, workdir=nil)
      branch = get_branch(branch)
      @repo.workdir = workdir if workdir
      @repo.checkout(branch, :strategy => :safe_create)
    end

    def hard_checkout(branch, workdir=nil)
      branch = get_branch(branch)
      @repo.workdir = workdir if workdir
      @repo.checkout(branch, :strategy => :force)
    end

    def reset_workdir
      @repo.workdir = @real_workdir
    end

    def path
      @repo.path
    end

    def file?(obj, release='master')
      if item = find_leaf(obj, release)
        (item[:type] == :blob and item[:filemode] != 40960) ? true : false
      else
        false
      end
    end

    def file(file, release='master')
      if file = find_leaf(file, release)
        @repo.lookup(file[:oid]).content
      end
    end

    def link?(obj, release='master')
      if item = find_leaf(obj, release)
        (item[:type] == :blob and item[:filemode] == 40960) ? true : false
      else
        false
      end
    end

    def tree_contents(path='', release='master')
      if tree = find_leaf(path, release)
        @repo.lookup(tree[:oid])
      else
        []
      end
    end

    def commit
      if updates?
        time = Time.new
        date = "%04d" % time.year + "%02d" % time.month + "%02d" % time.mday

        index = @repo.index
        index.remove_all
        index.add_all

        git_author_name  = Vcrepo.config['git_author_name']  || 'vcrepo'
        git_author_email = Vcrepo.config['git_author_email'] || 'vcrepo@vcrepo.null'

        Rugged::Commit.create(@repo,
          :author     => {:email => git_author_email, :name => git_author_name, :time => Time.now },
          :committer  => {:email => git_author_email, :name => git_author_name, :time => Time.now },
          :message    => date,
          :parents    => @repo.empty? ? [] : [ @repo.head.target ].compact,
          :update_ref => 'HEAD',
          :tree       => @repo.lookup(index.write_tree),
        )
      end
    end
    
    def branch_commits(branch='master')
      if br = @repo.branches[branch]
        @repo.walk(br.target_id)
      else
        []
      end
    end
    
    def tags
      @repo.tags
    end
    
    def lookup_tag(tag)
      @repo.tags[tag]
    end

    def lookup_commit(oid)
      if obj = @repo.lookup(oid)
        obj.type == :commit ? obj : nil
      end
    end
    
    def branches
      @repo.branches
    end

    def lookup_branch(branch='master')
      @repo.branches[branch]
    end

    private

    def open_or_create
      dir = @real_workdir

      if File.directory?(File.join(dir, '.git'))
        Rugged::Repository.new(File.join(dir, '.git'))
      else
        repo = Rugged::Repository.init_at(dir)

        git_author_name  = Vcrepo.config['git_author_name']  || 'vcrepo'
        git_author_email = Vcrepo.config['git_author_email'] || 'vcrepo@vcrepo.null'

        Rugged::Commit.create(repo,
          :author     => {:email => git_author_email, :name => git_author_name, :time => Time.now },
          :committer  => {:email => git_author_email, :name => git_author_name, :time => Time.now },
          :message    => "Initial commit",
          :parents    => repo.empty? ? [] : [ repo.head.target ].compact,
          :update_ref => 'HEAD',
          :tree       => repo.lookup(repo.index.write_tree),
        )
        repo
      end
    end

    def get_branch(branch)
      case branch
      when Rugged::Branch
        return branch
      when String
        return @repo.branches[branch]
      else
        raise RepoError, "Invalid arg for get_branch, must be a string or Rugged::Branch object"
      end
    end

    def updates?
      if head_commit = find_commit("master")
          package_repo     = Vcrepo::Repository.find(@package_repo)
          package_patterns = package_repo.class.respond_to?('package_patterns') ? package_repo.class.package_patterns : ['*']
          diff = head_commit.tree.diff_workdir(:recurse_untracked_dirs => true, :include_untracked => true, :paths => package_patterns)
          diff.deltas.empty? ? false : true
      else
        true
      end
    end

    def find_commit(release)
      return if @repo.empty?

      if release.length == 40 and object = @repo.lookup(release)
        return object if object.type == :commit

      elsif tag = @repo.tags[release]
        case
          when tag.target.type == :commit
            tag.target
          else
            raise RepoError, "No such revision: #{release}"
        end

      elsif branch = @repo.branches[release]
        @repo.lookup(branch.target_id)

      else
        raise RepoError, "No such revision: #{release}"
      end
    end

    def find_leaf(name, release)
      path   = name.split('/')
      leaf   = path.pop
      if commit = find_commit(release)
        
        tree = commit.tree
        path.each do |p|
          tree.each_tree do |t|
            tree = @repo.lookup(t[:oid]) and break if t[:name].to_s == p
          end
        end

        tree.each do |i|
          return i if i[:name].to_s == leaf
        end
      else
        raise RepoError.new("Could not find the path '#{name}' in revision #{release}", 404)
      end

      nil
    end
  end
end
