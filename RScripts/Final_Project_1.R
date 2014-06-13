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
if (not.installed("hash"))
  install.packages("hash")

if (not.installed("graphics"))
  install.packages("graphics")

if (not.installed("fpc"))
  install.packages("fpc")
if (not.installed("cluster"))
  install.packages("cluster")

library("fpc")
library("grid")
library("graphics")
library("stringr")
library("rjson") 
library("ggplot2") 
library("rmongodb") 
library("reshape2") 
library("MASS") 
library("plyr")
library("RMongo")
library("hash")
require("data.table")
library("cluster")
library("HSAUR")


library(plyr)
users = data.frame(stringsAsFactors = FALSE) 
repos = data.frame(stringsAsFactors = FALSE)
mongo_rmongodb <- mongo.create(host = "localhost") 
mongo_rmongo <- mongoDbConnect("cs249", host="localhost")
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

find_stars_lang <- function(df, repo, lang)
{
  lang <- tolower(lang)
  
  ret <- 0
  for(i in 1:nrow(df))
  {
    if(toString(df[i,1]) == repo && lang == tolower(toString(df[i,5])))
    {
      ret <- df[i,8]
    }
  }
  ret
}

find_forks_lang(ddply_sum_lineCount, "537fc5b7280ef15170b56d3b", "js")

find_forks_lang <- function(df, repo, lang)
{
  ret <- 0
  for(i in 1:nrow(df))
  {
    if(toString(df[i,1]) == repo && lang == toString(df[i,5]))
    {
      ret <- df[i,9]
    }
  }
  ret
}

find_lang_contrib_ratio <- function(bs, lang)
{
  lang = tolower(lang)
  c_ratios <- mongo.bson.value(bs,"contribution_ratio")
  ratio <- 0
  for(i in 1:length(c_ratios))
  {
    if(!is.null(c_ratios[i][[1]]$language) && tolower(c_ratios[i][[1]]$language) == lang)
    {
      
       ratio <- c_ratios[i][[1]]$ratio
    }
  }
  ratio
}

ddply_Overall = ddply( ddply_sum_lineCount,
                       c("language"), 
                       summarize,        
                       avg_popularity = mean(popularity),
                       avg_accessibility = mean(accessibility)
)  
print(head(ddply_Overall))
print(dim(ddply_Overall))

ggplot(ddply_Overall,aes(x= avg_popularity, y = avg_accessibility, colour = language)) + geom_point() + 
  geom_text(aes(label=language),hjust=0, vjust=0) + theme(legend.key.size = unit(0.4, "cm"))

ggplot(ddply_Overall,aes(x= log(avg_popularity), y = log(avg_accessibility), colour = language)) + geom_point()  + theme(legend.key.size = unit(0.4, "cm"))
######

mongo <- mongoDbConnect("cs249", host="localhost")
contribution_df <- dbGetQuery(mongo, "contributionratios", '{$or:[{"contribution_ratio": {$elemMatch:{"language":"JavaScript"}}},{"contribution_ratio": {$elemMatch:{"language":"CSS"}}}]}', skip=0, limit=100000)

domain <- c("JavaScript","CSS")
threshold <- c(0, 0) #change the 
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

update_hash_value <- function(h, key, value){
  if(!has.key(key,h))
    hash:::.set(h,keys=key,values=value)
  else
  {
    temp <- values(h, keys=key)
    hash:::.set(h,keys=key,values=(value+temp))
  }
}

author_ratios <- data.frame(stringsAsFactors = FALSE)
h_stars_css <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))
h_forks_css <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))

h_stars_js <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))
h_forks_js <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))

