

#		Binance API
#	Tommy Freethy - May 2018
#
# Binance API documentation can be found here: https://github.com/binance-exchange/binance-official-api-docs
#
# I currently use the API to analyse symbols on Binance's exchange. The API has several different endpoints
# for retrieving trading information and is probably my favourite API for candlestick data.
#
# The data streaming capabilities this API offers are also quite rich. It also provides a stream to monitor
# all tickers at the same time.
#
# This API also allows trading capabilities which I would like to explore a little more.
#

package require http
package require tls
package require json
package require websocket
package require sha256

namespace eval crypto_data {
	variable _api_key "****************************************************************"
	variable _secret_key "****************************************************************"
	
	variable _every
	variable _intervals [list "1M" "1w" "1d" "12h" "4h" "2h" "1h" "15m" "5m" "3m" "1m"]
	
	variable _kline_stream_socket ""
	variable _kline_streams_dict [dict create]
	
	variable _form_array
	
	variable _log_file "c:/tbf/binance_signal_log.txt"
	variable _dict_file "c:/tbf/binance_dict_file.txt"
	
	proc main {} {
		http::register https 443 [list ::tls::socket -tls1 1]
		http::register wss 9443 [list ::tls::socket -tls1 1]
		
		if {1} {
			ping_server
		} else {
			
			setup_real_time_indicators "batbtc_15m"
			
			# create_order_test
			
			# load_dict_file
			# reset_stream
			# setup_targets_table
			# target_form_create
			
		}
	}

	
# ----------------------------------------Examine History--------------------------------------------

	# These procedures are for retrieving and analysing candlestick history

#		Sample Object	BTCUSDT	
#		{
#			1517538960000 	- 0	Open Time					- open_time
#			8751.26000000 	- 1	Open						- open
#			8785.00000000 	- 2	High						- high
#			8751.01000000 	- 3	Low							- low
#			8777.39000000 	- 4	Close						- close
#			15.85400700 	- 5	Volume						- volume
#			1517539019999 	- 6	Close Time					- close_time
#			138851.52811284 - 7	Quote Asset Volume			- quote_asset_volume
#			227 			- 8	Number of Trades			- number_trades
#			9.66202100 		- 9	Taker buy base asset volume	- base_asset_buy_volume
#			84658.13307602  -10	Taker buy quote asset volume- quote_asset_buy_volume
#			0				-11	Ignore						- ignore
#		}
	
	# This procedure sets up the request to Binance to retrieve the candlestick history.
	# This also "massages" the data into a nicely formed dictionary. Above is some sample data,
	# you can see, it just contains a list of values, no description, no field names.
	proc get_historic_quote {Symbol Interval Limit TimeStamp} {
		set TimeStampString ""
		switch [string length $TimeStamp] {
			10 {
				# TimeStamp needs to include milliseconds
				append TimeStamp 000
				set TimeStampString "&endTime=$TimeStamp"
			}
			13 {
				set TimeStampString "&endTime=$TimeStamp"
			}
		}
		set URL "https://api.binance.com/api/v1/klines?interval=${Interval}&symbol=${Symbol}&limit=${Limit}${TimeStampString}"
		
		set Volume [json::json2dict [binance_request $URL]]
		set Fixed [list]
		foreach Item $Volume {
			set ThisDict [dict create]
			dict set ThisDict "open_time" [lindex $Item 0]
			dict set ThisDict "open" [lindex $Item 1]
			dict set ThisDict "high" [lindex $Item 2]
			dict set ThisDict "low" [lindex $Item 3]
			dict set ThisDict "close" [lindex $Item 4]
			dict set ThisDict "volume" [lindex $Item 5]
			dict set ThisDict "close_time" [lindex $Item 6]
			dict set ThisDict "quote_asset_volume" [lindex $Item 7]
			dict set ThisDict "number_trades" [lindex $Item 8]
			dict set ThisDict "base_asset_buy_volume" [lindex $Item 9]
			dict set ThisDict "quote_asset_buy_volume" [lindex $Item 10]
			dict set ThisDict "ignore" [lindex $Item 11]
			
			lappend Fixed $ThisDict
		}
		return $Fixed
	}
	
