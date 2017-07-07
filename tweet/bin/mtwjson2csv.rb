#!/usr/bin/env ruby
# encoding: utf-8

# 1.0: initial develpoment 2015/01/19
$version="1.0"
$revision="###VERSION###"

def help

STDERR.puts <<EOF
----------------------------
mtwjson2csv.rb version #{$version}
----------------------------
概要) mtwsearch.rb等のコマンドで取得したJSONファイル(twitter ver.1.1)をCSVに変換する
      リツイートのオリジナルツイートも出力されることに注意する。

用法) mtwjson2csv.rb i= o= [O=] [-org]

  i= : 入力JSONファイル【必須】
  o= : Tweetの出力CSVファイル【必須】
  O= : Tweetに付随するuser情報やentityデータを出力するパス【省略可】
         users.csv         : ユーザ情報 (entities,status,withheld_in_countries,withheld_scopeは出力されない)
         hashtags.csv      : ハッシュタグentity
         medias.csv        : メディアentity
         urls.csv          : URL entity
         user_mentions.csv : user_mentions entity
         retweet.csv       : リツイートの場合のオリジナルツイート
       各ファイルの出力項目の詳細はhttps://dev.twitter.com/overview/apiを参照されたい。
       基本的には、このURLに記述された名称が項目名として利用されている。
       ただし、tweet IDとuser IDは、tweetID,userIDで出力されている。

       o=ファイルに出力される項目のうち、リツイートに関する項目:
         rt : リツイートのオリジナルツイートであるかどうか(0 or 1)。あるツイートがリツイートの場合、
              そのオリジナルのツイートも全ての出力ファイルに出力されるが、それを区別するためのフラグ。
              実際に投稿されたツイートのみを選択したければ、この項目が0の行のみを選べばよい。
         rt_original_tweetID: あるツイートがリツイートの場合、オリジナルツイートのtweetID。 
                          その本人が投稿したツイートのみを選択したければこの項目がnullの行のみを選べばよい。
         次の項目は出力されない:
           current_user_retweet,place,scopes,withheld_copyright,withheld_in_countries,withheld_scope

  -org : 投稿テキスト中の改行削除を抑制する。
         このオプションを指定すると、テキスト項目に改行が入るので、CSVデータを表示した時に見にくくなることに注意する。
         ただし、ダブルクオーテーションで囲うことで妥当なCSVフォーマットが出力される。

必要なrubyライブラリ)
  json
  nysol
  date

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
require 'json'
require 'date'
require 'nysol/mcmd'

args=MCMD::Margs.new(ARGV,"i=,o=,O=,-org,err=","i=,o=")

# mcmdのメッセージは警告とエラーのみ
ENV["KG_VerboseLevel"]="2" unless args.bool("-mcmdenv")

jsonFile = args.file("i=","r")
tFile    = args.file("o=","w")
oPath    = args.file("O=","w")
errFile  = args.file("err=","w")
$orgText = args.bool("-org")

MCMD::mkDir(oPath) if oPath
uFile = "#{oPath}/users.csv"
hFile = "#{oPath}/hashtags.csv"
mFile = "#{oPath}/medias.csv"
rFile = "#{oPath}/urls.csv"
nFile = "#{oPath}/user_mentions.csv"