for(authorId in user_contribution_unique_list)
{
  cursor <- mongo.find(mongo_rmongodb, ns = "cs249.usercommitactvities", query=list(author=mongo.oid.from.string(authorId), language=list('$in'=c('JavaScript','CSS'))), fields=list(repository=1L,language=1L) )
  
  user_contributions_ratio <- mongo.find(mongo_rmongodb, ns = "cs249.contributionratios", query=list(author=mongo.oid.from.string(authorId)),fields=list(contribution_ratio=1L))
  ratio_lang <- 0
  
  ratio_css <- 0
  ratio_js <- 0
  
  if (mongo.cursor.next(user_contributions_ratio))
  {
    ratio <- mongo.cursor.value(user_contributions_ratio)
    ##ratio <- mongo.bson.value( ratio, "contribution_ratio")
    ratio_css <- find_lang_contrib_ratio(ratio, "CSS")
    ratio_js <- find_lang_contrib_ratio(ratio, "JavaScript")
  }
  
  while (mongo.cursor.next(cursor))
  {
    item <- mongo.cursor.value(cursor)
    oid <- mongo.bson.value(item, "repository")
    lang <- mongo.bson.value(item, "language")
    ## get stars and forks from the user commit activities
    stars <- find_stars_lang(ddply_sum_lineCount, mongo.oid.to.string(oid) , lang)
    forks <- find_forks_lang(ddply_sum_lineCount, mongo.oid.to.string(oid) , lang)
    if(lang == "CSS")
    {
        stars  <- stars * ratio_css
        forks  <- forks * ratio_css
        update_hash_value(h_forks_css, authorId, forks) 
        update_hash_value(h_stars_css, authorId, stars) 
    }
    else if(lang == "JavaScript")
    {
        stars  <- stars * ratio_js
        forks  <- forks * ratio_js
        update_hash_value(h_forks_js, authorId, forks) 
        update_hash_value(h_stars_js, authorId, stars) 
    }
    cat(authorId, "-",mongo.oid.to.string(oid),"-",stars,"-",forks,"-",lang,"\n")
  }
  mongo.cursor.destroy(cursor)
}

forks_lang_css <- c()
for(vals in  values(h_forks_css))
  forks_lang_css <- c(forks_lang_css, vals)

stars_lang_css <- c()
for(vals in  values(h_stars_css))
  stars_lang_css <- c(stars_lang_css, vals)

forks_lang_js <- c()
for(vals in  values(h_forks_js))
  forks_lang_js <- c(forks_lang_js, vals)

stars_lang_js <- c()
for(vals in  values(h_stars_js))
  stars_lang_js <- c(stars_lang_js, vals)

par(new=TRUE)
plot(stars_lang_css,forks_lang_css,ylim =c(0,20),xlim=c(0,60),xlab="stars",ylab="forks", col="red")
par(new=TRUE)
plot(stars_lang_js,forks_lang_js,ylim =c(0,20),xlim=c(0,60),xlab="stars",ylab="forks", col="blue")
par(new=TRUE)
l <- legend( "topleft", inset = c(0,0.4) 
#             , cex = 1.5
             , bty = "n"
             , legend = c("CSS", "Javascript")
             , text.col = c("red", "blue")
             , pt.bg = c("red","blue")
             , pch = c(21,21)
)
title("Measure of forks vs stars for both JS and CSS")

#plot(forks_lang_css,forks_lang_js,ylim =c(0,25),xlim=c(0,100),xlab="Stars for CSS",ylab="Stars for JS", col="red")
#title("Measure of Stars for CSS vs Stars for JS ")

#####user clustering#######

##find all unique languages
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
#######

# contains all the languages

unique_languages <- get_all_lang()
print(length(unique_languages))


user_contribution_cursor <- mongo.find(mongo_rmongodb, ns = "cs249.contributionratios" )
user_lang_contribution_df <- matrix(0,nrow=1,ncol=length(unique_languages))
author_id_vector <-c()
while (mongo.cursor.next(user_contribution_cursor))
{
  item <- mongo.cursor.value(user_contribution_cursor)
  authorId <- mongo.bson.value(item, "author")
  author_id_vector <- c(author_id_vector, mongo.oid.to.string(authorId))
  contributions_list <- mongo.bson.value(item, "contribution_ratio")

    #print(class(contributions_list))
    language_zeros <- matrix(0,nrow=1,ncol=length(unique_languages))
    #print(length(language_zeros))
        
    for(contribution in contributions_list)
    {
       #print((contribution$language))
      #print ("------")
      #print (contribution)
       if(class(contribution$language) != "NULL")
       {
        # print(match(tolower(contribution$language),tolower(unique_languages)))
         #print (contribution$language)
         #print (contribution$ratio)
         if (class(contribution$ratio) != "NULL") {
         language_zeros[match(tolower(contribution$language),tolower(unique_languages))] <- contribution$ratio
         }
       }
    }
    #print(language_zeros)
  user_lang_contribution_df <- rbind(user_lang_contribution_df,language_zeros)
  #user_lang_contribution_df <- rbind(user_lang_contribution_df, data.frame(author=mongo.oid.to.string(authorId),languages=language_zeros))
}

