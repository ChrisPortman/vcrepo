# Repo Manager

## Introduction

**This is alpha software that has limited testing and has yet to be deployed in a production environment**

This software allows for the creation of package repositories either by syncing them from upsream repositories or by generating them from local packages.  The repositories are maintained under GIT control so that you can arbitrarily revert to previous snapshots using standard GIT workflows.

## Installation
The Repo Manager is a ruby sinatra app.  It requires ruby >= 1.9.3 (due to the rugged gem that provides the GIT interface)

### High Level
1. Install ruby version 1.9.3 or better (I've been using 1.9.3).  Look at rbenv if your OS doesnt have it natively.
2. Install these gems:
  * sinatra
  * rugged (will need ruby-dev and cmake)
  * rack
3. Clone the source
```
git clone https://github.com/ChrisPortman/vcrepo.git /opt/vcrepo
```
4. Open the /opt/vcrepo/config.yaml file and update the `repo_base_location` to as appropriate.
5. From here you should be able to run with rackup:
```
cd /opt/vcrepo && rackup -p 80 config.ru
```
6. Browse to 'http://your.server'.  It will be pretty bare as there are no repos defined.

### Low Level (Ubuntu)

```
sudo -i
apt-get install ruby ruby-dev cmake createrepo yum-utils    # Mandatory packages
apt-get install lftp                                        # Required to sync repos from http sources
gem install sinatra rugged rack                             # Mandatory Gems
gem install rspec mocha                                     # Required for running tests when developing
git clone https://github.com/ChrisPortman/vcrepo.git /opt/vcrepo
cd /opt/vcrepo
cp config.yaml.sample config.yaml
vi config.yaml #update repo_base_dir, define repositories and save
rackup -p 80 config.ru
```

## Using the Software
### Defining Repos
Once installed, you need to define your repos.  The repo definitions live in the config.yaml.  In there, create a _repositories_ hash:
```
---
  repositories:
```

Then in there, define each repository. You should end up with something like this:
```
repositories:
  shinyrepo_myos_osvers_myarch:
    type: yum
    source: 'http://yum.puppetlabs.com/el/6/products/x86_64/'
```

The key for the repo, in this case 'shinyrepo_myos_osvers_myarch' can be whatever you like.  It will be what shows up in the list of repositories when you browse to / on your server.  The key/values inside the hash depend on the type of repository your creating.  In this case, its a yum (I havent implemented any other types yet) repository.  The source is where to get the packages from.

Valid source configs look like:

```
# Sync local packages.  Put the packages straight into the <repo_base_location>/<type>/repo_name/repo/ and run a sync.
source: local

# Sync packages from an HTTP location that has indexes enabled.
source: http://some.remote.server/package/dir/

# Sync from a public YUM repository that is defined in /etc/yum.repos.d/ (does not need to be enabled)
source: yum://yum_repos_d_config_name

# Sync from redhat protected repositories e.g, RHEL Server (see more below), that is defined in /etc/yum.repos.d/ (does not need to be enabled)
source: redhat_yum://yum_repos_d_config_name
```

### The Client
Vcrepo comes with a CLI client in the client directory of the source you just cloned.

```
[user@server repo]# cd /opt/vcrepo/client/bin
```

The client is basically just an interface to the server APIs.  Running the script without any arguments will produce help and a list of commands available:

```
[user@server bin]# ruby vcrepo.rb
Usage:
  vcrepo [OPTIONS] <command> [option [, option] ]
  vcrepo [OPTIONS] <command> help
  vcrepo [OPTIONS] help

Options:
  -h | --host : The server hosting the repos server (Default: localhost)

Valid commands:
  commit_list
  commit_tag
  repo_list
  repo_sync
  tag_delete
  tag_list
```

Running the script with a command followed by 'help' will tell you how to use that command:

```
[user@server bin]# ruby vcrepo.rb commit_tag help
Usage:
vcrepo.rb commit_tag <reponame> <commit_id> <tag_name>
```

### Syncing Repos
Once the repos have been defined, you need to sync them.  Using the CLI tool:
```
[user@server repo]# cd /opt/vcrepo/client/bin
[user@server repo]# ruby vcrepo.rb repo_list
---
- rhel6-x86_64-puppet_products
- rhel6-x86_64-gitlab
- rhel6-x86_64-updates
- rhel7-x86_64-updates
[user@server repo]# ruby vcrepo.rb repo_sync rhel6-x86_64-puppet_products
---
- Sync of rhel6-x86_64-puppet_products has been started.
```

This will initiate a repo sync.  It wont wait for it to finish though, it could take ages.  You can watch it grind away by tailing the log file for the repo, which by default is in /source_dir/logs/repo-name.log.

When its finished, browse to / on your server and click on your repo.  You should see packages and a repodata folder.  You can now use 'http://your.server/your_repo' in a yum config to give you machine access to the repo.

#### Syncing Local Repos
Local repos are maintained by manually placing packages into the repository and then running a sync against them.  Typically the process will look like this:

```
[user@server ~/]# cd /repo_base/yum/my_local_repo
[user@server my_local_repo]# git reset --hard master
[user@server my_local_repo]# cd repo/
[user@server repo]# wget http://some.server/package1.yum
[user@server repo]# wget http://some.server/package2.yum
...
[user@server repo]# wget http://some.server/packageN.yum
[user@server repo]# cd /opt/vcrepo/client/bin
[user@server bin]# ruby vcrepo.rb repo_sync my_local_repo
```

What happens is we change dir into the local repo's directory, make sure that the GIT work dir is on master:HEAD (99% of the time it will be already, but doesnt hurt to make sure), we get the new packages into the repo/ dir and then run the sync process.  Done.

#### Syncing Redhat Repos
Ahhh redhat and their locked down stuff.

You'll need to be running on a RHEL system and have that system subscribed to Redhat

```
[root@host]# subscription-manager register --username=rhuser --password=rhpass
```

Then add a Redhat Enterprise Linux entitlement to the system through their customer portal (or I believe you can do it using the subscription-manager tool).

Then in the samples directory, there are 2 .repo files for rhel6 and rhel7.  Copy either or both to /etc/yum.repos.d/.  These files contain all the repositories for the relevant versions of RHEL configured in a disabled state.  This means that yum (and thus, the reposync tool) will know about them, but wont try to install packages using them.

Lastly, when you subscribed the machine, it would have created client certs in /etc/pki./entitlement/.  Refer to config.yaml.sample and add the Redhat options to your config.yaml.

Now you can define Redhat RHEL repos.  Doing so is the same as the other types except your source will look like:

```
redhat_yum://repo-name
```

where repo-name is the name of the repo as defined in the rhel6/7.repo files in /etc/yum.repos.d/

### API
There is some documentation for the API in the [API Doc](docs/api.md)

### All the GIT Stuff
Once you've got to the point you've synced a repo and machines can use it, you can start managing your repository a bit more.

When the service starts up, it will check that 'repo_base_location' is a directory and create it if it can and needs to.  It will then, create the directory structure for each repo.  For yum repos, that looks like '/repo_base_location/type/your_repo/repo'.  Inside 'your_repo' it will initialise a GIT repository if its not already one.

What happens when a sync runs, is it mirrors all the packages into '/repo_base_location/type/reponame/repo/'.  In the case of local repos, you have already done that so it doesnt have to mirror anything.  It then looks for any package files in repos/ that are not links, moves them to 'your_repo/.git/packages/' and then symlinks them back to 'your_repo/repo/'.  It then generates the repo metadata and adds and commits it to git with a commit comment being the date and time. The commit contains all the *links* but not the packages (I tried commiting the packages. Worked fine with ~10, not so much with 1000).  Over time the .git/.packages directory will accumulate all the packages that the repo has seen, however, a given commit will only have links to a subset.

By default when you browse to / on your server, it will assume that you want to look at the HEAD of the master branch.  You can override this by browsing to /rev/branch|tag|commit_id/ and then into the desired repository.  You can also configure yum to use a url that include the branch, tag, or commit_id.

### Package Cache
All the packages that are synced into a repository are moved to the "package cache" and then symlinked back into the repository.  Its then the links that are version controlled in GIT rather than committing gigabytes of binary to the repo.

The package cache is at /repo_base_dir/package_cache/.  All the packages get lumped in there together.  That way they can be deduped if say, rhel and centos have the same packages.

### Intended Workflow
Basically the idea is to cron the syncing of the repos nightly.  Then there will be a nightly commit of in the GIT repo.  We will then be able to tag a specific commit as 'production', 'dev' whatever.  When we want to make new packages available to and environment, just move the tag and done.
