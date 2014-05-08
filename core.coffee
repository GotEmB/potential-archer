request = require "request"
async = require "async"
db = require "./db"

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
					repo = new db.Repository
						fullName: item.full_name
						stars: item.stargazers_count
						forks: item.forks_count
					repo.save (err, repo) ->
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
	apiJobs.push ->
		githubApi
			url: "/repos/#{repo.full_name}/commits"
			qs:
				until: date
				per_page: 100
		, (err, response, body) ->
			items = JSON.parse(body)
			items.forEach (item) ->
				getUserOrCreateUser (item.author.login, user) ->
					commit = new db.Commit
						sha: item.sha
						author: user._id
						repository: repo._id
						timestamp: item.commit.author.date
					commit.save(err, commit) ->
						if not err?
							exports.fetchCommit repo, commit

getUserOrCreateUser = (username, callback) ->
	db.User.findOne username: username, (err, resp) ->
		if err?
			user = new db.User
				username: username
			user.save (err, use)  ->
				return callback err if err?
				return callback null, use
		else
			return callback null, resp

fetchCommit = (repo, commit) ->
	apiJobs.push ->
		githubApi
			url: "/repos/#{repo.fullName}/commits/#{commit.sha}"
		, (err, response, body) ->

exports.startJobs = ->
	do doTask = ->
		console.log "#{searchJobs.length} Search Jobs and #{apiJobs.length} API Jobs in queue"
		searchJobs.shift()?() for i in [0 ... globals.searchRequestsPerMinute]
		apiJobs.shift()?() for i in [0 ... globals.apiRequestsPerMinute]
	setInterval doTask, 1000 * 60 # Runs every minute