user_lang_contribution_df <- user_lang_contribution_df[-1,]
user_lang_contribution_dataframe <- data.frame(user_lang_contribution_df)
row.names(user_lang_contribution_dataframe) <- author_id_vector
print(rownames(user_lang_contribution_dataframe))
print(dim(user_lang_contribution_dataframe))

cl <- kmeans(user_lang_contribution_dataframe, 5)

plotcluster(user_lang_contribution_df, cl$cluster, pointsbyclvecd = TRUE)

cluster_vector <- cl$cluster

y <- which(cluster_vector==3, arr.in=TRUE)
print(length(y))
print(cl$size)

print(author_id_vector[y[2]])
A <- c()
for(i in 1:length(y))
{
  currentId <- author_id_vector[y[i]]
  if (class(currentId) != "NULL")
  {
    cursor <- mongo.find(mongo_rmongodb, ns = "cs249.contributionratios", query=list(author=mongo.oid.from.string(currentId) ))
    while (mongo.cursor.next(cursor))
    {
      item <- mongo.cursor.value(cursor)
      contributions_list <- mongo.bson.value(item, "contribution_ratio")
      #print(contributions_list)
      for(contribution in contributions_list)
      {
        if(class(contribution$language) != "NULL")
        {
          if (class(contribution$ratio) != "NULL") {
            #print(contribution$language)
            A <- c(A, contribution$language)
          }
        }
      }
    }
  }
  
}
print(unique(A))

##########

y <- which(cluster_vector==2, arr.in=TRUE)
print(length(y))
A2 <- c()
for(i in 1:length(y))
{
  currentId <- author_id_vector[y[i]]
  if (class(currentId) != "NULL")
  {
    cursor <- mongo.find(mongo_rmongodb, ns = "cs249.contributionratios", query=list(author=mongo.oid.from.string(currentId) ))
    while (mongo.cursor.next(cursor))
    {
      item <- mongo.cursor.value(cursor)
      contributions_list <- mongo.bson.value(item, "contribution_ratio")
      #print(contributions_list)
      for(contribution in contributions_list)
      {
        if(class(contribution$language) != "NULL")
        {
          if (class(contribution$ratio) != "NULL") {
            #print(contribution$language)
            A2 <- c(A2, contribution$language)
          }
        }
      }
    }
  }
  
}
print(length(unique(A2)))
print(unique(A2))


##########

y <- which(cluster_vector==4, arr.in=TRUE)
print(length(y))
A4 <- c()
for(i in 1:length(y))
{
  currentId <- author_id_vector[y[i]]
  if (class(currentId) != "NULL")
  {
    cursor <- mongo.find(mongo_rmongodb, ns = "cs249.contributionratios", query=list(author=mongo.oid.from.string(currentId) ))
    while (mongo.cursor.next(cursor))
    {
      item <- mongo.cursor.value(cursor)
      contributions_list <- mongo.bson.value(item, "contribution_ratio")
      #print(contributions_list)
      for(contribution in contributions_list)
      {
        if(class(contribution$language) != "NULL")
        {
          if (class(contribution$ratio) != "NULL") {
            #print(contribution$language)
            A4 <- c(A4, contribution$language)
          }
        }
      }
    }
  }
  
}
print(length(unique(A4)))
print(unique(A4))


#########################################
mongo <- mongoDbConnect("cs249", host="localhost")
contribution_df <- dbGetQuery(mongo, "contributionratios", '{$or:[{"contribution_ratio": {$elemMatch:{"language":"C"}}},{"contribution_ratio": {$elemMatch:{"language":"C++"}}}]}', skip=0, limit=100000)

domain <- c("C","C++")
threshold <- c(0, 0) #change the 
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
print("User contributed to either C or C++")
print(length(unique(user_contribution_list)))
print("User contributed to both")
print(length((user_contribution_list)) - length(unique(user_contribution_list)))
print("537ff216280ef15170b59ba5" %in% user_contribution_list)
user_contribution_unique_list <- unique(user_contribution_list)