	# This proc takes a history of candlesticks and determines the highest/lowest closes
	proc get_high_low {History} {
		set Low 1000000000
		set High -1
		foreach Element $History {
			dict with Element {}
			if {$close > $High} {
				set High $close
			}
			if {$close < $Low} {
				set Low $close
			}
		}
		return [list $High $Low]
	}
	
	# This proc takes a history of candlesticks and determines the last closing price
	proc get_last_close {History} {
		set Last [lindex $History end]
		dict with Last {}
		return $close
	}
	
	# This proc takes a history of candlesticks and determines the opening price
	proc get_open_price {History} {
		set First [lindex $History 0]
		dict with First {}
		return $open
	}
	
	# This proc takes a history of candlesticks and determines RSI.
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

# ----------------------------------------REQUEST--------------------------------------------
	
	# All requests to Binance's API are made from here. The API key is included in every request.
	proc binance_request {URL {Query ""}} {
		variable _api_key
		
		# puts "binance_request...sending request to: $URL"
		if {[catch {
			if {$Query eq ""} {
				set Token [::http::geturl $URL \
					-headers [list "X-MBX-APIKEY" $_api_key] \
					-timeout 10000 \
				]
			} else {
				set Token [::http::geturl $URL -query $Query \
					-headers [list "X-MBX-APIKEY" $_api_key] \
					-timeout 10000 \
				]
			}
		} error]} {
			puts "binance_request...Something went wrong: $error";
			return "";
		}
		if {[http::status $Token] eq "timeout"} {
			puts "binance_request...timeout on URL:$URL...trying again";
			http::cleanup $Token
			return [binance_request $URL]
		}
		set Result [http::data $Token]
		# puts "binance_request...$Token - code = [http::code $Token], ncode = [http::ncode $Token], status = [http::status $Token]";
		http::cleanup $Token
		# puts "binance_request...returning, $Result"
		return $Result
	}
	
	# Some "sensitive" requests need a signature using the HMAC SHA 256 hashing algorithm. The secret key
	# is set up in Binance and used to sign the parameters being sent.
	proc generate_request_signature {Parameters} {
		variable _secret_key
		
		# The API requires a timestamp as part of Binance's validation.
		set TimeStamp [clock milliseconds]
		if {$Parameters eq ""} {
			append Parameters "?timestamp=$TimeStamp"
		} else {
			append Parameters "&timestamp=$TimeStamp"
		}
		append Parameters "&recvWindow=10000"
		
		# Need to scrape the "?" off the front of Parameters for signature - done with "string range"
		set Signature [sha2::hmac $_secret_key [string range $Parameters 1 end]]
		append Parameters "&signature=$Signature"
		return $Parameters
	}
	
# ----------------------------------------SIMPLE GETS--------------------------------------------

	# This guy is used to determine the latency to the API server.
	proc ping_server {} {
		set Timer [clock clicks -milliseconds]
		set URL "https://api.binance.com/api/v1/ping"
		set DummyData [binance_request $URL]
		puts "ping_server...Timer stop - [expr {[clock clicks -milliseconds] - $Timer}]"
		return $DummyData
	}
	# Simple ticker quote
	proc get_ticker {Symbol} {
		set URL "https://api.binance.com/api/v3/ticker/price?symbol=$Symbol"
		set TickerData [json::json2dict [binance_request $URL]]
		set Price [dict get $TickerData "price"]
		return $Price
	}
	# Info over past 24 hours
	proc get_ticker_24_hour {Symbol} {
		set URL "https://api.binance.com/api/v1/ticker/24hr?symbol=$Symbol"
		set TickerData [json::json2dict [binance_request $URL]]
		return $TickerData
	}
	# Used to compare server time to local time
	proc get_server_time {} {
		set URL "https://api.binance.com/api/v1/time"
		set ServerTime [json::json2dict [binance_request $URL]]
		return $ServerTime
	}
	
# ----------------------------------------Read/Write Files--------------------------------------------
	
