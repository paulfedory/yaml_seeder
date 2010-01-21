require 'rake'
spec = Gem::Specification.new do |s|
  s.name = 'yaml_seeder'
  s.version = '0.0.1'
  s.summary = 'Seeds your ActiveRecord models from YAML files'
  s.description = 'Seeds your ActiveRecord models from YAML files, when the YAML files are formatted like test fixtures.'
  s.author = 'Paul Fedory'
  s.homepage = 'http://github.com/paulfedory/yaml_seeder'
  s.extra_rdoc_files = [
   "MIT-LICENSE",
   "README.rdoc"
  ]
  s.has_rdoc = true

  s.files = FileList['lib/**/*.rb', '[A-Z]*'].to_a


 end
