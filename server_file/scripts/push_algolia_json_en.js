atomicalgolia = require("atomic-algolia")
var indexName = "index.en"
var indexPath = "/home/bardchen/software/hugo/blog/public/en/index.json"

var cb = function(error, result) {
    if (error) throw error

    console.log(result)
}

atomicalgolia(indexName, indexPath, cb)