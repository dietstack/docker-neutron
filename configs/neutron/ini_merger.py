#!/usr/bin/python3

import configparser
config = configparser.ConfigParser()
config.read('neutron.conf')
print(config.sections())
