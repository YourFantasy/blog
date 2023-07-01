cd /home/bardchen/software/hugo/blog;
git pull;
git submodule update --recursive --remote;
cd /home/bardchen/software/hugo/scripts &&source .env;
node push_algolia_json.js;
source .env;
node push_algolia_json_en.js;