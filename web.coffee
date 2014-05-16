require("look").start()

require "./import-env"
core = require "./core"

core.getAndInsertTopRepositories 10000