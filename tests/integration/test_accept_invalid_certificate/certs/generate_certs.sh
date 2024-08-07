#!/bin/bash

# 1. Generate CA's private key and self-signed certificate
openssl req -newkey rsa:4096 -x509 -days 3650 -nodes -batch -keyout ca-key.pem -out ca-cert.pem -subj "/C=RU/ST=Some-State/O=Internet Widgits Pty Ltd/CN=ca"

# 2. Generate self-signed certificate and private key for using as wrong server certificate (because it's not signed by CA)
openssl req -newkey rsa:4096 -x509 -days 3650 -nodes -batch -keyout self-key.pem -out self-cert.pem -subj "/C=RU/ST=Some-State/O=Internet Widgits Pty Ltd/CN=server"

# 3. Generate client's private key and certificate signing request (CSR)
openssl req -newkey rsa:4096 -nodes -batch -keyout client-key.pem -out client-req.pem -subj "/C=RU/ST=Some-State/O=Internet Widgits Pty Ltd/CN=client"

# 4. Use CA's private key to sign client's CSR and get back the signed certificate
openssl x509 -req -days 3650 -in client-req.pem -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out client-cert.pem
