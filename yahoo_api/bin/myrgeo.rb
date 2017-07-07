#!/usr/bin/env ruby
# encoding: utf-8

# 1.0: initial development 2014/11/14
$version="1.0"
$revision="###VERSION###"

def help

STDERR.puts <<EOF
----------------------------
mgpmetis.rb version #{$version}
----------------------------
概要) Yahoo!ローカルサーチAPIを用いて逆ジオコーディング検索を行う
      詳細な仕様は以下のURLを参照の事。
      http://developer.yahoo.co.jp/webapi/map/openlocalplatform/v1/localsearch.html

特徴) 1) 緯度/経度を与えてその周辺のランドマークや住所を得る。
      2) 緯度経度はCSVの項目として与え、CSV上の全レコードに対応する結果が得られる。
      3) 結果はXMLもしくはjson形式で、緯度/経度ごとに一つのファイルに保存される。
      4) 検索範囲、業種、検索結果優先順位を指定することが可能。

事前に必要なこと)
      1) YahooIDを取得すること。
      2) アプリケーションIDを取得すること(https://e.developer.yahoo.co.jp/register)
         コマンドの実行には、このアプリケーションIDを指定しなければ動作しない。

用法) myahoogeo.rb appid= lat= lon= [dist=] [sort=] [gc=] [output=] [urlpar=] i= O= [try=] [--help]


  appid=  : YahooのアプリケーションID【必須】
  i=      : 緯度と経度の2項目を含む入力ファイル【必須】
  O=      : XML(もしくはjson)を保存するディレクトリ名【必須】
            もし既に存在して入れば、そのディレクトリに追加される。
            ただし、ファイル名が重複すれば上書きされる。
  lat=    : i=ファイル上の緯度項目名【必須】
  lon=    : i=ファイル上の軽度項目名【必須】
  dist=   : 検索範囲を半径(km)で指定する。小数点も指定可。
  results=: 取得する件数
  sort=   : 検索結果のソート順を指定する。
            dist: 2点間の直線距離順(default)
            score: 適合度順
            hybrid: 距離と適合度順
            review: 口コミ件数順
            kana: アイウエオ順
            price: 金額順
            geo: 球面三角法による2点間の距離順
  gc=     : 検索対象の業種コード
            01:グルメ,02:ショッピング,03:レジャー,04:暮らし
            より詳細なコードについては以下のURLを参照のこと。
            http://developer.yahoo.co.jp/webapi/map/openlocalplatform/genre.html
  ouput=  : 出力フォーマット(xml or json) デフォルトはxml
  urlpar= : yahooローカルサーチAPIに渡すその他のパラメータ
            ここで指定した文字列はurlエンコーディングされ、そのままurlの末尾に付加される
              ex) urlpar='results=10&coupon=true'
            単純にurlに付加するだけなので、不正なパラメータが指定されたときの動作保証はない。
  try=    : 実際に実行する行数(テスト目的で利用される)(省略すれば全行実行)


必要なrubyライブラリ)
	uri
	json
	rexml
	nysol

必要な外部コマンド)
  curl or wget

