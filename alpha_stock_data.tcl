

#		Alpha Vantage & Iex Trading API
#	Tommy Freethy - November 2017
#
# 

package require http
package require tls
package require json
package require csv
package require tcom

namespace eval alpha_data {
	variable _api_key "****************"
	
	proc main {} {
		http::register https 443 [list alpha_data::alpha_socket -tls1 1]
		
		# get_stock_history_day "NFLX" 5
		# get_stock_history_intra "ATD.B" "60min"
		
		
		# set Timer [clock milliseconds]
		# get_stock_quote_info "NFLX"
		# puts "Timer - [expr {[clock milliseconds] - $Timer}]"
		
		# puts [get_stock_quote_info "ENB"]
		# puts [get_tsx_symbols]
		# limit_testing
		
		
		# find_volotile_stocks_today
		
		
		return
	}
	
# ----------------------------------------Example Filters--------------------------------------------
	
	# The next few procedures put everything together to give us filters on a particular market.
	# We are able to loop through every symbol on a given market and return a list of symbols that 
	# satisfy whatever criteria we can dream of.
	
	proc find_volotile_stocks_today {} {
		set SymbolsList [concat [get_symbols_list "NASDAQ"] [get_symbols_list "NYSE"]]
		# set SymbolsList [list "NFLX" "TLRY" "AMZN"]
		
		set RemainingList $SymbolsList
		set MyList [list]
		while {1} {
			if {$RemainingList > 100} {
				set SubList [lrange $RemainingList 0 99]
				set RemainingList [lrange $RemainingList 100 end]
			} else {
				set SubList $RemainingList
				set RemainingList ""
			}
			
			set SymbolString ""
			foreach Symbol $SubList {
				if {[string first ^ $Symbol] >= 0} {
					continue
				}
				append SymbolString "${Symbol},"
			}
			
			set SymbolString [string range $SymbolString 0 end-1]
			set URL "https://api.iextrading.com/1.0/stock/market/batch?types=quote&symbols=$SymbolString&range=1m"
			set Quote [iextrading_request $URL]
			
			if {$Quote eq ""} {
				puts "limit_testing...Quote is empty"
				return ""
			}
			
			set Result [json::json2dict $Quote]
			foreach Symbol $SymbolsList {
				if {![dict exists $Result $Symbol]} {
					continue
				}
				
				if {[dict get $Result $Symbol quote marketCap] < 250000000} {
					continue
				}
				set QuoteData [dict get $Result $Symbol quote]
				dict with QuoteData {}
				
				if {$previousClose < $low} {
					set low $previousClose
				}
				if {$previousClose > $high} {
					set high $previousClose
				}
				
				if {![string is double $low] || ![string is double $high]} {
					continue
				}
				
				set HighLowChange [expr {($high - $low) / $low * 100}]
				lappend MyList [list $Symbol $HighLowChange]
			}
			if {$RemainingList eq ""} {
				break
			}
		}
		set MyList [lsort -real -decreasing -index 1 $MyList]
		puts "---------------Top 25----------------------"
		foreach Symbol [lrange $MyList 0 24] {
			puts $Symbol
		}
	}
	
	proc find_volotile_stocks {} {
		set SymbolsList [concat [get_symbols_list "NASDAQ"] [get_symbols_list "NYSE"]]
		# set SymbolsList [list "NFLX" "TLRY" "AMZN"]
		
		set RemainingList $SymbolsList
		set MyList [list]
		while {1} {
			if {$RemainingList > 100} {
				set SubList [lrange $RemainingList 0 99]
				set RemainingList [lrange $RemainingList 100 end]
			} else {
				set SubList $RemainingList
				set RemainingList ""
			}
			
			set SymbolString ""
			foreach Symbol $SubList {
				if {[string first ^ $Symbol] >= 0} {
					continue
				}
				append SymbolString "${Symbol},"
			}
			
			set SymbolString [string range $SymbolString 0 end-1]
			set URL "https://api.iextrading.com/1.0/stock/market/batch?types=chart,quote&symbols=$SymbolString&range=1m"
			# puts "limit_testing...URL=$URL"
			set Quote [iextrading_request $URL]
			
			if {$Quote eq ""} {
				puts "limit_testing...Quote is empty"
				return ""
			}
			
			set Result [json::json2dict $Quote]
			foreach Symbol $SymbolsList {
				if {![dict exists $Result $Symbol]} {
					continue
				}
				
				if {[dict get $Result $Symbol quote marketCap] < 1000000000} {
					continue
				}
				set History [dict get $Result $Symbol chart]
				set TotalVolotility 0
				set Counter 0
				foreach Item [lrange $History end-2 end] {
					incr Counter
					
					dict with Item {}
					if {$low == 0} {
						continue
					}
					set HighLowChange [expr {($high - $low) / $low}]
					set TotalVolotility [expr {$TotalVolotility + $HighLowChange*100}]
				}
				if {$Counter == 0} {
					continue
				}
				set AverageDailyChange [expr {$TotalVolotility / $Counter}]
				lappend MyList [list $Symbol $AverageDailyChange]
			}
			if {$RemainingList eq ""} {
				break
			}
		}
		set MyList [lsort -real -decreasing -index 1 $MyList]
		puts "---------------Top 25----------------------"
		foreach Symbol [lrange $MyList 0 24] {
			puts $Symbol
		}
	}
	
