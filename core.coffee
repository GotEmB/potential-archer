request = require "request"
async = require "async"
db = require "./db"
mapper = require "./mapper"

globals =
	searchRequestsPerMinute: 20
	apiRequestsPerMinute: 80
	apiRootUrl: "https://api.github.com"

githubApi = ({url, qs} = {}, callback) ->
	qs ?= {}
	qs.access_token = process.env.GH_ACCESS_TOKEN
	request
		method: "GET"
		headers: 'User-Agent': "request"
		url: globals.apiRootUrl + url
		qs: qs
	, callback

searchJobs = []
apiJobs = []

exports.getAndInsertTopRepositories = (number) ->
	[1 .. Math.ceil(number / 100)].forEach (page) ->
		console.log "Adding Search Job to fetch page #{page} of Top Repositories"
		searchJobs.push ->
			console.log "Fetching page #{page} of Top Repositories"
			githubApi
				url: "/search/repositories"
				qs:
					q: "created:>1970-01-01"
					sort: "stars"
					per_page: Math.min 100, number - (page - 1) * 100
					page: page
			, (err, response, body) ->
				items = JSON.parse(body).items
				async.each items, (item, callback) ->
					db.Repository.findOneAndUpdate {fullName: item.full_name},
						fullName: item.full_name
						stars: item.stargazers_count
						forks: item.forks_count
					, upsert: true, new: true
					, (err, repo) ->
						fetchRepoLanguages repo
						fetchRepoCommits repo
						callback()
				, ->
					console.log "Saved #{items.length} repositories of Top Repositories from page #{page}"

fetchRepoLanguages = (repo) ->
	console.log "Adding API Job to fetch language statistics for repo #{repo.fullName}"
	apiJobs.push ->
		console.log "Fetching language statistics for repo #{repo.fullName}"
		githubApi
			url: "/repos/#{repo.fullName}/languages"
		, (err, response, body) ->
			languages = []
			for language, lineCount of JSON.parse body
				languages.push language: language, lineCount: lineCount
			db.Repository.update {_id: repo._id}, languages: languages, (err, count) ->
				console.log "Saved language statistics for repo #{repo.fullName}"

fetchRepoCommits = (repo, date = "") ->
	console.log "Adding API Job to fetch commits for repo #{repo.fullName}"
	apiJobs.push ->
		console.log "Fetching commits for repo #{repo.fullName}"
		githubApi opts =
			url: "/repos/#{repo.fullName}/commits"
			qs:
				until: date
				per_page: 100
		, (err, response, body) ->
			items = JSON.parse(body)
			if items.length > 0
				async.each items, (item, callback) ->
					date = item.commit.author.date
					return callback() unless item.author?
					getUserOrCreateUser item.author.login, (err, user) ->
						db.Commit.findOneAndUpdate {sha: item.sha},
							sha: item.sha
							author: user._id
							repository: repo._id
							timestamp: item.commit.author.date
						, upsert: true, new: true
						, (err, commit) ->
							fetchCommit repo, commit unless err?
							callback()
				, ->
					console.log "Saved commits for repo #{repo.fullName}"
					fetchRepoCommits repo, date


getUserOrCreateUser = (username, callback) ->
	db.User.findOneAndUpdate {username: username}, {username: username}, upsert: true, new: true, (err, user) ->
		callback err, user

fetchCommit = (repo, commit) ->
	console.log "Adding API Job to fetch commit #{commit.sha}"
	apiJobs.push ->
		console.log "Fetching commit #{commit.sha}"
		githubApi
			url: "/repos/#{repo.fullName}/commits/#{commit.sha}"
		, (err, response, body) ->
			changes = []
			com = undefined
			try
				com = JSON.parse(body)
			catch e
				return console.error "Invalid JSON: ", body
			items = com.files
			async.each items, (item, callback) ->
				fileName = item.filename
				changesMade = item.changes
				language = mapper.getLanguage fileName.substring fileName.lastIndexOf "."
				db.Commit.findOneAndUpdate {_id: commit._id}, {$addToSet: {changes: {language: language}}}, new: true, (err, resp) ->
					return callback err if err?
					db.Commit.findOneAndUpdate {_id: commit._id, "changes.language": language }, {$inc: {"changes.$.count": changesMade}}, new: true, (err, resp) ->
						return callback err if err?
						callback()
			, ->
				console.log "Saved commit #{commit.sha}"

exports.startJobs = ->
	intervalDescriptor = null
	doTask = ->
		console.log "#{searchJobs.length} Search Jobs and #{apiJobs.length} API Jobs in queue"
		clearInterval intervalDescriptor if searchJobs.length is 0 and apiJobs.length is 0
		searchJobs.shift()?() for i in [0 ... globals.searchRequestsPerMinute]
		apiJobs.shift()?() for i in [0 ... globals.apiRequestsPerMinute]
		undefined
	intervalDescriptor = setInterval doTask, 1000 * 60 # Runs every minute
	doTask()