### get tweet body
$tNames=[]
$tNames << "tweetID"
$tNames << "userID"
$tNames << "created_at"
$tNames << "date"
$tNames << "time"
$tNames << "rt"
$tNames << "rt_original_tweetID"
$tNames << "text"
$tNames << "source"
$tNames << "truncated"
$tNames << "in_reply_to_status_id"
$tNames << "in_reply_to_user_id"
$tNames << "in_reply_to_screen_name"
$tNames << "logitude"
$tNames << "latitude"
$tNames << "contributors"
#$tNames << "current_user_retweet"
$tNames << "avorite_count"
$tNames << "favorited"
$tNames << "filter_level"
$tNames << "lang"
#place	Places
$tNames << "possibly_sensitive"
#scopes	Object
$tNames << "retweet_count"
$tNames << "retweeted"
#withheld_copyright	Boolean
#withheld_in_countries	Array of String
#withheld_scope	String
def getTweet(tweet,rt)
	flds=[]

	rt_original_tweetID=nil
	if tweet["retweeted_status"]
		rt_original_tweetID=tweet["retweeted_status"]["id"]
	end

	tweetID=tweet["id"]
	flds << tweetID
	flds << tweet["user"]["id"]
	if tweet["created_at"]
		flds << tweet["created_at"]
		dt=DateTime.parse(tweet["created_at"])
		flds << dt.strftime("%Y%m%d")
		flds << dt.strftime("%H%M%S")
	else
		flds << nil
		flds << nil
		flds << nil
	end
	flds << rt
	flds << rt_original_tweetID
	if $orgText
		flds << tweet["text"]
	else
		if tweet["text"]
			flds << tweet["text"].gsub("\r","").gsub("\n","")
		else
			flds << nil
		end
	end
	if tweet["source"]
		flds << tweet["source"].gsub(/<a.*?>/,"").gsub(/<\/a.*?>/,"")
	else
		flds << nil
	end
	flds << tweet["truncated"]
	flds << tweet["in_reply_to_status_id"]
	flds << tweet["in_reply_to_user_id"]
	flds << tweet["in_reply_to_screen_name"]
	dat=tweet["coordinates"]
	if dat
		flds << dat[0]
		flds << dat[1]
	else
		flds << nil
		flds << nil
	end
	flds << tweet["contributors"]

	#dat=tweet["current_user_retweet"]
	#if dat
	#	flds << dat["id"]
	#else
	#	flds << nil
	#end

	flds << tweet["avorite_count"]
	flds << tweet["favorited"]
	flds << tweet["filter_level"]
	flds << tweet["lang"]
#place	Places
	flds << tweet["possibly_sensitive"]
#scopes	Object
	flds << tweet["retweet_count"]
	flds << tweet["retweeted"]
#	flds << tweet["withheld_copyright"]
#withheld_in_countries	Array of String
#	flds << tweet["withheld_scope"]


	return tweetID,flds
end

### get user info
$uNames=[]
$uNames << "userID"
$uNames << "tweetID"
$uNames << "name"
$uNames << "screen_name"
$uNames << "location"
$uNames << "url"
$uNames << "description"
$uNames << "protected"
$uNames << "verified"
$uNames << "followers_count"
$uNames << "friends_count"
$uNames << "listed_count"
$uNames << "favourites_count"
$uNames << "statuses_count"
$uNames << "created_at"
$uNames << "date"
$uNames << "time"
$uNames << "utc_offset"
$uNames << "time_zone"
$uNames << "geo_enabled"
$uNames << "lang"
$uNames << "contributors_enabled"
$uNames << "is_translator"
$uNames << "profile_background_color"
$uNames << "profile_background_image_url"
$uNames << "profile_background_image_url_https"
$uNames << "profile_background_tile"
$uNames << "profile_link_color"
$uNames << "profile_sidebar_border_color"
$uNames << "profile_sidebar_fill_color"
$uNames << "profile_text_color"
$uNames << "profile_use_background_image"
$uNames << "profile_image_url"
$uNames << "profile_image_url_https"
$uNames << "default_profile"
$uNames << "default_profile_image"
$uNames << "following"
$uNames << "follow_request_sent"
$uNames << "notifications"
def getUser(tweet,tweetID)
	userID=nil
	flds=[]
	$uNames.each{|name|
		if name=="userID"
			userID=tweet["id"]
			flds << userID
		elsif name=="tweetID"
			flds << tweetID
		elsif name=="description"
			if $orgText
				flds << tweet[name]
			else
				if tweet[name]
					flds << tweet[name].gsub("\r","").gsub("\n","")
				else
					flds << nil
				end
			end
		elsif name=="created_at"
			if tweet[name]
				flds << tweet[name]
				dt=DateTime.parse(tweet[name])
				flds << dt.strftime("%Y%m%d")
				flds << dt.strftime("%H%M%S")
			else
				flds << nil
				flds << nil
				flds << nil
			end
		elsif name=="date" or name=="time"
			next
		else
			flds << tweet[name]
		end
	}
	return userID,flds
