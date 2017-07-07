#!/usr/bin/env ruby
# encoding: utf-8

# 1.0: initial develpoment 2014/11/20
$version="1.0"
$revision="###VERSION###"

def help

STDERR.puts <<EOF
----------------------------
mtwst.rb version #{$version}
----------------------------
概要) TwitterのストリーミングAPIを用いてパブリックストリーミングを取得
      詳細な仕様は以下のURLを参照の事。
      https://dev.twitter.com/streaming/overview

特徴) 1) 検索キーワードに一致するパブリックストリーミングを取得できる。
      2) 取得する言語を選択できる。
      3) 結果は日別ディレクトリにjson形式で保存される。

事前に必要なこと)
      1) TwitterのApiキーを4種類取得すること。

用法) mtwst.rb apikey= [kw=] [lang=] [-RT] [tsize=] [stop=] [O=]

  apikey= : TwitterのAPIキーを記述したファイル【必須】記述方法は以下の例を参照
  kw=     : 検索キーワードを指定する。ただし日本語,韓国語,中国語は検索できない。詳細は以下のURL参照。
            https://dev.twitter.com/streaming/overview/request-parameters#track
  lang=   : 取得するツイートの言語を指定する。(ja:日本語,en:英語,fr:フランス語)
          : その他の指定方法はhttps://dev.twitter.com/rest/reference/get/help/languagesを参照。
  -RT     : リツイートも取得する(指定しなければリツイートは除外される)
  tsize=  : 一つのjsonファイルに書き込むtweet数(default=10000)
  O=      : 結果を保存するディレクトリ名【必須】
            このディレクトリに下に、結果出力時の日付に応じて日付ディレクトリ("YYYYMMDD")が作成され、
            その下に「連番.json」ファイルが作成される。
            本プログラムを再起動して同じディレクトリ名を指定しても、ファイルが上書きされることはない。
  stop=   : ストップ条件(総件数,時間)
          : 時間の場合: 数字の後にD(日),H(時),M(分),S(秒)のいずれかを付ければ時間、何も付けなければ取得件数により終了する。
          : このパラメータそのものを指定しなければストップ条件はなし。
          : 例) stop=1000 : 1000件取得して終了する。
          :     stop=10S  : 10秒間取得して終了する。
          :     stop=1D   : 1日間取得して終了する。

  apikeyファイルは以下に例示するようなjsonファイルで用意する。
    $ more apikey.json 
    {
    "consumer_key" : "Sri***",
    "consumer_secret" : "caL***",
    "access_token" : "831***",
    "access_token_secret" : "Iah***"
    }

備考) ctr-cで終了しても、直前に取得したtweetまでjsonで保存される事が保証される。
      取得速度は、kw=指定なしで50件/秒ほど(tsize=がデフォルトの10000で、一日430のJSONファイルが出力される計算)。
必要なrubyライブラリ)
  twitter
  json
  nysol

# Copyright(c) NYSOL 2012- All Rights Reserved.
EOF
exit
end

def ver()
  $revision ="0" if $revision =~ /VERSION/
  STDERR.puts "version #{$version} revision #{$revision}"
  exit
end

help() if ARGV[0]=="--help" or ARGV.size <= 0
ver()  if ARGV[0]=="--version"

require 'rubygems'
require 'twitter'
require 'nysol/mcmd'
require 'json'

args=MCMD::Margs.new(ARGV,"apikey=,kw=,lang=,O=,-RT,tsize=,stop=","apikey=,O=")

# mcmdのメッセージは警告とエラーのみ
ENV["KG_VerboseLevel"]="2" unless args.bool("-mcmdenv")

apiKeyFile = args.file("apikey=","r")
kw         = args.str("kw=")
lang       = args.str("lang=")
rt         = args.bool("-RT")

# parameters for conditions when write and stop
@tsize      = args.int("tsize=",10000)
stop        = args.str("stop=")
if stop=~/[DHMS]$/ then
	@stopType=stop[-1,1]
	@stopVal =stop.delete("DHMS").to_i
elsif stop
	@stopType="count"
	@stopVal =stop.to_i
else
	@stopType="infinite"
end
@totalTw=0 # total tweets clawled
@tweets=[] # store tweets here

