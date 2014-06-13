library("RMongo")
library("rmongodb") 
library("plyr")
library("ggplot2")

get_all_lang <- function()
{
  mongo <- mongoDbConnect("dataset", host="localhost")
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

user_commit_act <- mongo.find(mongo_rmongodb, ns="dataset.usercommitactvities", fields=list(language=1L,repository=1L,author=1L,changes=1L))
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


###############################

####developers

getUserName <- function(userId)
{
  username <- ""
  users <- mongo.find(mongo_rmongodb, ns = "dataset.users", query=list("_id"=mongo.oid.from.string(userId)),fields=list(username=1L))
  while (mongo.cursor.next(users))
  {
    item <- mongo.cursor.value(users)
    username <- mongo.bson.value(item, "username")
    
  }
  username
}
getRepoName <- function(repoId)
{
  reponame <- ""
  repos <- mongo.find(mongo_rmongodb, ns = "dataset.repositories", query=list("_id"=mongo.oid.from.string(repoId)),fields=list(fullName=1L))
  while (mongo.cursor.next(repos))
  {
    item <- mongo.cursor.value(repos)
    reponame <- mongo.bson.value(item, "fullName")    
  }
  reponame
}

print(getUser("537fcf98280ef15170b5808d"))
print(getRepos("53878329fd396a05469b4863"))


#################
ddply_auth_project <- data.frame(stringsAsFactors = FALSE)
ddply_auth_project = ddply(user_commit_activity,
                           c("author", "repository"),
                           summarize,
                           temp = length(language)
                          
)
print(head(ddply_auth_project))

ddply_projects_per_author = ddply( ddply_auth_project,
                                 c("author"), 
                                 summarize,        
                                 repo_count = length(repository)
)
print(head(ddply_projects_per_author))

par(las=2)
par(mar=c(5,8,4,2))
ddply_projects_per_author_matrix <- as.matrix(ddply_projects_per_author[, "repo_count"])
#row.names(ddply_projects_per_author_matrix) <- getUserName(ddply_projects_per_author[, "author"])
barplot(t(ddply_projects_per_author_matrix),horiz=TRUE,cex.names=1.0,xlim=c(0,25),xlab="Number of Repositories", main="Number of Repositories contributed by each user")
grid(nx=7,ny=1,lty=1)

####


ddply_auth_project = ddply(user_commit_activity,
                           c("author", "repository"),
                           summarize,
                           temp = length(language)
                           
)
ddply_auth_project$ <- factor(ddply_auth_project$x) 

print(head(ddply_auth_project))

ddply_projects_per_repos = ddply( ddply_auth_project,
                                   c("repository"), 
                                   summarize,        
                                   author_count = length(author)
                                  
)
print(head(ddply_projects_per_repos))

par(las=2)
par(mar=c(5,8,4,2))
ddply_projects_per_repos_matrix <- as.matrix(ddply_projects_per_repos[, "author_count"])
#row.names(ddply_projects_per_author_matrix) <- getUserName(ddply_projects_per_author[, "author"])
barplot(t(ddply_projects_per_repos_matrix),horiz=TRUE,cex.names=1.0,xlim=c(0,500),xlab="Number of Contributors", main="Number of Contributors for each Repository")
grid(nx=7,ny=1,lty=1)

