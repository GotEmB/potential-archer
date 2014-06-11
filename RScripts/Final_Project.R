not.installed=function(package_name)  !is.element(package_name,installed.packages()[,1])

if (not.installed("rjson")) 
  install.packages("rjson")
if (not.installed("rmongodb")) 
  install.packages("rmongodb")
if (not.installed("reshape2")) 
  install.packages("reshape2")
if (not.installed("data.table")) 
  install.packages("data.table")
if (not.installed("plyr")) 
  install.packages("plyr")
if (not.installed("ggplot2")) 
  install.packages("ggplot2")
if (not.installed("RMongo"))
  install.packages("RMongo")
library("rjson") 
library("ggplot2") 
library("rmongodb") 
library("reshape2") 
library("MASS") 
library("plyr")
library("RMongo")
require("data.table")


library(plyr)
users = data.frame(stringsAsFactors = FALSE) 
repos = data.frame(stringsAsFactors = FALSE)
mongo_rmongodb <- mongo.create(host = "localhost") 

DBNS_users = "cs249.users"
DBNS_repos = "cs249.repositories"
if (mongo.is.connected(mongo_rmongodb)) {
  repos = mongo.find.all(mongo_rmongodb, DBNS_repos, list(done=TRUE)) 
}


repos_by_languages <- data.frame(stringsAsFactors = FALSE)

for(i in 1: nrow(repos))
{
  repos_one <-  repos[i,]
  languages_list <- repos_one$languages
  
  totalLineCount <- 0
  if(!is.na(repos_one$stars) && repos_one$stars > 5 && !is.na(length(languages_list)) && class(repos_one$stars)!= 'mongo.oid')
  {
    for(j in 1:length(languages_list))
    {
      totalLineCount = totalLineCount + languages_list[[j]][['lineCount']]
    }
    for(j in 1:length(languages_list))
    {
      repos_by_languages <- rbind(repos_by_languages, data.frame(id=mongo.oid.to.string(repos[i,1][[1]]),name=repos_one$fullName,stars = repos_one$stars, forks = repos_one$forks, language = languages_list[[j]]['language'] , linecount = languages_list[[j]][['lineCount']], totalLineCount = totalLineCount ))
    }
  }
}

print(dim(repos_by_languages))
print(head(repos_by_languages))

ddply_sum_lineCount = ddply( repos_by_languages,
                             c("id","name", "stars","forks","language","linecount"), 
                             summarize,        
                             prop_lineCount = linecount/totalLineCount, 
                             popularity = stars * prop_lineCount,
                             accessibility = forks * prop_lineCount
)  

print(head(ddply_sum_lineCount))

ddply_Overall = ddply( ddply_sum_lineCount,
                       c("language"), 
                       summarize,        
                       avg_popularity = mean(popularity),
                       avg_accessibility = mean(accessibility)
)  
print(head(ddply_Overall))
print(dim(ddply_Overall))

ggplot(ddply_Overall,aes(x= avg_popularity, y = avg_accessibility, colour = language)) + geom_point() + 
  geom_text(aes(label=language),hjust=0, vjust=0)

ggplot(ddply_Overall,aes(x= log(avg_popularity), y = log(avg_accessibility), colour = language)) + geom_point() + 
  geom_text(aes(label=language),hjust=0, vjust=0)

######

mongo <- mongoDbConnect("cs249", host="localhost")
contribution_df <- dbGetQuery(mongo, "contributionratios", '{$or:[{"contribution_ratio": {$elemMatch:{"language":"JavaScript"}}},{"contribution_ratio": {$elemMatch:{"language":"CSS"}}}]}', skip=0, limit=100000)

domain <- c("JavaScript","CSS")
threshold <- c(1.0e-8, 1.0e-8) #change the 
contribution_ratios <- contribution_df[,c("author","contribution_ratio"), drop=FALSE]
user_contribution_list <- c()
for(i in 1:nrow(contribution_ratios))
{
  
  Contribution_jsonObject <- fromJSON( contribution_ratios[2][[1]][i])
  for(j in 1:length(Contribution_jsonObject))
  {
    if("language" %in% names(Contribution_jsonObject[[j]]))
    {
      curr_language <- Contribution_jsonObject[[j]]$language
      if(tolower(curr_language) %in% tolower(domain))
      { 
        Language_index <- match(tolower(curr_language),tolower(domain))
        threshold_language <- threshold[Language_index]
        if(Contribution_jsonObject[[j]]$ratio > threshold_language)
        {
          user_contribution_list <- c(user_contribution_list,contribution_ratios[1][[1]][i] )
        }
      }
    }
  } 
}
print("User contributed to either JS or CSS")
print(length(unique(user_contribution_list)))
print("User contributed to both")
print(length((user_contribution_list)) - length(unique(user_contribution_list)))
print("537ff216280ef15170b59ba5" %in% user_contribution_list)
user_contribution_unique_list <- unique(user_contribution_list)