	# Procedures for reading/writing to files
	
	proc write_to_log {Contents} {
		variable _log_file
		
		set FileHandle [open $_log_file a]
		puts $FileHandle "[clock format [clock seconds] -format %D-%T] - $Contents"
		close $FileHandle
	}
	
	proc update_dict_file {} {
		variable _dict_file
		variable _kline_streams_dict
		
		set FileHandle [open $_dict_file w]
		puts $FileHandle [::dict get $_kline_streams_dict]
		close $FileHandle
	}
	
	proc load_dict_file {} {
		variable _dict_file
		variable _kline_streams_dict
		
		set FileHandle [open $_dict_file r]
		set _kline_streams_dict [read $FileHandle]
		close $FileHandle
	}
	
# ---------------------------------------- Trading --------------------------------------------

	# Procedures used to test the trading API
	# Trading requires the parameters to be signed with the secret api key

	proc create_order {OrderArray} {
		set URL "https://api.binance.com/api/v3/order"
		
		set Query [::http::formatQuery [array get OrderArray]]
		set Query [string range [generate_request_signature "?$Query"] 1 end]
		puts "create_order_test...Query=$Query"
		
		set Result [binance_request $URL $Query]
		if {$Result eq ""} {
			return;
		}
		puts "create_order_test...Result=$Result"
		
		set ResultDict [json::json2dict $Result]
		puts "create_order_test...ResultDict=$ResultDict"
	}
	
	proc create_order_test {} {
		set URL "https://api.binance.com/api/v3/order/test"
		set Query [::http::formatQuery \
			symbol "BNBBTC" \
			side "BUY" \
			type "MARKET" \
			quantity 5 \
			newOrderRespType "FULL" \
		]
		set Query [string range [generate_request_signature "?$Query"] 1 end]
		puts "create_order_test...Query=$Query"
		set Result [binance_request $URL $Query]
		if {$Result eq ""} {
			return;
		}
		puts "create_order_test...Result=$Result"
		
		set ResultDict [json::json2dict $Result]
		puts "create_order_test...ResultDict=$ResultDict"
	}

# ---------------------------------------- Target Form --------------------------------------------
	
	# The Target Table/Form is used to monitor specific price target and even trend targets.
	# The idea is find the exact second that a ticker's price has broken above/below the target.
	