end

### get hashtags
$hNames=[]
$hNames << "tweetID"
$hNames << "hashtag"
$hNames << "indices_from"
$hNames << "indices_to"
def getHashtags(tweets,tweetID)
	return [] unless tweets
	hashtags=tweets["hashtags"]
	return [] unless hashtags

	lines=[]
	hashtags.each{|tweet|
		flds=[]
		flds << tweetID
		flds << tweet["text"]
		indices= tweet["indices"]
		flds << indices[0]
		flds << indices[1]
		lines << flds
	}
	return lines
end

### get medias
$mNames=[]
$mNames << "tweetID"
$mNames << "display_url"
$mNames << "expanded_url"
$mNames << "id"
$mNames << "media_url"
$mNames << "media_url_https"
$mNames << "small_h"
$mNames << "small_w"
$mNames << "small_resize"
$mNames << "thumb_h"
$mNames << "thumb_w"
$mNames << "thumb_resize"
$mNames << "medium_h"
$mNames << "medium_w"
$mNames << "medium_resize"
$mNames << "large_h"
$mNames << "large_w"
$mNames << "large_resize"
$mNames << "source_status_id"
$mNames << "type"
$mNames << "url"
$mNames << "indices_from"
$mNames << "indices_to"
def getMedias(tweets,tweetID)
	return [] unless tweets
	medias=tweets["media"]
	return [] unless medias

	lines=[]
	medias.each{|tweet|
		flds=[]
		flds << tweetID
		flds << tweet["display_url"]
		flds << tweet["expanded_url"]
		flds << tweet["id"]
		flds << tweet["media_url"]
		flds << tweet["media_url_https"]
		sizes=tweet["sizes"]
		if sizes then
			flds << sizes["small"]["h"]
			flds << sizes["small"]["w"]
			flds << sizes["small"]["resize"]
			flds << sizes["thumb"]["h"]
			flds << sizes["thumb"]["w"]
			flds << sizes["thumb"]["resize"]
			flds << sizes["medium"]["h"]
			flds << sizes["medium"]["w"]
			flds << sizes["medium"]["resize"]
			flds << sizes["large"]["h"]
			flds << sizes["large"]["w"]
			flds << sizes["large"]["resize"]
		else
			flds << nil ; flds << nil ; flds << nil
			flds << nil ; flds << nil ; flds << nil
			flds << nil ; flds << nil ; flds << nil
			flds << nil ; flds << nil ; flds << nil
		end
		flds << tweet["source_status_id"]
		flds << tweet["type"]
		flds << tweet["url"]
		indices= tweet["indices"]
		flds << indices[0]
		flds << indices[1]
		lines << flds
	}
	return lines
end

### get urls
$rNames=[]
$rNames << "tweetID"
$rNames << "indices_from"
$rNames << "indices_to"
$rNames << "url"
$rNames << "display_url"
$rNames << "expanded_url"
def getUrls(tweets,tweetID)
	return [] unless tweets
	urls=tweets["urls"]
	return [] unless urls

	lines=[]
	return lines unless urls
	urls.each{|tweet|
		flds=[]
		flds << tweetID
		indices= tweet["indices"]
		flds << indices[0]
		flds << indices[1]
		flds << tweet["url"]
		flds << tweet["display_url"]
		flds << tweet["expanded_url"]
		lines << flds
	}
	return lines
end