update_hash_value <- function(h, key, value){
  if(!has.key(key,h))
    hash:::.set(h,keys=key,values=value)
  else
  {
    temp <- values(h, keys=key)
    hash:::.set(h,keys=key,values=(value+temp))
  }
}

author_ratios <- data.frame(stringsAsFactors = FALSE)
h_stars_css <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))
h_forks_css <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))

h_stars_js <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))
h_forks_js <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))

for(authorId in user_contribution_unique_list)
{
  cursor <- mongo.find(mongo_rmongodb, ns = "cs249.usercommitactvities", query=list(author=mongo.oid.from.string(authorId), language=list('$in'=c('C','C++'))), fields=list(repository=1L,language=1L) )
  
  user_contributions_ratio <- mongo.find(mongo_rmongodb, ns = "cs249.contributionratios", query=list(author=mongo.oid.from.string(authorId)),fields=list(contribution_ratio=1L))
  ratio_lang <- 0
  
  ratio_css <- 0
  ratio_js <- 0
  
  if (mongo.cursor.next(user_contributions_ratio))
  {
    ratio <- mongo.cursor.value(user_contributions_ratio)
    ##ratio <- mongo.bson.value( ratio, "contribution_ratio")
    ratio_css <- find_lang_contrib_ratio(ratio, "C++")
    ratio_js <- find_lang_contrib_ratio(ratio, "C")
  }
  
  while (mongo.cursor.next(cursor))
  {
    item <- mongo.cursor.value(cursor)
    oid <- mongo.bson.value(item, "repository")
    lang <- mongo.bson.value(item, "language")
    ## get stars and forks from the user commit activities
    stars <- find_stars_lang(ddply_sum_lineCount, mongo.oid.to.string(oid) , lang)
    forks <- find_forks_lang(ddply_sum_lineCount, mongo.oid.to.string(oid) , lang)
    if(lang == "C++")
    {
      stars  <- stars * ratio_css
      forks  <- forks * ratio_css
      update_hash_value(h_forks_css, authorId, forks) 
      update_hash_value(h_stars_css, authorId, stars) 
    }
    else if(lang == "C")
    {
      stars  <- stars * ratio_js
      forks  <- forks * ratio_js
      update_hash_value(h_forks_js, authorId, forks) 
      update_hash_value(h_stars_js, authorId, stars) 
    }
    cat(authorId, "-",mongo.oid.to.string(oid),"-",stars,"-",forks,"-",lang,"\n")
  }
  mongo.cursor.destroy(cursor)
}

forks_lang_css <- c()
for(vals in  values(h_forks_css))
  forks_lang_css <- c(forks_lang_css, vals)

stars_lang_css <- c()
for(vals in  values(h_stars_css))
  stars_lang_css <- c(stars_lang_css, vals)

forks_lang_js <- c()
for(vals in  values(h_forks_js))
  forks_lang_js <- c(forks_lang_js, vals)

stars_lang_js <- c()
for(vals in  values(h_stars_js))
  stars_lang_js <- c(stars_lang_js, vals)

par(new=TRUE)
plot(stars_lang_css,forks_lang_css,ylim =c(0,20),xlim=c(0,60),xlab="stars",ylab="forks", col="red")
par(new=TRUE)
plot(stars_lang_js,forks_lang_js,ylim =c(0,20),xlim=c(0,60),xlab="stars",ylab="forks", col="blue")
par(new=TRUE)
l <- legend( "topleft", inset = c(0,0.4) 
             #             , cex = 1.5
             , bty = "n"
             , legend = c("C++", "C")
             , text.col = c("red", "blue")
             , pt.bg = c("red","blue")
             , pch = c(21,21)
)
title("Measure of forks vs stars for both C and C++")

#################################
mongo <- mongoDbConnect("cs249", host="localhost")
contribution_df <- dbGetQuery(mongo, "contributionratios", '{$or:[{"contribution_ratio": {$elemMatch:{"language":"Java"}}},{"contribution_ratio": {$elemMatch:{"language":"Ruby"}}}]}', skip=0, limit=100000)

