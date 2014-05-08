mongoose = require "mongoose"

mongoose.connect process.env.MONGOSTR

exports.User = mongoose.model "User",
	username: String
	fetched: Boolean
	metrics:
		languages: [
			language: String
			temporal: [
				period: String
				changes: Number
			]
		]