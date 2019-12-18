

#		Questrade API
#	Tommy Freethy - February 2019
#
# Questrade API documentation can be found here: https://www.questrade.com/api/documentation
#
# I currently use the API to analyse symbols on the TSX, NASDAQ, and NYSE. I am able to do fundamental
# and technical analyses with the data provided.
#
# The data streaming capabilities are quite rich and frequent. There is a lot of potential here with 
# getting real time alerts on price action or news.
#
# Questrade also provides data on options. I would really like to study up on options and create an
# effective script for monitoring options.


package require http
package require tls
package require json
package require csv
package require tcom
package require websocket

namespace eval questrade_api {
	variable _access_token ""
	variable _refresh_token ""
	variable _api_address ""
	
	variable _customer_id "******************************"
	
	variable _tsx_symbolIds_file "c:/tbf/tcl_source/questrade_tsx_symbolIds.txt"
	variable _nasdaq_symbolIds_file "c:/tbf/tcl_source/questrade_nasdaq_symbolIds.txt"
	variable _nyse_symbolIds_file "c:/tbf/tcl_source/questrade_nyse_symbolIds.txt"
	variable _api_options_file "c:/tbf/tcl_source/api_options.txt"
	
	proc main {} {
		http::register https 443 [list questrade_api::sni_socket -tls1 1]

		authorize
		if {1} {
			ping_server
		} {
			# get_symbol_id "ACB"
			
			# get_daily_rsi [get_symbol_id "WEED.TO"]
			# get_daily_rsi [get_symbol_id "LNF.TO"]
			# get_daily_rsi [get_symbol_id "CRON"]
			# get_daily_rsi [get_symbol_id "TSLA" "NASDAQ"]
			
			# refresh_tsx_symbolIds_file
			# refresh_nasdaq_symbolIds_file
			# refresh_nyse_symbolIds_file
			
			# find_weekly_oversold
			
			stream_testing
		}
	}

# ----------------------------------------Example Filters--------------------------------------------	
	
	# The next few procedures put everything together to give us filters on a particular market.
	# We are able to loop through every symbol on a given market and return a list of symbols that 
	# satisfy whatever criteria we can dream of.
	
	proc find_weekly_oversold {} {
		# set SymbolIds [read_tsx_symbolIds_from_file]
		set SymbolIds [read_nasdaq_symbolIds_from_file]
		# set SymbolIds [read_nyse_symbolIds_from_file]
		
		set SymbolsInfo [get_bulk_symbols_info $SymbolIds]
		set Unsorted [list]
		foreach Record $SymbolsInfo {
			switch [dict get $Record industrySector] {
				"FinancialServices" {
					continue
				}
			}
			if {![string is double [dict get $Record "pe"]] || [dict get $Record "pe"] > 50} {
				continue
			}
			if {[dict get $Record "marketCap"] < 1000000000 || [dict get $Record "marketCap"] eq "null"} {
				continue
			}
			
			set EndTime [clock seconds]
			set StartTime [clock add $EndTime -100 weeks]
			set StartTime [clock format $StartTime -format "%Y-%m-%dT%T-04:00"]
			set EndTime [clock format $EndTime -format "%Y-%m-%dT%T-04:00"]
			
			set History [get_candles [dict get $Record "symbolId"] $StartTime $EndTime "OneWeek"]
			if {[llength $History] < 20} {
				continue
			}
			set RSI [get_smoothed_rsi $History]
			puts "find_weekly_oversold...[dict get $Record symbol] RSI=$RSI"
			if {$RSI < 40} {
				set Symbol [dict get $Record "symbol"]
				set Description [dict get $Record "description"]
				lappend Unsorted [list $Symbol [dict get $Record "marketCap"] $Description [dict get $Record industrySector]]
			}
		}
		set Sorted [lsort -real -decreasing -index 1 $Unsorted]
		foreach Symbol $Sorted {
			puts $Symbol
		}
	}
	
