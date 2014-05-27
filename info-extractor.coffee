db = require './db'
async = require 'async'

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
		console.log resp
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

update_avg_author_weights (err, resp)->


## Remaining part: store temporal information

async.parallel [
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
