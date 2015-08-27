# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "lazar-gui"
  s.version     = File.read("./VERSION")
  s.authors     = ["Christoph Helma","Denis Gebele"]
  s.email       = ["helma@in-silico.ch","gebele@in-silico.ch"]
  s.homepage    = "http://github.com/opentox/lazar-gui"
  s.summary     = %q{lazar-gui}
  s.description = %q{Graphical User Interface for Lazar Toxicology Predictions}
  s.license     = 'GPL-3'

  s.rubyforge_project = "lazar-gui"

  s.files       = `git ls-files`.split("\n")
  s.required_ruby_version = '>= 1.9.2'

  #s.add_runtime_dependency "opentox-server"
  s.add_runtime_dependency "lazar"
  s.add_runtime_dependency "sinatra"
  s.add_runtime_dependency "haml"
  s.add_runtime_dependency "sass"
  s.add_runtime_dependency "unicorn"
end
