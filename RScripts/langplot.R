cat("Table data : \n\n\n")
print(head(ddply_sum_lineCount))
cat("\n\n\n")
cat("Dimensions : \n")
print(dim(ddply_sum_lineCount))


##### Use split, apply and combine to find the average popularity and accessibility
ddply_Overall = ddply( ddply_sum_lineCount,
                       c("language"), 
                       summarize,        
                       avg_popularity = mean(popularity),
                       avg_accessibility = mean(accessibility)
)  
cat("Table data : \n\n\n")
print(head(ddply_Overall))
cat("\n\n\n")
cat("Dimensions : \n")
print(dim(ddply_Overall))

#ggplot(ddply_Overall,aes(x= avg_popularity, y = avg_accessibility, colour = language)) + geom_point() + 
#  geom_text(aes(label=language),hjust=0, vjust=0)
x=1
