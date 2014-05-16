request = require "request"
async = require "async"
db = require "./db"
mapper = require "./mapper"
JobQueue = require "job-queue"
fs = require "fs"

globals =
	searchRequestsPerMinute: 20
	apiRequestsPerMinute: 80
	apiRootUrl: "https://api.github.com"

githubApi = ({url, qs} = {}, callback) ->
	return callback err: "No API endpoint specified" unless url?
	qs ?= {}
	request
		method: "GET"
		headers: 'User-Agent': "request"
		url: globals.apiRootUrl + url
		qs: qs
	, callback

access_tokens = []
try
	access_tokens = fs.readFileSync("access_tokens.txt", encoding: "utf8").split(/[\r\n]+/g).filter (x) -> x isnt ""
catch e
	access_tokens = [process.env.GH_ACCESS_TOKEN]

searchJobs = new JobQueue access_tokens.map((x) -> (request) -> request x), 20, 60
apiJobs = new JobQueue access_tokens.map((x) -> (request) -> request x), 82, 60

exports.getAndInsertTopRepositories = (number) ->
	[1 .. Math.ceil(number / 100)].forEach (page) ->
		console.log "Adding Search Job to fetch page #{page} of Top Repositories"
		searchJobs.enqueue (access_token) ->
			console.log "Fetching page #{page} of Top Repositories"
			githubApi
				url: "/search/repositories"
				qs:
					q: "created:>1970-01-01"
					sort: "stars"
					per_page: Math.min 100, number - (page - 1) * 100
					page: page
					access_token: access_token
			, (err, response, body) ->
				return console.error "Error at getAndInsertTopRepositories on page #{page}", err, response, body if err?
				items = JSON.parse(body).items ? []
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
	apiJobs.enqueue (access_token) ->
		console.log "Fetching language statistics for repo #{repo.fullName}"
		githubApi
			url: "/repos/#{repo.fullName}/languages"
			qs:
				access_token: access_token
		, (err, response, body) ->
			return console.error "Error at fetchRepoLanguages for repo #{repo.fullName}", err, response, body if err?
			languages = []
			for language, lineCount of JSON.parse body
				languages.push language: language, lineCount: lineCount
			db.Repository.update {_id: repo._id}, languages: languages, (err, count) ->
				console.log "Saved language statistics for repo #{repo.fullName}"

fetchRepoCommits = (repo, date = "") ->
	console.log "Adding API Job to fetch commits for repo #{repo.fullName}"
	apiJobs.enqueue (access_token) ->
		console.log "Fetching commits for repo #{repo.fullName}"
		githubApi opts =
			url: "/repos/#{repo.fullName}/commits"
			qs:
				until: date
				per_page: 100
				access_token: access_token
		, (err, response, body) ->
			return console.error "Error at fetchRepoCommits for repo #{repo.fullName}", err, response, body if err?
			items = JSON.parse(body) ? []
			if items.length > 0
				if date isnt ''
					items.shift()
				async.eachSeries items, (item, callback) ->
					date = item.commit.author.date
					return callback() unless item.author?
					getUserOrCreateUser item.author.login, (err, user) ->
						return callback() unless user?
						db.Commit.findOneAndUpdate {sha: item.sha},
							sha: item.sha
							author: user._id
							repository: repo._id
							timestamp: item.commit.author.date
						, upsert: true, new: true
						, (err, commit) ->
							fetchCommit repo, commit unless err?
							process.nextTick callback
				, ->
					console.log "Saved commits for repo #{repo.fullName}"
					fetchRepoCommits repo, date


getUserOrCreateUser = (username, callback) ->
	db.User.findOneAndUpdate {username: username}, {username: username}, upsert: true, new: true, (err, user) ->
		callback err, user

fetchCommit = (repo, commit) ->
	console.log "Adding API Job to fetch commit #{commit.sha}"
	apiJobs.enqueue (access_token) ->
		console.log "Fetching commit #{commit.sha}"
		githubApi
			url: "/repos/#{repo.fullName}/commits/#{commit.sha}"
			qs:
				access_token: access_token
		, (err, response, body) ->
			return console.error "Error at fetchCommit #{commit.sha}", err, response, body if err?
			changes = []
			items = JSON.parse(body).files ? []
			async.each items, (item, callback) ->
				fileName = item.filename
				changesMade = item.changes
				language = mapper.getLanguage fileName.substring fileName.lastIndexOf "."
				async.parallel [
					(callback) ->
						db.Commit.findOneAndUpdate {_id: commit._id}, {$addToSet: {changes: {language: language}}}, new: true, (err, resp) ->
							return callback err if err?
							db.Commit.findOneAndUpdate {_id: commit._id, "changes.language": language }, {$inc: {"changes.$.count": changesMade}}, new: true, (err, resp) ->
								return callback err if err?
								callback()
					, (callback) ->
						db.Repository.findOneAndUpdate {_id: repo._id}, {$addToSet: {contributors: {user: commit.author}}}, new: true, (err, resp) ->
							console.log err, resp if err?
							return callback err if err?
							db.Repository.findOneAndUpdate {_id: repo._id, "contributors.user": commit.author }, {$inc: {"contributors.$.weight": changesMade}}, new: true, (err, resp) ->
								return callback err if err?
								callback()
				], callback
			, ->
				console.log "Saved commit #{commit.sha}"