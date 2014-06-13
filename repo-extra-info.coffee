db = require './db'
async = require 'async'
mongoose = require 'mongoose'

db.Repository.find (err,resp) ->
  console.log err if err?
  for repo in resp
    setTimeout () ->
      request
        method: "GET"
        headers: 'User-Agent': "request"
        url: "https://cs249project:dm7-tmC-aD2-RfR@api.github.com/repos/#{repo.fullName}"
      , (err, response, body) =>
        console.log err if err?
        console.log body
        var1 = JSON.parse body
        console.log  "#{var1.created_at} #{var1.subscribers_count}"
      , 100
