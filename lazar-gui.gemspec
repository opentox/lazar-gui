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

  s.add_runtime_dependency "lazar", ">= 1.0.0"
  s.add_runtime_dependency "gem-path"
  s.add_runtime_dependency "sinatra"
  s.add_runtime_dependency "rdiscount"
  s.add_runtime_dependency "haml"
  s.add_runtime_dependency "sass"
  s.add_runtime_dependency "unicorn"

  s.post_install_message = %q{
  Service cmds:
    lazar-start &
    lazar-stop
  }
end
