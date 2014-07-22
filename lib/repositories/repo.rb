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
        repo = Rugged::Repository.init_at(dir)

        git_author_name  = Repositories.config['git_author_name']  || 'repos'
        git_author_email = Repositories.config['git_author_email'] || 'repos@repos.com'

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

    def repo_dir
      dir = File.join(@git_repo.workdir, 'repo')
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      dir
    end

    def package_cache_dir
      dir = File.join(Repositories.config['repo_base_location'], 'package_cache')
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      dir
    end

    def sync
      if locked?
        return [ 402, "Sync is already in progress" ]
      end

      pid = fork do
        @logger.info('Starting Sync')

        lock
        
        #For non local sources, we will create a temporary working dir to sync to.  This avoids complications
        #when someone has been messing about in the regular workdir (playing with tags or branching or something)
        #For locally sourced repos though, its expected that the admin knows what theyre doing.
        if source =~ /^local/
          #This should make the repo look like the last commit on Master without clobering any manual adds since (we want to add those)
          @git_repo.checkout(@git_repo.branches["master"], :strategy => :safe_create)
        else
          tmp_work_dir = File.join(Repositories.config['repo_base_location'], ".#{@name}-#{Time.new.to_i}")
    
          #create and use a temporary work dir so manual stuff in the normal work dir doesnt get in the way
          unless File.directory?(tmp_work_dir)
            FileUtils.mkdir_p(tmp_work_dir)
          end
    
          #save the real work dir
          real_workdir = @git_repo.workdir
    
          #set the workdir of the GIT repository to the one supplied to the method
          @git_repo.workdir = tmp_work_dir
    
          #Check the master branch out to the temp work dir.
          @git_repo.checkout(@git_repo.branches["master"], :strategy => :force)
        end

        #Run the sync source method which is defined in the repositories type class
        begin
          sync_source()
        rescue RepoError => e
          @logger.error("Sync of repository #{@name} failed: #{e.message}")
        else
          #commit the repo to git
          git_commit()
          @logger.info('Sync complete')
        end

        #remove the temporary work dir
        FileUtils.rm_rf(tmp_work_dir) if tmp_work_dir

        #Set the workdir of the GIT repo back to the real one
        @git_repo.workdir = real_workdir if real_workdir

        unlock
      end
      Process.detach(pid)
      [ 200, "Sync of #{@name} has been started." ]
    end

    def http_sync
      if system('which lftp > /dev/null 2>&1')
        http_sync_includes = self.class.http_sync_include.collect { |inc| "-I #{inc}" }.join(' ')
        http_sync_excludes = (self.class.http_sync_exclude).flatten.collect { |exc| "-X \"#{exc}\"" }.join(' ')

        sync_cmd = "#{`which lftp`.chomp} -c '; mirror -P -c -e -L -vvv #{http_sync_includes} #{http_sync_excludes} #{@source} #{repo_dir}'"
        
        IO.popen(sync_cmd).each do |line|
          @logger.info( line.chomp )
        end
      else
        raise RepoError, "Failed to run sync.  Processes required lftp but it does not appear to be installed"
      end
    end

    def local_sync
      git_commit
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
        package_files << Dir.glob(File.join(@git_repo.workdir, '**', pattern))
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
      packages_dir = package_cache_dir()

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

    def updates?
      if head_commit = find_commit("master")
          package_patterns = self.class.respond_to?('package_patterns') ? self.class.package_patterns : ['*']
          diff = head_commit.tree.diff_workdir(:recurse_untracked_dirs => true, :include_untracked => true, :paths => package_patterns)
          diff.deltas.empty? ? false : true
      else
        true
      end
    end
  end
end

require_relative 'repo/yum'
require_relative 'repo/apt'
