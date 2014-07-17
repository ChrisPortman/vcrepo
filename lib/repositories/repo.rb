module Repositories
  class Repo
    ### Class Variables ###
    #Stores the repository object for each repository
    @@repositories = {}

    ### Class Methods

    # self.create
    #
    # Args:
    #  1. type of repo e.g. yum/apt
    #  2. the os the repo belongs to
    #  3. the name of the repo
    #  4. the version of the os the repo belongs to
    #  5. the architecture the repo pertains to
    #  6. the source of the packages
    #
    # Creates the repository object by calling .new on the appropriate
    # child class depending on the type.
    def self.create(type, name, source)
      unless @@repositories[name]
        case type
          when 'yum'
            @@repositories[name] = Repositories::Repo::Yum.new(name, source)
          when 'apt'
            @@repositories[name] = Repositories::Repo::Apt.new(name, source)
          else
        end
      end
    end

    # self.all
    #
    # Returns the @@repositories class var containing all the repos.
    def self.all
      @@repositories
    end

    # self.repo
    #
    # Args:
    #   1. The name of the repo to retrieve
    #
    # Returns the repository object for the repo reqursted or nil.
    def self.repo(name)
      ret = nil
      @@repositories.each do |n,repo|
        if name == n
          ret = repo
        end
      end
      ret
    end

    # self.sync_all
    #
    # Triggers a sync on all repos.
    def self.sync_all
      @repositories.each do |name, repo|
        repo.sync
      end
    end

    def check_dir
      base = Repositories.config['repo_base_location']
      dir  = File.join(base, @type, @name)
      File.directory?(dir) || FileUtils.mkdir_p(dir)
      dir
    end

    def check_repo_dir
      dir = File.join(@dir, 'repo')
      File.directory?(dir) || FileUtils.mkdir_p(dir)
      dir
    end

    def check_git_repo
      if File.directory?(File.join(dir, '.git'))
        Rugged::Repository.new(File.join(dir, '.git'))
      else
        Rugged::Repository.init_at(dir)
      end
    end

    def http_sync
      if system('which lftp > /dev/null 2>&1')
        pid = fork do
          lock
          # This hack because lftp doesnt consider the real file behind a symlink, but just the symlink itself
          # It then goes ahead and deletes the symlinks and resyncs from scratch.
          existing_files = Dir.glob(File.join(@dir, 'repo', '**', '*')).collect{ |file| "*#{File.basename(file)}" }

          http_sync_includes = self.class.http_sync_include.collect { |inc| "-I #{inc}" }.join(' ')
          http_sync_excludes = (self.class.http_sync_exclude + existing_files).flatten.collect { |exc| "-X \"#{exc}\"" }.join(' ')

          sync_cmd = "#{`which lftp`.chomp} -c '; mirror -P -c -e -vvv #{http_sync_includes} #{http_sync_excludes} #{@source} #{@repo_dir}'"
          IO.popen(sync_cmd).each do |line|
            @logger.info( line.chomp )
          end

          git_commit
          unlock
          @logger.info('Sync complete')
        end
        Process.detach(pid)
        [ 200, "Sync of #{@name} has been started." ]
      else
        [ 402, "Failed to run sync.  Processes required lftp but it does not appear to be installed" ]
      end
    end

    def local_sync
      pid = fork do
        lock
          git_commit
          @logger.info('Sync complete')
        unlock
      end
      Process.detach(pid)
      [ 200, "Sync of #{@name} has been started." ]
    end

    def lock
      FileUtils.touch(File.join(@git_repo.path, '.locked'))
    end

    def unlock
      FileUtils.rm_f(File.join(@git_repo.path, '.locked'))
    end

    def locked?
      File.exist?(File.join(@git_repo.path, '.locked'))
    end


    def git_commit
      time = Time.new
      date = "%04d" % time.year + "%02d" % time.month + "%02d" % time.mday

      package_files = []
      self.class.package_patterns.each do |pattern|
        package_files << Dir.glob(File.join(@dir, '**', pattern))
      end

      package_files.flatten.each do |file|
        link_package(file)
      end

      generate_repo

      if updates?
        index = @git_repo.index
        index.remove_all
        index.add_all

        git_author_name  = Repositories.config['git_author_name']  || 'repos'
        git_author_email = Repositories.config['git_author_email'] || 'repos@repos.com'

        Rugged::Commit.create(@git_repo,
          :author     => {:email => git_author_email, :name => git_author_name, :time => Time.now },
          :committer  => {:email => git_author_email, :name => git_author_name, :time => Time.now },
          :message    => date,
          :parents    => @git_repo.empty? ? [] : [ @git_repo.head.target ].compact,
          :update_ref => 'HEAD',
          :tree       => @git_repo.lookup(index.write_tree),
        )
      end
    end

    def link_package(file)
      packages_dir = File.join(@git_repo.path, 'packages')
      unless File.directory?(packages_dir)
        Dir.mkdir(packages_dir)
      end

      newfile = File.join(packages_dir, File.basename(file))
      File.exists?(newfile) ? FileUtils.rm(file) : FileUtils.mv(file, newfile)
      FileUtils.ln_s(newfile, file)
    end

    def file?(file, release='master')
      file = "repo/#{file}"

      if item = find_leaf(file, release)
        (item[:type] == :blob and item[:filemode] != 40960) ? true : false
      else
        false
      end
    end

    def link?(file, release='master')
      file = "repo/#{file}"

      if item = find_leaf(file, release)
        (item[:type] == :blob and item[:filemode] == 40960) ? true : false
      else
        false
      end
    end

    def file(file, release='master')
      file = "repo/#{file}"
      if file = find_leaf(file, release)
        @git_repo.lookup(file[:oid]).content
      end
    end

    def contents(path=nil, release='master')
      path = path ? File.join('repo', path) : 'repo'

      if tree = find_leaf(path, release)
        @git_repo.lookup(tree[:oid])
      else
        []
      end
    end

    # find_commit(ref)
    #
    # Args:
    #   1) A the name of a tag or branch or a commit ID
    #
    # Returns a commit object that is the tip of the specified branch,
    # the commit taged with the specified tag, or, the commit specified
    # as the commit ID.
    def find_commit(release)
      return if @git_repo.empty?

      if release.length == 40 and object = @git_repo.lookup(release)
        return object if object.type == :commit

      elsif tag = @git_repo.references["refs/tags/#{release}"]
        case
          when tag.target_type == :commit
            tag
          when tag.target_type == :tag
            tag.target
          else
            raise RepoError, "No such revision: #{release}"
        end

      elsif branch = @git_repo.branches[release]
        @git_repo.lookup(branch.target_id)

      else
        raise RepoError, "No such revision: #{release}"
      end
    end

    # find_leaf(name, release)
    #
    # Args:
    #   1) the name of the leaf (most likely a file)
    #   2) the branch, tag or commit ID to find it in.
    #
    # Returns a git object that is the item requested by 'name' and from
    # the branch/tag/commit ID specified by release.  Item is most likely   
    # going to be a file, and the full relative path to the file should
    # be supplied.
    def find_leaf(name, release)
      path   = name.split('/')
      leaf   = path.pop
      if commit = find_commit(release)
        tree = commit.tree
        path.each do |p|
          tree.each_tree do |t|
            tree = @git_repo.lookup(t[:oid]) and break if t[:name].to_s == p
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

    # updates?
    #
    # Checks the work dir against the master branch HEAD to and returns
    # true if there are changes and false if not.
    def updates?
      if head_commit = find_commit("master")
        diff = head_commit.tree.diff_workdir
        diff.deltas.empty? ? false : true
      else
        true
      end
    end
    
    def checkout(branch='master')
      return if @git_repo.empty?
      
      #The current release of rugged doesnt have the checkout functionality.  
      #Its in the dev tree, but I dont want to use it.  
      #Ill just use the git command for now :(

      worktree = @git_repo.workdir
      gitdir   = @git_repo.path
      
      # Force the current work tree into alignment to its HEAD.  Git wont allow
      # you checkout to another branch if the current work tree is tainted.
      system("git --work-tree=#{worktree} --git-dir=#{gitdir} reset --hard HEAD > /dev/null 2>&1")
      
      # Checkout the desired branch
      system("git --work-tree=#{worktree} --git-dir=#{gitdir} checkout #{branch} > /dev/null 2>&1")
    end
  end
end

require_relative 'repo/yum'
require_relative 'repo/apt'