	proc bottom_feeder_filter {} {
		# set SymbolIds [read_tsx_symbolIds_from_file]
		set SymbolIds [read_nasdaq_symbolIds_from_file]
		# set SymbolIds [read_nyse_symbolIds_from_file]
		
		set SymbolsInfo [get_bulk_symbols_info $SymbolIds]
		
		set Unsorted [list]
		foreach Record $SymbolsInfo {
			if {[dict get $Record "marketCap"] < 1000000000 || [dict get $Record "marketCap"] eq "null"} {
				continue
			}
			if {[dict get $Record industrySector] eq "null"} {
				continue
			}
			
			set High52week [dict get $Record "highPrice52"]
			set Low52week [dict get $Record "lowPrice52"]
			set Current [dict get $Record "prevDayClosePrice"]
			if {![string is double $High52week] || \
				![string is double $Low52week] || \
				![string is double $Current] \
			} {
				continue
			}
			
			set PercentOffLow [expr {($Current - $Low52week) / $Low52week}]
			set PercentOffHigh [expr {($High52week - $Current) / $Current}]
			
			if {$PercentOffLow > 0.05} {
				continue
			}
			
			set Symbol [dict get $Record "symbol"]
			set Description [dict get $Record "description"]
			
			lappend Unsorted [list $Symbol [dict get $Record "marketCap"] $Description [dict get $Record industrySector]]
		}
		set Sorted [lsort -real -decreasing -index 1 $Unsorted]
		foreach Symbol $Sorted {
			puts $Symbol
		}
	}
	
	proc kirks_filter {} {
		set SymbolIds [read_tsx_symbolIds_from_file]
		# set SymbolIds [read_nasdaq_symbolIds_from_file]
		# set SymbolIds [read_nyse_symbolIds_from_file]
		
		set SymbolsInfo [get_bulk_symbols_info $SymbolIds]
		
		set Unsorted [list]
		foreach Record $SymbolsInfo {
			switch [dict get $Record industrySector] {
				"Utilities" -
				"FinancialServices" {
					set MarketCapThresh 5000000000
					set PEratioThresh 12
					set YieldThresh 4
				}
				"ConsumerCyclical" {
					set MarketCapThresh 10000000000
					set PEratioThresh 25
					set YieldThresh 2.5
				}
				"Energy" {
					set MarketCapThresh 5000000000
					set PEratioThresh 25
					set YieldThresh 5
				}
				"CommunicationServices" -
				"Technology" -
				"Industrial" -
				"BasicMaterials" -
				"RealEstate" -
				"ConsumerDefensive" -
				"Healthcare" -
				default {
					continue
				}
			}
			set MarketCapThresh 1000000000
			
			if {[dict get $Record "marketCap"] < $MarketCapThresh || \
				[dict get $Record "pe"] > $PEratioThresh || \
				[dict get $Record "yield"] < $YieldThresh \
			} {
				continue
			}
			
			set Symbol [dict get $Record "symbol"]
			set Description [dict get $Record "description"]
			
			lappend Unsorted [list $Symbol $Description [dict get $Record industrySector]]
		}
		set Sorted [lsort -decreasing -index 0 $Unsorted]
		foreach Symbol $Sorted {
			puts $Symbol
		}
	}

# ----------------------------------------Candles/RSI--------------------------------------------	

	# This procedure is used to get candlestick data 
	proc get_candles {Symbol StartTime EndTime Interval} {
		set URL "v1/markets/candles/${Symbol}?startTime=${StartTime}&endTime=${EndTime}&interval=${Interval}"
		set Result [questrade_request $URL]
		
		set ResultDict [json::json2dict $Result]
		set Candles [dict get $ResultDict "candles"]
		
		return $Candles
	}

