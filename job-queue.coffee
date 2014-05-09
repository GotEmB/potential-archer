class JobQueue
	constructor: ->
		@accessTokens = []
	addAccessTokensWithRateLimit: (tokens, limit, period) ->
		@accessTokens.push tokens.map((x) -> new AccessToken x, limit, period)...
	addToQueue: (jobs...) ->
		jobs.forEach (job) =>
			sts =
				@accessTokens
					.map (x) -> accessToken: x, timestamp: x.getNextTimestamp()
					.sort (x, y) -> x.timestamp - y.timestamp
			sts[0].accessToken.timestamps.push sts[0].timestamp
			setTimeout job, sts[0].timestamp - new Date

class AccessToken
	constructor: (@token, @limit, @period) ->
		@timestamps = []
	getNextTimestamp: ->
		clearTimestamp = new Date
		clearTimestamp.setSeconds clearTimestamp.getSeconds() - @period
		@timestamps.shift() while @timestamps[0] < clearTimestamp
		nowTimestamp = new Date
		if @timestamps.length < @limit
			nowTimestamp
		else
			nextTimestamp = new Date @timestamps[0]
			nextTimestamp.setSeconds nextTimestamp.getSeconds() + @period
			nextTimestamp

module.exports = JobQueue