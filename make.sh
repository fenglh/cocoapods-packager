#!/bin/bash

PASSWORD="bml123456"
echo $PASSWORD | sudo -S true  # 提前输入密码刷新缓存
sudo gem uninstall cocoapods-packager
gem build cocoapods-pack.gemspec
sudo gem install cocoapods-pack-1.5.0.gem --local
