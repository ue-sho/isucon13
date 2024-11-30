#!/bin/bash

sudo curl -L -s -o /etc/nginx/tls/_.t.isucon.pw.crt https://github.com/KOBA789/t.isucon.pw/releases/latest/download/fullchain.pem
sudo curl -L -s -o /etc/nginx/tls/_.t.isucon.pw.key https://github.com/KOBA789/t.isucon.pw/releases/latest/download/key.pem

sudo chmod 0600 /etc/nginx/tls/_.t.isucon.pw.crt
sudo chmod 0600 /etc/nginx/tls/_.t.isucon.pw.key

sudo systemctl reload nginx
