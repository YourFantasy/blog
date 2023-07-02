sudo yum update
if [$? -ne 0];then
    echo "update yum failed"
    exit 1
fi
yum install curl-devel expat-devel gettext-devel   openssl-devel zlib-devel
if [$? -ne 0];then
    echo "install  openssl failed"
    exit 1
fi
yum -y install git-core
if [$? -ne 0];then
    echo "install git-cored failed"
    exit 1
fi
ssh-keygen -t rsa -C "cz950601@gmail.com"