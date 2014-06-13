%%R

for(i in 1: nrow(repos))
{
  repos_one <-  repos[i,]
 #print(repos_one)
  languages_list <- repos_one$languages
  #  print(length(languages_list))
   # print(languages_list)
  #print(languages_list)
  
  totalLineCount <- 0  
  if(!is.na(repos_one$stars) && repos_one$stars > 5 && !is.na(length(languages_list)) && class(repos_one$stars)!= 'mongo.oid')
  {
    print("inn") 
      if(length(languages_list)==0)
    {
        print("dann")
    }
    for(j in languages_list)
    {
        print (j)
        print(exists("j$lineCount"))
        #cat("------\n")
      if(exists("j$lineCount"))
      {
          totalLineCount = totalLineCount + j$lineCount
          print("inn4")
      }
    }
    print(length(languages_list))
    for(j in 1:length(languages_list))
    {
      print("inn2")  
          if(exists("j$lineCount"))
        {

                  repos_by_languages <- rbind(repos_by_languages, data.frame(id=mongo.oid.to.string(repos[i,1][[1]]),name=repos_one$fullName,stars = repos_one$stars, forks = repos_one$forks, language = languages_list[[j]]['language'] , linecount = languages_list[[j]][['lineCount']], totalLineCount = totalLineCount ))
                  print("inn3")    

        }
    }
  }
}

#cat("Table data : \n\n\n")
#print(head(repos_by_languages))
#cat("\n\n\n")
#cat("Dimensions : \n")
#print(dim(repos_by_languages))
print(head(repos_by_languages))
