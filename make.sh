#!/bin/bash

PASSWORD="Bml123456"
echo $PASSWOR | sudo gem uninstall cocoapods-packager
gem build cocoapods-packager.gemspec
echo $PASSWOR | sudo gem install cocoapods-packager-1.5.0.gem --local