author_ratios <- data.frame(stringsAsFactors = FALSE)

for(authorId in user_contribution_unique_list)
{
  cursor <- mongo.find(mongo_rmongodb, ns = "cs249.usercommitactvities", query=list(author=mongo.oid.from.string(authorId), language=list('$in'=c('JavaScript','CSS'))), fields=list(repository=1L,language=1L) )
  
  user_contributions_ratio <- mongo.find(mongo_rmongodb, ns = "cs249.contributionratios", query=list(author=mongo.oid.from.string(authorId)),fields=list(contribution_ratio=1L))
  ratio_lang <- 0
  
  ratio_css <- 0
  ratio_js <- 0
  
  while (mongo.cursor.next(user_contributions_ratio))
  {
    ratio <- mongo.cursor.value(user_contributions_ratio)
    if(mongo.bson.value( ratio, "language") == "CSS")
    {
      ratio_css <- mongo.bson.value( ratio, "ratio")
    }
    else if(mongo.bson.value( ratio, "language") == "JavaScript")
    {
      ratio_js <- mongo.bson.value( ratio, "ratio")
    }
  }
  
  while (mongo.cursor.next(cursor))
  {
    item <- mongo.cursor.value(cursor)
    oid <- mongo.bson.value(item, "repository")
    lang <- mongo.bson.value(item, "language")
    ## get stars and forks from the user commit activities
    res <- mongo.find(mongo_rmongodb, ns = "cs249.repositories", query=list("_id"=oid),fields=list(stars=1L, forks=1L))
    while (mongo.cursor.next(res))
    {
      forks_stars <- mongo.cursor.value(res)
      stars <- mongo.bson.value( forks_stars, "stars")
      forks <- mongo.bson.value( forks_stars, "forks")
    }
    
    ## get the ratios
    
    
   
  }
  mongo.cursor.destroy(cursor)
}
###########################################3
#get list of repository ids
repos_v_devStrength <- data.frame(stringsAsFactors = FALSE)

for(i in 1:nrow(repos))
{
  repoId= repos[i,1][[1]]
  authors_lang_ForRepository <- mongo.find(mongo_rmongodb, ns = "cs249.usercommitactvities", query=list(repository=mongo.oid.from.string(repoId), fields=list(author=1L,language=1L) )
                                           
 while (mongo.cursor.next(authors_lang_ForRepository ))
 {
   developer_cursor <- mongo.cursor.value(authors_lang_ForRepository)
   authorID <- mongo.bson.value(developer_cursor, "author")
   language <- mongo.bson.value(developer_cursor, "language")
                    
   ddply_sum_lineCount
  
}
}
author_lang_df = data.frame(stringsAsFactors = FALSE)
authors_lang_cursor <- mongo.find(mongo_rmongodb, ns = "cs249.usercommitactvities", fields=list(author=1L,language=1L,repository=1L) )

while (mongo.cursor.next(authors_lang_cursor ))
{
  val = mongo.cursor.value(authors_lang_cursor)
  author=mongo.oid.to.string(mongo.bson.value(val,"author"))
  language = mongo.bson.value(val,"language")
  repository = mongo.oid.to.string(mongo.bson.value(val,"repository"))
  if(class(language)!="NULL" && class(author)!="NULL" && class(repository)!="NULL")
  {
  author_lang_df <- rbind(author_lang_df, data.frame(author=mongo.oid.to.string(mongo.bson.value(val,"author")),language = mongo.bson.value(val,"language"), repository = mongo.oid.to.string(mongo.bson.value(val,"repository")) ))
  }
}

print(colnames(author_lang_df))
ddply_auth_lang <- ddply(author_lang_df,c("author","repository"),
      summarise,
      lang_list = c(lang_list,language)
      )

