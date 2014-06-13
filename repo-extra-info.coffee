db = require './db'
async = require 'async'
mongoose = require 'mongoose'
request = require 'request'

db.Repository.find (err,resp) ->
  console.log err if err?
  for repo in resp
    func = (repoName) ->
      setTimeout () ->
        request
          method: "GET"
          headers: 'User-Agent': "request"
          url: "https://cs249project:dm7-tmC-aD2-RfR@api.github.com/repos/#{repoName}"
        , (err, response, body) =>
          console.log err if err?
          var1 = JSON.parse body
          console.log  "#{repoName} #{var1.created_at} #{var1.subscribers_count}"
          db.Repository.update fullName: repoName,
            $set :
              createdAt: var1.created_at
              subscribersCount: var1.subscribers_count
            (err, resp) ->
              console.log err if err?
      , 5000
    func repo.fullName
