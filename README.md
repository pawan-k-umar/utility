# utility


Steps for deployin application on server

Step 1: Create intance ubantu and assign elastic IP to domain DNS

Step 2: Add Inblund Rules to allow http and https

Step 3: Clone Utility repo from git  https://github.com/pawan-k-umar/utility

Step 4: Make file excutable 

    chmod +x utility/required-software.sh
    chmod +x utility/nginx-setup.sh

Step 5: Run ./utility/required-software.sh

Step 6: Run ./utility/nginx-setup.sh

Step 7: run Jenkins, Docker, Nginx

    systemctl start jenkins
    systemctl start docker
    systemctl start nginx

Step 8:  
	1. Open the sudoers file safely: sudo visudo
    2. Add this line at the bottom: jenkins ALL=(ALL) NOPASSWD: /usr/sbin/usermod, /bin/systemctl restart jenkins


Step 8: open https://jenkins.kpawan.com/ and setup pipeline using Pipeline Script from SCM
    SCM: Git
    Repository URL: https://github.com/pawan-k-umar/invoice-management
    Branch Specifier : */integration

Step 9: Build now

Step 10: open https://kpawan.com/