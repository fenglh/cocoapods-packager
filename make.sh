#!/bin/bash
sudo gem uninstall cocoapods-packager
gem build cocoapods-packager.gemspec
sudo gem install cocoapods-packager-1.5.0.gem --local