	# The next two procedures calculates the rsi on the daily time frame. Could easily do this on any 
	# time frame. Looks at the last 250 candles from a given EndTime for a smooth rsi calculation.
	proc get_daily_rsi {Symbol {EndTime ""}} {
		if {$EndTime eq ""} {
			set EndTime [clock seconds]
		}
		
		set StartTime [clock add $EndTime -250 days]
		set StartTime [clock format $StartTime -format "%Y-%m-%dT%T-04:00"]
		set EndTime [clock format $EndTime -format "%Y-%m-%dT%T-04:00"]
		
		set History [get_candles $Symbol $StartTime $EndTime "OneDay"]
		# puts "get_daily_rsi...History=$History"
		
		set RSI [get_smoothed_rsi $History]
		puts "get_daily_rsi...RSI=$RSI"
	}
	
	proc get_smoothed_rsi {History} {
		set TotalGains 0.0
		set TotalLoss 0.0
		set PrevClose ""
		foreach Element [lrange $History 0 13] {
			dict with Element {}
			if {$PrevClose eq ""} {set PrevClose $open}
			set Change [expr {$close - $PrevClose}]
			if {$Change < 0} {
				set TotalLoss [expr {$TotalLoss - $Change}]
			} else {
				set TotalGains [expr {$TotalGains + $Change}]
			}
			set PrevClose $close
		}
		set AverageGain [expr {$TotalGains / 14}]
		set AverageLoss [expr {$TotalLoss / 14}]
		
		foreach Element [lrange $History 14 end] {
			dict with Element {}
			set Change [expr {$close - $PrevClose}]
			if {$Change < 0} {
				set AverageLoss [expr {($AverageLoss * 13 - $Change) / 14}]
				set AverageGain [expr {($AverageGain * 13) / 14}]
			} else {
				set AverageGain [expr {($AverageGain * 13 + $Change) / 14}]
				set AverageLoss [expr {($AverageLoss * 13) / 14}]
			}
			set RS [expr {$AverageGain / $AverageLoss}]
			set RSI [expr {100 - (100 / (1 + $RS))}]
			set PrevClose $close
		}
		return $RSI
	}
	
# ----------------------------------------Symbol Info--------------------------------------------	
	
	# This procedure takes a long list of symbol id's and and calls get_symbols_info with 
	# 100 symbols at a time.
	proc get_bulk_symbols_info {SymbolIds} {
		set RemainingList $SymbolIds
		set ResultList [list]
		set MaxRequestSize 100
		
		while {1} {
			if {$RemainingList > $MaxRequestSize} {
				set SubList [lrange $RemainingList 0 [expr {$MaxRequestSize - 1}]]
				set RemainingList [lrange $RemainingList $MaxRequestSize end]
			} else {
				set SubList $RemainingList
				set RemainingList ""
			}
			
			set ResultList [concat $ResultList [get_symbols_info $SubList]]
			
			if {$RemainingList eq ""} {
				break
			}
		}
		return $ResultList
	}
	
	# Takes a list of symbol id's and retrieves general information on each symbol from the API.
	proc get_symbols_info {SymbolList} {
		set SymbolsString [string map [list " " ","] $SymbolList]
		set query [::http::formatQuery \
			"ids" $SymbolsString \
		]
		set URL "v1/symbols?${query}"
		set Result [questrade_request $URL]
		
		set ResultDict [json::json2dict $Result]
		set Symbols [dict get $ResultDict "symbols"]
		
		return $Symbols
	}
	
# ----------------------------------------SymbolIds--------------------------------------------	
	
	# The following several procedures are for converting symbols to symbol id's. The symbol ID's
	# are written to a file to reduce the amount of requests. The symbol ID's are separated by exchange.
	
	proc get_symbol_id {Symbol {Exchange "TSX"}}  {
		if {[string first ^ $Symbol] >= 0 || [string first < $Symbol] >= 0} {
			return ""
		}
		
		set URL "v1/symbols/search?prefix=${Symbol}"
		set Result [questrade_request $URL]
		
		set ResultDict [json::json2dict $Result]
		set Symbols [dict get $ResultDict "symbols"]
		
		set ReturnList [list]
		foreach Symbol $Symbols {
			if {[dict get $Symbol "isTradable"] eq "true" && \
				[string first $Exchange [dict get $Symbol "listingExchange"]] >= 0 && \
				[dict get $Symbol "securityType"] eq "Stock" \
			} {
				puts [dict get $Symbol "symbol"]
				return [dict get $Symbol "symbolId"]
			}
		}
	}

#	TSX
	proc read_tsx_symbolIds_from_file {} {
		variable _tsx_symbolIds_file
		
		set FileHandle [open $_tsx_symbolIds_file r]
		set Contents [read $FileHandle]
		close $FileHandle
		
		return $Contents
	}
	
