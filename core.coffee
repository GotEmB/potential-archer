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

access_tokens =
	try
		fs.readFileSync("access_tokens.txt", encoding: "utf8").split(/[\r\n]+/g).filter (x) -> x isnt ""
	catch
		[process.env.GH_ACCESS_TOKEN]

searchJobs = new JobQueue access_tokens.map((x) -> (request) -> request x), 20, 60
apiJobs = new JobQueue access_tokens.map((x) -> (request) -> request x), 82, 60

exports.getAndInsertTopRepositories = (number) ->
	fetchRepos number, 1 << 20, ->
		console.log "All done!"

fetchRepos = (totalRepos = 1000, stars, callback) ->
	maxStars = 0
	async.eachSeries [1 .. 10], (page, callback) ->
		console.log "Adding Search Job to fetch page #{page} of Top Repositories with stars <= #{stars}"
		searchJobs.enqueue (access_token) ->
			console.log "Fetching page #{page} of Top Repositories"
			githubApi
				url: "/search/repositories"
				qs:
					q: "stars:<=#{stars}"
					sort: "stars"
					per_page: 100
					page: page
					access_token: access_token
			, (err, response, body) ->
				return console.error "Error at getAndInsertTopRepositories on page #{page} with stars <= #{stars}", err, response, body if err?
				items = JSON.parse(body).items ? []
				async.eachLimit items, 10, (item, callback) ->
					maxStars = Math.max maxStars, item.stargazers_count
					db.Repository.findOneAndUpdate {fullName: item.full_name},
						fullName: item.full_name
						stars: item.stargazers_count
						forks: item.forks_count
						$inc:
							updated: 1
					, upsert: true, new: true
					, (err, repo) ->
						if repo.updated isnt 1
							console.log "Skipping repo #{repo.fullName}"
							return callback()
						async.parallel [
							(callback) -> fetchRepoLanguages repo, callback
							(callback) -> fetchRepoCommits repo, "", callback
						], ->
							console.log "Saved repository #{repo.fullName}"
							callback()
				, ->
					console.log "Saved #{items.length} repositories of Top Repositories from page #{page} with stars <= #{stars}"
					callback()
	, ->
		db.Repository.count (err, count) ->
			if count >= totalRepos
				callback()
			else
				fetchRepos totalRepos, (if maxStars is stars then maxStars - 1 else maxStars), callback

fetchRepoLanguages = (repo, callback) ->
	console.log "Adding API Job to fetch language statistics for repo #{repo.fullName}"
	apiJobs.enqueue (access_token) ->
		console.log "Fetching language statistics for repo #{repo.fullName}"
		githubApi
			url: "/repos/#{repo.fullName}/languages"
			qs:
				access_token: access_token
		, (err, response, body) ->
			if err?
				console.error "Error at fetchRepoLanguages for repo #{repo.fullName}", err, response, body
				return callback()
			languages = []
			for language, lineCount of JSON.parse body
				languages.push language: language, lineCount: lineCount
			db.Repository.update {_id: repo._id}, languages: languages, (err, count) ->
				console.log "Saved language statistics for repo #{repo.fullName}"
				callback()

fetchRepoCommits = (repo, date = "", callback) ->
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
			if err?
				console.error "Error at fetchRepoCommits for repo #{repo.fullName}", err, response, body
				return callback()
			items = JSON.parse(body) ? []
			if items.length > 0
				if date isnt ''
					items.shift()
				async.eachLimit items, 100, (item, callback) ->
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
							return callback() if err?
							fetchCommit repo, commit, callback
				, ->
					console.log "Saved commits for repo #{repo.fullName}"
					fetchRepoCommits repo, date, callback
			else
				callback()


getUserOrCreateUser = (username, callback) ->
	db.User.findOneAndUpdate {username: username}, {username: username}, upsert: true, new: true, (err, user) ->
		callback err, user

fetchCommit = (repo, commit, callback) ->
	console.log "Adding API Job to fetch commit #{commit.sha}"
	apiJobs.enqueue (access_token) ->
		console.log "Fetching commit #{commit.sha}"
		githubApi
			url: "/repos/#{repo.fullName}/commits/#{commit.sha}"
			qs:
				access_token: access_token
		, (err, response, body) ->
			return callback() console.error "Error at fetchCommit #{commit.sha}", err, response, body if err?
			changes = []
			items = JSON.parse(body).files ? []
			async.each items, (item, callback) ->
				fileName = item.filename
				changesMade = item.changes
				language = mapper.getLanguage fileName.substring fileName.lastIndexOf "."
				async.parallel [
					(callback) ->
						db.Commit.update {_id: commit._id}, {$addToSet: {changes: {language: language}}}, (err, resp) ->
							return callback() if err?
							db.Commit.update {_id: commit._id, "changes.language": language }, {$inc: {"changes.$.count": changesMade}}, (err, resp) ->
								callback()
					(callback) ->
						db.Repository.update {_id: repo._id}, {$addToSet: {contributors: {user: commit.author}}}, (err, resp) ->
							return callback() if err?
							db.Repository.update {_id: repo._id, "contributors.user": commit.author }, {$inc: {"contributors.$.weight": changesMade}}, (err, resp) ->
								callback()
				], callback
			, ->
				console.log "Saved commit #{commit.sha}"
				callback()