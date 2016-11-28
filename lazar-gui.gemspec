# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "lazar-gui"
  s.version     = File.read("./VERSION")
  s.authors     = ["Christoph Helma","Denis Gebele"]
  s.email       = ["helma@in-silico.ch","gebele@in-silico.ch"]
  s.homepage    = "http://github.com/opentox/lazar-gui"
  s.summary     = %q{lazar-gui}
  s.description = %q{Graphical User Interface for Lazar Toxicology Predictions}
  s.license     = 'GPL-3.0'
  s.executables = ["lazar-start", "lazar-stop"]
  s.rubyforge_project = "lazar-gui"
  s.files       = `git ls-files`.split("\n")

  s.add_runtime_dependency "lazar"
  s.add_runtime_dependency "gem-path", "~> 0.6.1", '>= 0.6.1'
  s.add_runtime_dependency "sinatra", "~> 1.4.0", '>= 1.4.0'
  s.add_runtime_dependency "rdiscount", "~> 2.1.0", '>= 2.1.0'
  s.add_runtime_dependency "haml", "~> 4.0.0", '>= 4.0.0'
  s.add_runtime_dependency "sass", "~> 3.4.0", '>= 3.4.0'
  s.add_runtime_dependency "unicorn", "~> 5.1.0", '>= 5.1.0'

  s.post_install_message = %q{
  Service cmds:
    lazar-start &
    lazar-stop
  }
end
