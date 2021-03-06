module Vcrepo
  class Repository
    attr_reader :name, :settings, :source, :type, :dir, :enabled, :git_repo, :logger

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

    def self.all
      repos = []
      Dir.glob(File.join( repo_configs_dir, '*.yaml' )).each do |f|
        repos.push( self.load( File.basename(f, '.yaml') ) )
      end
      repos
    end

    def self.all_enabled
      #Check the disabled ones
      self.all.select { |r| r.enabled }
    end

    def self.repo_configs_dir
      File.join(Vcrepo.config['repo_base_dir'], 'repos.d')
    end

    def self.config_file(name)
      File.join(self.repo_configs_dir, "#{name}.yaml")
    end

    def config_file
      File.join(self.class.repo_configs_dir, "#{name}.yaml")
    end

    def self.sync_all
      self.all.each.each do |name, repo|
        repo.sync
      end
    end

    def self.load(name)
      if @@repositories[name]
        settings = @@repositories[name]
      else
        begin
          settings = File::open(config_file(name), 'r') { |fh| YAML::load(fh) } || {}
        rescue Errno::ENOENT
          raise RuntimeError, "The config file for repo #{name} does not exist"
        rescue Errno::EACCES
          raise RuntimeError, "The config file for repo #{name} is not readable"
        end
        settings['name'] = name
        @@repositories[name] = settings
      end

      if type = settings['type']
        begin
          repo = self.const_get(type.capitalize).new(settings)
        rescue Exception => e
          puts e.message
          repo = Vcrepo::Repository.new(settings)
        end
      else
        repo = Vcrepo::Repository.new(settings)
      end
      repo
    end

    def initialize(settings)
      @name     = settings['name']
      @type     = settings['type'] || 'generic'
      @source   = settings['source']
      @enabled  = (@source and @type) ? true : false
      
      #Progress through setting up the repo as log as enabled remains true
      (@enabled = (@logger   = create_log                  ) ? true : false) if @enabled
      (@enabled = (@dir      = git_dir                     ) ? true : false) if @enabled
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
        generate_repo
        prepare_repo
        git_repo.commit
        logger.info('Sync complete')
      else
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

        sync_cmd = "#{`which lftp`.chomp} -c 'set net:reconnect-interval-base 0; mirror -P -c -e -L -vvv #{http_sync_includes} #{http_sync_excludes} #{@source} #{package_dir}'".gsub(/\s+/, ' ')

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

    def tmp_work_dir
      tmpdir = File.join(Vcrepo.config['repo_base_dir'], ".#{@name}")
      #create and use a temporary work dir so manual stuff in the normal work dir doesnt get in the way
      unless File.directory?(tmpdir)
        FileUtils.mkdir_p(tmpdir)
      end
      tmpdir
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
        end .compact.first
      end      

      dir = File.join([Vcrepo.config['repo_base_dir'], 'package_cache', extension, index_path].compact)
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      dir
    end

    def create_log
      log_dir  = Vcrepo.config['logdir'] || './logs'
      log_file = File.join(log_dir, name)
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

      package_files.flatten.sort.each do |file|
        link_package(file)
      end
    end

    def link_package(file, force=true)
      return if File.symlink?(file)

      if File.size?(file)
        packages_dir = package_cache_dir(file)
  
        newfile = File.join(packages_dir, File.basename(file))
        logger.info("Linking #{file} to #{newfile}")
        
        FileUtils.rm(newfile) if File.exists?(newfile) and force
        
        if File.exists?(newfile)
          logger.info("Package already in cache, removing and linking: #{newfile}")
          FileUtils.rm(file)
        else
          logger.info("Package NOT in cache, moving and linking: #{newfile}")
          FileUtils.mv(file, newfile)
        end
        
        FileUtils.ln_s(newfile, file)
      else
        FileUtils.rm(file)
      end
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
require_relative 'repository/iso'