	# Simple price targets can be monitored as well as trends. A trend is nothing more than a sloped
	# line with the formula "y=mx+b". To calculate the "m" and "b" values, we need two timestamps with
	# the price at those times. In this case the "x" variable indicates the number of candles. Given
	# the current timestamp, the current candle number can be determined. The current candle number is
	# substituted into the formula to give us the current price target.
	
	
	# The form provides a way to enter price targets or trends to monitor. A simple target price is
	# needed for high_target and low_target. High and low indicate whether the target is higher or lower
	# than the current price.
	# The higher_trend_target and lower_trend_target trends need two timestamp,price data points to
	# determine the formula of the trend.
	proc target_form_create {} {
		variable _form_array
		target_form_array_setup
		
		# package require Tk
		package require BWidget
		
		
		pack [labelframe .lf1 -text "Frame 1"]
		
		pack [frame .lf1.r1]
		pack [label .lf1.r1.l -text "Symbol:  "]
		pack [entry .lf1.r1.e -textvariable crypto_data::_form_array(symbol)]
		
		pack [frame .lf1.r2]
		pack [label .lf1.r2.l -text "Interval:  "]
		pack [ComboBox .lf1.r2.e -textvariable crypto_data::_form_array(interval)]
		.lf1.r2.e insert end "1M" "1w" "1d" "12h" "4h" "2h" "1h" "15m" "5m" "3m" "1m"
		
		pack [frame .lf1.r3]
		pack [label .lf1.r3.l -text "Target Type:  "]
		pack [ComboBox .lf1.r3.e -textvariable crypto_data::_form_array(targetType)]
		.lf1.r3.e insert end "high_target" "low_target" "lower_trend_target" "higher_trend_target"
		
		pack [labelframe .lf2 -text "Frame 2"]
		
		pack [frame .lf2.r1]
		pack [label .lf2.r1.l -text "Target:  "]
		pack [entry .lf2.r1.e -textvariable crypto_data::_form_array(target)]
		
		pack [labelframe .lf3 -text "Frame 3"]
		
		pack [frame .lf3.r1]
		pack [label .lf3.r1.l -text "TimeStamp 1:  "]
		pack [entry .lf3.r1.e -textvariable crypto_data::_form_array(timeStamp1)]
		
		pack [frame .lf3.r2]
		pack [label .lf3.r2.l -text "Price 1:  "]
		pack [entry .lf3.r2.e -textvariable crypto_data::_form_array(price1)]
		
		pack [frame .lf3.r3]
		pack [label .lf3.r3.l -text "TimeStamp 2:  "]
		pack [entry .lf3.r3.e -textvariable crypto_data::_form_array(timeStamp2)]
		
		pack [frame .lf3.r4]
		pack [label .lf3.r4.l -text "Price 2:  "]
		pack [entry .lf3.r4.e -textvariable crypto_data::_form_array(price2)]
		
		pack [button .b -text "Submit" -command [namespace code target_form_submit]]
	}
	
	# Once the for is submitted we need to add the target/trend to our global stream dict
	proc target_form_submit {} {
		variable _kline_streams_dict
		variable _form_array
		
		set Stream "${_form_array(symbol)}@kline_${_form_array(interval)}"
		puts $Stream
		
		switch $_form_array(targetType) {
			higher_trend_target -
			lower_trend_target {
				set _form_array(timeStamp1) [clock scan $_form_array(timeStamp1)] 
				set _form_array(timeStamp2) [clock scan $_form_array(timeStamp2)] 
				
				set IntervalSeconds [expr {[get_milliseconds_from_interval $_form_array(interval)] / 1000}]
				set Slope [expr {($_form_array(price2) - $_form_array(price1)) / (($_form_array(timeStamp2) - $_form_array(timeStamp1)) / $IntervalSeconds)}]
				::dict set _kline_streams_dict $Stream targets $_form_array(targetType) [dict create \
					interval $_form_array(interval) \
					initial_timestamp $_form_array(timeStamp1) \
					formula "${Slope} * %_x + $_form_array(price1)" \
					active 1 \
					target "" \
				]
			}
			high_target -
			low_target {
				::dict set _kline_streams_dict $Stream targets $_form_array(targetType) [dict create \
					target $_form_array(target) \
					active 1 \
				]
			}
		}
		setup_volume_ma $Stream
		reset_stream
		target_form_array_setup
	}
	
	proc target_form_array_setup {} {
		variable _form_array
		
		set _form_array(symbol) ""
		set _form_array(interval) ""
		set _form_array(targetType) "high_target"
		set _form_array(target) ""
		set _form_array(timestamp1) ""
		set _form_array(timestamp2) ""
		set _form_array(price1) ""
		set _form_array(price2) ""
	}

# ---------------------------------------- Targets Table --------------------------------------------
	
