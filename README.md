# stock-crypto-data
Using various API's to retrieve stock and crypto trading data

Here I've got all my scripts that retrieve and analyse stock and crypto data. 

The crypto data I am analysing is coming from Binance's
API. I am mostly using their end point that returns candlestick data on whatever timeframe, with a max of 500 candles. Binance also offers
streaming capabilities which I have dabbled with.

The stock data is coming from a few different sources. The main API used Questrade. I am a paying customer at Questrade and they
provide real time stock data through the trading platform and API. A couple other API's I have included are Alpha Vantage and IEXtrading.
IEXtrading provides quality reporting on financials and even new articles. Alpha is not that great compared to the others.

There is also a couple of other API's I am using to retrieve an up to date list of symbols on particular markets. One API provides
and easy way to get symbols lists for american exchanges but not the TSX. Another API provides symbols on the TSX but it's a tougher
API call since it retruns an Excel spreadsheet. The Excel spreadsheet must be read in using a package called Tcom, which can interact
with Microsoft products such as Excel.
