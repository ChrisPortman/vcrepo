

Fabricator(:rugged, :class_name => Rugged::Repository) do

end

Fabricator(:git, :class_name => Vcrepo::Git) do
  real_workdir '/dev/null'
  repo         { Fabricate(:rugged) } 
  package_repo 'package_repo'
end

Fabricator(:repository, :class_name => Vcrepo::Repository::Yum ) do
  name     = name
  source   = source
  type     = 'yum'
  enabled  = true
end
