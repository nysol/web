#!/usr/bin/env ruby
# encoding: utf-8
require "rubygems"

spec = Gem::Specification.new do |s|
  s.name="nysol-web"
  s.version="3.0.0"
  s.author="NYSOL"
  s.email="info@nysol.jp"
  s.homepage="http://www.nysol.jp/"
  s.summary="nysol web tools"
	s.files=[
		"bin/myrgeo.rb",
		"bin/mtwsearch.rb",
		"bin/mtwstream.rb",
		"bin/mtwtimeline.rb",
		"bin/mtwjson2csv.rb"
	]
	s.bindir = 'bin'
	s.executables = [
		"mtwsearch.rb",
		"mtwstream.rb",
		"mtwtimeline.rb",
		"mtwjson2csv.rb",
		"myrgeo.rb"
	]
	s.require_path = "lib"
	s.description = <<-EOF
	  nysol web tools
	EOF
end