	# For displaying all the targets/trends
	proc setup_targets_table {} {
		package require Tk
		package require tablelist
		
		variable _targets_table
		variable _targets_table_data
		
		set _targets_table [tablelist::tablelist .t -columntitles [list "Symbol" "Interval" "Target Type" "Current Price" "Target" "Volume" "Average Volume"]]
		$_targets_table configure -listvariable crypto_data::_targets_table_data -labelcommand [namespace code sort_targets_table]
		$_targets_table configure -stretch all -background white -stripefg black -stripebg #F6F9FB -labelpady 5 -spacing 5
		pack $_targets_table -fill both -expand 1 -side top
		
		$_targets_table columnconfigure 0 -title "Symbol" -name index -sortmode dictionary
		$_targets_table columnconfigure 1 -title "Interval" -name index -sortmode dictionary
		$_targets_table columnconfigure 2 -title "Target Type" -name index -sortmode dictionary
		$_targets_table columnconfigure 3 -title "Current Price" -name index -sortmode real
		$_targets_table columnconfigure 4 -title "Target" -name index -sortmode real
		$_targets_table columnconfigure 5 -title "Volume" -name index -sortmode real
		$_targets_table columnconfigure 6 -title "Average Volume" -name index -sortmode real
		
		refresh_targets_table
	}
	
	# Refreshes the data displayed in the targets table.
	# The data is stored in a list of lists. Where each outer list is a row and each inner list element
	# are cell values.
	proc refresh_targets_table {} {
		variable _targets_table_data
		variable _kline_streams_dict
		
		set _targets_table_data {}
		foreach Stream [::dict keys $_kline_streams_dict] {
			set Symbol [string toupper [lindex [split $Stream "@"] 0]]
			set Interval [lindex [split $Stream "_"] 1]
			
			set CurrentPrice [::dict get $_kline_streams_dict $Stream volume current_price]
			set Volume [::dict get $_kline_streams_dict $Stream volume current_volume]
			set AverageVolume [::dict get $_kline_streams_dict $Stream volume moving_average]
			
			foreach TargetType [::dict keys [::dict get $_kline_streams_dict $Stream targets]] {
				if {$TargetType eq "volume"} {continue}
				set Target [::dict get $_kline_streams_dict $Stream targets $TargetType target]
				lappend _targets_table_data [list $Symbol $Interval $TargetType $CurrentPrice $Target $Volume $AverageVolume]
			}
		}
	}
	
	# Simple sorting when column headers are toggled
	proc sort_targets_table {TableWidget ColumnIndex} {
		if {[$TableWidget sortcolumn] eq $ColumnIndex} {
			if {[$TableWidget sortorder] eq "decreasing"} {
				$TableWidget sortbycolumn $ColumnIndex -increasing
			} else {
				$TableWidget sortbycolumn $ColumnIndex -decreasing
			}
		} else {
			$TableWidget sortbycolumn $ColumnIndex -decreasing
		}
	}
	
# ---------------------------------------- Data Stream Helpers --------------------------------------------
	
	# These procedures are used to calculate real time indicators for the tickers we are monitoring.
	# Indicators like, price action, volume, rsi, moving averages, etc. can be valuable to know 
	# along side a target price or trend line being broken.
	
