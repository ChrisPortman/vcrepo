require 'spec_helper'

describe "Vcrepo::Repository" do
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
      Vcrepo::Repository::Yum.any_instance.stubs(:create_log).returns(true)
      Vcrepo::Repository::Yum.any_instance.stubs(:check_dir).returns('/dev/null')
      Vcrepo::Git.stubs(:new).returns(true)
      Vcrepo::Repository::Yum.any_instance.stubs(:repo_dir).returns('/dev/null')
    end

    it "should report that it cannot run if the repo is locked" do
      repo = Vcrepo::Repository::Yum.new('my_repo', 'local') 
      repo.expects(:locked?).returns(true)
      expect(repo.sync).to eq([402, "Sync is already in progress"])
    end

    it "should run if the repo is not locked" do
      repo = Vcrepo::Repository::Yum.new('my_repo', 'local') 
      repo.expects(:locked?).returns(false)
      repo.stubs(:execute_sync).returns(true)
      expect(repo.sync).to eq([ 200, "Sync of my_repo has been started." ])
    end
  end

end
