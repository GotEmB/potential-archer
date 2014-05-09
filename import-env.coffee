fs = require "fs"

fs.readFile ".env", encoding: "utf8", (err, data) ->
	data = data.split /[\n\r]+/g
	data.forEach (line) ->
		line = line.split /\=/g
		process.env[line.shift()] = line.join "="