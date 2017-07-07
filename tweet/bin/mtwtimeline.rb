#!/usr/bin/env ruby
# encoding: utf-8

# 1.0: initial develpoment 2014/11/22
$version="1.0"
$revision="###VERSION###"

def help

STDERR.puts <<EOF
----------------------------
mtwtimeline.rb version #{$version}
----------------------------
概要) TwitterのREST APIを用いてパブリックストリーミングを取得
      詳細な仕様は以下のURLを参照の事。
      https://dev.twitter.com/rest/public

特徴) 1) 検索キーワードに一致するパブリックストリーミングを取得できる。
      2) ユーザリストを与えてタイムラインを取得できる。
			3) 結果は日別ディレクトリにjson形式で保存される。

事前に必要なこと)
      1) TwitterのApiキーを4種類取得すること。

用法) mtwtimeline.rb apikey= [kw=] [users=] [lang=] [tsize=] [maxid=] [sinceid=] [stop=] [O=] 

  apikey=  : TwitterのAPIキーを記述したファイル【必須】記述方法は以下の例を参照
  kw=      : 検索キーワードを指定する。and検索する場合は"A B"で可能
             検索キーワードに-RTを含めるとリツイートは除外される。
             複数の検索を連続で行う場合はキーワドをカンマで区切る。ex) A B,C
	users=   : screen_nameを記述したファイル。記述のあるscreen_nameのタイムラインが取得される。
  lang=    : 取得するツイートの言語を指定する。(ja:日本語,en:英語,fr:フランス語)
             その他の指定方法はhttps://dev.twitter.com/rest/reference/get/help/languagesを参照。
	tsize=   : 一つのjsonファイルに書き込むTweet数(default=1000)
  O=       : XML(もしくはjson)を保存するディレクトリ名【必須】
             もし既に存在して入れば、そのディレクトリに追加される。
             ただし、ファイル名が重複すれば上書きされる。
  maxid=   : 指定したツイートIDよりも古いツイートが取得される。
	sinceid= : 指定したツイートIDよりも新しいツイートが所得される。
  stop=    : ストップ条件(総件数,時間)
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

備考) ctr-cで終了しても、直前に取得したtweetまでjsonで保存される事が保証される。

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
require 'uri'
require 'nysol/mcmd'
require 'json'

args=MCMD::Margs.new(ARGV,"apikey=,kw=,users=,lang=,tsize=,maxid=,sinceid=,stop=,O=,","apikey=,O=")

# mcmdのメッセージは警告とエラーのみ
ENV["KG_VerboseLevel"]="2" unless args.bool("-mcmdenv")

apiKeyFile  = args.file("apikey=","r")
uFile       = args.file("users=","r")
kw          = args.str("kw=")
lang        = args.str("lang=")
maxid       = args.str("maxid=",nil)
sinceid     = args.str("sinceid=",nil)

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
oPath      = args.str("O=")
MCMD::mkDir(oPath)
oPath      = args.file("O=","w")


@startTime=Time.now
@userLists =Set.new


# mandatory parameters
apikey = args.file("apikey=")
if apikey==""
  raise "#ERROR# apikeyFile is specified."
end

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
  MCMD::msgLog("crawled tweets: #{@totalTw}")
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




#================================================================
# 概要：指定したユーザのフレンズ(フォローしているユーザ)を取得する
# Rate Limit : 15 times / 15 minits
#================================================================
def getFriends(client,userName)

  res=[]
  userList=userName.to_a

  userList.each{|user|
	
		#if client.follow!(user)
	  client.follow(user).each{|follow| 
#p follow
    }
  }

end