### get user_mentions
$nNames=[]
$nNames << "tweetID"
$nNames << "indices_from"
$nNames << "indices_to"
$nNames << "name"
$nNames << "screen_name"
$nNames << "id"
def getUsermentions(tweets,tweetID)
	return [] unless tweets
	ums=tweets["user_mentions"]
	return [] unless ums

	lines=[]
	return lines unless ums
	ums.each{|tweet|
		flds=[]
		flds << tweetID
		indices= tweet["indices"]
		flds << indices[0]
		flds << indices[1]
		flds << tweet["name"]
		flds << tweet["screen_name"]
		flds << tweet["id"]
		lines << flds
	}
	return lines
end

# output all fields to different files
def writeCSV(tweet,rt,tCSV,oCSVs)
	tweetID,body=getTweet(tweet,rt)
	tCSV.write(body)

	if oCSVs.size>0 then
		userID,user=getUser(tweet["user"],tweetID)
		oCSVs["uCSV"].write(user)

		hashtags=getHashtags(tweet["entities"],tweetID)
		hashtags.each{|hashtag|
			oCSVs["hCSV"].write(hashtag)
		}

		medias=getMedias(tweet["entities"],tweetID)
		medias.each{|media|
			oCSVs["mCSV"].write(media)
		}

		urls=getUrls(tweet,tweetID)
		urls.each{|url|
			oCSVs["rCSV"].write(url)
		}

		user_mentions=getUsermentions(tweet,tweetID)
		user_mentions.each{|user_mention|
			oCSVs["nCSV"].write(user_mention)
		}
	end
end

def writeErrCSV(tweet,rtFlag,e,errCSV)
	tweetID=tweet["id"]
	msg="#{e.message}: #{e.backtrace[0]} in tweet #{tweetID}"
	msg << " (retweet)" if rtFlag

	errCSV.write([tweetID,msg])
	MCMD::warningLog(msg)
end

####### Entry Point

# read JSON file
json=open(jsonFile){|json_fp| JSON.load(json_fp)}

# open write files
tFldNames=$tNames.join(',') # tweet body
tCSV=MCMD::Mcsvout.new("o=#{tFile} f=#{tFldNames}")

errCSV=MCMD::Mcsvout.new("o=#{errFile} f=tweetID,msg")

oCSVs={}
if oPath then
	uFldNames=$uNames.join(',') # user info
	oCSVs["uCSV"]=MCMD::Mcsvout.new("o=#{uFile} f=#{uFldNames}")
	hFldNames=$hNames.join(',') # hashtags
	oCSVs["hCSV"]=MCMD::Mcsvout.new("o=#{hFile} f=#{hFldNames}")
	mFldNames=$mNames.join(',') # medias
	oCSVs["mCSV"]=MCMD::Mcsvout.new("o=#{mFile} f=#{mFldNames}")
	rFldNames=$rNames.join(',') # urls
	oCSVs["rCSV"]=MCMD::Mcsvout.new("o=#{rFile} f=#{rFldNames}")
	nFldNames=$nNames.join(',') # user_mentions
	oCSVs["nCSV"]=MCMD::Mcsvout.new("o=#{nFile} f=#{nFldNames}")
end

### main routine
json.each{|tweet|
	begin
		rtFlag=0
		writeCSV(tweet,rtFlag,tCSV,oCSVs)

		retweet=tweet["retweeted_status"]
		if retweet
			rtFlag=1
			writeCSV(retweet,rtFlag,tCSV,oCSVs)
		end
	rescue => e
		writeErrCSV(tweet,rtFlag,e,errCSV)
		next
	end
}


# close write files
tCSV.close
errCSV.close
if oCSVs.size>0 then
	oCSVs["uCSV"].close
	oCSVs["hCSV"].close
	oCSVs["mCSV"].close
	oCSVs["rCSV"].close
	oCSVs["nCSV"].close
end

# end message
MCMD::endLog(args.cmdline)