	proc limit_testing {} {
		set SymbolsList [concat [get_symbols_list "NASDAQ" "Technology"] [get_symbols_list "NYSE" "Technology"]]
		# set SymbolsList [concat [get_tsx_symbols]]
		set RemainingList $SymbolsList
		set MyList [list]
		while {1} {
			if {$RemainingList > 100} {
				set SubList [lrange $RemainingList 0 99]
				set RemainingList [lrange $RemainingList 100 end]
			} else {
				set SubList $RemainingList
				set RemainingList ""
			}
			
			set SymbolString ""
			foreach Symbol $SubList {
				if {[string first ^ $Symbol] >= 0} {
					continue
				}
				append SymbolString "${Symbol},"
			}
			
			set SymbolString [string range $SymbolString 0 end-1]
			set URL "https://api.iextrading.com/1.0/stock/market/batch?types=stats,quote,financials&symbols=$SymbolString"
			# puts "limit_testing...URL=$URL"
			set Quote [iextrading_request $URL]
			
			if {$Quote eq ""} {
				puts "limit_testing...Quote is empty"
				return ""
			}
			
			set Result [json::json2dict $Quote]
			foreach Symbol $SymbolsList {
				if {[dict exists $Result $Symbol stats]} {
					if {[dict exists $Result $Symbol stats dividendYield]} {
						set DividendYield [dict get $Result $Symbol stats dividendYield]
					} else {
						set DividendYield 0
					}
					set ThisQuote [dict get $Result $Symbol quote]
					dict with ThisQuote {}
					if {$marketCap > 1000000000} {
						if {![string is double $week52Low] || ![string is double $week52High] || ![string is double $latestPrice]} {
							continue
						}
						if {$week52Low == 0 || $week52High == 0 || $latestPrice == 0} {
							continue
						}
						
						if {![dict exists $Result $Symbol financials financials]} {
							continue
						}
						set Ratio [expr {($week52High - $week52Low) / $week52Low}]
						if {$Ratio < 0.3} {
							continue
						}
						set HighCurrentRatio [expr {($week52High - $latestPrice) / $latestPrice}]
						if {$HighCurrentRatio < 0.10} {
							continue
						}
						set ProfitUpTrend 1
						set LastQuarter ""
						foreach Quarter [dict get $Result $Symbol financials financials] {
							if {![dict exists $Quarter totalRevenue]} {
								continue
							}
							set ThisQuarter [dict get $Quarter totalRevenue]
							if {$LastQuarter eq ""} {
								set LastQuarter $ThisQuarter
								continue
							}
							if {$ThisQuarter > $LastQuarter || $ThisQuarter eq "null"} {
								set ProfitUpTrend 0
								break
							}
							set LastQuarter $ThisQuarter
						}
						if {!$ProfitUpTrend} {
							continue
						}
						
						if {![string is double $peRatio] || $peRatio eq "" || $peRatio < 0} {
							set peRatio 99999
						}
						lappend MyList [list $Symbol $peRatio $DividendYield $latestPrice $week52High $week52Low]
					}
				}
			}
			if {$RemainingList eq ""} {
				break
			}
		}
		set MyList [lsort -real -increasing -index 1 $MyList]
		puts "---------------Top 25----------------------"
		foreach Symbol [lrange $MyList 0 24] {
			puts $Symbol
		}
	}
	
	proc sort_by_peRatio {} {
		set SymbolsList [concat [get_symbols_list "NASDAQ"] [get_symbols_list "NYSE"]]
		set MyList [list]
		foreach Symbol $SymbolsList {
			puts "Symbol=$Symbol"
			set Quote [get_stock_quote_info $Symbol]
			if {$Quote eq ""} {
				continue
			}
			dict with Quote {}
			if {![string is double $peRatio] || $peRatio eq "" || $peRatio < 0} {
				set peRatio 99999
			}
			lappend MyList [list $Symbol $peRatio $close $week52High $week52Low]
		}
		set MyList [lsort -real -increasing -index 1 $MyList]
		puts "---------------Top 25----------------------"
		foreach Symbol [lrange $MyList 0 24] {
			puts $Symbol
		}
	}

# ----------------------------------------Iex--------------------------------------------	

