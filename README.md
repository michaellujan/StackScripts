A Linode.com StrackScript based on nigma's StrackScript that configures a complete web environment with Apache, MongoDB, Python, mod_wsgi and Django-nonrel.

By default, it creates a Virtual Host using the reverse DNS of your Linode's primary IP and sets up a sample Django project in the /srv directory.

Writes command output to /root/stackscript.log and records /etc changes using Mercurial. When completed notifies via  email. 

Please allow 10 minutes after booting for script to run. 

