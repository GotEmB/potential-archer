# Workflow

* Hit `api.github.com/search/repositories` with a sort criteria set to `stars`.
* Store repository's statistics.
* From the results, get `contributors_url` and create `User`s with the `login` if not found.
	* Add `Repository` to `User`.