	# Here are the different API calls made to Iex. Sample JSON objects are provided
	
	proc get_stock_chart {Symbol} {
		
#		{
#			"date": "20171215"
#			"minute": "09:30",
#			"label": "09:30 AM",
#			"high": 143.98,
#			"low": 143.775,
#			"average": 143.889,
#			"volume": 3070,
#			"notional": 441740.275,
#			"numberOfTrades": 20,
#			"marktHigh": 143.98,
#			"marketLow": 143.775,
#			"marketAverage": 143.889,
#			"marketVolume": 3070,
#			"marketNotional": 441740.275,
#			"marketNumberOfTrades": 20,
#			"open": 143.98,
#			"close": 143.775,
#			"marktOpen": 143.98,
#			"marketClose": 143.775,
#			"changeOverTime": -0.0039,
#			"marketChangeOverTime": -0.004
#		}
		
		set URL "https://api.iextrading.com/1.0/stock/${Symbol}/chart/1m"
		set Quote [iextrading_request $URL]
		if {$Quote eq ""} {
			return ""
		}
		set FileHandle [open "c:/users/temp/documents/tests/crypto/test_output.txt" w]
		foreach Item [json::json2dict $Quote] {
			puts $FileHandle $Item
		}
		close $FileHandle
		return [lindex [json::json2dict $Quote] 0 4]
	}
	
	proc get_stock_quote_info {Symbol} {
#		{
#			"symbol": "AAPL",
#			"companyName": "Apple Inc.",
#			"primaryExchange": "Nasdaq Global Select",
#			"sector": "Technology",
#			"calculationPrice": "tops",
#			"open": 154,
#			"openTime": 1506605400394,
#			"close": 153.28,
#			"closeTime": 1506605400394,
#			"high": 154.80,
#			"low": 153.25,
#			"latestPrice": 158.73,
#			"latestSource": "Previous close",
#			"latestTime": "September 19, 2017",
#			"latestUpdate": 1505779200000,
#			"latestVolume": 20567140,
#			"iexRealtimePrice": 158.71,
#			"iexRealtimeSize": 100,
#			"iexLastUpdated": 1505851198059,
#			"delayedPrice": 158.71,
#			"delayedPriceTime": 1505854782437,
#			"extendedPrice": 159.21,
#			"extendedChange": -1.68,
#			"extendedChangePercent": -0.0125,
#			"extendedPriceTime": 1527082200361,
#			"previousClose": 158.73,
#			"change": -1.67,
#			"changePercent": -0.01158,
#			"iexMarketPercent": 0.00948,
#			"iexVolume": 82451,
#			"avgTotalVolume": 29623234,
#			"iexBidPrice": 153.01,
#			"iexBidSize": 100,
#			"iexAskPrice": 158.66,
#			"iexAskSize": 100,
#			"marketCap": 751627174400,
#			"peRatio": 16.86,
#			"week52High": 159.65,
#			"week52Low": 93.63,
#			"ytdChange": 0.3665,
#		}
		set URL "https://api.iextrading.com/1.0/stock/${Symbol}/quote"
		set Quote [iextrading_request $URL]
		if {$Quote eq ""} {
			return ""
		}
		return [json::json2dict $Quote]
	}
	
	proc get_financials {} {
# {
#	"symbol": "AAPL",
#	"financials": [
#     {
#       "reportDate": "2017-03-31",
#       "grossProfit": 20 591 000 000,
#       "costOfRevenue": 32 305 000 000,
#       "operatingRevenue": 52 896 000 000,
#       "totalRevenue": 52 896 000 000,
#       "operatingIncome": 14 097 000 000,
#       "netIncome": 11 029 000 000,
#       "researchAndDevelopment": 277 6000 000,
#       "operatingExpense": 6 494 000 000,
#       "currentAssets": 101 990 000 000,
#       "totalAssets": 334 532 000 000,
#       "totalLiabilities": 200 450 000 000,
#       "currentCash": 15 157 000 000,
#       "currentDebt": 13 991 000 000,
#       "totalCash": 67 101 000 000,
#       "totalDebt": 98 522 000 000,
#       "shareholderEquity": 134 082 000 000,
#       "cashChange": -1 214 000 000,
#       "cashFlow": 12 523 000 000,
#       "operatingGainsLosses": null 
#     } // , { ... }
#	]
# }

		set SymbolsList [concat [get_symbols_list "NASDAQ" "Technology"]]
		foreach Symbol $SymbolsList {
			set URL "https://api.iextrading.com/1.0/stock/${Symbol}/financials"
			set Quote [iextrading_request $URL]
			if {$Quote eq ""} {
				return ""
			}
			
			set Financials [json::json2dict $Quote]
			if {![dict exists $Financials financials]} {
				continue
			}
			
			set ProfitUpTrend 1
			set LastQuarter ""
			foreach Quarter [dict get $Financials financials] {
				if {![dict exists $Quarter grossProfit]} {
					continue
				}
				
				set ThisQuarter [dict get $Quarter grossProfit]
				if {$LastQuarter eq ""} {
					set LastQuarter $ThisQuarter
					continue
				}
				if {$ThisQuarter < $LastQuarter} {
					set ProfitUpTrend 0
					break
				}
			}
			if {$ProfitUpTrend} {
				puts $Symbol
			}
		}
	}

# ----------------------------------------Alpha--------------------------------------------	
	
