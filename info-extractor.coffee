db = require './db'
async = require 'async'
mongoose = require 'mongoose'
request = require 'request'
jq = require 'job-queue'
getcreads = require './get-creds'

extract_repo_activity = (done) ->
	db.Commit.aggregate $match: {}
	.unwind 'changes'
	.project  
		author : '$author' 
		language : '$changes.language'
		change : '$changes.count'
		repo : '$repository' 
	.group
		_id: 
			language: '$language'
			repo: '$repo'
		total:  $sum: '$change' 
	.exec (err, resp)->
			console.log err if err?
			async.each resp,
			(activity, callback)->
				new db.RepoCommitActvity
					language: activity._id.language
					repository: activity._id.repo
					changes: activity.total
				.save (err, resp)->
					callback err, resp
			,
			(err)->
				return done err, null

extract_user_activity =  (done) ->
	db.Commit.aggregate $match: {}
	.unwind 'changes'
	.project  
		author : '$author' 
		language : '$changes.language'
		change : '$changes.count'
		repo : '$repository' 
	.group
		_id: 
			language: '$language'
			repo: '$repo'
			author: '$author'
		total:  $sum: '$change' 
	.exec (err, resp)->
			console.log err if err?
			async.each resp,
			(activity, callback)->
				new db.UserCommitActvity
					language: activity._id.language
					repository: activity._id.repo
					author: activity._id.author
					changes: activity.total
				.save (err, resp)->
					callback err, resp
			,
			(err)->
				return done err, null

update_avg_author_weights = (done) -> 
	db.Repository.aggregate $match: {}
	.unwind 'contributors'
	.project
		author: '$contributors.user'
		weight: '$contributors.weight'
	.group
		_id:
			id: '$author'
		avg: $avg: '$weight'
	.exec (err, resp) ->
		console.log err if err?
		async.each resp,
		(authorwt, callback) ->
			new db.UserAvgWeight
				author: authorwt._id.id
				weight: authorwt.avg
			.save (err, resp)->
				callback err, resp
		,
		(err) ->
			return done err, null

update_repo_author_weights = (done) ->
	db.Repository.aggregate $match: {}
	.unwind 'contributors'
	.group
		_id:
			id: '$_id'
		total: $sum: '$contributors.weight'
		authorIds : $addToSet : '$contributors.user'
	.exec (err, resp) ->
		console.log err if err?
		async.each resp
		,(repo, callback)->
			if repo.authorIds? && repo.authorIds.length > 0
				async.each repo.authorIds
				,(id, callback1) ->
					db.Repository.update { _id: repo._id.id, 'contributors.user': id }
						, { $mul: { 'contributors.$.weight': 1/repo.total } }
						, (err, resp) ->
							callback1 err, resp 
				,(err) ->
					callback err
		,(err) ->
			update_avg_author_weights (err, resp) ->
				done err, null

analyze_languagewise_reposactivity = (done)->
	repo_act = {}
	db.RepoCommitActvity.aggregate $match: {}
	.group
		_id:
			repository: '$repository'
			language: '$language'
		total_changes: $sum: '$changes'
	.exec (err, resp) ->
		return done err, null if err?
		for repo_activity in resp
			if not repo_act[repo_activity._id.repository]?
				repo_act[repo_activity._id.repository] = {}
			repo_act[repo_activity._id.repository][repo_activity._id.language] = repo_activity.total_changes
		return done null, repo_act		

analyze_languagewise_contribution = (language_ratio ,repo_act, callback)->
	db.UserCommitActvity.aggregate $match: {}
	.group
		_id:
			author: '$author'
			language: '$language'
		contribution : $sum: '$changes'
	.exec (err, resp) ->
		console.log err if err?
		async.each resp, (contribution, done) ->
			total_line_count = 0
			for repo in Object.keys(repo_act)
				total_line_count += repo_act[repo][contribution._id.language] ? 0
			db.ContributionRatio.findOneAndUpdate { author : contribution._id.author } 
			, { $addToSet: {contribution_ratio : { language: contribution._id.language , ratio : language_ratio[contribution._id.language] * contribution.contribution / total_line_count } } }
			, upsert: true, new: true
			, (err, resp) ->
				console.log err if err?
				do done
		,(err) ->
			console.log err if err?
			callback

