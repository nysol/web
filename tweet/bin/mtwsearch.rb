#!/usr/bin/env ruby
# encoding: utf-8

# 1.0: initial develpoment 2014/11/26
# 1.1: debug for stopping in some errors, simplify the parameters 2015/08/14
$version="1.1"
$revision="###VERSION###"

def help

STDERR.puts <<EOF
----------------------------
mtwsearch.rb version #{$version}
----------------------------
概要) TwitterのSeach APIを用いて検索条件にマッチしたTweetを取得
      APIの詳細な仕様は以下のURLを参照の事。
      https://dev.twitter.com/rest/public

特徴) 1) 検索条件(キーワードや言語など)に一致するパブリックストリーミングを取得できる。
      2) 過去のツイートをできる限り多く取得するモード(-past)を指定できる。
			3) Stream APIのように現在のツイートを取得し続けるモード(-stream)を指定できる。
      4) -pastと-streamを同時に指定することも可能。
      5) 結果は日別ディレクトリに連番のjson形式で保存される。

事前に必要なこと)
      1) TwitterのApiキーを4種類取得すること。

用法) mtwsearch.rb apikey= [query=] [lang=] [geocode=] [stop=] [-past|-stream] O= [info=]

  apikey=  : TwitterのAPIキーを記述したファイル【必須】記述方法は以下の例を参照
  query=   : クエリーを指定する。
	-past    : 過去のツイートを可能な限り取得しに行く。180回/15分のrequestを使い切ったら、sleepした後に再取得しにいく。
           : -pastを付けなければ、requestを使い切ったら終了する。
	-stream  : 現在のツイートを取得しに行く。stop=を指定しなければ永久に取得し続ける。
           : 正確には、最初のsearchのみ過去を遡って取得し、
           : 取得できなくなる、もしくは180requestを使い果たした後、現在のツイートを取得していく。
           : 現在のツイートを取得しきったら、15分間sleepして再度取得しにいく。
           : -pastと-streamを同時に指定した場合、まず-pastモードで実行され、終了後に-streamモードへと切り替わる。
           : -pastで取得したツイートと-streamで取得したツイートが重複することはない。
  lang=     : 取得するツイートの言語を指定する。(ja:日本語,en:英語,fr:フランス語,デフォルトは全言語対象) ex: lang=ja
              その他の指定方法はhttps://dev.twitter.com/rest/reference/get/help/languagesを参照。
  geocode=  : 検索対象の地理的範囲。緯度,経度,範囲半径 ex: geocode="34.701889,135.494972,1mi"

  O=        : 取得した全ツイート(status)をJSONで保存するディレクトリ名【必須】
            : このディレクトリに下に、結果出力時の日付に応じて日付ディレクトリ("YYYYMMDD")が作成され、
            : その下に「連番.json」ファイルが作成される。
            : 本プログラムを再起動して同じディレクトリ名を指定しても、ファイルが上書きされることはない。
	info=     : 取得情報ファイル名(json形式による)
            :   smallestID: 最小の(最も古い)ツイートID
            :   biggestID : 最大(最新)のツイートID
            :   total     : 取得件数
            :   elapse    : 経過時間
  stop=     : ストップ条件(総件数,時間)
            : 時間の場合: 数字の後にD(日),H(時),M(分),S(秒)のいずれかを付ければ時間、何も付けなければ取得件数により終了する。
            : このパラメータそのものを指定しなければストップ条件はなし。
            : 例) stop=10000 : 10000件取得して終了する。
            :     stop=10S   : 10秒間取得して終了する。
            :     stop=1D    : 1日間取得して終了する。

  apikeyファイルは以下に例示するようなjsonファイルで用意する。
    $ more apikey.json 
    {
    "consumer_key" : "Sri・・・",
    "consumer_secret" : "caL・・・",
    "access_token" : "831・・・",
    "access_token_secret" : "Iah・・・"
    }

  クエリー例
    query='選挙 当選' : 「選挙」と「当選」の両方を含む
    query='"twitter api"' : 「twitter api」を含む
    query='選挙 OR 当選' : 「選挙」もしくは「当選」の両方を含む
    query='選挙 -当選' : 「選挙」を含み、かつ「当選」を含まない
    query='#haiku' : ハッシュタグ「#haiku」を含む
    query='from:abc' : ユーザabcから発信されたツイート
    query='to:abc' : ユーザabcへ発信したツイート
    query='@abc' : ユーザabcへのリプライツイート
    query='選挙 since:2014-11-01' : 2014/11/01以降で「選挙」を含むツイート
    query='選挙 until:2014-11-01' : 2014/11/01以前で「選挙」を含むツイート
    より詳細は、https://dev.twitter.com/rest/public/searchを参照のこと。