	# I didn't use this API too much. I found Iex trading to be much better.
	
	proc get_stock_history_intra {Symbol Interval} {
		set URL "https://www.alphavantage.co/query?function=TIME_SERIES_INTRADAY&"
		append URL "symbol=${Symbol}&interval=${Interval}"
		set History [alpha_request $URL]
		puts $History
	}
	
	proc get_stock_history_day {Symbol Size} {
		set URL "https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=${Symbol}"
		set History [alpha_request $URL]
		if {$History eq ""} {
			return ""
		}
		
		set FileHandle [open "c:/users/temp/documents/tests/crypto/test_output.txt" w]
		puts $FileHandle $History
		close $FileHandle
		
		set History [json::json2dict $History]
		set Data [dict get $History "Time Series (Daily)"]
		# puts $Data
		set Return [lrange $Data 0 [expr {$Size - 1}]]
		foreach Item $Return {
			puts $Item
		}
		
		return $History
	}
	
# ----------------------------------------REQUESTS--------------------------------------------	
	
	# I don't think I use this API any more. Requires an API key (free).
	proc alpha_request {URL} {
		variable _api_key
		
		append URL "&apikey=${_api_key}"
		
		puts "alpha_request...sending request to: $URL"
		if {[catch {
			set Token [::http::geturl $URL -timeout 10000]
		} error]} {
			puts "alpha_request...Something went wrong: $error";
			return "";
		}
		if {[http::status $Token] eq "timeout"} {
			puts "alpha_request...timeout on URL:$URL...trying again";
			http::cleanup $Token
			return [alpha_request $URL]
		}
		set Result [http::data $Token]
		puts "alpha_request...$Token - code = [http::code $Token], ncode = [http::ncode $Token], status = [http::status $Token]"
		http::cleanup $Token
		# puts "alpha_request...returning, $Result"
		return $Result
	}
	
	proc iextrading_request {URL} {
		# puts "iextrading_request...sending request to: $URL"
		if {[catch {
			set Token [::http::geturl $URL -timeout 1000000]
		} error]} {
			puts "iextrading_request...Something went wrong: $error"
			puts "URL = $URL"
			return "";
		}
		if {[http::status $Token] eq "timeout"} {
			puts "iextrading_request...timeout on URL:$URL...trying again"
			http::cleanup $Token
			return [iextrading_request $URL]
		}
		# puts "iextrading_request...$Token - code = [http::code $Token], ncode = [http::ncode $Token], status = [http::status $Token]"
		set Result [http::data $Token]
		
		if {[http::ncode $Token] ne 200} {
			puts "iextrading_request...$Token - code = [http::code $Token], ncode = [http::ncode $Token], status = [http::status $Token]"
			# puts "iextrading_request...Code not 200, [http::meta $Token]"
			return ""
		}
		http::cleanup $Token
		return $Result
	}
	
	# This uses a third party resource to get a list of symbols on the NASDAQ or NYSE
	# The response is in CSV format which we parse and convert to a tcl list.
	proc get_symbols_list {Market {SectorFilter ""}} {
		set SymbolsURL "https://www.nasdaq.com/screening/companies-by-industry.aspx?exchange=${Market}&render=download"
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
				# puts "get_symbols_list...First Line = $SymbolLine"
				set IsFirstLineOfCSV 0
				continue
			}
			set SymbolResultList [csv::split $SymbolLine]
			if {[lsearch $SectorFilter [lindex $SymbolResultList 6]] >= 0 || $SectorFilter eq ""} {
				lappend Result [string trim [lindex $SymbolResultList 0]]
			}
		}
		
		http::cleanup $SymbolsToken
		# puts "get_symbols_list...Result=$Result"
		return $Result
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
	
	# Both API's require sockets using SNI
	proc alpha_socket {args} {
		set opts [lrange $args 0 end-2]
		set host [lindex $args end-1]
		set port [lindex $args end]
		
		::tls::socket -servername $host {*}$opts $host $port
	}
}

alpha_data::main