mongoose = require "mongoose"

mongoose.connect process.env.MONGO_CONN_STR

exports.User = mongoose.model "User",
	username: String
	languages: [
		language: String
		temporal: [
			period: String
			changes: Number
		]
	]
	starsEarned: Number
	followers: Number

exports.Repository = mongoose.model "Repository",
	fullName: String
	stars: Number
	forks: Number
	contributors: [
		user: type: mongoose.Schema.ObjectId, ref: "User"
		weigth: Number
	]
	languages: [
		language: String
		lineCount: Number
	]

exports.Commit = mongoose.model "Commit",
	sha: String
	author: type: mongoose.Schema.ObjectId, ref: "User"
	repository: type: mongoose.Schema.ObjectId, ref: "Repository"
	changes: [
		language: String
		count: Number
	]
	timestamp: Date