備考) Search APIは15分に180 requestsの制限がある。それを超えて取得しに行こうとすると自動的に15分間休眠する。
      1回のsearch requestあたり100ツイートが取得される。
      一つのファイルに保存される最大数は、18000ツイート(100ツイート×180requests)。

必要なrubyライブラリ)
  twitter 5.13.0以降
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

gem 'twitter','>=5.13.0'
require 'rubygems'
require 'twitter'
require 'json'
require 'nysol/mcmd'

args=MCMD::Margs.new(ARGV,"apikey=,query=,lang=,geocode=,stop=,O=,info=,-past,-stream","apikey=,query=,O=")

# mcmdのメッセージは警告とエラーのみ
ENV["KG_VerboseLevel"]="2" unless args.bool("-mcmdenv")

ApiKeyFile  = args.file("apikey=","r")
Query       = args.str("query=")
Lang        = args.str("lang=")
Geocode     = args.str("geocode=")
Past        = args.bool("-past")
Stream      = args.bool("-stream")

# parameters for conditions when write and stop
@tsize      = args.int("tsize=",1000)
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
Opath      = args.file("O=","w")
MCMD::mkDir(Opath)

infoFile   = args.file("info=","w")

@startTime=Time.now

@smallestID="A" # id_str as a string number is never greater than "A".
@biggestID =" " # id_str as a string number become never greater than " ".

MAXTRY=5  # how many times to retry when error occur.

#####
# create twitter client
def mkClient(apiKeyFile)
  apiKey=nil
  File.open(apiKeyFile){|io| apiKey=JSON.load(io)}

  # create twitter client
  client = Twitter::REST::Client.new do |config|
      config.consumer_key        = apiKey["consumer_key"]
      config.consumer_secret     = apiKey["consumer_secret"]
      config.access_token        = apiKey["access_token"]
      config.access_token_secret = apiKey["access_token_secret"]
  end
  return client
end


def writeRsl(tweets,oPath)

	return if tweets.size==0

	# get min or max id_str
	tweets.each{|attrs|
		id=attrs[:id_str]
		@smallestID=id if id<@smallestID
		@biggestID =id if id>@biggestID
	}

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
  MCMD::msgLog("total tweets: #{@totalTw}")
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

def sleeping(seconds,msg)
	# considering the stop condition by time
  if "DHMS".include?(@stopType)
    remaining=@stopVal-(Time.now-@startTime).to_i
#puts "time=#{Time.now} start=#{@startTime} seconds=#{seconds} duration=#{remaining}"
		seconds=remaining if seconds>remaining
	end
	MCMD::msgLog("#{msg}, sleeping for #{seconds} seconds")
	sleep(seconds)
end

###

# return the remaining number of request and seconds for resetting the rateLimit
def getLimits(client)

	rate_limit_status=Twitter::REST::Request.new(client,"get","/1.1/application/rate_limit_status.json").perform

	# the number of requrests rmaining
	remaining=rate_limit_status[:resources][:search][:"/search/tweets"][:remaining]

	# seconds until resetting the rateLimit
	t=rate_limit_status[:resources][:search][:"/search/tweets"][:reset]

	MCMD::msgLog("# getLimits: remaining=#{remaining}, sec=#{t-Time.now.to_i}")
	return remaining,t-Time.now.to_i
