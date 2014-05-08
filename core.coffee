request = require "request"
async = require "async"
db = require "db"

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

fetchRepoLanguages = (repo) ->
	apiJobs.push ->
		githubApi
			url: "/repos/#{repo.full_name}/languages"
		, (err, response, body) ->
			repo.languages = [];
			for language, lineCount in JSON(body)
				repo.languages.push language: language, lineCount: lineCount
			repo.save()

exports.startJobs = ->
	setInterval ( ->
		doSearchJobs = searchJobs[...globals.searchRequestsPerMinute]
		searchJobs = searchJobs[globals.searchRequestsPerMinute...]
		doApiJobs = apiJobs[...globals.apiRequestsPerMinute]
		apiJobs = apiJobs[globals.apiRequestsPerMinute...]
		doSearchJobs.forEach (job) -> job()
		doApiJobs.forEach (job) -> job()
	), 60 * 1000
