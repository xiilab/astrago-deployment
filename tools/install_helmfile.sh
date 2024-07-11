#!/bin/bash

CURRENT_DIR=$(dirname "$(realpath "$0")")
sudo cp $CURRENT_DIR/linux/* /usr/local/bin/
