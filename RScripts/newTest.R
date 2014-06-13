library("RMongo")
library("rmongodb") 
library("plyr")
library("ggplot2")

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

#unique_languages <- get_all_lang()
#print(length(unique_languages))

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

ddply_lang_project = ddply(user_commit_activity,
                           c("language", "repository"),
                           summarize,
                           temp = length(author)
)
print(head(ddply_lang_project))

ddply_projects_per_lang = ddply( ddply_lang_project,
                                 c("language"), 
                                 summarize,        
                                 repo_count = length(repository)
)
print(head(ddply_projects_per_lang))

########

ddply_changes_per_user = ddply( user_commit_activity,
                                c("language", "author"), 
                                summarize,        
                                total_changes = sum(changes)
)
print(head(ddply_changes_per_user))

ddply_changes_per_user_lang = ddply( ddply_changes_per_user,
                                     c("language"), 
                                     summarize,        
                                     avg_commits = mean(total_changes)
)
print(head(ddply_changes_per_user_lang))

########

ddply_dev_lang = ddply( user_commit_activity,
                        c("language", "author"), 
                        summarize,
                        temp=length(repository)
)
print(head(ddply_dev_lang))

ddply_dev_per_lang = ddply( ddply_dev_lang,
                            c("language"), 
                            summarize,        
                            dev_count = length(author)
)
print(head(ddply_dev_per_lang))

#######

plot(x=ddply_projects_per_lang$repo_count,y=ddply_projects_per_lang$language,type="l")
plot(ddply_changes_per_user_lang)
plot(ddply_dev_per_lang)


par(las=2)
par(mar=c(5,8,4,2))
ddply_projects_per_lang_matrix <- as.matrix(ddply_projects_per_lang[, "repo_count"])
row.names(ddply_projects_per_lang_matrix) <- ddply_projects_per_lang[, "language"]
barplot(t(ddply_projects_per_lang_matrix),horiz=TRUE,cex.names=0.8,xlim=c(0,700),xlab="Number of Repositories", main="Number of Repositories for each Language")
grid(nx=7,ny=1,lty=1)

###############

par(las=2)
par(mar=c(5,8,4,2))
ddply_changes_per_user_lang_matrix <- as.matrix(ddply_changes_per_user_lang[, "avg_commits"])
row.names(ddply_changes_per_user_lang_matrix) <- ddply_changes_per_user_lang[, "language"]
barplot(t(ddply_changes_per_user_lang_matrix),horiz=TRUE,xlim=c(0,150000),cex.names=0.8,xlab="Average Line Changes", main="Average Line Changes for each Language")
grid(nx=5,ny=1,lty=1)

##########

par(las=2)
par(mar=c(5,8,4,2))
ddply_dev_per_lang_matrix <- as.matrix(ddply_dev_per_lang[, "dev_count"])
row.names(ddply_dev_per_lang_matrix) <- ddply_dev_per_lang[, "language"]
barplot(t(ddply_dev_per_lang_matrix),horiz=TRUE,xlim=c(0,5000),cex.names=0.8,xlab="Number of Developers", main="Number of Developers for each Language")
grid(nx=5,ny=1,lty=1)
