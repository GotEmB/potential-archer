Zombie = require "zombie"
async = require "async"
md5 = require "MD5"

globals =
	password: "abc123321"
	totalCreds: 250

generatedUsernames = []

module.exports = (callback) ->
	async.each [
		[0...5]
		(crawlerId, callback) ->
			crawler = new Zombie runScripts: false, windowName: "", loadCSS: false
			async.whilst [
				->
					generatedUsernames.length < globals.totalCreds
				(callback) ->
					login = md5("#{new Date} yada yada #{Math.random()} Parker!")[1..10] until login? and login not in generatedUsernames
					generatedUsernames.push login
					crawler.cookies().clear()
					crawler.visit "https://github.com", (err) ->
						try
							crawler
								.fill "user[login]", login
								.fill "user[email]", "#{login}@gmail.com"
								.fill "user[password]", globals.password
								.pressButton "Sign up for GitHub", ->
									if crawler.location.pathname is "/join/plan"
										console.log "Crawler #{crawlerId}: Generated login #{login} [#{generatedUsernames.length} / #{globals.totalCreds}]"
									else
										generatedUsernames.splice generatedUsernames.indexOf(login), 1
										console.log "Crawler #{crawlerId}: Login #{login} already exists  [#{generatedUsernames.length} / #{globals.totalCreds}]"
									callback()
						catch
							generatedUsernames.splice generatedUsernames.indexOf(login), 1
							console.log "Crawler #{crawlerId}: Weird error [#{generatedUsernames.length} / #{globals.totalCreds}]"
							callback()
				callback
			]...
		->
			callback? null, generatedUsernames.map (x) -> login: x, password: globals.password
	]...