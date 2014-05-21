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
		weight: Number
	]
	languages: [
		language: String
		lineCount: Number
	]
	done: Boolean
	instanceId: String

exports.Commit = mongoose.model "Commit",
	sha: String
	author: type: mongoose.Schema.ObjectId, ref: "User"
	repository: type: mongoose.Schema.ObjectId, ref: "Repository"
	changes: [
		language: String
		count: Number
	]
	timestamp: Date

exports.InstanceStatus = mongoose.model "InstanceStatus",
	instanceId: String
	alive: Boolean