domain <- c("Java","Ruby")
threshold <- c(0, 0) #change the 
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
print("User contributed to either Java or Ruby")
print(length(unique(user_contribution_list)))
print("User contributed to both")
print(length((user_contribution_list)) - length(unique(user_contribution_list)))
print("537ff216280ef15170b59ba5" %in% user_contribution_list)
user_contribution_unique_list <- unique(user_contribution_list)

update_hash_value <- function(h, key, value){
  if(!has.key(key,h))
    hash:::.set(h,keys=key,values=value)
  else
  {
    temp <- values(h, keys=key)
    hash:::.set(h,keys=key,values=(value+temp))
  }
}

author_ratios <- data.frame(stringsAsFactors = FALSE)
h_stars_css <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))
h_forks_css <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))

h_stars_js <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))
h_forks_js <- hash(keys=user_contribution_unique_list, values= rep(0, length(user_contribution_unique_list)))

for(authorId in user_contribution_unique_list)
{
  cursor <- mongo.find(mongo_rmongodb, ns = "cs249.usercommitactvities", query=list(author=mongo.oid.from.string(authorId), language=list('$in'=c('Java','Ruby'))), fields=list(repository=1L,language=1L) )
  
  user_contributions_ratio <- mongo.find(mongo_rmongodb, ns = "cs249.contributionratios", query=list(author=mongo.oid.from.string(authorId)),fields=list(contribution_ratio=1L))
  ratio_lang <- 0
  
  ratio_css <- 0
  ratio_js <- 0
  
  if (mongo.cursor.next(user_contributions_ratio))
  {
    ratio <- mongo.cursor.value(user_contributions_ratio)
    ##ratio <- mongo.bson.value( ratio, "contribution_ratio")
    ratio_css <- find_lang_contrib_ratio(ratio, "Ruby")
    ratio_js <- find_lang_contrib_ratio(ratio, "Java")
  }
  
  while (mongo.cursor.next(cursor))
  {
    item <- mongo.cursor.value(cursor)
    oid <- mongo.bson.value(item, "repository")
    lang <- mongo.bson.value(item, "language")
    ## get stars and forks from the user commit activities
    stars <- find_stars_lang(ddply_sum_lineCount, mongo.oid.to.string(oid) , lang)
    forks <- find_forks_lang(ddply_sum_lineCount, mongo.oid.to.string(oid) , lang)
    if(lang == "Ruby")
    {
      stars  <- stars * ratio_css
      forks  <- forks * ratio_css
      update_hash_value(h_forks_css, authorId, forks) 
      update_hash_value(h_stars_css, authorId, stars) 
    }
    else if(lang == "Java")
    {
      stars  <- stars * ratio_js
      forks  <- forks * ratio_js
      update_hash_value(h_forks_js, authorId, forks) 
      update_hash_value(h_stars_js, authorId, stars) 
    }
    cat(authorId, "-",mongo.oid.to.string(oid),"-",stars,"-",forks,"-",lang,"\n")
  }
  mongo.cursor.destroy(cursor)
}

forks_lang_css <- c()
for(vals in  values(h_forks_css))
  forks_lang_css <- c(forks_lang_css, vals)

stars_lang_css <- c()
for(vals in  values(h_stars_css))
  stars_lang_css <- c(stars_lang_css, vals)

forks_lang_js <- c()
for(vals in  values(h_forks_js))
  forks_lang_js <- c(forks_lang_js, vals)

stars_lang_js <- c()
for(vals in  values(h_stars_js))
  stars_lang_js <- c(stars_lang_js, vals)

par(new=TRUE)
plot(stars_lang_css,forks_lang_css,ylim =c(0,20),xlim=c(0,60),xlab="stars",ylab="forks", col="red")
par(new=TRUE)
plot(stars_lang_js,forks_lang_js,ylim =c(0,20),xlim=c(0,60),xlab="stars",ylab="forks", col="blue")
par(new=TRUE)
l <- legend( "topleft", inset = c(0,0.4) 
             #             , cex = 1.5
             , bty = "n"
             , legend = c("Ruby", "Java")
             , text.col = c("red", "blue")
             , pt.bg = c("red","blue")
             , pch = c(21,21)
)
title("Measure of forks vs stars for both Java and Ruby")




