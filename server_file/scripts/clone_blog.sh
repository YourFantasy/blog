mkdir -p /home/bardchen/software/hugo
cd /home/bardchen/software/hugo
git clone git@github.com:YourFantasy/blog.git
if [$? -ne 0];then
    echo "git clone failed"
    exit 1
fi