例)
    $ cat dat.csv
    latitude,longitude
    34.652536,135.506325
    34.7085,135.498583
    34.701889,135.494972

    $ myrgeo.rb appid=<ここにappidを指定> i=dat.csv lat=latitude lon=longitude O=result
    $ ls result # resultディレクトリに入力ファイルの行別に3つのXMLファイルが作成される
    0.xml 1.xml 2.xml

    $ cat 0.xml # 各XMLには、入力の緯度経度に近い複数のランドマークが格納される。 myrgeo要素には、指定したパラメータ値を属性として格納する。
    <myrgeo lineNo='0' lat='34.652536' lon='135.506325' appid='<指定したappid>' sort='geo' output='xml'>
      <YDF xmlns='http://olp.yahooapis.jp/ydf/1.0' totalResultsReturned='10' totalResultsAvailable='14817' firstResultPosition='1'>
        <ResultInfo>
          <Count>
            10
          </Count>
          <Total>
            14817
          </Total>
            :
        </ResultInfo>
        <Feature>
          <Id>
            5872904
          </Id>
            :

    # meach.rbコマンドを用いることで、各XMLファイル別にmxml2csvコマンドを適用して必要な項目を抜き出してCSVを出力する。
    $ meach.rb i=result/*.xml o=output.csv cmd='mxml2csv i=##file## k=/myrgeo/YDF/Feature f=/myrgeo@lineNo:lineNo,/myrgeo@lat:orgLat,/myrgeo@lon:orgLon,Name:name,Geometry/Coordinates:latlon'
    $ cat output.csv
    lineNo,orgLat,orgLon,name,latlon
    0,34.652536,135.506325,通天閣,"135.50638403839,34.652519052836"
    1,34.7085,135.498583,ホテル阪急インターナショナル,"135.498578944,34.708529737356"
    2,34.701889,135.494972,回転寿司がんこエキマルシェ大阪店,"135.49469057411,34.701838812217"

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

require "rubygems"
require "json"
require 'rexml/document'
require "nysol/mcmd"

args=MCMD::Margs.new(ARGV,"appid=,lat=,lon=,i=,O=,results=,output=,try=,gc=,dist=,sort=,urlpar=,T=,-mcmdenv,T=","appid=,lat=,lon=,i=,O=")

# mcmdのメッセージは警告とエラーのみ
ENV["KG_VerboseLevel"]="2" unless args.bool("-mcmdenv")

# コマンド実行可能確認
hasCurl=MCMD::chkCmdExe("curl","executable")
exit(1) unless hasCurl

#ワークファイルパス
if args.str("T=")!=nil then
	ENV["KG_TmpPath"] = args.str("T=").sub(/\/$/,"")
end

oPath  = args.file("O=","w")
ifile  = args.file("i=","r")
lat    = args.field("lat=",ifile)["names"][0]
lon    = args.field("lon=",ifile)["names"][0]
try    = args.int("try=")
urlpar = args.str("urlpar=")
urlparENC = URI.escape(urlpar) if urlpar

# mandatory parameters
appid =args.str("appid=")
if appid==""
  raise "#ERROR# blank appid is specified."
end

# parameters having default
sort  =args.str("sort=","geo")
output=args.str("output=","xml")

# optional parameters
gc     =args.str("gc=")      ; gcp  ="&gc=#{gc}"              if gc
dist   =args.str("dist=")    ; distp="&dist=#{dist}"          if dist
results=args.int("results=") ; resultsp="&results=#{results}" if results

MCMD::mkDir(oPath)

params="appid=#{appid}&sort=#{sort}&output=#{output}#{gcp}#{distp}#{resultsp}"

MCMD::mkDir(oPath)

wf=MCMD::Mtemp.new
xxout=wf.file

counter=0
MCMD::Mcsvin.new("i=#{ifile}"){|csv|
	csv.each{|flds|
		break if try && counter >= try
		latv=flds[lat]
		lonv=flds[lon]
		url="http://search.olp.yahooapis.jp/OpenLocalPlatform/V1/localSearch?lat=#{latv}&lon=#{lonv}&#{params}#{urlparENC}"

		puts   "curl -o #{xxout} '#{url}'"
		system "curl -o #{xxout} '#{url}'"

		if output=="xml" then
			rsl = REXML::Document.new(open("#{xxout}"))
			doc = REXML::Document.new
			ele = REXML::Element.new("myrgeo")
			ele.attributes["lineNo"]=counter
			ele.attributes["lat"]=latv
			ele.attributes["lon"]=lonv
			ele.attributes["urlpar"]=urlpar
			ele.attributes["appid"]=appid
			ele.attributes["sort"]=sort if sort
			ele.attributes["output"]=output if output
			ele.attributes["gc"]=gc if gc
			ele.attributes["dist"]=dist if dist
			doc.add(ele)
			doc.root.add(rsl.root)
			xml=""
			formatter = REXML::Formatters::Pretty.new
			formatter.write(doc,xml)
			open("#{oPath}/#{counter}.xml","w"){|fpw|
				fpw.write(xml)
			}
		else
# 検索結果なしの場合
# {"ResultInfo":{"Count":0,"Total":0,"Start":1,"Status":200,"Description":"","Copyright":"","Latency":0.036}}

			rsl=nil
			open(xxout){|io| rsl=JSON.load(io)}
			feature=rsl['Feature']
			name = feature[0]["Name"]
			MCMD::msgLog("#[#{counter}] closest point at (#{latv},#{lonv}): #{name}")

			rsl["appid"]=appid
			rsl["lineNo"]=counter
			rsl["lat"]=latv
			rsl["lon"]=lonv

			open("#{oPath}/#{counter}.json","w"){|fpw|
				JSON.dump(rsl,fpw)
			}
		end
		counter+=1
	}
}

# 終了メッセージ
MCMD::endLog(args.cmdline)

