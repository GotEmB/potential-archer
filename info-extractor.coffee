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
			for activity in resp
				new db.RepoCommitActvity
					language: activity._id.language
					repository: activity._id.repo
					changes: activity.total
				.save (err, resp)->
					return done err if err?
					return done null, resp

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
			for activity in resp
				new db.UserCommitActvity
					language: activity._id.language
					repository: activity._id.repo
					author: activity._id.author
					changes: activity.total
				.save (err, resp)->
					return done err if err?
					return done null, resp

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
			## find all repositories to which the author has committed
			db.UserCommitActvity.distinct 'repository', 'author' : contribution._id.author, (err, repos) ->
				for repo in repos
					total_line_count += repo_act[repo][contribution._id.language]
				## total_line_count contains the total changes made for a particular language for a particular repo to which 
				## the author has contributed to 
				db.ContributionRatio.findOneAndUpdate { author : contribution._id.author } 
				, { $addToSet: {contribution_ratio : { language: contribution._id.language , ratio : language_ratio[contribution._id.language] * contribution.contribution / total_line_count } } }
				, upsert: true, new: true
				, (err, resp) ->
					console.log err if err?
					do done
		,(err) ->
			console.log err if err?
			callback
			
analyze_languagewise_reposactivity (err,resp)->
	console.log err if err?
	language_importance_ratio = {}
	total_commits = 0
	###
		language_importance_ratio  will contain the importance ratio of a particular language ie. ratio of total commits made for
		a particular language to the total changes (commits) ever made
	###
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
		