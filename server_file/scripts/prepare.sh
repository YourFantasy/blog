mkdir -p /home/bardchen/software/hugo/scripts;
cd /home/bardchen/software/hugo;
git pull git@github.com:YourFantasy/blog.git&&cd blog;
cd server_file/scripts/&&cp git_pull.sh .env  push_algolia_json.js push_algolia_json_en.js /home/bardchen/software/hugo/scripts/;
cd ../yum.repos.d&&cp *.repo /etc/yum.repos.d/;

# install softwares
sudo yum update;
sudo yum install hugo;
sudo yum install -y nginx;
sudo update;
sudo yum install npm&&npm install atomic-algolia --save;

# start nginx
sudo netstat -tulpn | grep :80;
sudo netstat -tulpn | grep :443
sudo systemctl enable nginx;
sudo systemctl start nginx;
sudo systemctl status nginx;
cd ../nginx &&cp nginx.conf /etc/nginx/nginx.conf;
sudo nginx -s reload;
sudo systemctl status nginx;
sudo systemctl restart nginx;

# add crontab task
echo "* * * * * /home/bardchen/software/hugo/scripts/git_pull.sh" | crontab -;





