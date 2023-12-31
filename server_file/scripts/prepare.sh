mkdir -p /home/bardchen/software/hugo
cd /home/bardchen/software/hugo
git clone git@github.com:YourFantasy/blog.git
if [$? -ne 0];then
    echo "git clone failed"
    exit 1
fi
mkdir -p /home/bardchen/software/hugo/scripts
cd /home/bardchen/software/hugo/blog/server_file/scripts/
cp git_pull.sh .env  push_algolia_json.js push_algolia_json_en.js /home/bardchen/software/hugo/scripts/
cd ../yum.repos.d&&cp *.repo /etc/yum.repos.d/

# install softwares
echo "y" | sudo yum update
if [$? -ne 0];then
    echo "update yum failed"
    exit 1
fi
echo "y" | sudo yum install hugo
if [$? -ne 0];then
    echo "install hugo failed"
    exit 1
fi
echo "y" | sudo yum install -y nginx
if [$? -ne 0];then
    echo "install nginx failed"
    exit 1
fi
echo "y" | sudo yum update
if [$? -ne 0];then
    echo "update yum failed"
    exit 1
fi
echo "y" | sudo yum install npm
if [$? -ne 0];then
    echo "install npm failed"
    exit 1
fi
npm install atomic-algolia --save
if [$? -ne 0];then
    echo "install npm and atomic-algolia failed"
    exit 1
fi

# start nginx
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443
sudo systemctl enable nginx
sudo systemctl start nginx
sudo systemctl status nginx
cd ../nginx &&cp nginx.conf /etc/nginx/nginx.conf
cd ../certificate&&cp * /etc/nginx/
sudo nginx -s reload
sudo systemctl status nginx
sudo systemctl restart nginx

# add crontab task
echo "* * * * * /home/bardchen/software/hugo/scripts/git_pull.sh" | crontab -
crontab -l





