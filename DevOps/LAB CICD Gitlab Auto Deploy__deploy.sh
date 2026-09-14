echo 'deploy app to server Test: =======>'
rm -fr $HOME/pythonapp
mkdir -p $HOME/pythonapp
cd $HOME/pythonapp
git clone https://gitlabcmc.ccnapnh.fun/thanhnk/pythonapp.git .
sudo docker-compose down
sudo docker-compose up -d
echo '=====> deploy success on Test server'