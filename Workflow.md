# Workflow

* Hit `api.github.com/search/repositories` with a sort criteria set to `stars`.
* From the results, get `contributors_url` and create `User`s with the `login` and a flag, `fetched` set to `false`.
* For each `User`, hit `api.github.com/users/<User>/events/public?page=<page>`