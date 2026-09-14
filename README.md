# Documents
```
//on local
git clone https://github.com/zkt2202/Documents.git

cd Documents
git remote add origin https://github.com/zkt2202/Documents.git
git add .
git commit -m "Add Document"
git push origin main --force

```


# Create an SSH key in PEM format

I have not been able to use `ssh-keygen -e` to reliably generate a private key for SSH in PEM format.  This format is sometimes used by commercial products.  Instead, I had to convert the key using `openssl`.

``` bash
# generate an RSA key of size 2048 bits
ssh-keygen -t rsa -b 2048 -f jabba -C 'ronnie-jabba'

# copy key to 10.1.56.50 and add to authorized_keys

# convert private key to PEM format
openssl rsa -in jabba -outform PEM -out jabba.pem
chmod 700 jabba.pem

# test key
ssh -i ./jabba.pem rmaini@10.1.56.50 -p 2222

# add a passphrase
ssh-keygen -p -f jabba.pem

# does it have a passphrase
ssh-keygen -y -f jabba.pem

# test key, now with passphrase
ssh -i ./jabba.pem rmaini@10.1.56.50 -p 2222
```
