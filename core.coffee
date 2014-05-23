request = require "request"
async = require "async"
db = require "./db"
mapper = require "./mapper"
JobQueue = require "job-queue"
fs = require "fs"
winston = require "winston"
md5 = require "MD5"
os = require "os"

winston.add winston.transports.File, filename: "winston.log"

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
	getNextTimestamp: =>
		@nextTimestamp

searchJobs = undefined
apiJobs = undefined
myInstanceId = undefined
siblingInstanceStatuses = {}

exports.setCreds = (creds) ->
	console.log "Setting Credentials"
	searchJobs = new JobQueue creds.map (cred) -> new GitHubApiConsumer cred
	apiJobs = new JobQueue creds.map (cred) -> new GitHubApiConsumer cred

exports.getAndInsertTopRepositories = (number) ->
	fetchRepos number, 1 << 20, ->
		winston.info "All done!"

fetchRepos = (totalRepos = 1000, stars, callback) ->
	minStars = Infinity
	async.eachSeries [1 .. Math.min 10, Math.ceil totalRepos / 100], (page, callback) ->
		winston.info "Adding Search Job to fetch page #{page} of Top Repositories with stars <= #{stars}"
		searchJobs.enqueue thisJob =
			onExecute: ->
				winston.info "Fetching page #{page} of Top Repositories with stars <= #{stars}"
			path: "/search/repositories"
			qs:
				q: "stars:<=#{stars}"
				sort: "stars"
				per_page: Math.min 100, totalRepos - (page - 1) * 100
				page: page
			callback: (err, response, body) ->
				if err?
					winston.error "Error at getAndInsertTopRepositories on page #{page} with stars <= #{stars}", err, response, body
					return searchJobs.enqueue thisJob
				if response.statusCode >= 400
					winston.error "Bad response at getAndInsertTopRepositories on page #{page} with stars <= #{stars}", body
					return searchJobs.enqueue thisJob
				items = JSON.parse(body)?.items
				unless items?
					winston.error "Field items does not exist at getAndInsertTopRepositories on page #{page} with stars <= #{stars}"
					return searchJobs.enqueue thisJob
				async.eachLimit items, 10, (item, callback) ->
					minStars = Math.min minStars, item.stargazers_count
					do fetchOneRepo = ->
						db.Repository.findOneAndUpdate {fullName: item.full_name},
							fullName: item.full_name
							stars: item.stargazers_count
							forks: item.forks_count
							$setOnInsert:
								instanceId: myInstanceId
						, upsert: true, new: true
						, (err, repo) ->
							if repo.done is true
								winston.info "Skipping completed repo #{repo.fullName}"
								return callback()
							if repo.instanceId isnt myInstanceId
								return pingSiblingInstance repo.instanceId, (err, siblingAlive) ->
									winston.info "Checking if sibling instance fetching repo #{repo.fullName} is alive"
									if siblingAlive
										winston.info "Skipping repo #{repo.fullName} fetched by sibling instance"
										return callback()
									cleanRepo repo, (err) ->
										fetchOneRepo()
							async.parallel [
								(callback) -> fetchRepoLanguages repo, callback
								(callback) -> fetchRepoCommits repo, "", callback
							], ->
								db.Repository.update {_id: repo._id}, {done: true}, (err) ->
									winston.info "Saved repository #{repo.fullName}"
									callback()
				, ->
					winston.info "Saved #{items.length} repositories of Top Repositories from page #{page} with stars <= #{stars}"
					callback()
	, ->
		if totalRepos <= 10 * 100 or minStars is Infinity
			callback()
		else
			fetchRepos totalRepos - 10 * 100, (if minStars is stars then minStars - 1 else minStars), callback

