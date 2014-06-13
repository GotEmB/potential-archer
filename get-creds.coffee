Zombie = require "zombie"
async = require "async"
md5 = require "MD5"
fs = require "fs"

globals =
	password: "abc123321"
	totalCreds: 100

generatedUsernames =
	try
		fs.readFileSync "creds.txt", encoding: "utf8"
			.split /[\r\n]/
			.filter (x) -> x isnt ""
	catch
		[]

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
					crawler.localStorage("github.com").clear()
					crawler.sessionStorage("github.com").clear()
					crawler.visit "https://github.com", (err) ->
						try
							crawler
								.fill "user[login]", login
								.fill "user[email]", "#{login}@gmail.com"
								.fill "user[password]", globals.password
								.pressButton "Sign up for GitHub", ->
									if crawler.location.pathname is "/join/plan"
										console.log "Crawler #{crawlerId}: Generated login #{login} [#{generatedUsernames.length} / #{globals.totalCreds}]"
										fs.appendFileSync "creds.txt", "#{login}\n"
										crawler.pressButton ".sign-out-button", (err) ->
											callback()
									else
										generatedUsernames.splice generatedUsernames.indexOf(login), 1
										console.log "Crawler #{crawlerId}: Login #{login} already exists  [#{generatedUsernames.length} / #{globals.totalCreds}]"
										fs.appendFileSync "cred-errors.txt", "Not in `/join/plan`: In `#{crawler.location.pathname}`"
										callback()
						catch ex
							generatedUsernames.splice generatedUsernames.indexOf(login), 1
							console.log "Crawler #{crawlerId}: Weird error [#{generatedUsernames.length} / #{globals.totalCreds}]"
							fs.appendFileSync "cred-errors.txt", "#{ex}\n#{crawler.html()}\n"
							callback()
				callback
			]...
		->
			callback? null, generatedUsernames.map (x) -> login: x, password: globals.password
	]...