end

###
# get tweets matching to the conditions
#   query   : query string, which will be url encoded in the method.
#   max_id  : searching only tweets whose id is smaller than or equal to this value.
#   since_id: searching only tweets whose id is bigger than this value.
def getTweets(client,query,count,max_id,since_id,lang,geocode,msg=nil)

	@tweets=[]

	params=""
	params << ",:count => #{count}"               if count
	params << ",:max_id=>\"#{max_id}\""           if max_id
	params << ",:since_id=>\"#{since_id}\""       if since_id
	params << ",:lang=>\"#{lang}\""               if lang
	params << ",:geocode=>\"#{geocode}\""         if geocode

	tries=MAXTRY
	tws=nil
	begin
		MCMD::msgLog("### client.search: '#{query}' #{params} (#{msg})")
		eval "tws=client.search('#{query}' #{params})"

		tws.each{|tweet|
			@tweets << tweet.attrs.dup
			@totalTw+=1

			MCMD::msgLog("#{@totalTw} date=#{@tweets.last[:created_at]}") if @totalTw % 100==0
			tries=MAXTRY # clear retry counter here
			break if isStopTiming?
		}

		rescue Twitter::Error::TooManyRequests => e
			return

	rescue => e
		if (tries-=1)>0 then
			MCMD::msgLog("Error occured while getting tweets, retrying... (#{tries}): #{e.message}")
			sleep 10*3**(MAXTRY-tries-1)+10
			retry
		else
			MCMD::msgLog("could not solve the error after retried #{MAXTRY} times: #{e.message}")
			raise
		end
	end
end


#####
# run the Search API as the Streaminig API
def crawling(past,stream,client,query,lang,geocode,oPath)

	pastMode=false
	strmMode=false
	pastMode=true if past
	strmMode=true if stream

	max_id=nil    # get tweets until max_id
	since_id=nil  # get tweets since since_id

	while true
		msg=nil
		if pastMode
			msg="past mode"
		elsif strmMode
			msg="stream mode"
		end

		getTweets(client,query,100  ,max_id,since_id,lang,geocode,"#{msg},max_id:#{max_id},since_id:#{since_id}")

		## check remaining requests and seconds to reset
		remaining,seconds=getLimits(client)

		# check stop condition
		break if isStopTiming?

		# could not get any tweets
		if @tweets.size==0
			if pastMode then
				pastMode=false
			else
				sleeping(60*15,"no results found")
			end
		end

		# output the results, and update smallest or biggest id_str
 		writeRsl(@tweets,oPath)

		# preparing for getting the next tweets
		if pastMode then
			max_id=(@smallestID.to_i-1).to_s
			since_id=nil
		elsif strmMode then
			max_id=nil
			since_id=@biggestID
		else
			break
		end

		# wait if no remaining requests left
		if remaining==0
			sleeping(seconds,"no remaining requests left")
		end
	end
end

# create twitter client
client=mkClient(ApiKeyFile)

# crawling start
begin
	crawling(Past,Stream,client,Query,Lang,Geocode,Opath)

rescue Interrupt # ctlr-c
	MCMD::msgLog("pressed ctrl-c, saving the results")
  writeRsl(@tweets,Opath) if @tweets.size>0

rescue =>e
	MCMD::msgLog("unknown error occured: #{e.message}")

ensure
	# output the latest tweet ID, by which user can specify with scince_id= in the next crawling.
	results={}
	results["smallestID"]=@smallestID
	results["biggestID"] =@biggestID
	results["total"]     =@totalTw
	results["elapse"]    =(Time.now-@startTime).to_i
	if infoFile then
		File.open(infoFile,"w"){|fpw|
			JSON.dump(results,fpw)
		}
	end
	MCMD::msgLog(JSON.dump(results))
end

# end message
MCMD::endLog(args.cmdline)

