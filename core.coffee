request = require "request"
async = require "async"
db = require "./db"
mapper = require "./mapper"

globals =
	searchRequestsPerMinute: 20
	apiRequestsPerMinute: 80
	apiRootUrl: "https://api.github.com"

githubApi = ({url, qs} = {url: "", qs: {}}, callback) ->
	qs.access_token = process.env.GH_ACCESS_TOKEN
	request
		method: "GET"
		headers: 'User-Agent': "request"
		url: globals.apiRootUrl + url
		qs: qs
	, callback

searchJobs = []
apiJobs = []
# commits
# contributors
# languages

exports.getAndInsertTopRepositories = (number) ->
	itemsDone = 0
	[1 .. Math.ceil(number / 100)].forEach (page) ->
		searchJobs.push ->
			githubApi
				url: "/search/repositories"
				qs:
					q: "created:>1970-01-01"
					sort: "stars"
					per_page: 100
					page: page
			, (err, response, body) ->
				items = JSON.parse(body).items
				itemsDone += items.length
				items.forEach (item) ->
					repo = new db.Repository
						fullName: item.full_name
						stars: item.stargazers_count
						forks: forks_count
					repo.save()
					exports.fetchRepoLanguages repo
					exports.fetchRepoCommits repo, ''

fetchRepoLanguages = (repo) ->
	apiJobs.push ->
		githubApi
			url: "/repos/#{repo.full_name}/languages"
		, (err, response, body) ->
			repo.languages = [];
			for language, lineCount in JSON(body)
				repo.languages.push language: language, lineCount: lineCount
			repo.save()

fetchRepoCommits = (repo, date) ->
	apiJobs.push ->
		githubApi
			url: "/repos/#{repo.full_name}/commits"
			qs:
				until: date
				per_page: 100
		, (err, response, body) ->
			items = JSON.parse(body)
			items.forEach (item) ->
				getUserOrCreateUser item.author.login, (err, user) ->
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
			url: "/repos/#{repo.full_name}/commits/#{commit.sha}"
		, (err, response, body) ->
			changes = []
			com = JSON.parse(body)
			items = com.files
			items.forEach (item) ->
				mapper.getLanguage


exports.startJobs = ->
	setInterval ( ->
		doSearchJobs = searchJobs[...globals.searchRequestsPerMinute]
		searchJobs = searchJobs[globals.searchRequestsPerMinute...]
		doApiJobs = apiJobs[...globals.apiRequestsPerMinute]
		apiJobs = apiJobs[globals.apiRequestsPerMinute...]
		doSearchJobs.forEach (job) -> job()
		doApiJobs.forEach (job) -> job()
	), 60 * 1000
