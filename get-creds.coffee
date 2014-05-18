Zombie = require "zombie"
async = require "async"
md5 = require "MD5"

password = "abc123321"
generatedUsernames = []

q = async.queue (task, callback) ->
	login = md5 "#{new Date} yada #{Math.random()} Parker!"
	Zombie.visit "https://github.com", (err, crawler) ->
		crawler
			.fill "user[login]", login
			.fill "user[email]", "#{login}@gmail.com"
			.fill "user[password]", password
			.pressButton "Sign up for GitHub", ->
				if crawler.location.pathname is "/join/plan"
					generatedUsernames.push login
					console.log "Generated login: #{login}"
				else
					q.push {}
					console.log "Login #{login} already exists"
				crawler.close()
				callback()
, 1

module.exports = (callback) ->
	async.each [0...1000], -> q.push {}
	q.drain = ->
		callback? generatedUsernames.map (x) -> login: x, password: password