	proc setup_real_time_indicators {Stream} {
		variable _kline_streams_dict
		
		set Symbol [string toupper [lindex [split $Stream "@"] 0]]
		set Interval [lindex [split $Stream "_"] 1]
		set History [get_historic_quote $Symbol $Interval 250 ""]
		if {[llength $History] < 1} {
			return
		}
		
		set TotalGains 0.0
		set TotalLoss 0.0
		set AverageGain 0.0
		set AverageLoss 0.0
		set PrevClose ""
		set Counter 0
		set TotalVolume 0.0
		set High ""
		set Low ""
		
		foreach Element $History {
			set Current [dict get $Element close]
			
			# ------------------Volume-----------------
			set ThisVolume 0.0
			switch [string first "BTC" $Symbol] {
				0 {
					#BTC - Base
					set ThisVolume [dict get $Element volume]
				}
				default {
					#BTC - Quote
					set ThisVolume [dict get $Element quote_asset_volume]
				}
			}
			set TotalVolume [expr {$TotalVolume + $ThisVolume}]
			
			# ------------------RSI-----------------
			if {$PrevClose eq ""} {set PrevClose [dict get $Element open]}
			set Change [expr {$Current - $PrevClose}]
			if {$Counter < 14} {
				if {$Change < 0} {
					set TotalLoss [expr {$TotalLoss - $Change}]
				} else {
					set TotalGains [expr {$TotalGains + $Change}]
				}
				set AverageGain [expr {$TotalGains / 14}]
				set AverageLoss [expr {$TotalLoss / 14}]
			} else {
				if {$Change < 0} {
					set AverageLoss [expr {($AverageLoss * 13 - $Change) / 14}]
					set AverageGain [expr {($AverageGain * 13) / 14}]
				} else {
					set AverageGain [expr {($AverageGain * 13 + $Change) / 14}]
					set AverageLoss [expr {($AverageLoss * 13) / 14}]
				}
				set RS [expr {$AverageGain / $AverageLoss}]
				set RSI [expr {100 - (100 / (1 + $RS))}]
			}
			
			# ------------------Price Action-----------------
			if {$High eq "" || $Current > $High} {
				set High $Current
			}
			if {$Low eq "" || $Current < $Low} {
				set Low $Current
			}
			set PrevClose $Current
			
			incr Counter
		}
		set AverageVolume [expr {$TotalVolume / $Counter}]
		set CloseTime [dict get [lindex $History end] close_time]
		
		puts "setup_real_time_indicators...Stream=$Stream, AverageVolume=$AverageVolume, RSI=$RSI, High=$High, Low=$Low"
	}
	
	proc setup_volume_ma {Stream} {
		variable _kline_streams_dict
		
		set Symbol [string toupper [lindex [split $Stream "@"] 0]]
		set Interval [lindex [split $Stream "_"] 1]
		set History [get_historic_quote $Symbol $Interval 21 ""]
		
		set TotalVolume 0.0
		foreach Element $History {
			dict with Element {}
			switch [string first "BTC" $Symbol] {
				-1 {
					#BTC - Not Found
					return
				}
				0 {
					#BTC - Base
					set ThisVolume $volume
				}
				default {
					#BTC - Quote
					set ThisVolume $quote_asset_volume
				}
			}
			if {$ThisVolume eq ""} {
				continue
			}
			set TotalVolume [expr {$TotalVolume + $ThisVolume}]
		}
		set AverageVolume [expr {$TotalVolume / [llength $History]}]
		set CloseTime [dict get [lindex $History end] close_time]
		
		::dict set _kline_streams_dict $Stream volume [::dict create \
			current_price $close \
			current_volume $ThisVolume \
			moving_average $AverageVolume \
			close_time $CloseTime \
		]
		
		update_dict_file
	}

	# Compare the current price with the target price
	proc examine_trend_line {TimeStamp Trend} {
		set Interval [::dict get $Trend interval]
		set IntervalSeconds [expr {[get_milliseconds_from_interval $Interval] / 1000}]
		
		set InitialTimeStamp [::dict get $Trend initial_timestamp]
		set X [expr {($TimeStamp - $InitialTimeStamp) / $IntervalSeconds}]
		
		set Formula [::dict get $Trend formula]
		set Formula [string map [list "%_x" $X] $Formula]
		
		set PriceTarget [format %.8f [expr [subst {$Formula}]]]
		return $PriceTarget
	}
	
# ----------------------------------------Data Streams--------------------------------------------
	
	# This procedure makes the API call to Binance to establish data streams with the tickers
	# we would like to monitor. The tickers come from the _kline_streams_dict keys.
	proc reset_stream {} {
		variable _kline_stream_socket
		variable _kline_streams_dict
		
		if {$_kline_stream_socket ne ""} {
			close_data_stream
		}
		if {[llength [::dict keys $_kline_streams_dict]] == 0} {
			return
		}
		
		set Url "wss://stream.binance.com:9443/stream?streams="
		foreach Stream [::dict keys $_kline_streams_dict] {
			append Url "${Stream}/"
		}
		set Url [string range $Url 0 end-1]
		puts "connect_to_kline_stream, Url=$Url"
		
		set _kline_stream_socket [::websocket::open $Url [namespace code kline_stream_in]]
	}
	
