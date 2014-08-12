require 'spec_helper'

describe "Vcrepo::Repository" do
  before :each do
    Vcrepo.config.stubs(:[]).with('repo_base_dir').returns('/tmp/test_repos/')
    Vcrepo.config.stubs(:[]).with('repositories').returns({ 'test_repo' => { 'type' => 'yum', 'source' => 'local' } })
    Vcrepo.config.stubs(:[]).with('git_author_name').returns(nil)
    Vcrepo.config.stubs(:[]).with('git_author_email').returns(nil)

    logger = mock()
    Vcrepo::Repository.any_instance.stubs(:create_log).returns(logger)
    Vcrepo::Repository.any_instance.stubs(:logger).returns(logger)
    logger.stubs(:info).returns(true)
  end

  after :each do
    FileUtils.rm_rf('/tmp/test_repos/')
  end

  context "self.find" do
    before :each do
      repos = {
        'my_repo_1' => 'my_repo_1_test',
        'my_repo_2' => 'my_repo_2_test',
        'my_repo_3' => 'my_repo_3_test',
      }

      Vcrepo::Repository.stubs(:all).returns(repos)
    end

    it "Should return the repository that matches a name" do
      expect(Vcrepo::Repository.find('my_repo_2')).to eq('my_repo_2_test')
    end

    it "Sould return nil if the repository does not exist" do
      expect(Vcrepo::Repository.find('my_repo_4')).to be_nil
    end
  end

  context "sync_all" do
    before :each do
      localrepo = mock()
      httprepo  = mock()

      repos = {
        'local' => localrepo,
        'http'  => httprepo,
      }

      repos.each do |k,v|
        #Expect .sync to run on each one 
        v.expects(:sync).returns(true)
      end

      Vcrepo::Repository.stubs(:all).returns(repos)
    end

    it "should call the sync method for each repo" do
      #This will fail if the sync method is called on each repo <> 1 times
      Vcrepo::Repository.sync_all
    end
  end

  context "sync" do
    before :each do
      Vcrepo::Repository.any_instance.stubs(:check_dir).returns('/dev/null')
      Vcrepo::Git.stubs(:new).returns(true)
      Vcrepo::Repository.any_instance.stubs(:package_dir).returns('/dev/null')
    end

    it "should report that it cannot run if the repo is locked" do
      repo = Vcrepo::Repository.new('my_repo', 'local') 
      repo.expects(:locked?).returns(true)
      expect(repo.sync).to eq([402, "Sync is already in progress"])
    end

    it "should run if the repo is not locked" do
      repo = Vcrepo::Repository.new('my_repo', 'local') 
      repo.expects(:locked?).returns(false)
      repo.stubs(:execute_sync).returns(true)
      expect(repo.sync).to eq([ 200, "Sync of my_repo has been started." ])
    end
  end
  
  context "execute_sync" do
    it "should call certain processes for local repos" do
      repo = Vcrepo::Repository.new('test_repo', 'local')
      repo.expects(:lock).returns(true)
      Vcrepo::Git.any_instance.expects(:safe_checkout).returns(true)
      repo.expects(:prepare_repo).returns(true)
      Vcrepo::Git.any_instance.expects(:commit).returns(true)
      Vcrepo::Git.any_instance.expects(:reset_workdir).returns(true)
      repo.expects(:unlock).returns(true)
      repo.execute_sync
    end
  end
  
  context "lock" do
    it "Should create a lock file in the GIT directory" do
      repo = Vcrepo::Repository.new('test_repo', 'local')
      expect(File.exists?('/tmp/test_repos/generic/test_repo/.git/.locked')).to be false
      repo.lock
      expect(File.exists?('/tmp/test_repos/generic/test_repo/.git/.locked')).to be true
    end
  end
      
  context "unlock" do
    it "Should create a lock file in the GIT directory" do
      repo = Vcrepo::Repository.new('test_repo', 'local')
      repo.lock
      expect(File.exists?('/tmp/test_repos/generic/test_repo/.git/.locked')).to be true
      repo.unlock
      expect(File.exists?('/tmp/test_repos/generic/test_repo/.git/.locked')).to be false
    end
  end

  context "locked?" do
    it "Should be false before a repo is locked" do
      repo = Vcrepo::Repository.new('test_repo', 'local')
      expect(File.exists?('/tmp/test_repos/generic/test_repo/.git/.locked')).to be false
      expect(repo.locked?).to be false
    end

    it "Should be true after a repo is locked and without it being unlocked" do
      repo = Vcrepo::Repository.new('test_repo', 'local')
      repo.lock
      expect(File.exists?('/tmp/test_repos/generic/test_repo/.git/.locked')).to be true
      expect(repo.locked?).to be true
    end

    it "Should be false after being locked and unlocked" do
      repo = Vcrepo::Repository.new('test_repo', 'local')
      repo.lock
      expect(File.exists?('/tmp/test_repos/generic/test_repo/.git/.locked')).to be true
      repo.unlock
      expect(File.exists?('/tmp/test_repos/generic/test_repo/.git/.locked')).to be false
      expect(repo.locked?).to be false
    end
  end

  context "git_dir" do
    it "should create the directory tree to the repo" do
      Vcrepo::Git.stubs(:new).returns(true)
      Vcrepo::Repository.any_instance.stubs(:package_dir).returns('/dev/null')

      #stub check_dir so that it does nothing when the repo obj is instantiated.
      #then create the repo, unstub check_dir and then run check_dir in isolation
      Vcrepo::Repository.any_instance.stubs(:git_dir).returns(true)
      repo = Vcrepo::Repository.new('test_repo', 'local')
      Vcrepo::Repository.any_instance.unstub(:git_dir)

      expect(File.directory?('/tmp/test_repos/generic/test_repo/')).to be false
      repo.git_dir
      expect(File.directory?('/tmp/test_repos/generic/test_repo/')).to be true
    end
  end

  context "sync_http" do
    it "should raise an error if lftp is not available" do
      repo = Vcrepo::Repository.new('test_repo', 'local')
      repo.expects(:system).with('which lftp > /dev/null 2>&1').returns(false)
      expect{repo.sync_http}.to raise_error(RepoError)
    end
    
    describe "runs lftp with the appropriate options" do
      it "for yum repos that add includes and exclues options" do
        repo = Vcrepo::Repository::Yum.new('test_repo', 'local', 'yum')
        repo.expects(:system).with('which lftp > /dev/null 2>&1').returns(true)
        repo.expects(:`).with('which lftp').returns('/bin/lftp')
        
        excludes = [ "-X \"/headers/\"", "-X \"/repodata/\"", "-X \"/SRPMS/\"", "-X \"*.src.rpm\"" ].join(' ')
        includes = "-I *.rpm"
        
        #Expected sync command 
        sync_cmd = "/bin/lftp -c '; mirror -P -c -e -L -vvv #{includes} #{excludes} local /tmp/test_repos/yum/test_repo/packages'"
        IO.expects(:popen).with(sync_cmd).returns([])
  
        repo.sync_http
      end
      
      it "for generic repos that DO NOT add includes and exclues options" do
        repo = Vcrepo::Repository.new('test_repo', 'local')
        repo.expects(:system).with('which lftp > /dev/null 2>&1').returns(true)
        repo.expects(:`).with('which lftp').returns('/bin/lftp')
        
        #Expected sync command 
        sync_cmd = "/bin/lftp -c '; mirror -P -c -e -L -vvv local /tmp/test_repos/generic/test_repo/packages'"
        IO.expects(:popen).with(sync_cmd).returns([])
  
        repo.sync_http
      end

    end
  end
end
