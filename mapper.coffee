fs = require('fs')
mapperJson = {}

init = ->
	data = fs.readFileSync 'extensions.json', encoding: 'utf8'
	extensions = JSON.parse data
	Object.keys(extensions).forEach (key) ->
		info = extensions[key]
		info.extensions.map (extension)->
			mapperJson[extension] = key

exports.getLanguage = (ext) ->
	return mapperJson[ext]

init()