fetchRepoLanguages = (repo, callback) ->
	winston.info "Adding API Job to fetch language statistics for repo #{repo.fullName}"
	apiJobs.enqueue thisJob =
		onExecute: ->
			winston.info "Fetching language statistics for repo #{repo.fullName}"
		path: "/repos/#{repo.fullName}/languages"
		callback: (err, response, body) ->
			if err?
				winston.error "Error at fetchRepoLanguages for repo #{repo.fullName}", err, response, body
				return apiJobs.enqueue thisJob
			if response.statusCode >= 400
				winston.error "Bad response at fetchRepoLanguages for repo #{repo.fullName}", body
				return apiJobs.enqueue thisJob
			languages = []
			for language, lineCount of JSON.parse body
				languages.push language: language, lineCount: lineCount
			db.Repository.update {_id: repo._id}, languages: languages, (err, count) ->
				winston.info "Saved language statistics for repo #{repo.fullName}"
				callback()

fetchRepoCommits = (repo, date = "", callback) ->
	logDate = if date is "" then "forever" else date
	winston.info "Adding API Job to fetch commits for repo #{repo.fullName} since #{logDate}"
	apiJobs.enqueue thisJob =
		onExecute: ->
			winston.info "Fetching commits for repo #{repo.fullName} since #{logDate}"
		path: "/repos/#{repo.fullName}/commits"
		qs:
			until: date
			per_page: 100
		callback: (err, response, body) ->
			if err?
				winston.error "Error at fetchRepoCommits for repo #{repo.fullName} since #{logDate}", err, response, body
				return apiJobs.enqueue thisJob
			if response.statusCode >= 400
				winston.error "Bad response at fetchRepoCommits for repo #{repo.fullName} since #{logDate}", body
				return apiJobs.enqueue thisJob
			items = JSON.parse body
			unless items?
				winston.error "Field items does not exist at fetchRepoCommits for repo #{repo.fullName} since #{logDate}"
				return apiJobs.enqueue thisJob
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
	apiJobs.enqueue thisJob =
		onExecute: ->
			winston.info "Fetching commit #{commit.sha}"
		path: "/repos/#{repo.fullName}/commits/#{commit.sha}"
		callback: (err, response, body) ->
			if err?
				winston.error "Error at fetchCommit #{commit.sha}", err, response, body
				return apiJobs.enqueue thisJob
			if response.statusCode >= 400
				winston.error "Bad response at fetchCommit #{commit.sha}", body
				return apiJobs.enqueue thisJob
			changes = []
			items = JSON.parse(body)?.files
			unless items?
				winston.error "Field files.items does not exist at fetchCommit #{commit.sha}"
				return apiJobs.enqueue thisJob
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

cleanRepo = (repo, callback) ->
	db.Commit.remove repository: repo._id, (err) ->
		if err?
			winston.error "Error removing commits for repo #{repo.fullName}", err
			return callback err
		winston.info "Removed commits for repo #{repo.fullName}"
		db.Repository.remove _id: repo._id, (err) ->
			if err?
				winston.error "Error removing repo #{repo.fullName}", err
				return callback err
			callback null

pingSiblingInstance = (instanceId, callback) ->
	return callback null, siblingInstanceStatuses[instanceId] if instanceId of siblingInstanceStatuses
	instanceStatus = new db.InstanceStatus instanceId: instanceId
	instanceStatus.save (err, instanceStatus) ->
		if err?
			winston.error "Error pinging instance #{instanceId}", err
			return callback err
		setTimeout (->
			db.InstanceStatus.findByIdAndRemove instanceStatus._id, (err, instanceStatus) ->
				siblingInstanceStatuses[instanceId] = instanceStatus.alive is true
				callback null, siblingInstanceStatuses[instanceId]
		), 5 * 1000

do setup = ->
	myInstanceId = md5 "instanceId #{os.hostname()} ya #{os.platform()} da #{os.uptime()} ya #{os.freemem()} da #{os.loadavg()} #{new Date} #{Math.random()} Parker!"
	setInterval (->
		db.InstanceStatus.update({instanceId: myInstanceId}, {alive: true}, multi: true).exec()
	), 2 * 1000