extract_temporal_commit_info = (callback)->
	process.env.TZ = 'UTC'
	o = {}
	o.map = ()->
		dt = new Date 0
		dt.setMonth do this.timestamp.getMonth
		dt.setYear do this.timestamp.getFullYear
		dt.setDate 1

		ret = {}
		lang_changes = {}
		count = 0
		for change in this.changes
			if change.language? && dt?
				emit change.language , { "date" : dt.toUTCString() , "changes" : change.count}
			
	o.reduce = (lang, changes)->
		res = {}
		for change in changes
			if change.date?
				res[change.date] ?= 0
				res[change.date] += change.changes
		arr =
			for key, value of res
				date : key , changes : value
		ret = {}
		ret["lang"] = lang
		ret["temporal"] = arr
		ret
	o.out =  replace: "temporalcommits_new" 
	db.Commit.mapReduce o, (err, model, stats)->
		console.log stats
		callback err, model

## Remaining part: store temporal information
###
async.parallel [
	(callback) ->
		extract_temporal_commit_info (err,resp)->
			console.log "Completed -> extract_temporal_commit_info"
			callback err, null
	(callback) ->
		update_repo_author_weights (err, resp)->
			console.log "Completed -> update_repo_author_weights"
			callback err, null
	(callback) ->
		extract_repo_activity (err, resp)->
			console.log "Completed -> extract_repo_activity"
			callback err, null
	(callback) ->
		extract_user_activity (err, resp)->
			console.log "Completed -> extract_user_activity"
			callback err, null
	
]
, (err, results)->
	analyze_languagewise_reposactivity (err,resp)->
		console.log err if err?
		language_importance_ratio = {}
		total_commits = 0
		
		#language_importance_ratio  will contain the importance ratio of a particular language ie. ratio of total commits made for
		#a particular language to the total changes (commits) ever made
		
		for repo in Object.keys resp
			for lang_count in Object.keys resp[repo]
				if not language_importance_ratio[lang_count]?
					language_importance_ratio[lang_count] = 0
				language_importance_ratio[lang_count] += resp[repo][lang_count]
				total_commits += resp[repo][lang_count]

		for lang in Object.keys language_importance_ratio
			language_importance_ratio[lang] = language_importance_ratio[lang]/total_commits

		analyze_languagewise_contribution language_importance_ratio, resp, (err)->
			console.log err if err?
			console.log "Done..!!"
###

class GitHubApiConsumer
	constructor: (@cred) ->
		@nextTimestamp = new Date
	consume: ({path, qs, onExecute, callback} = {}) =>
		onExecute?()
		return callback err: "No API endpoint specified" unless path?
		qs ?= {}
		request
			method: "GET"
			headers: 'User-Agent': "request"
			url: "https://#{@cred.login}:#{@cred.password}@api.github.com#{path}"
			qs: qs
		, (err, response, body) =>
			unless err?
				@nextTimestamp = if Number(response.headers["x-ratelimit-remaining"]) is 0 then new Date Number response.headers["x-ratelimit-remaining"] else new Date
			callback err, response, body
		console.log "https://#{@cred.login}:#{@cred.password}@api.github.com#{path}"
	getNextTimestamp: =>
		@nextTimestamp

getcreads (err, creds) ->
	apiJobs = new jq creds.map (cred) -> new GitHubApiConsumer cred
	db.User.find (err, resp)->
		console.log err if err?
		async.eachLimit resp, 100, (usr, callback) ->
			apiJobs.enqueue thisJob =
				onExecute: ->
					console.log "Executing for #{usr.username}"
				path: "/users/#{usr.username}"
				callback: (err, resp, body) ->
					console.log err if err?
					if resp.statusCode >= 400
						if resp.statusCode is 404
							console.log "#{usr.username} not found"
							return callback()
						else
							console.log "Re-enqueuing job for #{usr.username}"
							return apiJobs.enqueue thisJob
					var1 = JSON.parse body
					console.log var1
					
					db.User.update username : usr.username, 
						$set :
							location : var1.location ? ""
							hireable : var1.hireable ? false
							followers : var1.followers ? 0
							following : var1.following ? 0
							name : var1.name ? ""
					, (err, resp) ->
						callback()
						console.log err if err?
						console.log "Done"