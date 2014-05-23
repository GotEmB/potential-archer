require "./import-env"
core = require "./core"
getCreds = require "./get-creds"

getCreds (err, creds) ->
	return console.error err if err?
	core.setCreds creds
	core.getAndInsertTopRepositories 10000, ->
		process.exit 0