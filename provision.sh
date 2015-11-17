#!/bin/bash

apache_config_file="/etc/apache2/envvars"
apache_vhost_file="/etc/apache2/sites-available/vagrant_vhost.conf"
php_config_file="/etc/php5/apache2/php.ini"
xdebug_config_file="/etc/php5/mods-available/xdebug.ini"
mysql_config_file="/etc/mysql/my.cnf"
default_apache_index="/var/www/html/index.html"

# This function is called at the very bottom of the file
main() {
	update_go

	if [[ -e /var/lock/vagrant-provision ]]; then
	    cat 1>&2 << EOD
################################################################################
# To re-run full provisioning, delete /var/lock/vagrant-provision and run
#
#    $ vagrant provision
#
# From the host machine
################################################################################
EOD
	    exit
	fi

	network_go
	tools_go
	apache_go
	php_go
	mysql_go
	nodejs_go
	ruby_go
	composer_go

	touch /var/lock/vagrant-provision
}

update_go() {
	# Update the server
	apt-get update
	apt-get -y upgrade
}

network_go() {
	IPADDR=$(/sbin/ifconfig eth0 | awk '/inet / { print $2 }' | sed 's/addr://')
	sed -i "s/^${IPADDR}.*//" /etc/hosts
	echo ${IPADDR} ubuntu.localhost >> /etc/hosts			# Just to quiet down some error messages
}

tools_go() {
	# Install basic tools
	apt-get -y install build-essential binutils-doc git curl libcairo2-dev libav-tools nfs-common portmap
}

nodejs_go() {
	apt-get update
	apt-get install -y python-software-properties python g++ make
	add-apt-repository -y ppa:chris-lea/node.js
	apt-get update
	apt-get install -y nodejs

	sudo apt-get install -y npm -y
	sudo npm config set registry http://registry.npmjs.org/
	sudo npm install source-map -g
	sudo npm update --save-dev
	sudo npm install uglify-js@1.3 -g
}

zsh_go() {
	# Added zsh shell.
	sudo apt-get install zsh
	wget --no-check-certificate https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | sh
	sudo chsh -s /bin/zsh vagrant

	# Change the oh my zsh default theme.
	sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="3den"/g' ~/.zshrc
}

composer_go() {
	# install Composer
	curl -s https://getcomposer.org/installer | php
	mv composer.phar /usr/local/bin/composer
}

ruby_go() {
	echo 'Installing Ruby and Gems..'
	sudo apt-get remove --purge ruby-rvm ruby
	sudo rm -rf /usr/share/ruby-rvm /etc/rmvrc /etc/profile.d/rvm.sh
	rm -rf ~/.rvm* ~/.gem/ ~/.bundle*
	echo 'gem: --no-rdoc --no-ri' >> ~/.gemrc
	echo "export rvm_max_time_flag=20" >> ~/.rvmrc
	#tail ~/.gemrc
	echo "[[ -s '${HOME}/.rvm/scripts/rvm' ]] && source '${HOME}/.rvm/scripts/rvm'" >> ~/.bashrc
	curl -L https://get.rvm.io | bash -s stable --ruby
	sudo gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3

	#source /home/vagrant/.rvm/scripts/rvm
	source /usr/local/rvm/scripts/rvm

	# Fix permissions and add Vagrant to the RVM group
	sudo rvm group add rvm vagrant
	sudo rvm fix-permissions

	# Now that permissions are fixed, install ruby 2.2.2
	sudo rvm install 2.2.2

	gem install cyaml
	gem install compass
	gem install sass
	gem install bundler

	# Reinstall ruby 1.9.3 for backwards compatability
	sudo bash -c "rvm reinstall 1.9.3"

	# Use Ruby 2.2.2 by default globally
	sudo rvm --default use 2.2.2
}



apache_go() {
	# Install Apache
	apt-get -y install apache2

	sed -i "s/^\(.*\)www-data/\1vagrant/g" ${apache_config_file}
	chown -R vagrant:vagrant /var/log/apache2

	cat << EOF > ${apache_vhost_file}
<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot /vagrant/src
        LogLevel debug

        ErrorLog /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log combined

        <Directory /vagrant/src>
            AllowOverride All
            Require all granted
        </Directory>
</VirtualHost>
EOF

	a2dissite 000-default
	a2ensite vagrant_vhost

	a2enmod rewrite

	service apache2 reload
	update-rc.d apache2 enable
}

php_go() {
	apt-get -y install php5 php5-curl php5-mysql php5-sqlite php5-xdebug

	sed -i "s/display_startup_errors = Off/display_startup_errors = On/g" ${php_config_file}
	sed -i "s/display_errors = Off/display_errors = On/g" ${php_config_file}

	cat << EOF > ${xdebug_config_file}
zend_extension=xdebug.so
xdebug.remote_enable=1
xdebug.remote_connect_back=1
xdebug.remote_port=9000
xdebug.remote_host=10.0.2.2
EOF
	service apache2 reload
}

mysql_go() {
	# Install MySQL
	echo "mysql-server mysql-server/root_password password root" | debconf-set-selections
	echo "mysql-server mysql-server/root_password_again password root" | debconf-set-selections
	apt-get -y install mysql-client mysql-server

	sed -i "s/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" ${mysql_config_file}

	# Allow root access from any host
	echo "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'root' WITH GRANT OPTION" | mysql -u root --password=root
	echo "GRANT PROXY ON ''@'' TO 'root'@'%' WITH GRANT OPTION" | mysql -u root --password=root

	service mysql restart
	update-rc.d apache2 enable
}

main
exit 0