#================================================================
# 概要：指定したユーザのタイムラインを取得する
# Rate Limit : 180 times / 15 minits
# 1)最新の200件のTweetを取得する。
# 2)sinceIDを設定した場合、指定ID以降の最新200件のTweetを取得する。Tweet
#   の更新取得をする場合に利用
# 3)max_idを設定した場合、指定ID以前の最大200件のTweetを取得する。
#   最新200件 #  以上のTweetを取得する場合に利用。
#   ただし、API制約で3200件までしか遡れない。
#================================================================
def getTimeLine(client,userName,since_id,max_id,oPath)

	userList=userName.to_a

	timeLines=Array.new
	userList.each{|user|
  	#ユーザータイムライン取得実行
  	if max_id then
#puts "maxid"
  	  twt_tl = client.user_timeline(user, :count=>200, :max_id=>max_id)
 	  elsif since_id
#puts "since_id"
      twt_tl = client.user_timeline(user, :count=>200, :since_id=>since_id)
		else
#puts "other"
      twt_tl = client.user_timeline(user, :count=>200)
  	end

		twt_tl.each{|tl|

      timeLine=Hash.new

      timeLine["id_str"]                  = tl.id
      timeLine["screen_name"]             = user
      timeLine["favorite_count"]          = tl.favorite_count
      timeLine["filter_level"]            = tl.filter_level
      timeLine["in_reply_to_screen_name"] = tl.in_reply_to_screen_name
      timeLine["in_reply_to_status_id"]   = tl.in_reply_to_status_id
      timeLine["in_reply_to_user_id"]     = tl.in_reply_to_user_id
      timeLine["lang"]                    = tl.lang
      timeLine["retweet_count"]           = tl.retweet_count
      timeLine["source"]                  = tl.source
      timeLine["text"]                    = tl.text
      timeLine["url"]                     = tl.url
      
      @tweets<<timeLine
      @totalTw+=1
#	p tl.id
#	p tl.tl.user
#	p tl.filter_level
#	p tl.in_reply_to_screen_name
#	p tl.in_reply_to_status_id
#	p tl.in_reply_to_user_id
#	p tl.lang
#	p tl.retweet_count
#	p tl.source
#	p tl.text
#	p tl.url

#p @tweets.to_json

      max_id=timeLine["id_str"]
      if isWriteTiming? then
        writeRsl(@tweets,oPath)
        @tweets=[]
      end
      if isStopTiming? then
        writeRsl(@tweets,oPath) if @tweets.size>0
        break
      end
    }
	}	
end

# ---------------------------------------------------
# 概要：キーワードにHitしたTweetをn件取得する
# Rate Limit : 180 times / 15 minits
# 1)最新のn件のTweetを取得する。 count optionで指定
# 2)sinceIDを設定した場合、指定ID以降の最新100件のTweetを取得する。最も新しいtidを指定
# Tweetを更新取得をする場合に利用。
# 3)max_idを設定した場合、指定IDより過去の最大100件のTweetを取得する。最も古いtidを指定
# ただし、API制約で1週間前までしか遡れない。
# ---------------------------------------------------

def getKwTweet(client,kw,lang,max_id,since_id,oPath)

  #max_id=536844659700797440
	#since_id=536847285205090304
	userList=[]

	searchTerm = kw.split(",")
  searchTerm.each{|term|

		#　他のoptionはhttp://www.rubydoc.info/gems/twitter/Twitter/REST/Search#search-instance_methodを参照
	if max_id        # max_idより過去のツイートを取得
		maxid=max_id-1 # max_id-1で既に取得済みのTweet(max_id)を除く
    # take(10)を実際の運用時には外す
    #tws=client.search(term, :lang=>"#{lang}", :count=>100, :result_type=>"recent",:max_id=>"#{maxid}").take(10)
    tws=client.search(term, :lang=>"#{lang}", :count=>100, :result_type=>"recent",:max_id=>"#{maxid}")
	elsif since_id   # since_idより新しいツイートを取得
    tws=client.search(term, :lang=>"#{lang}", :count=>100, :result_type=>"recent",:since_id=>"#{since_id}")
	else             # 最新のツイートをcount件取得
    tws=client.search(term, :lang=>"#{lang}", :count=>100, :result_type=>"recent")
	end

	tws.each{|tweet|

    @tweets << tweet.attrs.dup
    @totalTw+=1
    max_id=tweet.attrs[:id_str]
    #userList<<tweet.attrs[:user][:id_str]
    userList<<tweet.attrs[:user][:screen_name] # timeLineはscreen_nameで取得
    if isWriteTiming? then
      writeRsl(@tweets,oPath)
      @tweets=[]
    end
    if isStopTiming? then
      writeRsl(@tweets,oPath) if @tweets.size>0
      break
    end
    }
	}
end


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


# create twitter client
client=mkClient(apiKeyFile)

userNames=[]
# crawling start
begin
  if kw 
    getKwTweet(client,kw,lang,maxid,sinceid,oPath)
	elsif uFile
		IO.foreach("#{uFile}") { |s| userNames << s.chomp }
	  getTimeLine(client,userNames,sinceid,maxid,oPath)
	end
rescue Interrupt # ctlr-c
  writeRsl(@tweets,oPath) if @tweets.size>0
end


#getFriends(client,userNames)


# end message
MCMD::endLog(args.cmdline)