# args.file cannot check writable status with directory with more than two layers
oPath      = args.str("O=")
MCMD::mkDir(oPath)
oPath      = args.file("O=","w")


@startTime=Time.now

def writeRsl(tweets,oPath)
	# create directory as current date
	time=Time.now
	oDir="#{oPath}/#{time.strftime("%Y%m%d")}"
	MCMD::mkDir(oDir)

	# count files under "oDir" directory in order to give the new file name as a number.
	fileCount=Dir["#{oDir}/*.json"].size

	# output json to the file
	File.open("#{oDir}/#{fileCount}.json","w"){|fpw|
		JSON.dump(tweets,fpw)
	}
	MCMD::msgLog("crawled tweets: #{@totalTw} (#{(@totalTw.to_f/(Time.now-@startTime).to_f*10.0).round/10.0} tweets/sec)")
end

def isWriteTiming?()
	if @totalTw % @tsize==0
		return true
	else
		return false
	end
end

def isStopTiming?()
#puts "type=#{@stopType} val=#{@stopVal}"
	result=false
	if @stopType=="count" then
		result=true if @totalTw >= @stopVal
	elsif "DHMS".include?(@stopType)
		duration=Time.now-@startTime
		if @stopType=="D"
			duration=duration/(60*60*24)
		elsif @stopType=="H"
			duration=duration/(60*60)
		elsif @stopType=="M"
			duration=duration/(60)
		elsif @stopType=="S"
			duration=duration
		end
		result=true if duration >= @stopVal
	end
	return result
end

###
# create twitter client
def mkClient(apiKeyFile)
	# get twitter api key in JSON format
	apiKey=nil
	File.open(apiKeyFile){|io| apiKey=JSON.load(io)}

  # create twitter client
  client = Twitter::Streaming::Client.new do |config|
      config.consumer_key        = apiKey["consumer_key"]
      config.consumer_secret     = apiKey["consumer_secret"]
      config.access_token        = apiKey["access_token"]
      config.access_token_secret = apiKey["access_token_secret"]
  end
	return client
end

###
# get tweets by keywords (english only)
def streaming_filter(client,keyWords,lang,rt,oPath)
	tries=5
	begin
		client.filter(:track => keyWords) {|tweet|
			next unless tweet.is_a?(Twitter::Tweet)
			next if not rt and tweet.text.index("RT")
			next if lang and tweet.user.lang==lang

			@tweets << tweet.attrs.dup
			@totalTw+=1
			if isWriteTiming? then
 				writeRsl(@tweets,oPath)
				@tweets=[]
			end
			if isStopTiming? then
 				writeRsl(@tweets,oPath) if @tweets.size>0
				break
			end
		}
	rescue EOFError => e
		if (tries-=1)>0 then
			sleep 10
			retry
		else
			MCMD::msgLog("EOF error occured after 5 times reconnection")
			raise e
		end
	end
end

###
# get tweets at random
def streaming_sample(client,lang,rt,oPath)
	tries=5
	sleepTime=10
	begin
		client.sample{|tweet|
			next unless tweet.is_a?(Twitter::Tweet)
			next if not rt and tweet.text.index("RT")
			next if lang and tweet.user.lang==lang

			@tweets << tweet.attrs.dup
			@totalTw+=1
			if isWriteTiming? then
 				writeRsl(@tweets,oPath)
				@tweets=[]
			end
			if isStopTiming? then
 				writeRsl(@tweets,oPath) if @tweets.size>0
				break
			end

			# reset error handling if tweets are successfully obtained
			tries=5
			sleepTime=10
		}
	rescue EOFError => e
		if (tries-=1)>0 then
			sleep sleepTime
			retry
		else
			MCMD::msgLog("EOF error occured after 5 times reconnection with #{sleepTime} sec")
			tries=5
			sleepTime*=2
			retry
		end
	end
end

# create twitter client
client=mkClient(apiKeyFile)

# crawling start
begin
	if kw
		streaming_filter(client,kw,lang,rt,oPath)
	else
		streaming_sample(client   ,lang,rt,oPath)
	end
rescue Interrupt # ctlr-c
	writeRsl(@tweets,oPath) if @tweets.size>0
end

# end message
MCMD::endLog(args.cmdline)