	proc refresh_tsx_symbolIds_file {} {
		variable _tsx_symbolIds_file
		
		set FileHandle [open $_tsx_symbolIds_file w]
		puts $FileHandle [get_all_tsx_symbolIds]
		close $FileHandle
	}
	
	proc get_all_tsx_symbolIds {} {
		set RawSymbols [get_tsx_symbols]
		
		set SymbolIds [list]
		foreach Symbol $RawSymbols {
			
			set ThisSymbolId [get_symbol_id $Symbol]
			if {$ThisSymbolId ne ""} {
				lappend SymbolIds $ThisSymbolId
			}
		}
		return $SymbolIds
	}
	
#	NASDAQ	
	proc read_nasdaq_symbolIds_from_file {} {
		variable _nasdaq_symbolIds_file
		
		set FileHandle [open $_nasdaq_symbolIds_file r]
		set Contents [read $FileHandle]
		close $FileHandle
		
		return $Contents
	}
	
	proc refresh_nasdaq_symbolIds_file {} {
		variable _nasdaq_symbolIds_file
		
		set FileHandle [open $_nasdaq_symbolIds_file w]
		puts $FileHandle [get_all_nasdaq_symbolIds]
		close $FileHandle
	}
	
	proc get_all_nasdaq_symbolIds {} {
		set RawSymbols [get_symbols_list "NASDAQ"]
		
		set SymbolIds [list]
		foreach Symbol $RawSymbols {
			set ThisSymbolId [get_symbol_id $Symbol "NASDAQ"]
			if {$ThisSymbolId ne ""} {
				lappend SymbolIds $ThisSymbolId
			}
		}
		return $SymbolIds
	}
	
#	NYSE	
	proc read_nyse_symbolIds_from_file {} {
		variable _nyse_symbolIds_file
		
		set FileHandle [open $_nyse_symbolIds_file r]
		set Contents [read $FileHandle]
		close $FileHandle
		
		return $Contents
	}
	
	proc refresh_nyse_symbolIds_file {} {
		variable _nyse_symbolIds_file
		
		set FileHandle [open $_nyse_symbolIds_file w]
		puts $FileHandle [get_all_nyse_symbolIds]
		close $FileHandle
	}
	
	proc get_all_nyse_symbolIds {} {
		set RawSymbols [get_symbols_list "NYSE"]
		
		set SymbolIds [list]
		foreach Symbol $RawSymbols {
			set ThisSymbolId [get_symbol_id $Symbol "NYSE"]
			if {$ThisSymbolId ne ""} {
				lappend SymbolIds $ThisSymbolId
			}
		}
		return $SymbolIds
	}


# ----------------------------------------REQUESTS--------------------------------------------	

	# Ping the server to test latency
	proc ping_server {} {
		set Timer [clock clicks -milliseconds]
		set URL "v1/time"
		set DummyData [questrade_request $URL]
		puts "ping_server...Timer - [expr {[clock clicks -milliseconds] - $Timer}]"
		return $DummyData
	}

