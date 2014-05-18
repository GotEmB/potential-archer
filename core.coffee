request = require "request"
async = require "async"
db = require "./db"
mapper = require "./mapper"
JobQueue = require "job-queue"
fs = require "fs"
winston = require "winston"

winston.add winston.transports.File, filename: "winston.log"

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
		winston.info "All done!"

fetchRepos = (totalRepos = 1000, stars, callback) ->
	minStars = Infinity
	async.eachSeries [1 .. 10], (page, callback) ->
		winston.info "Adding Search Job to fetch page #{page} of Top Repositories with stars <= #{stars}"
		searchJobs.enqueue (access_token) ->
			winston.info "Fetching page #{page} of Top Repositories with stars <= #{stars}"
			githubApi
				url: "/search/repositories"
				qs:
					q: "stars:<=#{stars}"
					sort: "stars"
					per_page: 100
					page: page
					access_token: access_token
			, (err, response, body) ->
				return winston.error "Error at getAndInsertTopRepositories on page #{page} with stars <= #{stars}", err, response, body if err?
				items = JSON.parse(body)?.items
				unless items?
					winston.error "Field items does not exist at getAndInsertTopRepositories on page #{page} with stars <= #{stars}"
					return callback()
				async.eachLimit items, 10, (item, callback) ->
					minStars = Math.min minStars, item.stargazers_count
					db.Repository.findOneAndUpdate {fullName: item.full_name},
						fullName: item.full_name
						stars: item.stargazers_count
						forks: item.forks_count
						$inc:
							updated: 1
					, upsert: true, new: true
					, (err, repo) ->
						if repo.updated isnt 1
							winston.info "Skipping repo #{repo.fullName}"
							return callback()
						async.parallel [
							(callback) -> fetchRepoLanguages repo, callback
							(callback) -> fetchRepoCommits repo, "", callback
						], ->
							winston.info "Saved repository #{repo.fullName}"
							callback()
				, ->
					winston.info "Saved #{items.length} repositories of Top Repositories from page #{page} with stars <= #{stars}"
					callback()
	, ->
		db.Repository.count (err, count) ->
			if count >= totalRepos or minStars is Infinity
				callback()
			else
				fetchRepos totalRepos, (if minStars is stars then minStars - 1 else minStars), callback

fetchRepoLanguages = (repo, callback) ->
	winston.info "Adding API Job to fetch language statistics for repo #{repo.fullName}"
	apiJobs.enqueue (access_token) ->
		winston.info "Fetching language statistics for repo #{repo.fullName}"
		githubApi
			url: "/repos/#{repo.fullName}/languages"
			qs:
				access_token: access_token
		, (err, response, body) ->
			if err?
				winston.error "Error at fetchRepoLanguages for repo #{repo.fullName}", err, response, body
				return callback()
			languages = []
			for language, lineCount of JSON.parse body
				languages.push language: language, lineCount: lineCount
			db.Repository.update {_id: repo._id}, languages: languages, (err, count) ->
				winston.info "Saved language statistics for repo #{repo.fullName}"
				callback()

fetchRepoCommits = (repo, date = "", callback) ->
	logDate = if date is "" then "forever" else date
	winston.info "Adding API Job to fetch commits for repo #{repo.fullName} since #{logDate}"
	apiJobs.enqueue (access_token) ->
		winston.info "Fetching commits for repo #{repo.fullName} since #{logDate}"
		githubApi opts =
			url: "/repos/#{repo.fullName}/commits"
			qs:
				until: date
				per_page: 100
				access_token: access_token
		, (err, response, body) ->
			if err?
				winston.error "Error at fetchRepoCommits for repo #{repo.fullName} since #{logDate}", err, response, body
				return callback()
			items = JSON.parse body
			unless items?
				winston.error "Field items does not exist at fetchRepoCommits for repo #{repo.fullName} since #{logDate}"
				return callback()
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
					fetchRepoCommits repo, date, callback
			else
				winston.info "Saved commits for repo #{repo.fullName} since #{logDate}"
				callback()


getUserOrCreateUser = (username, callback) ->
	db.User.findOneAndUpdate {username: username}, {username: username}, upsert: true, new: true, (err, user) ->
		callback err, user

fetchCommit = (repo, commit, callback) ->
	winston.info "Adding API Job to fetch commit #{commit.sha}"
	apiJobs.enqueue (access_token) ->
		winston.info "Fetching commit #{commit.sha}"
		githubApi
			url: "/repos/#{repo.fullName}/commits/#{commit.sha}"
			qs:
				access_token: access_token
		, (err, response, body) ->
			return callback() winston.error "Error at fetchCommit #{commit.sha}", err, response, body if err?
			changes = []
			items = JSON.parse(body)?.files
			unless items?
				winston.error "Field files.items does not exist at fetchCommit #{commit.sha}"
				return callback()
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
				winston.info "Saved commit #{commit.sha}"
				callback()