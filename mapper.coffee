fs = require('fs')
mapperJson = {}

exports.init = ()->
	fs.readFileSync 'extensions.json', 'utf8',  (err,data)  ->
  		if (err) 
    		return console.log err
    	extensions = JSON.parse data
    	
    	Object.keys(extensions).forEach (key) ->
    		info = extensions[key];
    		info.extensions.map (extension)->
    			mapperJson[extension] = key

exports.getLanguage = (ext) ->
	return mapperJson[ext]

exports.init