	# Wrapper for all questrade api requests, minus authorization
	proc questrade_request {URL} {
		variable _access_token
		variable _api_address
		
		set URL "${_api_address}${URL}"
		
		# puts "questrade_request...sending request to: $URL"
		if {[catch {
			set Token [::http::geturl $URL \
				-headers [list "Authorization" "Bearer $_access_token"] \
				-timeout 10000 \
			]
			
		} error]} {
			puts "questrade_request...Something went wrong: $error, URL = $URL"
			return "";
		}
		
		if {[http::status $Token] eq "timeout"} {
			puts "questrade_request...timeout on URL:$URL...trying again"
			http::cleanup $Token
			return [questrade_request $URL]
		}
		
		# puts "questrade_request...$Token - code = [http::code $Token], ncode = [http::ncode $Token], status = [http::status $Token]"
		set Result [http::data $Token]
		
		if {[http::ncode $Token] ne 200} {
			puts "questrade_request...Code not 200, [http::meta $Token], Result=$Result"
			puts "questrade_request...URL=$URL"
			return ""
		}
		http::cleanup $Token
		return $Result
	}
	
	# To authorize, a refresh token is provided in the payload. If authorization succeeds a new refresh 
	# token is returned along with an access token and an api address.
	# The refresh token is read from a file and refreshed after authorization.
	proc authorize {} {
		variable _customer_id
		variable _refresh_token

		variable _access_token
		variable _api_address
		variable _api_options_file
		
		# Read refresh token
		set FileHandle [open $_api_options_file r]
		set _refresh_token [lindex [split [read $FileHandle] "\n"] 0]
		close $FileHandle
		
		set Tail "grant_type=refresh_token&refresh_token=${_refresh_token}"
		set URL "https://login.questrade.com/oauth2/token?${Tail}"
		
		if {[catch {
			set Token [http::geturl $URL];
		} error]} {
			puts "authorize...Something went wrong: $error, URL = $URL"
			return "";
		}
		
		set Result [http::data $Token]
		if {[http::ncode $Token] ne 200} {
			puts "authorize...Code not 200, [http::meta $Token], Result=$Result"
			http::cleanup $Token
			return ""
		}
		set ResultDict [json::json2dict $Result]
		puts "authorize...ResultDict=$ResultDict"
		
		# Update refresh token
		set FileHandle [open $_api_options_file w]
		puts $FileHandle [dict get $ResultDict "refresh_token"]
		close $FileHandle
		
		set _api_address [dict get $ResultDict "api_server"]
		set _access_token [dict get $ResultDict "access_token"]
		
		
		http::cleanup $Token
	}
	
	# These guys don't make it easy. In order to retrieve the data we need to provide a session cookie.
	# We do this by making an initial GET request, the response contains a cookie in the header. With
	# the cookie we make the second request and receive an excel spreadsheet in return. Next we have to 
	# use tcom to parse the spreadsheet data.
	proc get_tsx_symbols {} {
		#	first HTTP request
		set Token [::http::geturl "https://api.tmxmoney.com/en/migreport/search" -timeout 10000]
		set Cookies [list]
		foreach {Name Value} [http::meta $Token] {
			if {$Name eq "Set-Cookie"} {
				set Cookie [lindex [split $Value ";"] 0]
				lappend Cookies $Cookie
				set csrfToken [lindex [split $Cookie "="] 1]
			}
		}
		http::cleanup $Token
		#-------------------------------------------------------------------
		#	second HTTP request, with cookie from first request
		set query [::http::formatQuery \
			csrfmiddlewaretoken $csrfToken \
			report_type "excel" \
			sectors "" \
			hqregions "" \
			hqlocations "" \
			exchanges "TSX" \
			marketcap "" \
		]

		set FileName "C:/tbf/tsx_stock_list.xlsx"
		set FileHandle [open $FileName w]
		fconfigure $FileHandle -translation binary

		#	the response will be in .xlsx format, write the response to a file
		set Token [::http::geturl "https://api.tmxmoney.com/en/migreport/search" \
			-query $query -headers [list Cookie [join $Cookies ";"]] -binary 1 -channel $FileHandle]
		close $FileHandle
		http::cleanup $Token
		#-------------------------------------------------------------------
		#	use tcom to open the file in excel to read data
		set ExcelApp [tcom::ref createobject "Excel.Application"]
		set Workbooks [$ExcelApp Workbooks]
		set Workbook [$Workbooks Open $FileName]
		set Worksheets [$Workbook Worksheets];
		set Worksheet [$Worksheets Item [expr 1]];
		set Cells [$Worksheet Cells];

		set SymbolsList [list]
		set Row 1
		while {1} {
			set Value [[$Cells Item $Row "C"] Value]
			if {$Value eq ""} {
				break
			}
			lappend SymbolsList $Value
			incr Row
		}
		$Workbook Close
		$ExcelApp Quit
		
		return $SymbolsList
	}
	
