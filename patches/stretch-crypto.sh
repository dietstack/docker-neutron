#!/bin/sh

# on stretch we need cryptography 1.9
sed -i '/cryptography/c\cryptography===1.9' /app/upper-constraints.txt

