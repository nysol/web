require "bundler/gem_tasks"
iDic = "./bin"

fList = [
	iDic,
	"bin/myrgeo.rb",
	"bin/mtwsearch.rb",
	"bin/mtwstream.rb",
	"bin/mtwtimeline.rb",
	"bin/mtwjson2csv.rb"
]

directory iDic
file "bin/myrgeo.rb" => "yahoo_api/bin/myrgeo.rb" do |t|
	cp t.source, t.name
end

file "bin/mtwsearch.rb" => "tweet/bin/mtwsearch.rb" do |t|
	cp t.source, t.name
end
file "bin/mtwstream.rb" => "tweet/bin/mtwstream.rb" do |t|
	cp t.source, t.name
end

file "bin/mtwtimeline.rb" => "tweet/bin/mtwtimeline.rb" do |t|
	cp t.source, t.name
end
file "bin/mtwjson2csv.rb" => "tweet/bin/mtwjson2csv.rb" do |t|
	cp t.source, t.name
end

task "build" => fList do
end