	# This uses a third party resource to get a list of symbols on the NASDAQ or NYSE
	# The response is in CSV format which we parse and convert to a tcl list.
	proc get_symbols_list {Market {SectorFilter ""}} {
		set SymbolsURL "https://www.nasdaq.com/screening/companies-by-industry.aspx?exchange=${Market}&render=download"
		# set SymbolsURL "https://www.nasdaq.com/market-activity/stocks/screener?exchange=${Market}&amp;render=download"
		
		if {[catch {
			set SymbolsToken [http::geturl $SymbolsURL -timeout 10000]
		} error]} {
			puts "Something went wrong retrieving Symbols on the $Market"
		}
		
		set SymbolsData [http::data $SymbolsToken]
		
		set IsFirstLineOfCSV 1
		set Result ""
		foreach SymbolLine [split $SymbolsData "\n"] {
			if {$IsFirstLineOfCSV} {
				puts "get_symbols_list...First Line = $SymbolLine"
				set IsFirstLineOfCSV 0
				continue
			}
			set SymbolResultList [csv::split $SymbolLine]
			if {[lsearch $SectorFilter [lindex $SymbolResultList 6]] >= 0 || $SectorFilter eq ""} {
				lappend Result [string trim [lindex $SymbolResultList 0]]
			}
		}
		
		::http::cleanup $SymbolsToken
		puts "get_symbols_list...Result=$Result"
		return $Result
	}
	
	# Binance API requires sockets using SNI
	proc sni_socket {args} {
		set opts [lrange $args 0 end-2]
		set host [lindex $args end-1]
		set port [lindex $args end]
		
		set Command [subst -nocommands {::tls::socket -servername $host $opts $host $port}]
		eval $Command
	}
	
# ----------------------------------------Data Streaming--------------------------------------------	
	
	# If you subscribe to one of Questrade's data packages, the real time data is also provided through the
	# web socket API. These data streams give very frequent updates on price and volume.
	#
	# I have just scratched the surface here.
	
	proc stream_testing {} {
		variable _api_address
		
		set URLtail "v1/markets/quotes?ids="
		foreach Symbol [list AAPL AMZN] {
			append URLtail "[get_symbol_id $Symbol NASDAQ],"
		}
		set URLtail "[string range $URLtail 0 end-1]&stream=true&mode=WebSocket"
		
		set Result [questrade_request $URLtail]
		set ResultDict [::json::json2dict $Result]
		set Port [::dict get $ResultDict streamPort]
		
		set URL "[string range $_api_address 0 end-1]:${Port}/$URLtail"
		puts "stream_testing...URL=$URL"
		
		set StockStreamSocket [::websocket::open $URL [namespace code stock_stream]]
	}
	proc stock_stream {Socket Type Message} {
		variable _access_token
		
		switch $Type {
			"connect" {
				puts "Connected on $Socket"
				websocket::send $Socket "text" $_access_token
			}
			"ping" {
				puts "stock_stream... ping on $Socket"
				websocket::send $Socket "pong" ""
			}
			"text" {
				set PayLoad [::json::json2dict $Message]
				if {[::dict exists $PayLoad success]} {
					puts "stock_stream... Token Success"
				}
				if {[::dict exists $PayLoad quotes]} {
					foreach Quote [::dict get $PayLoad quotes] {
						set Symbol [::dict get $Quote symbol]
						set Price [::dict get $Quote lastTradePrice]
						
						puts "stock_stream...$Symbol - $Price"
					}
				}
			}
		}
	}
}

questrade_api::main