	# Close data streams - done every time we update our tickers list (_kline_streams_dict)
	proc close_data_stream {} {
		variable _kline_stream_socket
		
		::websocket::close $_kline_stream_socket
		set _kline_stream_socket ""
	}
	
	# This is where all incoming traffic from the data stream comes.
	proc kline_stream_in {Socket Type Message} {
		variable _kline_streams_dict
		
		switch $Type {
			"connect" {
				puts "Connected on $Socket"
			}
			"ping" {
				puts "kline_stream_in... ping on $Socket"
				websocket::send $Socket "pong" ""
			}
			"text" {
				set PayLoad [::json::json2dict $Message]
				
				set Stream [::dict get $PayLoad stream]
				set Symbol [::dict get $PayLoad data s]
				set Time [::dict get $PayLoad data k t]
				set TimeStamp [string range $Time 0 end-3]
				set Current [::dict get $PayLoad data k c]
				set Volume [::dict get $PayLoad data k q]
				set AverageVolume [::dict get $_kline_streams_dict $Stream volume moving_average]
				# puts "kline_stream_in ($Time), $Symbol - $Current"
				
				::dict set _kline_streams_dict $Stream volume current_volume $Volume
				::dict set _kline_streams_dict $Stream volume current_price $Current
				
				if {$Volume > [expr {$AverageVolume * 2}]} {
					puts "*** kline_stream_in, VOLUME BREAKOUT - $Symbol ***"
				}
				
				# Check all of our targets for this ticker - may be more than 1
				foreach TargetType {higher_trend_target lower_trend_target high_target low_target} {
					if {[::dict exists $_kline_streams_dict $Stream targets $TargetType]} {
						if {![::dict get $_kline_streams_dict $Stream targets $TargetType active]} {
							continue
						}
						switch $TargetType {
							higher_trend_target -
							lower_trend_target {
								set Target [examine_trend_line $TimeStamp [::dict get $_kline_streams_dict $Stream targets $TargetType]]
								::dict set _kline_streams_dict $Stream targets $TargetType target $Target
							}
							high_target -
							low_target {
								set Target [::dict get $_kline_streams_dict $Stream targets $TargetType target]
							}
						}
						puts "kline_stream_in...$Symbol $TargetType - Target=$Target, Current=$Current, AverageVolume=$AverageVolume, Volume=$Volume"
						
						set Operand ">"
						switch $TargetType {
							low_target -
							lower_trend_target {
								set Operand "<"
							}
						}
						
						# Write to a log if we break a target/trend
						if [subst {$Current $Operand $Target}] {
							puts "*** kline_stream_in, $Symbol has broke $TargetType ***"
							write_to_log "*** $Symbol has broke $TargetType *** Target=$Target, Current=$Current"
							
							::dict unset _kline_streams_dict $Stream targets $TargetType
							if {[llength [::dict keys [::dict get $_kline_streams_dict $Stream targets]]] == 0} {
								::dict unset _kline_streams_dict $Stream
							}
							update_dict_file
							reset_stream
						}
					}
				}
				
				if {$Time > [::dict get $_kline_streams_dict $Stream volume close_time]} {
					set Timer [clock clicks -milliseconds]
					setup_volume_ma $Stream
				}
				refresh_targets_table
				puts "--------------------------------------------------------"
			}
			"close" -
			"disconnect" {
				
			}
		}
		# "data":{
		  # "e": "kline",     // Event type
		  # "E": 123456789,   // Event time
		  # "s": "BNBBTC",    // Symbol
		  # "k": {
			# "t": 123400000, // Kline start time
			# "T": 123460000, // Kline close time
			# "s": "BNBBTC",  // Symbol
			# "i": "1m",      // Interval
			# "f": 100,       // First trade ID
			# "L": 200,       // Last trade ID
			# "o": "0.0010",  // Open price
			# "c": "0.0020",  // Close price
			# "h": "0.0025",  // High price
			# "l": "0.0015",  // Low price
			# "v": "1000",    // Base asset volume
			# "n": 100,       // Number of trades
			# "x": false,     // Is this kline closed?
			# "q": "1.0000",  // Quote asset volume
			# "V": "500",     // Taker buy base asset volume
			# "Q": "0.500",   // Taker buy quote asset volume
			# "B": "123456"   // Ignore
		  # }
		# }
	}
	proc watch_all_tickers {} {
		set Url "wss://stream.binance.com:9443/!miniTicker@arr"
		set market_stream_socket [::websocket::open $Url [namespace code market_stream_in]]
	}
	proc market_stream_in {Socket Type Message} {
		switch $Type {
			"connect" {
				puts "Connected on $Socket"
			}
			"ping" {
				puts "kline_stream_in... ping on $Socket"
				websocket::send $Socket "pong" ""
			}
			"text" {
				set PayLoad [::json::json2dict $Message]
				
				set Stream [::dict get $PayLoad stream]
				
			}
		}
	}	
	
# ----------------------------------------Helper Procs--------------------------------------------

