library("RMongo")
library("rmongodb") 


get_all_lang <- function()
{
  mongo <- mongoDbConnect("cs249", host="localhost")
  output <- dbAggregate(mongo, "commits", c('{ "$unwind" : "$changes"}',
                                            ' { "$project" : { "lang" : "$changes.language" } } ',
                                            ' { "$group" : { "_id" : "$lang" } } '))
  
  Languages_All <- c()
  for(i in 1:length(output))
  {
    bson <- mongo.bson.from.JSON(output[i])
    lang <- mongo.bson.value(bson,"_id")
    if(!is.null(lang) && nchar(lang) > 0)
      Languages_All <- c(Languages_All, lang)
  }
  
  unique_languages <- unique(Languages_All)
  unique_languages
}

unique_languages <- get_all_lang()
print(length(unique_languages))

mongo_rmongodb <- mongo.create(host = "localhost")
user_commit_activity <- data.frame(stringsAsFactors = FALSE)

user_commit_act <- mongo.find(mongo_rmongodb, ns="cs249.usercommitactvities", fields=list(language=1L,repository=1L,author=1L,changes=1L))
while (mongo.cursor.next(user_commit_act))
{
  item <- mongo.cursor.value(user_commit_act)
  repository <- mongo.oid.to.string(mongo.bson.value(item, "repository"))
  author <- mongo.oid.to.string(mongo.bson.value(item, "author"))
  language <- mongo.bson.value(item, "language")
  changes <- mongo.bson.value(item, "changes")
  if (class(repository) != "NULL" && class(author) != "NULL" && class(language) != "NULL" && class(changes) != "NULL") {
    user_commit_activity <- rbind(user_commit_activity, data.frame(author=author,repository=repository,language=language,changes=changes))
  }
}

ddply_projects_per_lang = ddply( user_commit_activity,
                             c("language"), 
                             summarize,        
                             repo_count = count(repository)
)
print(head(ddply_projects_per_lang))

ddply_changes_per_user = ddply( user_commit_activity,
                                 c("language", "author"), 
                                 summarize,        
                                 total_changes = sum(changes),
)
print(head(ddply_changes_per_user))

ddply_changes_per_user_lang = ddply( ddply_changes_per_user,
                                     c("language"), 
                                     summarize,        
                                     avg_commits = mean(total_changes),
)
print(head(ddply_changes_per_user_lang))



