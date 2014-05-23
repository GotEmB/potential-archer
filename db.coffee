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

exports.UserCommitActvity = mongoose.model "UserCommitActvity",
	author: type: mongoose.Schema.ObjectId, ref: "User"
	repository: type: mongoose.Schema.ObjectId, ref: "Repository"
	language: String
	changes: Number

exports.RepoCommitActvity = mongoose.model "RepoCommitActvity",
	repository: type: mongoose.Schema.ObjectId, ref: "Repository"
	language: String
	changes: Number


exports.ContributionRatio = mongoose.model "ContributionRatio",
	author: type: mongoose.Schema.ObjectId, ref: "User"
	contribution_ratio: [
		language: String
		ratio: Number
	]