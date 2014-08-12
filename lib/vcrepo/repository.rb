module Vcrepo
  class Repository
    attr_reader :name, :source, :type, :dir, :enabled, :git_repo, :logger

    ### Class Variables ###
    #Stores the repository object for each repository
    @@repositories = {}

    ### Class Methods
    def self.package_patterns
      [ "*" ]
    end

    def self.http_sync_include
      []  #No specific includes
    end

    def self.http_sync_exclude
      []  #No excludes
    end

    def self.create(name, source, type)
      case type
        when 'yum'
          @@repositories[name] = Vcrepo::Repository::Yum.new(name, source, type)
        when 'apt'
          @@repositories[name] = Vcrepo::Repository::Apt.new(name, source, type)
        else
          #Just create a generic file repository with basic sync options and no metadata generation
          @@repositories[name] = Vcrepo::Repository.new(name, source)
      end
    end

    def self.all
      @@repositories
    end

    def self.all_enabled
      #Check the disabled ones
      @@repositories.select{ |key,val| !val.enabled }.each do |name, repo|
        create(repo.name, repo.source, repo.type)
      end
      
      @@repositories.select{ |key,val| val.enabled }
    end

    def self.find(name)
      ret = nil
      self.all.each do |n,repo|
        if name == n
          ret = repo
        end
      end
      ret
    end

    def self.sync_all
      self.all.each.each do |name, repo|
        repo.sync
      end
    end

    def initialize(name, source, type='generic')
      @name     = name
      @source   = source
      @type     = type
      @enabled  = true
      
      #Progress through setting up the repo as log as enabled remains true
      (@enabled = (@logger   = create_log                  ) ? true : false) if @enabled
      (@enabled = (@dir      = git_dir                   ) ? true : false) if @enabled
      (@enabled = (@git_repo = Vcrepo::Git.new(@dir, @name)) ? true : false) if @enabled
      (@enabled = (package_dir                             ) ? true : false) if @enabled
    end

    #Dispatch to a method that matches sync_<proto>
    def sync_source
      proto = source.match(/^(\w+)/)[1]
      if self.respond_to?("sync_#{proto}")
        self.method("sync_#{proto}").call
      else
        raise RepoError, "Unknown sync protocol '#{proto}'"
      end
    end

    def sync
      if locked?
        return [ 402, "Sync is already in progress" ]
      end

      pid = fork do
        execute_sync
      end
      Process.detach(pid)
      
      [ 200, "Sync of #{@name} has been started." ]
    end
    
    def execute_sync
      logger.info('Starting Sync')
  
      lock
  
      #For non local sources, we will create a temporary working dir to sync to.  This avoids complications
      #when someone has been messing about in the regular workdir (playing with tags or branching or something)
      #For locally sourced repos though, its expected that the admin knows what theyre doing.
      if source =~ /^local/
        #This should make the repo look like the last commit on Master without clobering any manual adds since (we want to add those)
        git_repo.safe_checkout("master")
        prepare_repo
        generate_repo
        git_repo.commit
        logger.info('Sync complete')
      else
        tmp_work_dir = File.join(Vcrepo.config['repo_base_dir'], ".#{@name}-#{Time.new.to_i}")
  
        #create and use a temporary work dir so manual stuff in the normal work dir doesnt get in the way
        unless File.directory?(tmp_work_dir)
          FileUtils.mkdir_p(tmp_work_dir)
        end
  
        #Check the master branch out to the temp work dir.
        git_repo.hard_checkout("master", tmp_work_dir)
  
        #Run the sync source method which is defined in the repositories type class
        begin
          sync_source
        rescue RepoError => e
          logger.error("Sync of repository #{@name} failed: #{e.message}")
        else
          #Move the packages to the cache and generate metadata then commit
          generate_repo
          prepare_repo
          git_repo.commit
          logger.info('Sync complete')
        end
  
        #remove the temporary work dir
        FileUtils.rm_rf(tmp_work_dir) if tmp_work_dir
      end
  
      #Set the workdir of the GIT repo back to the real one
      git_repo.reset_workdir
  
      unlock    
    end

    def sync_http
      if system('which lftp > /dev/null 2>&1')
        http_sync_includes = self.class.respond_to?('http_sync_include') ? self.class.http_sync_include.collect { |inc| "-I #{inc}" }.join(' ') : ''
        http_sync_excludes = self.class.respond_to?('http_sync_exclude') ? self.class.http_sync_exclude.flatten.collect { |exc| "-X \"#{exc}\"" }.join(' ') : ''

        sync_cmd = "#{`which lftp`.chomp} -c '; mirror -P -c -e -L -vvv #{http_sync_includes} #{http_sync_excludes} #{@source} #{package_dir}'".gsub(/\s+/, ' ')

        IO.popen(sync_cmd).each do |line|
          logger.info( line.chomp )
        end
      else
        raise RepoError, "Failed to run sync.  Processes required lftp but it does not appear to be installed"
      end
    end
    
    def lock
      FileUtils.touch(File.join(git_repo.path, '.locked'))
    end

    def unlock
      FileUtils.rm_f(File.join(git_repo.path, '.locked'))
    end

    def locked?
      File.exist?(File.join(git_repo.path, '.locked'))
    end

    def git_dir
      base = Vcrepo.config['repo_base_dir']
      dir  = File.join(base, @type, @name)

      begin
        File.directory?(dir) || FileUtils.mkdir_p(dir)
      rescue Exception => e
        logger.error("Can not create directory for this repository it will be disabled: #{e.message}")
        return nil
      end

      dir
    end

    def package_dir
      dir = File.join(git_repo.workdir, 'packages')
      unless File.directory?(dir)
        begin
          FileUtils.mkdir_p(dir)
        rescue Exception => e
          logger.error("Can not create directory for the packages it will be disabled: #{e.message}")
          return nil
        end
      end
      dir
    end

    def package_cache_dir(package=nil)
      index_path = nil
      extension  = nil
      
      if package
        extension  = File.extname(package).sub(/^\./, '')
        filebase   = File.basename(package)  
        index_path = Vcrepo.config.package_indexing_patterns.collect do |i|
          if index = filebase.match(/^#{i}/)
            index[0]
          end
        end.compact.first
      end      

      dir = File.join([Vcrepo.config['repo_base_dir'], 'package_cache', extension, index_path].compact)
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      dir
    end

    def create_log
      log_dir  = Vcrepo.config['logdir'] || './logs'
      log_file = File.join(log_dir, @name)
      logger   = nil

      begin
        unless File.directory?(log_dir)
          FileUtils.mkdir_p(log_dir)
        end
          logger = Logger.new(log_file)
      rescue
        return nil
      end
      logger
    end

    def generate_repo
      # This is a stub.  Generic repos dont generate metadata. 
      # Classes for specific types will overload this method
    end
    
    def prepare_repo
      package_files = []
      self.class.package_patterns.each do |pattern|
        package_files << Dir.glob(File.join(git_repo.workdir, '**', pattern))
      end

      package_files.flatten.each do |file|
        link_package(file)
      end
    end

    def link_package(file)
      packages_dir = package_cache_dir(file)

      newfile = File.join(packages_dir, File.basename(file))
      File.exists?(newfile) ? FileUtils.rm(file) : FileUtils.mv(file, newfile)
      
      FileUtils.ln_s(newfile, file)
    end

    def file?(file, release='master')
      file = "packages/#{file}"
      git_repo.file?(file, release)
    end

    def link?(file, release='master')
      file = "packages/#{file}"
      git_repo.link?(file, release)
    end
    
    def dir?(file, release='master')
      file = "packages/#{file}"
      git_repo.dir?(file, release)
    end

    def file(file, release='master')
      file = "packages/#{file}"
      git_repo.file(file, release)
    end

    def contents(path=nil, release='master')
      path = path ? File.join('packages', path) : 'packages'
      git_repo.tree_contents(path, release)
    end

    def find_commit(release)
      git_repo.find_commit(release)
    end
  end
end

require_relative 'repository/yum'
require_relative 'repository/apt'
