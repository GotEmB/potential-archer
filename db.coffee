mongoose = require "mongoose"

mongoose.connect process.env.MONGO_CONN_STR ? "localhost"

exports.User = mongoose.model "User",
	username: type: String, index: true
	languages: [
		language: String
		temporal: [
			period: String
			changes: Number
		]
	]
	starsEarned: Number
	followers: Number
	location: String
	following: Number
	name: String
	hireable: Boolean

exports.Repository = mongoose.model "Repository",
	fullName: type: String, index: true
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
	serverError: Boolean
	createdAt: Date
	subscribersCount: Number

exports.Commit = mongoose.model "Commit",
	sha: type: String, index: true
	author: type: mongoose.Schema.ObjectId, ref: "User"
	repository: type: mongoose.Schema.ObjectId, ref: "Repository"
	changes: [
		language: String
		count: Number
	]
	timestamp: Date

exports.InstanceStatus = mongoose.model "InstanceStatus",
	instanceId: type: String, index: true
	alive: Boolean

exports.UserAvgWeight = mongoose.model "UserAvgWeight",
	author: type: mongoose.Schema.ObjectId, ref: "User"
	weight: Number

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