	# Simple helpers.

	proc get_btc_symbols {} {
		set URL "https://api.binance.com/api/v1/exchangeInfo"
		set ExchangeInfo [json::json2dict [binance_request $URL]]
		set Symbols [dict get $ExchangeInfo "symbols"]
		set BTCsymbols [list]
		foreach btcSymbol $Symbols {
			dict with btcSymbol {}
			if {[string first "BTC" $symbol] >= 0} {
				lappend BTCsymbols $symbol
			}
		}
		return $BTCsymbols
	}
	
	proc get_multiplier_from_interval {Interval} {
		switch $Interval {
			"1w" {return [expr {1.0 / 7}]}
			"3d" {return [expr {1.0 / 3}]}
			"1d" {return 1}
			"12h" {return 2}
			"8h" {return 3}
			"6h" {return 4}
			"4h" {return 6}
			"2h" {return 12}
			"1h" {return 24}
			"30m" {return 48}
			"15m" {return 96}
			"5m" {return 288}
			"3m" {return 480}
			"1m" {return 1440}
		}
	}

	proc get_milliseconds_from_interval {Interval} {
		switch $Interval {
			"1w" {return [expr {1 * 7 * 24 * 60 * 60 * 1000}]}
			"3d" {return [expr {3 * 24 * 60 * 60 * 1000}]}
			"1d" {return [expr {1 * 24 * 60 * 60 * 1000}]}
			"12h" {return [expr {12 * 60 * 60 * 1000}]}
			"8h" {return [expr {8 * 60 * 60 * 1000}]}
			"6h" {return [expr {6 * 60 * 60 * 1000}]}
			"4h" {return [expr {4 * 60 * 60 * 1000}]}
			"2h" {return [expr {2 * 60 * 60 * 1000}]}
			"1h" {return [expr {1 * 60 * 60 * 1000}]}
			"30m" {return [expr {30 * 60 * 1000}]}
			"15m" {return [expr {15 * 60 * 1000}]}
			"5m" {return [expr {5 * 60 * 1000}]}
			"3m" {return [expr {3 * 60 * 1000}]}
			"1m" {return [expr {1 * 60 * 1000}]}
		}
	}
	
	proc every {MS Body} {
		variable _every
		
		if {$MS eq "cancel"} {
			after cancel $_every($Body)
			unset _every($Body)
			return
		}
		set _every($Body) [info level 0]
		eval $Body
		after $MS [info level 0]
	}
}



crypto_data::main
















